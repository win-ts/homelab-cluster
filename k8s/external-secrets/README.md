# External Secrets Operator with Vault

This setup lets External Secrets Operator (ESO) authenticate to Vault with a
Kubernetes service-account token. Argo CD applies the shared authentication
resources and `SecretStore`; each application repository owns its
`ExternalSecret` and resulting Kubernetes Secret.

## 1. Configure Vault

Run these commands from a machine with working `kubectl` and `vault` clients.
Authenticate to Vault with an administrative token first.

```bash
export VAULT_ADDR=http://vault.win-ts.int:8200
vault login

kubectl config view --raw --minify \
  -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \
  | base64 --decode > /tmp/win-ts-k8s-ca.crt

vault auth list -format=json | jq -e '."kubernetes/"' >/dev/null || \
  vault auth enable kubernetes

vault policy write inari-eso-read \
  k8s/external-secrets/vault/inari-eso-read.hcl

vault write auth/kubernetes/role/eso-inari \
  bound_service_account_names=eso-vault-auth \
  bound_service_account_namespaces=inari \
  audience=vault \
  token_policies=inari-eso-read \
  token_ttl=1h \
  token_max_ttl=4h
```

Vault runs outside Kubernetes, so verify that the Vault VM can resolve and
reach the API server:

```bash
getent hosts k8s.win-ts.int
curl --cacert /path/to/win-ts-k8s-ca.crt \
  https://k8s.win-ts.int:6443/version
```

An HTTP 401 or 403 still proves network and TLS connectivity; a DNS or timeout
error must be fixed first.

## 2. Add the first Vault secret

The `ExternalSecret` extracts all fields from
`secret/inari/inari-backend`:

```bash
vault kv put -mount=secret inari/inari-backend \
  DB_USERNAME=inari \
  DB_PASSWORD='replace-me' \
  MINIO_ACCESS_KEY='replace-me' \
  MINIO_SECRET_KEY='replace-me'
```

Do not commit real values to Git.

## 3. Install with Argo CD

Commit and push this directory before creating the applications. Install the
operator first and wait for its CRDs and controllers, then install the Inari
resources:

```bash
kubectl apply -f k8s/argocd/applications/external-secrets.yaml
kubectl -n argocd wait application/external-secrets \
  --for=jsonpath='{.status.health.status}'=Healthy --timeout=5m

kubectl apply -f k8s/argocd/applications/inari-external-secrets.yaml
```

After Argo CD creates the reviewer resources, configure Vault with the token
that Kubernetes generated. Run this on the machine where both `kubectl` and
`vault` are configured:

```bash
kubectl -n inari get serviceaccount vault-token-reviewer
kubectl -n inari get secret vault-token-reviewer-token
kubectl get clusterrolebinding vault-token-reviewer

REVIEWER_JWT=$(kubectl -n inari get secret \
  vault-token-reviewer-token \
  -o jsonpath='{.data.token}' | base64 --decode)

vault write auth/kubernetes/config \
  kubernetes_host=https://k8s.win-ts.int:6443 \
  kubernetes_ca_cert=@/tmp/win-ts-k8s-ca.crt \
  token_reviewer_jwt="$REVIEWER_JWT" \
  disable_local_ca_jwt=true \
  disable_iss_validation=true

unset REVIEWER_JWT

vault read auth/kubernetes/config | grep token_reviewer_jwt_set
```

The expected value is `true`. The token itself is stored in Vault and must
never be committed to Git.

Upgrade the existing Argo CD release with `k8s/argocd/values.yaml` as you
normally do. That values file now includes an `ExternalSecret` health check, so
Argo CD waits for ESO's `Ready=True` condition. In an application containing
both an `ExternalSecret` and a workload, annotate the workload with a later
wave, for example:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

## 4. Verify

```bash
kubectl -n inari get secretstore vault
kubectl -n inari get externalsecret inari-backend
kubectl -n inari describe externalsecret inari-backend
kubectl -n inari get secret inari-backend
```

Inspect only the key names without printing secret values:

```bash
kubectl -n inari get secret inari-backend \
  -o go-template='{{range $key, $value := .data}}{{$key}}{{"\n"}}{{end}}'
```

An application Deployment can consume the generated Secret normally:

```yaml
envFrom:
  - secretRef:
      name: inari-backend
```

The supplied `ExternalSecret` is wave `0`; application workloads can use wave
`1` so Argo CD waits for the generated Secret before deploying them.

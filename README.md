# homelab-cluster

Config and Manifest Files for Homelab Cluster

## Commands

Helm Commands
```bash
# Save Values to File
helm show values \
  <repo>/<chart> \
  > default-values.yaml

# Install
helm install <name> \
  <repo>/<chart> \
  --namespace <namespace>

# Upgrade
helm upgrade <name> \
  <repo>/<chart> \
  --namespace <namespace>
```

### ArgoCD

Update Account Password
```bash
argocd account update-password \
  --account <account-name>
```

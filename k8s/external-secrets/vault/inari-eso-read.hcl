# ESO only needs to read secret values. Human developer permissions remain in
# the separate dev-secrets policy.
path "secret/data/inari/*" {
  capabilities = ["read"]
}

path "secret/metadata/inari/*" {
  capabilities = ["read", "list"]
}

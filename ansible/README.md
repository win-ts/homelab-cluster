# Homelab infrastructure playbooks

These playbooks configure three Debian VMs:

| Inventory host | Address | Service | Runtime |
| --- | --- | --- | --- |
| `db-1` | `192.168.1.14` | MySQL 8.4 | Docker Compose |
| `vault-1` | `192.168.1.15` | Vault with Raft storage | systemd |
| `vm-misc-1` | `192.168.1.16` | Redis 8 with AOF and MinIO | Docker Compose |

## Prerequisites

- The target VMs run Debian and are reachable over SSH.
- The AWX Machine Credential supplies the SSH user, private key, and sudo
  privilege escalation.
- The separate `sdb` disk is mounted at `/data` on both `db-1` and
  `vm-misc-1`. Every data-bearing role verifies this mount before starting a
  container, preventing service data from being written to the OS disk.
- MySQL stores data in `/data/mysql`; Redis and MinIO use `/data/redis` and
  `/data/minio` respectively.
- The AWX execution environment includes the collection in
  `collections/requirements.yml`.

Install the collection for local runs with:

```bash
ansible-galaxy collection install -r ansible/collections/requirements.yml
```

## Secrets

Provide these as secret AWX survey fields, injected credential variables, or
encrypted Ansible variables:

- `mysql_root_password`
- `redis_password`
- `minio_root_user`
- `minio_root_password` (at least eight characters)

Do not commit their values. The non-secret defaults are in
`group_vars/all.yml`.

## AWX job templates

Use the `Homelab` inventory and `Homelab SSH` Machine Credential for each job:

| Template | Playbook |
| --- | --- |
| `01 - Deploy MySQL` | `ansible/playbooks/mysql.yml` |
| `02 - Deploy Redis` | `ansible/playbooks/redis.yml` |
| `03 - Deploy MinIO` | `ansible/playbooks/minio.yml` |
| `04 - Deploy Vault` | `ansible/playbooks/vault.yml` |
| `Deploy Infrastructure` | `ansible/playbooks/infrastructure.yml` |

MinIO exposes its S3 API on port `9000` and its web console on port `9001`.

For an AWX project rooted directly at this `ansible` directory, omit the
leading `ansible/` from the playbook paths.

## Vault initialization

Deployment starts Vault in a durable, single-node Raft configuration but does
not initialize or unseal it. Perform that security-sensitive operation once
from a trusted workstation:

```bash
export VAULT_ADDR=http://vault.win-ts.int:8200
vault status
vault operator init
```

Store the unseal keys and initial root token somewhere secure and separate from
the Vault VM. Never place them in Git, normal AWX extra variables, or job logs.

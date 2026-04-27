# DevOps hooks

Guards for infrastructure commands Claude shouldn't run blind: `terraform destroy`, destructive AWS calls against prod profiles, `kubectl` on prod clusters, irreversible DB migrations, and Docker operations on production containers. One non-blocking hook validates GitHub Actions YAML before write, and one logs every infra command for later review.

Every blocker can be bypassed for legitimate use via a `CLAUDE_ALLOW_*` environment variable; see the hook header for the exact name.

## Hooks

- [`terraform-destroy-guard`](terraform-destroy-guard.sh) ([catalog](../../docs/hooks.md#devops)) — Blocks `terraform destroy` unless `CLAUDE_ALLOW_DESTROY=1`. Warns on `terraform apply -destroy`.
- [`kubernetes-prod-guard`](kubernetes-prod-guard.sh) ([catalog](../../docs/hooks.md#devops)) — Blocks `kubectl` against prod clusters or namespaces.
- [`aws-prod-guard`](aws-prod-guard.sh) ([catalog](../../docs/hooks.md#devops)) — Blocks destructive AWS CLI commands targeting profiles named prod/production.
- [`db-migration-guard`](db-migration-guard.sh) ([catalog](../../docs/hooks.md#devops)) — Blocks `DROP TABLE`/`DROP DATABASE`, `TRUNCATE`, unsafe `DELETE FROM`, and migration rollbacks.
- [`docker-prod-guard`](docker-prod-guard.sh) ([catalog](../../docs/hooks.md#devops)) — Blocks `docker rm`/`stop`/`kill`/`volume rm` on containers or volumes whose name contains `prod`/`production`/`live`.
- [`github-actions-validator`](github-actions-validator.sh) ([catalog](../../docs/hooks.md#devops)) — Validates YAML syntax of GitHub Actions workflow files before write. Blocks invalid YAML.
- [`infra-audit-log`](infra-audit-log.sh) ([catalog](../../docs/hooks.md#devops)) — Logs every `terraform`/`kubectl`/`aws`/`gcloud`/`helm`/`docker` command to `~/.claude/infra-audit.log`. Always exits 0.

## Install just this category

The `devops` profile installs every hook in this directory:

```bash
bash scripts/install.sh --profile=devops --global
```

Or use the category flag:

```bash
bash scripts/install.sh --category=devops --global
```

For team-shared infrastructure repos, install with `--project` instead so the rules ship with the codebase.

# GitHub Actions workflows

The pipeline spans three repositories. Images are built, scanned and signed by CI,
pushed to GHCR, then pulled by the server — **the VPS never builds anything**.

```
Lumiris-Backend ──tag v*──► ghcr.io/lumiris-dpp/lumiris-api
Lumiris-Front   ──tag v*──► ghcr.io/lumiris-dpp/lumiris-{site,app,admin,mobile}
                                          │
Lumiris-Infra   prod-deploy (manual) ─────┴──► Ansible over SSH ──► docker compose pull && up -d
```

## Workflows in this repo

### `local-check.yml` — every push and PR

| Job            | What it gates                                                         |
| -------------- | --------------------------------------------------------------------- |
| `lint`         | yamllint, shellcheck (`scripts/` + `seed/apply-seed.sh`), prettier    |
| `compose`      | `docker compose config` on the prod stack, both overlays, local stack |
| `ansible-lint` | `prod/ansible/` at the **production** profile                         |
| `secret-scan`  | gitleaks + a check that `*.sops` files really are encrypted           |
| `actionlint`   | the workflows themselves                                              |

### `prod-deploy.yml` — manual (`workflow_dispatch`)

Inputs: `api_tag`, `front_tag`, `force_recreate`, `trust_host_key_on_first_use`.

1. **Preflight** — refuses to start unless every secret and variable is present,
   and verifies both image tags actually exist in the registry. Nothing touches
   production until this passes.
2. **Deploy** — installs sops + Ansible, materialises the age key, the SSH key and
   the pinned host key, renders the inventory, then runs `playbooks/deploy.yml`.
3. **Smoke test** — probes the four public endpoints and fails the run if any is down.

**Rollback** — re-run with the previous tags. Images from the last seven days stay
on the box, so a rollback needs no rebuild.

The same playbook runs from a laptop:

```bash
cd prod/ansible
ansible-playbook playbooks/deploy.yml -e api_image_tag=v0.4.2 -e front_image_tag=v0.4.2
```

## Required configuration

Repository **variables** (Settings → Secrets and variables → Actions → Variables):

| Variable          | Example       | Required                       |
| ----------------- | ------------- | ------------------------------ |
| `PROD_HOST`       | `51.15.x.x`   | yes                            |
| `PROD_USER`       | `juba`        | yes                            |
| `PROD_SSH_PORT`   | `22`          | no — defaults to `22`          |
| `PROD_DOMAIN`     | `lumiris.eu`  | no — defaults to `lumiris.eu`  |
| `REGISTRY`        | `ghcr.io`     | no — defaults to `ghcr.io`     |
| `IMAGE_NAMESPACE` | `lumiris-dpp` | no — defaults to `lumiris-dpp` |

Repository **secrets**:

| Secret               | What it is                                                             |
| -------------------- | ---------------------------------------------------------------------- |
| `DEPLOY_SSH_KEY`     | Private half of the CI-only ed25519 deploy key                         |
| `DEPLOY_KNOWN_HOSTS` | Output of `ssh-keyscan -p <port> -H <host>` — pins the server identity |
| `SOPS_AGE_KEY`       | `AGE-SECRET-KEY-…` used to decrypt `prod/secrets/prod.env.sops`        |
| `GHCR_PULL_TOKEN`    | Optional PAT with `read:packages`, if the packages are not public      |

`GITHUB_TOKEN` is provided automatically and is used as the registry fallback.

## Host key policy

Host key verification is **on**. The first deploy of a new server can be run with
`trust_host_key_on_first_use = true`, which records the key via `ssh-keyscan` and
prints it so it can be stored in `DEPLOY_KNOWN_HOSTS`. Every later run pins it.

## Pinning policy

Every third-party action is pinned to a **full commit SHA** with the version in a
trailing comment — a moved tag cannot change what runs. Dependabot bumps the SHA
and the comment together. Tools without a trustworthy action (gitleaks, actionlint)
are downloaded as pinned release binaries instead.

# prod/

Production runs on a single self-hosted server (`lumiris.eu`). Images are built,
scanned and signed by CI, pushed to GHCR, then pulled here — **the server never
builds**.

## Deploying

From GitHub: run the **prod-deploy** workflow in Actions with the two image tags.
It refuses to start unless the images exist in the registry, waits for a manual
approval on the `production` environment, then smoke-tests the public endpoints.

From a laptop, the exact same playbook:

```bash
make prod-deploy API_TAG=v0.4.2 FRONT_TAG=v0.4.2
```

Rolling back is a redeploy of the previous tags. The last seven days of images
stay on the box, so no rebuild is needed.

## First run on a fresh server

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
cp ansible/inventories/prod/hosts.yml.example ansible/inventories/prod/hosts.yml  # fill it in
API_TAG=v0.1.0 FRONT_TAG=v0.1.0 make prod-bootstrap
```

`scripts/prod-bootstrap.sh` hardens the host, installs Docker, rolls out the
first release and seeds the database. It refuses to run until:

- `prod/secrets/prod.env.sops` exists and is genuinely encrypted
- `$SOPS_AGE_KEY_FILE` points at a readable age private key
- `ansible/inventories/prod/hosts.yml` exists without `REPLACE_ME` placeholders
- `API_TAG` and `FRONT_TAG` name the release to deploy

## Layout

```text
prod/
├── docker-compose.prod.yml         # traefik + postgres + redis + minio + api + 3 fronts, all from GHCR
├── docker-compose.monitoring.yml   # optional overlay
├── docker-compose.crowdsec.yml     # optional overlay
├── .env.prod.example               # template — the real file is rendered from SOPS at deploy time
├── ansible/
│   ├── ansible.cfg / requirements.yml
│   ├── inventories/prod/           # hosts.yml.example + group_vars
│   ├── playbooks/                  # site, bootstrap, deploy, backup, rotate-secrets
│   └── roles/                      # common, docker, app
├── secrets/prod.env.sops           # SOPS-encrypted runtime env (committed encrypted)
├── traefik-prod/                   # static + dynamic configs (ACME Let's Encrypt)
└── monitoring-prod/                # OTel collector config
```

## Routing

Traefik's Docker label provider is **disabled** — its client defaults to API 1.24,
which the Docker 29 daemon rejects. Routing is declared statically in
[`traefik-prod/dynamic/routes.yml`](traefik-prod/dynamic/routes.yml); Traefik
reaches each container by name on the shared `lumiris_prod` network. Adding a
service means editing that file, not adding labels.

## Secrets

Runtime secrets live in `secrets/prod.env.sops`, encrypted with age and committed
in that form. At deploy time Ansible decrypts them **on the controller** and
writes `.env.prod` (mode 0600) on the server. Nothing is ever committed in clear;
CI enforces this with gitleaks plus a check on the SOPS header.

## Local validation

`make prod-check` runs the same gate as CI: yamllint, shellcheck, prettier,
ansible-lint (production profile) and `docker compose config` on every stack.

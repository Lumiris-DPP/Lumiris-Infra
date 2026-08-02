# CLAUDE.md — LUMIRIS Infra

> Orchestration locale + préparation prod (Docker, Traefik, monitoring, scripts).

## Repos voisins

```
~/Dev/Lumiris/
├── Lumiris-Front/     # Bun + Turbo · Next.js 16 · 4 apps · ports 3000-3003
├── Lumiris-Backend/   # Spring Boot 3.4 · Java 21 · port 8080
└── Lumiris-Infra/     # ← ce repo
```

## Layout

```
Lumiris-Infra/
├── local/             # Docker compose dev (base + monitoring + tools overlays)
├── prod/              # Terraform + Ansible + compose.prod (inert until VPS bootstrapped)
├── scripts/           # _lib.sh + setup-{hosts,certs}.sh + smoke-test + secrets-*.sh + seed
├── seed/              # apply-seed.sh + fixtures
├── secrets/           # *.sops.yaml (chiffrés via age)
├── bench/             # k6 scenarios
├── .mise.toml         # toolchain dev (bun, java, jq, mkcert, age, sops, mprocs, tmux)
├── mprocs.yaml        # orchestration TUI infra + backend + front
└── docs/              # ARCHITECTURE / LOCAL / SERVICES / MIGRATION-TO-PROD / …
```

## Commandes essentielles

```bash
make tools         # mise install (bun/java/jq/mkcert/age/sops/mprocs/tmux selon .mise.toml)
make setup         # hosts + certs + .env (idempotent)
make dev           # mprocs : infra docker + backend mvn + front bun dans un TUI unique
make smoke-test    # curl healthchecks des URLs principales
make reset         # docker compose down -v (CONFIRMATION requise, perte des volumes)
make help          # tous les targets groupés
```

Pas de scripts d'orchestration maison (`all-up/down/status`) ni de check de
pré-requis : remplacés par `mise` (`.mise.toml`) + `mprocs` (`mprocs.yaml`).
Hotkeys mprocs : `r` restart focus · `x` kill · `s` start · `q` quit (envoie
SIGTERM à tous les process, arrête proprement les containers).

Profils additionnels : `make up-monitoring` (Grafana/Prom/Tempo/Loki/OTel),
`make up-tools` (pgAdmin/Redis Commander), `make up-full` (les deux).

## Scripts shell — convention

Tous les scripts sourcent **`scripts/_lib.sh`** (helpers couleur, logging, paths,
catalogue des URLs, healthchecks docker/HTTP, `confirm`/`step`). Pour écrire un
nouveau script :

```bash
#!/usr/bin/env bash
# shellcheck source=./_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

info "Hello"
ok "$ROOT"
```

Le script obtient `info/ok/warn/err/die/confirm/step`, les variables `ROOT`,
`LOCAL_DIR`, `SCRIPTS_DIR`, `SESSION`, le tableau `SERVICES[]` (label/host/desc),
et les helpers `wait_for_healthy`, `print_container_health`, `http_status`,
`http_reachable`, `print_urls_table`.

Lint : `make lint` (yamllint + shellcheck + hadolint + gitleaks si installés).

## Source de vérité — ports & vhosts

Cette table est la **référence canonique** ; les fichiers ci-dessous doivent
rester alignés.

| Service     | Vhost                   | Port host | Port container | Référencé par                                                                       |
| ----------- | ----------------------- | --------- | -------------- | ----------------------------------------------------------------------------------- |
| site        | `lumiris.local`         | 3000      | —              | Front `apps/site/.env.example` · `prod/compose:lumiris-site`                        |
| admin       | `admin.lumiris.local`   | 3001      | —              | Front `apps/admin/.env.example` · `prod/compose:lumiris-admin`                      |
| mobile      | `mobile.lumiris.local`  | 3002      | —              | Front `apps/mobile/.env.example` · `prod/compose:lumiris-mobile`                    |
| client      | `client.lumiris.local`  | 3003      | —              | Front `apps/client/.env.example` · `prod/compose:lumiris-client`                    |
| api         | `api.lumiris.local`     | 8080      | 8080           | Backend `Dockerfile:EXPOSE 8080` · `Makefile:API_PORT` · `prod/compose:lumiris-api` |
| postgres    | —                       | 5432      | 5432           | `local/docker-compose.yml` (POSTGRES_PORT)                                          |
| redis       | —                       | 6379      | 6379           | `local/docker-compose.yml` (REDIS_PORT)                                             |
| minio-s3    | `cdn.lumiris.local`     | 9000      | 9000           | `local/docker-compose.yml` (MINIO_API_PORT)                                         |
| minio-cons. | `minio.lumiris.local`   | 9001      | 9001           | `local/docker-compose.yml` (MINIO_CONSOLE_PORT)                                     |
| mailhog     | `mailhog.lumiris.local` | 1025/8025 | 1025/8025      | `local/docker-compose.yml`                                                          |
| otlp http   | —                       | 4318      | 4318           | OTel collector (profile monitoring)                                                 |
| traefik     | `traefik.lumiris.local` | 80/443    | 80/443         | `local/docker-compose.yml` (entrypoints)                                            |

**Variables d'env** (Lumiris-Infra/local/.env) qui pilotent les ports exposés :
`POSTGRES_PORT`, `REDIS_PORT`, `MINIO_API_PORT`, `MINIO_CONSOLE_PORT`. La prod
(`prod/docker-compose.prod.yml`) n'expose **pas** ces ports — postgres/redis/minio
y sont des services managés externes.

## CORS (cross-référence Backend ↔ Front)

`Lumiris-Backend/.env.example:CORS_ALLOWED_ORIGINS` doit contenir **les 4 vhosts
front + les 4 ports localhost** ci-dessus. Validation runtime : Spring logue
`CORS allowed origins (N): [...]` au démarrage (cf. `CorsConfig.java`).

## Secrets (SOPS + age)

- `secrets/*.sops.yaml` — chiffrés via age, recipients dans [`.sops.yaml`](.sops.yaml)
- `SOPS_AGE_KEY_FILE` doit pointer sur la clé privée locale
- Helpers : `scripts/secrets-{encrypt,decrypt,rotate}.sh`
- Rotation après ajout/retrait d'un mainteneur : `./scripts/secrets-rotate.sh`

## Phase 2 — Prod

`prod/` est inert tant que `make prod-bootstrap` n'a pas été exécuté. Voir
[`docs/MIGRATION-TO-PROD.md`](docs/MIGRATION-TO-PROD.md) pour la checklist.
`make prod-check` lint le scaffolding (terraform fmt/validate, ansible-lint,
yamllint, shellcheck).

## Voir aussi

- [`README.md`](README.md) — Quickstart utilisateur
- [`docs/SERVICES.md`](docs/SERVICES.md) — credentials détaillés
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — symptômes / causes / fix
- [`../Lumiris-Front/CLAUDE.md`](../Lumiris-Front/CLAUDE.md) — conventions front
- [`../Lumiris-Backend/README.md`](../Lumiris-Backend/README.md) — conventions backend

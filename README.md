# Lumiris-Infra

> Infrastructure & orchestration du Lumiris Ecosystem

Ce dépôt centralise tout ce qui permet de faire tourner localement (et bientôt en
production) la stack Lumiris : Docker compose, configuration Traefik, certificats
mkcert, scripts d'amorçage, monitoring, et orchestration des autres repos via
[mprocs](https://github.com/pvolok/mprocs).

## Layout

```text
~/Dev/Lumiris/
├── Lumiris-Front/      Monorepo Bun + Turbo (4 apps Next.js 16 + packages partages)
├── Lumiris-Backend/    API Spring Boot 3.4.5 / Java 21 (port 8080)
└── Lumiris-Infra/      Orchestration locale + prep prod (ce repo)
    ├── local/          Docker compose dev (Traefik, Postgres, Redis, MinIO, Mailhog, monitoring)
    ├── prod/           Stack containerisee pour deploiement futur (inerte)
    ├── scripts/        setup-hosts.sh, setup-certs.sh, smoke-test, secrets, seed
    ├── seed/           Jeux de donnees de seed
    ├── secrets/        SOPS + age (config initiale)
    ├── bench/          Outils de benchmark
    ├── .mise.toml      Toolchain dev (bun, java, jq, mkcert, age, sops, mprocs)
    ├── mprocs.yaml     Orchestration TUI infra + backend + front
    └── docs/           Documentation (ce dossier)
```

## Quickstart

### 1. Pré-requis système (à installer une fois)

- Docker Engine + Docker Compose v2
- `make`
- [`mise`](https://mise.jdx.dev) (`curl https://mise.run | sh`)

Tout le reste (bun, java 21, jq, mkcert, age, sops, mprocs, tmux) est géré par
`mise` via [`.mise.toml`](.mise.toml).

### 2. Installer la toolchain

```bash
cd ~/Dev/Lumiris/Lumiris-Infra
make tools                       # = mise install ; mise ls
mise activate zsh >> ~/.zshrc    # (une seule fois) auto-PATH dans les nouveaux shells
```

### 3. Setup initial (une seule fois)

```bash
make setup
```

Ce target enchaine :

- `setup-hosts.sh` — ajoute les vhosts `*.lumiris.local` dans `/etc/hosts`
- `setup-certs.sh` — genere les certificats locaux via `mkcert`
- Initialisation des fichiers `.env` a partir des `.env.example`

### 4. Démarrer la stack complète

```bash
make dev
```

Lance [mprocs](https://github.com/pvolok/mprocs) avec 4 process (cf. [`mprocs.yaml`](mprocs.yaml)) :

| Process   | Rôle                                                                        |
| --------- | --------------------------------------------------------------------------- |
| `infra`   | `docker compose up` (Traefik + Postgres + Redis + MinIO + Mailhog)          |
| `backend` | `./mvnw spring-boot:run` dans Lumiris-Backend (port 8080)                   |
| `front`   | `bun dev` (Turbo orchestre les 4 apps) dans Lumiris-Front (ports 3000-3003) |
| `stripe`  | `stripe listen --forward-to :8080/api/stripe/webhook` (webhooks Stripe)     |

Hotkeys mprocs : `↑↓` naviguer · `<Tab>` logs↔liste · `r` restart focus ·
`x` kill focus · `s` start arrêté · `q` quit (envoie SIGTERM à tous les process,
les containers s'arrêtent proprement).

> Pas d'auto-restart sur modif fichier : volontaire. Tu redémarres un process
> à la main avec `r` quand tu en as besoin.

> Le process `stripe` reste vivant avec un message si le CLI Stripe n'est pas
> installé ou si `STRIPE_SECRET_KEY` manque du `.env` backend — il ne fait pas
> planter le TUI. Détails : [Stripe (webhooks locaux)](#stripe-webhooks-locaux).

### 5. Base de données — migrer + seed (au premier lancement)

⚠️ **Flyway ne s'exécute PAS automatiquement au boot du backend** (Spring Boot 4).
Sur une base neuve, il faut appliquer les migrations **et** les seeds une fois,
sinon aucun utilisateur n'existe et la connexion est impossible :

```bash
cd ~/Dev/Lumiris/Lumiris-Backend
set -a && . ./.env && set +a
./mvnw flyway:migrate \
  -Dflyway.locations=filesystem:src/main/resources/db/migration,filesystem:src/main/resources/db/seed
```

> Les seeds (`V2__seed_users`, `V6__seed_artisan_profiles`) vivent dans
> `db/seed`, **séparés** de `db/migration`. Le plugin Flyway ne lit que
> `db/migration` par défaut : il faut donc passer **les deux** chemins pour
> obtenir les comptes de connexion. La commande est idempotente (re-jouable).

### 6. Se connecter — comptes de démo (seed)

Un compte par rôle est seedé pour le dev local (mot de passe = `<rôle>123`) :

| Rôle       | Email                  | Mot de passe  | App concernée              |
| ---------- | ---------------------- | ------------- | -------------------------- |
| `ARTISAN`  | `artisan@lumiris.com`  | `artisan123`  | **Atelier** (client, 3003) |
| `ADMIN`    | `admin@lumiris.com`    | `admin123`    | Back-office (admin, 3001)  |
| `CONSUMER` | `client@lumiris.com`   | `client123`   | Site / mobile              |
| `REPAIRER` | `repairer@lumiris.com` | `repairer123` | —                          |

Vérifier que l'auth répond (retourne un JWT + l'utilisateur) :

```bash
curl -s http://localhost:8080/api/auth/login \
  -H 'content-type: application/json' \
  -d '{"email":"artisan@lumiris.com","password":"artisan123"}'
```

### Dépannage rapide

| Symptôme                                                 | Cause probable / fix                                                                                   |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `front` meurt en `EADDRINUSE` (ports 3000-3003, 5432…)   | Une **autre stack Docker** squatte les ports. Stoppe-la avant (`docker compose -p <projet> down`).     |
| Backend : `Unable to determine Dialect` / DB injoignable | Postgres pas démarré, ou port décalé. Le backend attend `localhost:5433` (cf. `Lumiris-Backend/.env`). |
| Login `401` / aucun utilisateur                          | Base migrée mais **pas seedée** → refais l'étape 5 avec les **deux** `flyway.locations`.               |
| Login `500 column "…" does not exist`                    | Base issue d'une ancienne lignée de migration. Reset : `make reset` (ou drop schema) puis étape 5.     |
| Webhooks Stripe en échec de signature                    | `STRIPE_WEBHOOK_SECRET` du `.env` ≠ secret de `stripe listen`. Voir [Stripe](#stripe-webhooks-locaux). |

Plus de cas : [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).

## Stack locale

Tous les vhosts ci-dessous resolvent vers `127.0.0.1` (via `/etc/hosts`) puis sont
routes par Traefik vers leur cible.

| Vhost                   | Cible                | Description                    |
| ----------------------- | -------------------- | ------------------------------ |
| `lumiris.local`         | host:3000            | Site marketing (Next.js)       |
| `admin.lumiris.local`   | host:3001            | Back-office                    |
| `mobile.lumiris.local`  | host:3002            | App mobile (web + Tauri-ready) |
| `client.lumiris.local`  | host:3003            | Workspace artisans B2B         |
| `api.lumiris.local`     | host:8080            | API Spring Boot                |
| `traefik.lumiris.local` | traefik:8080         | Dashboard Traefik (basic auth) |
| `minio.lumiris.local`   | minio:9001           | MinIO Console                  |
| `cdn.lumiris.local`     | minio:9000           | MinIO S3 endpoint              |
| `pgadmin.lumiris.local` | pgadmin:80           | pgAdmin (profile `tools`)      |
| `redis.lumiris.local`   | redis-commander:8081 | Redis UI (profile `tools`)     |
| `mailhog.lumiris.local` | mailhog:8025         | Fake SMTP UI                   |
| `grafana.lumiris.local` | grafana:3000         | Grafana (profile `monitoring`) |

Voir [`docs/SERVICES.md`](docs/SERVICES.md) pour les credentials et les ports
exposes sur l'hote.

## Stripe (webhooks locaux)

La facturation (abonnements ATELIER) passe par Stripe **en mode test**. Le
backend écoute les webhooks sur `POST /api/stripe/webhook` ; en local on les
forwarde avec le **CLI Stripe**, lancé automatiquement par le process `stripe`
de `make dev`.

**Pré-requis** (une fois) :

1. Installer le [CLI Stripe](https://docs.stripe.com/stripe-cli) (fourni par
   `mise` si listé dans `.mise.toml`, sinon installation manuelle).
2. Le backend `Lumiris-Backend/.env` doit contenir les clés **test** :
   `STRIPE_SECRET_KEY=sk_test_…`, `STRIPE_PUBLISHABLE_KEY=pk_test_…`,
   `STRIPE_WEBHOOK_SECRET=whsec_…` (voir `.env.example`).

Le process utilise `--api-key "$STRIPE_SECRET_KEY"` : **pas besoin de
`stripe login`**. Le secret de signature imprimé par `stripe listen` est stable
par compte et doit correspondre à `STRIPE_WEBHOOK_SECRET`.

**Le lancer à la main** (hors `make dev`) :

```bash
cd ~/Dev/Lumiris/Lumiris-Backend
stripe listen --api-key "$(grep -E '^STRIPE_SECRET_KEY=' .env | cut -d= -f2-)" \
  --forward-to localhost:8080/api/stripe/webhook
```

**Tester** un événement de bout en bout (le backend doit répondre `[200]`) :

```bash
stripe trigger --api-key "$(grep -E '^STRIPE_SECRET_KEY=' Lumiris-Backend/.env | cut -d= -f2-)" \
  customer.subscription.created
```

## Production

Serveur unique auto-hébergé. La CI construit, scanne et signe les images puis les
pousse sur GHCR ; le serveur ne construit jamais rien, il ne fait que tirer.

Déploiement courant — workflow **prod-deploy** sur GitHub (approbation manuelle
requise), ou en local :

```bash
make prod-deploy API_TAG=v0.4.2 FRONT_TAG=v0.4.2
```

Première mise en service d'un serveur :

1. Remplir + chiffrer `prod/secrets/prod.env.sops`
2. Remplir `prod/ansible/inventories/prod/hosts.yml`
3. Lancer `API_TAG=vX.Y.Z FRONT_TAG=vX.Y.Z make prod-bootstrap` (interactif, refuse tant qu'une pièce manque)

Détail : [`prod/README.md`](prod/README.md) et
[`.github/workflows/README.md`](.github/workflows/README.md).

Détail complet : [`docs/MIGRATION-TO-PROD.md`](docs/MIGRATION-TO-PROD.md). Coûts attendus : [`docs/COSTS.md`](docs/COSTS.md).

## Repos lies

- [`../Lumiris-Front/`](../Lumiris-Front/) — front (monorepo Bun + Turbo)
- [`../Lumiris-Backend/`](../Lumiris-Backend/) — API Spring Boot

## Docs

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — vision d'ensemble + diagramme
- [`docs/LOCAL.md`](docs/LOCAL.md) — guide local pas-a-pas
- [`docs/SERVICES.md`](docs/SERVICES.md) — services + credentials + ports
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — symptomes / causes / fix
- [`docs/RUNBOOK.md`](docs/RUNBOOK.md) — procedures ops (local + prod)
- [`docs/ONBOARDING.md`](docs/ONBOARDING.md) — checklist nouveau dev
- [`docs/MIGRATION-TO-PROD.md`](docs/MIGRATION-TO-PROD.md) — plan d'activation prod
- [`docs/ONBOARDING-PROD.md`](docs/ONBOARDING-PROD.md) — comptes externes à créer
- [`docs/COSTS.md`](docs/COSTS.md) — coûts attendus (free tiers)

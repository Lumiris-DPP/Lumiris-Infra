SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

ROOT          := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
LOCAL_DIR     := $(ROOT)/local
SCRIPTS_DIR   := $(ROOT)/scripts

ifneq (,$(wildcard $(LOCAL_DIR)/.env))
include $(LOCAL_DIR)/.env
export
endif

COMPOSE_PROJECT_NAME ?= lumiris
export COMPOSE_PROJECT_NAME

CF_BASE       := -f $(LOCAL_DIR)/docker-compose.yml
CF_MONITORING := -f $(LOCAL_DIR)/docker-compose.yml -f $(LOCAL_DIR)/docker-compose.monitoring.yml
CF_TOOLS      := -f $(LOCAL_DIR)/docker-compose.yml -f $(LOCAL_DIR)/docker-compose.tools.yml
CF_FULL       := -f $(LOCAL_DIR)/docker-compose.yml -f $(LOCAL_DIR)/docker-compose.monitoring.yml -f $(LOCAL_DIR)/docker-compose.tools.yml

DC          := docker compose --project-directory $(LOCAL_DIR)

##@ Help
.PHONY: help
help: ## Liste les targets groupés par section
	@awk 'BEGIN { FS = ":.*?##[ @]" } \
	      /^##@ / { printf "\n\033[1;33m%s\033[0m\n", substr($$0, 5); next } \
	      /^[a-zA-Z0-9_.-]+:.*?## / { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 }' \
	      $(MAKEFILE_LIST)
	@printf '\n\033[1;33mInfo\033[0m  project=%s  root=%s\n' "$(COMPOSE_PROJECT_NAME)" "$(ROOT)"

##@ Bootstrap
.PHONY: tools setup
tools: ## Installe la toolchain dev via mise (lit .mise.toml)
	@command -v mise >/dev/null 2>&1 || { echo "[tools] mise absent — install: curl https://mise.run | sh"; exit 1; }
	@mise install
	@mise ls

setup: ## Hosts + certs + .env (idempotent)
	@$(SCRIPTS_DIR)/setup-hosts.sh
	@$(SCRIPTS_DIR)/setup-certs.sh
	@if [ ! -f $(LOCAL_DIR)/.env ]; then \
	  cp $(LOCAL_DIR)/.env.example $(LOCAL_DIR)/.env; \
	  echo "[setup] $(LOCAL_DIR)/.env créé depuis .env.example"; \
	else \
	  echo "[setup] $(LOCAL_DIR)/.env déjà présent — pas écrasé"; \
	fi
	@echo "[setup] OK"

##@ Stack locale (dev)
.PHONY: dev
dev: ## Lance infra + backend + front dans un TUI mprocs (q = quit, r = restart focused)
	@command -v mise >/dev/null 2>&1 || { echo "[dev] mise absent — install: curl https://mise.run | sh"; exit 1; }
	@$(SCRIPTS_DIR)/preflight-dev.sh
	@mise exec -- mprocs -c mprocs.yaml

.PHONY: up down restart ps logs
up: ## docker compose up -d (infra seule, sans tmux ni apps)
	@$(DC) $(CF_BASE) up -d
	@$(MAKE) urls

down: ## docker compose down (volumes conservés)
	@$(DC) $(CF_BASE) down

restart: down up ## down && up

ps: ## docker compose ps
	@$(DC) $(CF_BASE) ps

logs: ## Logs follow de tous les services
	@$(DC) $(CF_BASE) logs -f

logs-%: ## Logs follow d'un service (ex: make logs-postgres)
	@$(DC) $(CF_BASE) logs -f $*

.PHONY: up-monitoring up-tools up-full down-monitoring down-tools
up-monitoring: ## up + profile monitoring (Grafana, Prom, Tempo, Loki, OTel, cAdvisor, node-exporter)
	@$(DC) $(CF_MONITORING) --profile monitoring up -d
	@echo "  Grafana → https://grafana.lumiris.local  (admin/admin)"
	@echo "  Prometheus → http://127.0.0.1:9090"
	@echo "  Tempo OTLP → http://127.0.0.1:4318"

up-tools: ## up + profile tools (pgAdmin, Redis Commander)
	@$(DC) $(CF_TOOLS) --profile tools up -d
	@echo "  pgAdmin → https://pgadmin.lumiris.local"
	@echo "  Redis Commander → https://redis.lumiris.local"

up-full: ## up + monitoring + tools (lourd)
	@$(DC) $(CF_FULL) --profile monitoring --profile tools up -d

down-monitoring: ## Stop monitoring profile only
	@$(DC) $(CF_MONITORING) --profile monitoring down

down-tools: ## Stop tools profile only
	@$(DC) $(CF_TOOLS) --profile tools down

##@ Maintenance
.PHONY: reset reset-hard psql redis-cli urls config
reset: ## docker compose down -v (PERTE des données — confirmation requise)
	@printf "\033[1;31mTous les volumes seront détruits. Tape 'yes' pour confirmer: \033[0m"; \
	read ans; \
	if [ "$$ans" = "yes" ]; then \
	  $(DC) $(CF_FULL) --profile monitoring --profile tools down -v; \
	  echo "[reset] volumes détruits"; \
	else \
	  echo "[reset] annulé"; \
	fi

reset-hard: reset ## reset + suppression des volumes Docker nommés (lumiris_postgres_data, etc.)
	@docker volume rm -f lumiris_postgres_data lumiris_redis_data lumiris_minio_data 2>/dev/null || true
	@echo "[reset-hard] volumes Docker purgés"

psql: ## Ouvre psql dans le container postgres
	@$(DC) $(CF_BASE) exec postgres psql -U $${POSTGRES_USER:-lumiris} -d $${POSTGRES_DB:-lumiris}

redis-cli: ## Ouvre redis-cli dans le container redis
	@$(DC) $(CF_BASE) exec redis redis-cli -a "$${REDIS_PASSWORD:-lumiris_local_dev_only}"

urls: ## Tableau des URLs accessibles localement
	@printf '\n\033[1;33mURLs locales\033[0m\n'
	@printf '  %-32s %s\n' "https://lumiris.local"          "Site (host:3000)"
	@printf '  %-32s %s\n' "https://admin.lumiris.local"    "Admin (host:3001)"
	@printf '  %-32s %s\n' "https://mobile.lumiris.local"   "Mobile (host:3002)"
	@printf '  %-32s %s\n' "https://client.lumiris.local"   "Client (host:3003)"
	@printf '  %-32s %s\n' "https://api.lumiris.local"      "API Spring Boot (host:8080)"
	@printf '  %-32s %s\n' "https://traefik.lumiris.local"  "Traefik dashboard (admin/admin)"
	@printf '  %-32s %s\n' "https://minio.lumiris.local"    "MinIO Console"
	@printf '  %-32s %s\n' "https://cdn.lumiris.local"      "MinIO S3 endpoint"
	@printf '  %-32s %s\n' "https://mailhog.lumiris.local"  "Mailhog UI"
	@printf '  %-32s %s\n' "https://grafana.lumiris.local"  "Grafana (profile monitoring)"
	@printf '  %-32s %s\n' "https://pgadmin.lumiris.local"  "pgAdmin (profile tools)"
	@printf '  %-32s %s\n' "https://redis.lumiris.local"    "Redis Commander (profile tools)"

config: ## docker compose config (validation syntaxique)
	@$(DC) $(CF_BASE) config --quiet && echo "[config] $(LOCAL_DIR)/docker-compose.yml OK"
	@$(DC) $(CF_MONITORING) --profile monitoring config --quiet && echo "[config] + monitoring overlay OK"
	@$(DC) $(CF_TOOLS) --profile tools config --quiet && echo "[config] + tools overlay OK"

##@ Qualité
.PHONY: lint fmt smoke-test
lint: ## yamllint + shellcheck + hadolint + gitleaks (si installés)
	@command -v yamllint   >/dev/null && yamllint -c .yamllint.yml . || echo "[lint] yamllint absent"
	@command -v shellcheck >/dev/null && shellcheck $(SCRIPTS_DIR)/*.sh || echo "[lint] shellcheck absent"
	@command -v hadolint   >/dev/null && find . -name Dockerfile -not -path './.git/*' -exec hadolint {} + || echo "[lint] hadolint absent (ou pas de Dockerfile local)"
	@command -v gitleaks   >/dev/null && gitleaks detect --no-banner --redact . || echo "[lint] gitleaks absent"

fmt: ## prettier --write sur md/yml/json
	@command -v prettier >/dev/null && prettier --write '**/*.{md,yml,yaml,json}' --ignore-path .prettierignore || npx --yes prettier@3 --write '**/*.{md,yml,yaml,json}' --ignore-path .prettierignore

smoke-test: ## Curl healthchecks des URLs principales
	@$(SCRIPTS_DIR)/smoke-test-local.sh

##@ Bench
.PHONY: bench
BENCH_DIR := $(ROOT)/bench
SCENARIO  ?= scoring
bench: ## k6 local (SCENARIO=browse|audit|scoring)
	@command -v k6 >/dev/null || { echo "[bench] k6 absent — https://k6.io"; exit 1; }
	@test -f $(BENCH_DIR)/scenarios/$(SCENARIO).js || { echo "[bench] SCENARIO=$(SCENARIO) introuvable"; exit 1; }
	k6 run $(BENCH_DIR)/scenarios/$(SCENARIO).js

##@ Phase 2 — Préparation prod (refuse si non configuré)
PROD_DIR       := $(ROOT)/prod
ANSIBLE_DIR    := $(PROD_DIR)/ansible
ANSIBLE_INV    := $(ANSIBLE_DIR)/inventories/prod/hosts.yml

.PHONY: prod-check prod-bootstrap prod-deploy prod-backup prod-seed prod-rotate-secrets
prod-check: ## Même gate que la CI : yamllint, shellcheck, prettier, ansible-lint, compose config
	@command -v ansible-lint >/dev/null || { echo "[prod-check] ansible-lint absent"; exit 1; }
	@command -v yamllint >/dev/null || { echo "[prod-check] yamllint absent"; exit 1; }
	@command -v shellcheck >/dev/null || { echo "[prod-check] shellcheck absent"; exit 1; }
	@echo "[prod-check] yamllint"
	@yamllint -c $(ROOT)/.yamllint.yml $(ROOT)
	@echo "[prod-check] shellcheck seed/ + scripts/ (severity=warning)"
	@shellcheck -S warning $(SCRIPTS_DIR)/*.sh $(ROOT)/seed/apply-seed.sh
	@echo "[prod-check] prettier --check"
	@npx --yes prettier@3 --check '**/*.{md,yml,yaml,json}' --ignore-path $(ROOT)/.prettierignore
	@echo "[prod-check] ansible-lint"
	@cd $(ANSIBLE_DIR) && ansible-lint
	@echo "[prod-check] docker compose config"
	@cd $(PROD_DIR) && API_IMAGE_TAG=v0.0.0 FRONT_IMAGE_TAG=v0.0.0 \
		docker compose -f docker-compose.prod.yml --env-file .env.prod.example config >/dev/null
	@cd $(ROOT)/local && docker compose -f docker-compose.yml --env-file .env.example config >/dev/null
	@echo "[prod-check] OK"

prod-bootstrap: ## scripts/prod-bootstrap.sh — durcissement + docker + premier déploiement
	@$(SCRIPTS_DIR)/prod-bootstrap.sh

prod-deploy: ## Déploie des images déjà publiées. Usage: make prod-deploy API_TAG=v0.4.2 FRONT_TAG=v0.4.2
	@test -f $(ANSIBLE_INV) || { echo "[prod-deploy] $(ANSIBLE_INV) absent"; exit 1; }
	@test -n "$(API_TAG)" || { echo "[prod-deploy] usage: make prod-deploy API_TAG=v0.4.2 FRONT_TAG=v0.4.2"; exit 2; }
	@test -n "$(FRONT_TAG)" || { echo "[prod-deploy] usage: make prod-deploy API_TAG=v0.4.2 FRONT_TAG=v0.4.2"; exit 2; }
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/deploy.yml \
		-e api_image_tag=$(API_TAG) -e front_image_tag=$(FRONT_TAG)

prod-backup: ## ansible-playbook backup.yml
	@test -f $(ANSIBLE_INV) || { echo "[prod-backup] inventory absent — voir docs/MIGRATION-TO-PROD.md"; exit 1; }
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/backup.yml

prod-seed: ## seed/apply-seed.sh prod
	@$(ROOT)/seed/apply-seed.sh prod

prod-rotate-secrets: ## ansible-playbook rotate-secrets.yml
	@test -f $(ANSIBLE_INV) || { echo "[prod-rotate-secrets] inventory absent"; exit 1; }
	@cd $(ANSIBLE_DIR) && ansible-playbook playbooks/rotate-secrets.yml

##@ Seed
.PHONY: seed
seed: ## Seed data locale (placeholder Prompt 2)
	@$(SCRIPTS_DIR)/seed-local.sh

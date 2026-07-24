#!/usr/bin/env bash
# shellcheck source=./_lib.sh
# Préflight de `make dev` : vérifie qu'aucun port requis n'est déjà pris par
# un AUTRE projet (ex: le stack docker "portfolio") avant de lancer mprocs.
# Sans ça, mprocs démarre mais front/back meurent en EADDRINUSE sans message clair.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# Ports configurables lus depuis local/.env (défauts si absent) — évite la dérive.
env_port() {
  local val=""
  [[ -f "$LOCAL_DIR/.env" ]] && val="$(grep -E "^$1=" "$LOCAL_DIR/.env" | tail -1 | cut -d= -f2-)"
  printf '%s' "${val:-$2}"
}
PG_PORT="$(env_port POSTGRES_PORT 5433)"
RD_PORT="$(env_port REDIS_PORT 6379)"
S3_PORT="$(env_port MINIO_API_PORT 9000)"
S3C_PORT="$(env_port MINIO_CONSOLE_PORT 9001)"

# port|description. Deux familles :
#  - apps : lancées sur l'hôte par mprocs (front bun, back mvnw) → AUCUN listener attendu
#  - infra : publiées par le compose lumiris → tenues par nos propres containers = OK
APP_PORTS=(
  "3000|front site"
  "3001|front admin"
  "1420|mobile vite (tauri desktop)"
  "3003|front client"
  "8080|backend api"
)
INFRA_PORTS=(
  "80|traefik http"
  "443|traefik https"
  "$PG_PORT|postgres"
  "$RD_PORT|redis"
  "$S3_PORT|minio s3"
  "$S3C_PORT|minio console"
  "1025|mailhog smtp"
  "8025|mailhog ui"
)

# Vrai si un socket est en LISTEN sur ce port (toutes interfaces).
port_listening() {
  [[ -n "$(ss -ltnH "( sport = :$1 )" 2>/dev/null)" ]]
}

# "nom|projet_compose" du container qui publie ce port, sinon "".
docker_owner() {
  command -v docker >/dev/null 2>&1 || return 0
  docker ps --filter "publish=$1" \
    --format '{{.Names}}|{{.Label "com.docker.compose.project"}}' 2>/dev/null | head -1
}

conflicts=0

# allow_lumiris=yes : un listener du projet "lumiris" est normal (infra déjà up).
check_port() {
  local port="${1%%|*}" desc="${1##*|}" allow_lumiris="$2"
  port_listening "$port" || return 0

  local owner name proj
  owner="$(docker_owner "$port")"
  name="${owner%%|*}"
  proj="${owner##*|}"

  if [[ -n "$owner" ]]; then
    if [[ "$allow_lumiris" == "yes" && "$proj" == "lumiris" ]]; then
      info "$port ($desc) déjà tenu par '$name' [lumiris] — infra up, OK"
      return 0
    fi
    err "$port ($desc) occupé par le container '$name' [projet: ${proj:-inconnu}]"
    printf "         → libère-le : %sdocker compose -p %s down%s\n" \
      "$YELLOW" "${proj:-<projet>}" "$NC"
  else
    err "$port ($desc) occupé par un process hôte (hors docker)"
    printf "         → identifie-le : %ssudo ss -ltnp '( sport = :%s )'%s puis kill\n" \
      "$YELLOW" "$port" "$NC"
  fi
  conflicts=$((conflicts + 1))
}

step "Préflight ports — make dev"

for p in "${APP_PORTS[@]}";   do check_port "$p" no;  done
for p in "${INFRA_PORTS[@]}"; do check_port "$p" yes; done

if (( conflicts > 0 )); then
  echo
  die "$conflicts conflit(s) de port — libère-les ci-dessus puis relance 'make dev'"
fi

ok "Ports requis libres (ou tenus par l'infra lumiris) — lancement de mprocs"

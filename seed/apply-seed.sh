#!/usr/bin/env bash
# shellcheck source=../scripts/_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)/_lib.sh"

SEED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SEED_DIR

usage() {
  cat <<'EOF'
Usage: seed/apply-seed.sh <local|prod>

Creates the four named Lumiris accounts (admin, repairer, artisan, consumer) in
the target database and prints their generated passwords once.

Identities are overridable through the environment:
  SEED_ADMIN_EMAIL     SEED_ADMIN_NAME
  SEED_REPAIRER_EMAIL  SEED_REPAIRER_NAME
  SEED_ARTISAN_EMAIL   SEED_ARTISAN_NAME    SEED_ARTISAN_SIRET
  SEED_CONSUMER_EMAIL  SEED_CONSUMER_NAME
EOF
}

[[ $# -eq 1 ]] || { usage >&2; exit 2; }
TARGET_ENV="$1"
readonly TARGET_ENV

case "$TARGET_ENV" in
  local) ENV_FILE="$ROOT/local/.env" ;;
  prod) ENV_FILE="$ROOT/prod/.env.prod" ;;
  *) usage >&2; exit 2 ;;
esac
readonly ENV_FILE

readonly POSTGRES_CONTAINER="lumiris-postgres"

command -v docker >/dev/null || die "docker introuvable"

if [[ ! -f "$ENV_FILE" ]]; then
  die "$ENV_FILE absent — pour la prod : sops -d --input-type dotenv --output-type dotenv prod/secrets/prod.env.sops > prod/.env.prod"
fi

docker inspect --format '{{.State.Running}}' "$POSTGRES_CONTAINER" >/dev/null 2>&1 \
  || die "conteneur $POSTGRES_CONTAINER introuvable — lance la stack $TARGET_ENV d'abord"

env_value() {
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -n1
}

PG_USER="$(env_value POSTGRES_USER)"
PG_DB="$(env_value POSTGRES_DB)"
[[ -n "$PG_USER" && -n "$PG_DB" ]] || die "POSTGRES_USER / POSTGRES_DB absents de $ENV_FILE"

generate_password() {
  local alphanumeric
  alphanumeric="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
  printf '%s' "${alphanumeric:0:20}"
}

# AuthService normalise l'adresse en minuscules avant toute recherche : une majuscule stockée
# telle quelle rendrait le compte impossible à connecter.
ADMIN_EMAIL="${SEED_ADMIN_EMAIL:-contact@lumiris.eu}"
ADMIN_EMAIL="${ADMIN_EMAIL,,}"
ADMIN_NAME="${SEED_ADMIN_NAME:-Juba Aitadda}"
REPAIRER_EMAIL="${SEED_REPAIRER_EMAIL:-gaoubak@gmail.com}"
REPAIRER_EMAIL="${REPAIRER_EMAIL,,}"
REPAIRER_NAME="${SEED_REPAIRER_NAME:-Kader}"
ARTISAN_EMAIL="${SEED_ARTISAN_EMAIL:-adrien2098@hotmail.fr}"
ARTISAN_EMAIL="${ARTISAN_EMAIL,,}"
ARTISAN_NAME="${SEED_ARTISAN_NAME:-Adrien}"
CONSUMER_EMAIL="${SEED_CONSUMER_EMAIL:-rijenththedon@gmail.com}"
CONSUMER_EMAIL="${CONSUMER_EMAIL,,}"
CONSUMER_NAME="${SEED_CONSUMER_NAME:-Rijenth}"

# SIRET de démonstration tant qu'Adrien n'a pas fourni le sien — le KYB est pré-validé, la
# vérification SIRENE ne repassera pas dessus.
ARTISAN_SIRET="${SEED_ARTISAN_SIRET:-73282932000074}"

ADMIN_PASSWORD="$(generate_password)"
REPAIRER_PASSWORD="$(generate_password)"
ARTISAN_PASSWORD="$(generate_password)"
CONSUMER_PASSWORD="$(generate_password)"

step "Seed $TARGET_ENV → $POSTGRES_CONTAINER/$PG_DB"

created="$(
  docker exec -i \
    -e PGOPTIONS=--client-min-messages=warning \
    "$POSTGRES_CONTAINER" \
    psql -U "$PG_USER" -d "$PG_DB" \
    -v ON_ERROR_STOP=1 --quiet --no-psqlrc --tuples-only --no-align \
    -v admin_email="$ADMIN_EMAIL" -v admin_name="$ADMIN_NAME" -v admin_password="$ADMIN_PASSWORD" \
    -v repairer_email="$REPAIRER_EMAIL" -v repairer_name="$REPAIRER_NAME" -v repairer_password="$REPAIRER_PASSWORD" \
    -v artisan_email="$ARTISAN_EMAIL" -v artisan_name="$ARTISAN_NAME" -v artisan_password="$ARTISAN_PASSWORD" \
    -v consumer_email="$CONSUMER_EMAIL" -v consumer_name="$CONSUMER_NAME" -v consumer_password="$CONSUMER_PASSWORD" \
    -v artisan_atelier="Atelier $ARTISAN_NAME" -v artisan_slug="atelier-$(printf '%s' "$ARTISAN_NAME" | tr '[:upper:]' '[:lower:]')" \
    -v artisan_city=Paris -v artisan_region="Île-de-France" \
    -v artisan_company="Atelier $ARTISAN_NAME" -v artisan_naf=14.13Z -v artisan_siret="$ARTISAN_SIRET" \
    -f - <"$SEED_DIR/001_accounts.sql"
)" || die "psql a échoué"

print_credential() {
  local email="$1" password="$2" role="$3"
  if grep -qxF "$email" <<<"$created"; then
    printf '  %-10s %-32s %s\n' "$role" "$email" "$password"
  else
    printf '  %-10s %-32s %s\n' "$role" "$email" "(compte préexistant — mot de passe inchangé)"
  fi
}

step "Comptes"
printf '  %-10s %-32s %s\n' "RÔLE" "EMAIL" "MOT DE PASSE"
print_credential "$ADMIN_EMAIL" "$ADMIN_PASSWORD" ADMIN
print_credential "$REPAIRER_EMAIL" "$REPAIRER_PASSWORD" REPAIRER
print_credential "$ARTISAN_EMAIL" "$ARTISAN_PASSWORD" ARTISAN
print_credential "$CONSUMER_EMAIL" "$CONSUMER_PASSWORD" CONSUMER

unset ADMIN_PASSWORD REPAIRER_PASSWORD ARTISAN_PASSWORD CONSUMER_PASSWORD

if [[ -z "$created" ]]; then
  warn "Aucun compte créé : tous existaient déjà."
else
  ok "Mots de passe affichés une seule fois — range-les dans un gestionnaire maintenant."
fi

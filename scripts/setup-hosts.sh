#!/usr/bin/env bash
# shellcheck source=./_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

HOSTS_FILE="/etc/hosts"
SENTINEL_START="# >>> lumiris-local-hosts >>>"
SENTINEL_END="# <<< lumiris-local-hosts <<<"

if grep -qF "$SENTINEL_START" "$HOSTS_FILE" 2>/dev/null; then
  ok "Bloc lumiris-local-hosts déjà présent dans $HOSTS_FILE."
  info "Pour réinstaller : supprime le bloc entre les sentinelles puis relance ce script."
  exit 0
fi

info "Ajout des vhosts Lumiris dans $HOSTS_FILE (sudo requis)..."

TMP_BLOCK="$(mktemp)"
trap 'rm -f "$TMP_BLOCK"' EXIT

{
  echo ""
  echo "$SENTINEL_START"
  service_hosts | while read -r host; do
    printf "127.0.0.1\t%s\n" "$host"
  done
  echo "$SENTINEL_END"
} > "$TMP_BLOCK"

if sudo tee -a "$HOSTS_FILE" >/dev/null < "$TMP_BLOCK"; then
  ok "Bloc ajouté dans $HOSTS_FILE."
else
  die "Échec de l'écriture dans $HOSTS_FILE."
fi

info "Validation : ping lumiris.local..."
if ping -c 1 -W 2 lumiris.local >/dev/null 2>&1; then
  ok "lumiris.local résout correctement vers 127.0.0.1."
else
  warn "Le ping a échoué — la résolution DNS peut être mise en cache. Réessaie dans quelques secondes."
fi

ok "setup-hosts terminé. Vhosts configurés : $(service_hosts | wc -l)"

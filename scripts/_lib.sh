#!/usr/bin/env bash
[[ -n "${_LUMIRIS_LIB_LOADED:-}" ]] && return 0
_LUMIRIS_LIB_LOADED=1

set -euo pipefail
IFS=$'\n\t'

GREEN=$'\033[1;32m'
RED=$'\033[1;31m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[1;34m'
NC=$'\033[0m'

info() { printf "%s[info]%s %s\n" "$BLUE"   "$NC" "$*"; }
ok()   { printf "%s[ ok ]%s %s\n" "$GREEN"  "$NC" "$*"; }
warn() { printf "%s[warn]%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s[fail]%s %s\n" "$RED"    "$NC" "$*" >&2; }

die() {
  err "$*"
  exit 1
}

step() {
  printf '\n%s══ %s ══%s\n' "$GREEN" "$*" "$NC"
}

confirm() {
  local prompt="${1:-Continue?}"
  read -r -p "$(printf '%s%s%s [yes/N] ' "$YELLOW" "$prompt" "$NC")" ans
  [[ "$ans" == "yes" ]] || die "aborted by user"
}

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LIB_DIR/.." && pwd)"
LOCAL_DIR="$ROOT/local"
SCRIPTS_DIR="$ROOT/scripts"
export ROOT LOCAL_DIR SCRIPTS_DIR

# Format: "label|host|description". Source de vérité pour setup-hosts.sh.
SERVICES=(
  "Site      |lumiris.local         |Vitrine (host:3000)"
  "Admin     |admin.lumiris.local   |Admin (host:3001)"
  "Mobile    |mobile.lumiris.local  |Mobile (host:3002)"
  "Client    |client.lumiris.local  |Client (host:3003)"
  "API       |api.lumiris.local     |API Spring Boot (host:8080)"
  "Traefik   |traefik.lumiris.local |Traefik dashboard"
  "MinIO     |minio.lumiris.local   |MinIO Console"
  "CDN       |cdn.lumiris.local     |MinIO S3 endpoint"
  "MailHog   |mailhog.lumiris.local |MailHog UI"
  "Grafana   |grafana.lumiris.local |Grafana (profile monitoring)"
  "pgAdmin   |pgadmin.lumiris.local |pgAdmin (profile tools)"
  "Redis UI  |redis.lumiris.local   |Redis Commander (profile tools)"
)

_trim() { local s="$*"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

service_field() {
  local entry="$1" idx="$2" IFS='|'
  read -r f1 f2 f3 <<<"$entry"
  case "$idx" in
    1) _trim "$f1" ;;
    2) _trim "$f2" ;;
    3) _trim "$f3" ;;
  esac
}

# One vhost per line, in declaration order. service_field does not terminate its
# output, so the newline is added here.
service_hosts() {
  local entry
  for entry in "${SERVICES[@]}"; do
    printf '%s\n' "$(service_field "$entry" 2)"
  done
}

# Args: url [timeout=2]; prints status code or "DOWN".
http_status() {
  local url="$1" timeout="${2:-2}"
  curl -k -s -o /dev/null -w '%{http_code}' --max-time "$timeout" "$url" 2>/dev/null || echo DOWN
}

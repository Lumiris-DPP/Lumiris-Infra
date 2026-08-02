#!/usr/bin/env bash
# shellcheck source=./_lib.sh
# Idempotent first-deploy orchestrator: hardens the box, installs Docker, then
# rolls out the first release. Images come from the registry — CI builds them.
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

readonly SOPS_ENV="$ROOT/prod/secrets/prod.env.sops"
readonly ANSIBLE_DIR="$ROOT/prod/ansible"
readonly ANSIBLE_INV="$ANSIBLE_DIR/inventories/prod/hosts.yml"

die() {
  err "$*"
  printf '%s[bootstrap] Fix the issue above, then re-run.%s\n' "$YELLOW" "$NC" >&2
  exit 1
}

step "1/6 Prereq check"
for bin in sops ansible-playbook docker; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin is not installed"
done

step "2/6 Runtime secrets"
[[ -f "$SOPS_ENV" ]] || die "$SOPS_ENV not found"
grep -q '^sops_' "$SOPS_ENV" || die "$SOPS_ENV is in cleartext — encrypt it before going anywhere near prod"
[[ -n "${SOPS_AGE_KEY_FILE:-}" ]] || die "SOPS_AGE_KEY_FILE is unset — point it at your age private key"
[[ -r "$SOPS_AGE_KEY_FILE" ]] || die "SOPS_AGE_KEY_FILE ($SOPS_AGE_KEY_FILE) is not readable"
sops --decrypt --input-type dotenv --output-type dotenv "$SOPS_ENV" >/dev/null \
  || die "sops decrypt failed — your age key is not on the recipient list"

step "3/6 Ansible inventory"
[[ -f "$ANSIBLE_INV" ]] || die "$ANSIBLE_INV not found — copy hosts.yml.example and fill it in"
grep -q 'REPLACE_ME' "$ANSIBLE_INV" && die "$ANSIBLE_INV still contains REPLACE_ME placeholders"

step "4/6 Release to deploy"
: "${API_TAG:?set API_TAG, e.g. API_TAG=v0.4.2}"
: "${FRONT_TAG:?set FRONT_TAG, e.g. FRONT_TAG=v0.4.2}"
info "Deploying lumiris-api:$API_TAG and front:$FRONT_TAG"

step "5/6 Ansible bootstrap (hardening + docker)"
confirm "Run the bootstrap playbook against the VPS?"
(cd "$ANSIBLE_DIR" && ansible-playbook playbooks/bootstrap.yml)

step "5b/6 Ansible deploy (first rollout)"
(cd "$ANSIBLE_DIR" && ansible-playbook playbooks/deploy.yml \
  -e api_image_tag="$API_TAG" -e front_image_tag="$FRONT_TAG")

step "6/6 Production seed"
confirm "Apply seed data (creates an admin user, plans, optional demo artisan)?"
"$ROOT/seed/apply-seed.sh" prod

step "Smoke tests"
DOMAIN="${DOMAIN:-lumiris.eu}"
for url in "https://$DOMAIN/" \
  "https://api.$DOMAIN/actuator/health/readiness" \
  "https://admin.$DOMAIN/" \
  "https://app.$DOMAIN/"; do
  if curl -fsSL -o /dev/null "$url"; then
    printf '  %s✓%s %s\n' "$GREEN" "$NC" "$url"
  else
    printf '  %s✗%s %s\n' "$RED" "$NC" "$url"
  fi
done

cat <<EOF

${GREEN}═══════════════════════════════════════════════════════════════════${NC}
${GREEN}  ✓ Prod bootstrap complete${NC}
${GREEN}═══════════════════════════════════════════════════════════════════${NC}

Next steps:
  1. Log in as the seeded admin once, then rotate the password.
  2. Pin the server host key for CI:
       ssh-keyscan -p <port> -H <host>
     and store the output in the DEPLOY_KNOWN_HOSTS repository secret.
  3. Later deploys go through the prod-deploy workflow, or:
       make prod-deploy API_TAG=vX.Y.Z FRONT_TAG=vX.Y.Z
EOF

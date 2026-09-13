#!/usr/bin/env bash
# Render the deploy templates into a repo. Never overwrites existing files.
#
# Web app (Traefik ingress):
#   scaffold.sh <repo-dir> --app NAME --port N --host-port N [--health /health] [--hostname h]
# Background service (no ingress, like a worker or cron-style daemon):
#   scaffold.sh <repo-dir> --app NAME --no-ingress
# Common: [--branch main] [--data-uid 1000] [--mem 256m]
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SKILL_DIR/scripts/lib.sh"
: "${GH_OWNER:?set GH_OWNER in $CONFIG}"

REPO="${1:?usage: see header of $0}"; shift
APP="" PORT="" HOST_PORT="" EXTRA_HOST="" BRANCH=main HEALTH=/health DATA_UID=1000 MEM=256m INGRESS=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-ingress) INGRESS=0; shift; continue ;;
    --app) APP=$2 ;; --port) PORT=$2 ;; --host-port) HOST_PORT=$2 ;;
    --hostname) EXTRA_HOST=$2 ;; --branch) BRANCH=$2 ;; --health) HEALTH=$2 ;;
    --data-uid) DATA_UID=$2 ;; --mem) MEM=$2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift 2
done
[[ "$APP" =~ ^[a-z0-9][a-z0-9-]{2,63}$ ]] || { echo "--app must be lowercase [a-z0-9-], 3-64 chars" >&2; exit 2; }

ROUTERS_FILE=$(mktemp) HEALTH_URL=""
trap 'rm -f "$ROUTERS_FILE"' EXIT
router() { # router <name> <hostname>
  cat >> "$ROUTERS_FILE" <<EOF
      - traefik.http.routers.$1.rule=Host(\`$2\`)
      - traefik.http.routers.$1.entrypoints=$TRAEFIK_ENTRYPOINT
      - traefik.http.routers.$1.tls.certresolver=$TRAEFIK_CERT_RESOLVER
      - traefik.http.routers.$1.service=$APP
EOF
}
if (( INGRESS )); then
  [[ -n "$PORT" && -n "$HOST_PORT" ]] || { echo "--port and --host-port are required (or pass --no-ingress)" >&2; exit 2; }
  EXTRA_HOST="${EXTRA_HOST:-${APP_DOMAIN:+$APP.$APP_DOMAIN}}"
  router "$APP" "$APP.$VPS_HOST"
  [[ -n "$EXTRA_HOST" ]] && router "$APP-custom" "$EXTRA_HOST"
  HEALTH_URL="http://127.0.0.1:$HOST_PORT$HEALTH"
fi

cd "$SKILL_DIR/templates"
find . -type f | while read -r rel; do
  dest="$REPO/${rel#./}"
  if [[ -e "$dest" ]]; then echo "skip (exists): ${rel#./}"; continue; fi
  mkdir -p "$(dirname "$dest")"
  if (( INGRESS )); then strip='/^#>>> ingress$/d; /^#<<< ingress$/d'
  else strip='/^#>>> ingress$/,/^#<<< ingress$/d'; fi
  # \x01 as the sed delimiter: values contain | (Traefik's `||`), / and &-free by construction.
  d=$'\x01'
  sed -e "$strip" \
      -e "/^{{ROUTER_LABELS}}\$/{r $ROUTERS_FILE" -e "d;}" \
      -e "s${d}{{APP}}${d}$APP${d}g" -e "s${d}{{PORT}}${d}$PORT${d}g" -e "s${d}{{HOST_PORT}}${d}$HOST_PORT${d}g" \
      -e "s${d}{{HEALTH_URL}}${d}$HEALTH_URL${d}g" \
      -e "s${d}{{BRANCH}}${d}$BRANCH${d}g" -e "s${d}{{DATA_UID}}${d}$DATA_UID${d}g" -e "s${d}{{MEM_LIMIT}}${d}$MEM${d}g" \
      -e "s${d}{{GH_OWNER}}${d}$GH_OWNER${d}g" \
      "$rel" > "$dest.tmp"
  mv "$dest.tmp" "$dest"
  [[ "$rel" == *.sh ]] && chmod +x "$dest"
  echo "wrote: ${rel#./}"
done

if grep -rnE '\{\{[A-Z_]+\}\}' "$REPO/deploy" "$REPO/.github/workflows/deploy.yml"; then
  echo "!! unrendered placeholders above" >&2; exit 1
fi

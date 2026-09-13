#!/usr/bin/env bash
# Remove a project from the VPS. Dry run by default; --apply to act.
#   1. docker compose down in /docker/<app> (containers + project network; images pruned)
#   2. archive /docker/<app> (data/, .env, compose) to /root/teardown-archives/, then delete it
#   3. delete CNAME <app>.$APP_DOMAIN via the API - only if it points at $VPS_HOST
#   4. revoke ~/.ssh/<app>_deploy from the VPS authorized_keys (backed up first)
# Leaves alone (prints commands instead): the GitHub repo, its GHCR package, the local key file.
#
# Usage: teardown.sh <app> [--apply] [--keep-dns] [--no-archive]
set -euo pipefail
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: teardown.sh <app> [--apply] [--keep-dns] [--no-archive]}"; shift
APPLY=0 KEEP_DNS=0 ARCHIVE=1
for a in "$@"; do
  case "$a" in --apply) APPLY=1 ;; --keep-dns) KEEP_DNS=1 ;; --no-archive) ARCHIVE=0 ;; *) echo "unknown arg: $a" >&2; exit 2 ;; esac
done
[[ "$APP" =~ ^[a-z0-9][a-z0-9-]{2,63}$ && "$APP" != traefik ]] || { echo "refusing app name: $APP" >&2; exit 2; }
run() { if (( APPLY )); then "$@"; else echo "  [dry run] would: $*"; fi; }
STAMP=$(date -u +%Y%m%dT%H%M%SZ)

echo "== 1-2. VPS project /docker/$APP"
vps_ssh "APP=$APP APPLY=$APPLY ARCHIVE=$ARCHIVE STAMP=$STAMP bash -s" <<'REMOTE'
set -euo pipefail
dir=/docker/$APP
if [[ ! -d "$dir" ]]; then echo "  no $dir - nothing to do"; exit 0; fi
echo "  contents:"; ls -la "$dir" | sed 's/^/    /'; du -sh "$dir/data" 2>/dev/null | sed 's/^/    data: /' || true
(cd "$dir" && docker compose ps --format '    {{.Name}} {{.Status}}') || true
if [[ "$APPLY" != 1 ]]; then
  echo "  [dry run] would: docker compose down --rmi all; $([[ $ARCHIVE == 1 ]] && echo "tar to /root/teardown-archives/$APP-$STAMP.tgz; ")rm -rf $dir"
  exit 0
fi
image=$(cd "$dir" && docker compose config --images 2>/dev/null | head -1)
(cd "$dir" && docker compose down --rmi all --remove-orphans)
# down --rmi only removes the current tag; older deploy tags of the same image linger.
if [[ -n "$image" ]]; then
  docker images "${image%:*}" -q | sort -u | xargs -r docker rmi -f >/dev/null && echo "  removed all ${image%:*} images"
fi
if [[ "$ARCHIVE" == 1 ]]; then
  install -d -m 700 /root/teardown-archives
  tar -C /docker -czf "/root/teardown-archives/$APP-$STAMP.tgz" "$APP"
  echo "  archived to /root/teardown-archives/$APP-$STAMP.tgz"
fi
rm -rf "$dir"
echo "  removed $dir"
REMOTE

echo "== 3. DNS $APP.${APP_DOMAIN:-<no APP_DOMAIN>}"
if (( KEEP_DNS )) || [[ -z "${APP_DOMAIN:-}" ]]; then
  echo "  skipped"
else
  TOKEN_FILE="${HOSTINGER_TOKEN_FILE:-$HOSTINGER_HOME/token}"
  [[ -n "${HOSTINGER_API_TOKEN:-}" ]] || HOSTINGER_API_TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
  API="https://developers.hostinger.com/api/dns/v1/zones/$APP_DOMAIN"
  api() { curl -sS --fail-with-body -H "Authorization: Bearer $HOSTINGER_API_TOKEN" -H "Content-Type: application/json" "$@"; }
  recs=$(api "$API" | jq -r --arg n "$APP" '.[] | select(.name==$n) | "\(.type) \([.records[].content]|join(","))"')
  if [[ -z "$recs" ]]; then
    echo "  no records named $APP"
  elif [[ "$recs" == "CNAME ${VPS_HOST%.}." || "$recs" == "CNAME ${VPS_HOST%.}" || "$recs" == "CNAME $APP.${VPS_HOST%.}." ]]; then
    echo "  found: $recs"
    run api -o /dev/null -X DELETE "$API" -d "$(jq -nc --arg n "$APP" '{filters: [{name: $n, type: "CNAME"}]}')"
    (( APPLY )) && { api "$API" | jq -e --arg n "$APP" 'any(.[]; .name==$n)' >/dev/null && echo "  !! still present" || echo "  deleted"; }
  else
    echo "  !! records for $APP don't point at this VPS - leaving them: $recs"
  fi
fi

echo "== 4. deploy key ~/.ssh/${APP}_deploy"
KEY="$HOME/.ssh/${APP}_deploy"
if [[ -f "$KEY.pub" ]]; then
  PUB=$(cat "$KEY.pub")
  if vps_ssh "grep -qxF '$PUB' ~/.ssh/authorized_keys"; then
    run vps_ssh "cp -p ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak-$STAMP && grep -vxF '$PUB' ~/.ssh/authorized_keys.bak-$STAMP > ~/.ssh/authorized_keys"
    (( APPLY )) && echo "  revoked (backup ~/.ssh/authorized_keys.bak-$STAMP on VPS)"
  else
    echo "  not in VPS authorized_keys"
  fi
  if [[ "$KEY" == "$VPS_ADMIN_KEY" ]]; then echo "  !! this is VPS_ADMIN_KEY - pick another admin key in config.env"; fi
else
  echo "  no local $KEY.pub - check authorized_keys for a '${APP}-deploy@' comment manually"
fi

cat <<EOF

Not touched - do these yourself if wanted (irreversible):
  rm ~/.ssh/${APP}_deploy ~/.ssh/${APP}_deploy.pub
  gh repo archive ${GH_OWNER:-<owner>}/$APP        # or: gh repo delete ${GH_OWNER:-<owner>}/$APP
  GHCR package: https://github.com/users/${GH_OWNER:-<owner>}/packages/container/$APP/settings
  Update ~/.hostinger/notes.md
EOF
(( APPLY )) || echo "Dry run. Re-run with --apply."

#!/usr/bin/env bash
# Create or update CNAME <name>.$APP_DOMAIN -> $VPS_HOST via the Hostinger API, touching no
# other records. Prints the zone diff and waits until public DNS resolves it.
#
# Usage: dns-cname.sh <name> [--target host] [--dry-run]
# Token: $HOSTINGER_API_TOKEN, else the file $HOSTINGER_TOKEN_FILE (default $HOSTINGER_HOME/token).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
: "${APP_DOMAIN:?set APP_DOMAIN in $CONFIG}"

NAME="${1:?usage: dns-cname.sh <name> [--target host] [--dry-run]}"; shift
TARGET="$VPS_HOST" DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in --target) TARGET=$2; shift ;; --dry-run) DRY=1 ;; *) echo "unknown arg: $1" >&2; exit 2 ;; esac
  shift
done

TOKEN_FILE="${HOSTINGER_TOKEN_FILE:-$HOSTINGER_HOME/token}"
if [[ -z "${HOSTINGER_API_TOKEN:-}" ]]; then
  [[ -r "$TOKEN_FILE" ]] || { echo "!! no HOSTINGER_API_TOKEN and no $TOKEN_FILE" >&2; exit 1; }
  HOSTINGER_API_TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
fi
API="https://developers.hostinger.com/api/dns/v1/zones/$APP_DOMAIN"
api() { curl -sS --fail-with-body -H "Authorization: Bearer $HOSTINGER_API_TOKEN" -H "Content-Type: application/json" "$@"; }
flat() { jq -r '.[] | "\(.type) \(.name) \(.ttl) \([.records[].content]|join(","))"' | sort; }

before=$(api "$API" | flat)
existing=$(grep -E "^[A-Z]+ $NAME " <<<"$before" || true)
[[ -n "$existing" ]] && echo "existing records for $NAME: $existing"
grep -qE "^(A|AAAA) $NAME " <<<"$before" && { echo "!! $NAME has A/AAAA records; a CNAME can't coexist - resolve manually" >&2; exit 1; }

BODY=$(jq -nc --arg n "$NAME" --arg t "${TARGET%.}." --argjson ttl "${DNS_TTL}" \
  '{overwrite: true, zone: [{name: $n, type: "CNAME", ttl: $ttl, records: [{content: $t}]}]}')
api -o /dev/null -X POST "$API/validate" -d "$BODY"
echo "valid: CNAME $NAME.$APP_DOMAIN -> ${TARGET%.}."
(( DRY )) && { echo "dry run - not applied"; exit 0; }

# overwrite:true replaces only records with this name+type (verified: rest of zone untouched).
api -o /dev/null -X PUT "$API" -d "$BODY"
diff <(echo "$before") <(api "$API" | flat) || true

for i in $(seq 1 30); do
  ip=$(dig +short "$NAME.$APP_DOMAIN" @1.1.1.1 | tail -1)
  [[ -n "$ip" ]] && { echo "resolves publicly: $NAME.$APP_DOMAIN -> $ip"; exit 0; }
  sleep 10
done
echo "!! not resolving on 1.1.1.1 after 5 min - check the zone in hPanel" >&2; exit 1

#!/usr/bin/env bash
# Read-only audit of the VPS: compose projects, routed hostnames, loopback/public ports,
# duplicate hostnames, stray networks. Safe to run any time.
# Usage: vps-audit.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

vps_ssh 'bash -s' <<'REMOTE'
set -uo pipefail
echo "== compose projects"
docker compose ls -a

echo; echo "== routed hostnames (from running container labels)"
routes=$(for c in $(docker ps -q); do
  name=$(docker inspect -f '{{.Name}}' "$c" | tr -d /)
  docker inspect -f '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' "$c" \
    | grep -E '^traefik\.http\.routers\.[^.]+\.rule=' \
    | grep -oE 'Host\(`[^`]+`\)' | sed -E "s/Host\(\`(.*)\`\)/\1 $name/"
done | sort)
echo "$routes" | column -t
dups=$(echo "$routes" | awk '{print $1}' | sort | uniq -d)
[[ -n "$dups" ]] && echo "!! hostname claimed by more than one container: $dups"

echo; echo "== published ports"
docker ps --format '{{.Names}}\t{{.Ports}}' | column -t -s $'\t'
docker ps --format '{{.Names}} {{.Ports}}' | grep -E '0\.0\.0\.0|\[::\]' \
  | sed 's/^/!! public (bypasses Traefik TLS): /'

echo; echo "== user-defined networks and attached containers"
for n in $(docker network ls --filter driver=bridge --format '{{.Name}}' | grep -v '^bridge$'); do
  printf '%-40s %s\n' "$n" "$(docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' "$n")"
done

echo; echo "== memory"
free -h | head -2
docker stats --no-stream --format '{{.Name}}\t{{.MemUsage}}' | column -t -s $'\t'
REMOTE

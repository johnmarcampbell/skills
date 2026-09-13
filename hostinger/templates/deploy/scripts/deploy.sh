#!/usr/bin/env bash
# Runs ON THE VPS, invoked over SSH by .github/workflows/deploy.yml after it rsyncs
# deploy/ to /docker/{{APP}}/. Self-bootstrapping: the first run creates data/ and .env.
# Usage: IMAGE_TAG={{BRANCH}}-<sha> /docker/{{APP}}/scripts/deploy.sh
set -euo pipefail

cd "$(dirname "$0")/.."

: "${IMAGE_TAG:?IMAGE_TAG is required (e.g. {{BRANCH}}-abc1234)}"
# Empty for services without HTTP ingress: then success = container running (and
# healthy, if the image defines a HEALTHCHECK).
HEALTH_URL="{{HEALTH_URL}}"

# .env is VPS-local (runtime secrets live here too). Only the IMAGE_TAG line is managed
# here, so reboots and manual `docker compose up -d` keep the last-deployed image.
touch .env
chmod 600 .env
sed -i '/^IMAGE_TAG=/d' .env
echo "IMAGE_TAG=${IMAGE_TAG}" >> .env

# Create the bind-mount source with the container user's ownership; docker would
# otherwise create it root-owned and a non-root app could not write to it.
install -d -o {{DATA_UID}} -g {{DATA_UID}} data

echo "==> Pulling ${IMAGE_TAG}"
docker compose pull

echo "==> Restarting stack"
docker compose up -d --remove-orphans

healthy() {
  if [[ -n "$HEALTH_URL" ]]; then
    curl -fsS -m 3 "$HEALTH_URL" >/dev/null 2>&1
  else
    local s
    s=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' {{APP}} 2>/dev/null)
    [[ "$s" == healthy || "$s" == running ]]
  fi
}

echo "==> Waiting for ${HEALTH_URL:-container {{APP}} to be running/healthy}"
for i in $(seq 1 30); do
  if healthy; then
    echo "==> Healthy after ${i} checks"
    docker image prune -f >/dev/null
    exit 0
  fi
  sleep 5
done

echo "!! {{APP}} did not become healthy within 150s" >&2
docker compose ps >&2
docker compose logs --tail 100 >&2
exit 1

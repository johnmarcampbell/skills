#!/usr/bin/env bash
# One-time: give a GitHub repo SSH deploy access to the VPS.
#   1. generate ~/.ssh/<app>_deploy (ed25519, no passphrase) if missing
#   2. append its public key to authorized_keys on the VPS (idempotent, via VPS_ADMIN_KEY)
#   3. set SSH_HOST / SSH_USER / SSH_PRIVATE_KEY / SSH_KNOWN_HOSTS repo secrets via gh
#
# Usage: setup-deploy-access.sh <app> <owner/repo>
set -euo pipefail
source "$(dirname "$0")/lib.sh"

APP="${1:?usage: setup-deploy-access.sh <app> <owner/repo>}"
REPO="${2:?usage: setup-deploy-access.sh <app> <owner/repo>}"
KEY="$HOME/.ssh/${APP}_deploy"

if [[ ! -f "$KEY" ]]; then
  ssh-keygen -t ed25519 -N '' -C "${APP}-deploy@github-actions" -f "$KEY" >/dev/null
  echo "generated $KEY"
fi

PUB=$(cat "$KEY.pub")
vps_ssh "grep -qxF '$PUB' ~/.ssh/authorized_keys || echo '$PUB' >> ~/.ssh/authorized_keys"
ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY" "$VPS_USER@$VPS_HOST" true
echo "deploy key works against $VPS_HOST"

gh secret set SSH_HOST        -R "$REPO" -b "$VPS_HOST"
gh secret set SSH_USER        -R "$REPO" -b "$VPS_USER"
gh secret set SSH_PRIVATE_KEY -R "$REPO" < "$KEY"
ssh-keyscan -H "$VPS_HOST" 2>/dev/null | gh secret set SSH_KNOWN_HOSTS -R "$REPO"
echo "secrets set on $REPO"

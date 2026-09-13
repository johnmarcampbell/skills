# Sourced by the other scripts: loads the user's config and defines vps_ssh.
HOSTINGER_HOME="${HOSTINGER_HOME:-$HOME/.hostinger}"
CONFIG="${HOSTINGER_SKILL_CONFIG:-$HOSTINGER_HOME/config.env}"
if [[ ! -f "$CONFIG" ]]; then
  echo "!! no config at $CONFIG - copy the skill's config.example.env there and fill it in" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONFIG"
: "${VPS_HOST:?set VPS_HOST in $CONFIG}" "${VPS_USER:=root}" "${VPS_ADMIN_KEY:?set VPS_ADMIN_KEY in $CONFIG}"
VPS_ADMIN_KEY="${VPS_ADMIN_KEY/#\~/$HOME}"
: "${TRAEFIK_ENTRYPOINT:=websecure}" "${TRAEFIK_CERT_RESOLVER:=letsencrypt}" "${DNS_TTL:=3600}"

vps_ssh() {
  ssh -o BatchMode=yes -o IdentitiesOnly=yes -i "$VPS_ADMIN_KEY" "$VPS_USER@$VPS_HOST" "$@"
}

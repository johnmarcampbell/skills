# How a Hostinger Docker VPS fits together

## Docker Manager = compose projects under /docker

hPanel's Docker Manager is a UI over plain Docker Compose. Each project is a directory
`/docker/<project>/` containing `docker-compose.yml` and a `.env` (the GUI's "Environment" box).
`docker compose ls -a` on the VPS shows the same list as the GUI. GUI-created projects also get a
`.build.log`. Anything you put in `/docker/<name>/` and `docker compose up -d` shows up in the GUI.

Conventions worth keeping:
- State as a bind mount beside the compose file (`./data:/data`) so Hostinger's VPS backups cover it.
- A bind mount masks ownership set in the image; the host dir must be owned by the container's UID.
- `COMPOSE_PROJECT_NAME` defaults to the directory name; GUI templates use it in label names.

## Traefik

Hostinger's Docker VPS template runs Traefik as its own project (commonly `/docker/traefik`). Check
which of the two variants you have:

| Variant | How to tell | What app containers need |
|---|---|---|
| **Host-networked** (older) | `network_mode: host` in its compose; no `traefik-proxy` network | Nothing - Traefik reaches every bridge network directly. Do **not** add `networks:` |
| **Proxy network** (newer catalog) | a `traefik-proxy` (or similar) external network exists | Join that external network, and set `traefik.docker.network=<it>` label |

The templates assume host-networked. For the proxy-network variant add to the service:
`networks: [traefik-proxy]`, top-level `networks: {traefik-proxy: {external: true}}`, and the
`traefik.docker.network` label.

Discovery is label-based with `exposedbydefault=false`, so only containers with
`traefik.enable=true` are routed. Typical command flags: `web` (:80, redirects to https) and
`websecure` (:443) entrypoints, ACME resolver `letsencrypt` using the HTTP-01 challenge.

### Label anatomy

```yaml
labels:
  - traefik.enable=true
  - traefik.http.services.<app>.loadbalancer.server.port=<container port>
  - traefik.http.routers.<app>.rule=Host(`<app>.srvNNN.hstgr.cloud`)
  - traefik.http.routers.<app>.entrypoints=websecure
  - traefik.http.routers.<app>.tls.certresolver=letsencrypt
  - traefik.http.routers.<app>.service=<app>
  - traefik.http.routers.<app>-custom.rule=Host(`<app>.example.com`)
  - ... same three lines for <app>-custom
```

- Router and service names are global across the VPS. Copy-pasting labels between projects
  without renaming them causes collisions and hostname hijacks - `vps-audit.sh` flags duplicate hostnames.
- A service with labels but no port (and no `EXPOSE`) logs `port is missing` every poll. If a
  container has no HTTP server, remove its Traefik labels entirely.

### Certificates (the sharp edges)

- **One certificate per router.** Every `Host()` in a router's rule goes on one ACME order. If any
  hostname fails validation (e.g. NXDOMAIN because the CNAME doesn't exist yet), *no* certificate is
  issued for any of them and Traefik serves its self-signed default. Hence one router per hostname.
  This only bites when a certificate is *requested*: first issuance, or renewal (Traefik renews
  90-day certs ~30 days before expiry). A combined cert that's already issued keeps working - but if one
  of its hostnames loses DNS later, the renewal fails and every hostname on it expires together.
  Inspect what a live cert covers: `echo | openssl s_client -connect H:443 -servername H 2>/dev/null | openssl x509 -noout -dates -ext subjectAltName`.
- Traefik reuses a stored cert that covers a hostname, so a cert can list hostnames that are no longer
  in any router (left over from an earlier rule).
- **No automatic retry.** After a failure Traefik tries again only when the router config changes
  (container recreated, Traefik restarted).
- **Rate limits.** Let's Encrypt allows 5 failed validations per hostname per hour and 50 certificates
  per registered domain per week. Don't loop deploys against a hostname whose DNS isn't ready.
- HTTP-01 needs port 80 reachable from the internet and DNS pointing at the VPS.
- The `srvNNNNNN.hstgr.cloud` hostname has wildcard DNS, so `<anything>.srvNNNNNN.hstgr.cloud`
  works with no DNS changes - useful as the always-available hostname.

### Health checks hide containers

Traefik's docker provider skips containers whose Docker health status is `starting` or `unhealthy`.
During every restart the app 404s until the first successful check. Keep that window short in the
Dockerfile: `HEALTHCHECK --interval=30s --start-period=20s --start-interval=2s ...`.

## Ports

Traefik doesn't need published ports. A `ports: - "8000:8000"` binds `0.0.0.0` and exposes the app
over plain HTTP to the internet, bypassing TLS and any Traefik middleware. Publish only
`127.0.0.1:<port>:<container port>`, with a host port unique on the VPS, for health checks and
`ssh -L <port>:127.0.0.1:<port>` admin access.

## SSH and networking

- Hostinger VPS hostnames have both A and AAAA records. Some GitHub Actions runners have no IPv6
  route; SSH then hangs ~2 minutes and fails with `Network is unreachable`. Force IPv4 in CI
  (`AddressFamily inet`), as the workflow template does.
- `authorized_keys` for root holds one line per deploy key; comment each key `<app>-deploy@...` so
  it's clear what to revoke.

## Memory

Common plans are small (e.g. 4 GB). Give every service a `mem_limit` and check `docker stats` before
adding a project.

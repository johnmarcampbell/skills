# Troubleshooting

Start with `scripts/vps-audit.sh`, then Traefik's logs:
`docker logs --since 30m <traefik container> 2>&1 | grep -iE 'acme|<app>|error'`.

| Symptom | Likely cause | Fix |
|---|---|---|
| Browser cert warning; `curl -w '%{ssl_verify_result}'` = 20 | ACME failed; Traefik serves its self-signed default. Log: `Unable to obtain ACME certificate` | Read the error. NXDOMAIN -> create/fix DNS, wait for `dig` to resolve, then `docker compose up -d --force-recreate`. If several hosts share one router, split into one router per host |
| `404 page not found` (Traefik's plain 404) | No router matches: labels missing/typo, `traefik.enable` absent, container health `starting`/`unhealthy`, or wrong hostname | `docker inspect <c> --format '{{json .Config.Labels}}'`; `docker inspect -f '{{.State.Health.Status}}' <c>` |
| 404 for ~20-30s after each deploy/restart | Health status `starting` hides the container from Traefik | Shorter `--start-interval` / `--start-period` in the Dockerfile HEALTHCHECK |
| `502 Bad Gateway` | Wrong `loadbalancer.server.port`, or the app listens on 127.0.0.1 inside the container | App must bind `0.0.0.0`; port label = container port |
| Another app's content on my hostname | Two routers claim the same `Host()` (copy-pasted labels) | `vps-audit.sh` duplicate check; fix the offending project's labels |
| Traefik log spams `port is missing` | Service has Traefik labels but no port (e.g. a background worker) | Remove its Traefik labels |
| Deploy job: `ssh: connect ... Network is unreachable` after ~2 min | Runner has no IPv6; host resolved to AAAA | `AddressFamily inet` in the runner's ssh config (template does this) |
| Deploy job: `Permission denied (publickey)` | Key not in VPS `authorized_keys`, or secret has wrong key / mangled newlines | Re-run `setup-deploy-access.sh` (idempotent) |
| Deploy job: `Host key verification failed` | `SSH_KNOWN_HOSTS` missing/stale (VPS rebuilt) | Re-run `setup-deploy-access.sh` |
| `docker compose pull`: `denied` / `unauthorized` | VPS isn't logged in to GHCR, or the token lacks `read:packages` / expired | User runs `docker login ghcr.io -u <owner>` on the VPS |
| `pull access denied ... :main` on first deploy | Image never pushed (build job failed or wrong owner/name) | Check the build-push job; image names must be lowercase |
| App can't write `/data` (`EACCES`, SQLite readonly) | Bind-mount dir owned by root | `chown -R <uid>:<uid> /docker/<app>/data`; set `--data-uid` correctly |
| Edits made on the VPS disappeared | Deploy rsyncs `deploy/` with `--delete` | Make the change in the repo |
| Health check timeout in `deploy.sh` | App crashed, slow start, wrong health path/port | `deploy.sh` prints `compose ps` + last 100 log lines; `docker compose logs -f` on the VPS |

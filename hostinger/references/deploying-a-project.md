# Deploying a project to the VPS

End state: merging to a branch builds an image to GHCR and deploys it to `/docker/<app>/` on the
VPS; the app is served at `https://<app>.$VPS_HOST` and (optionally) `https://<app>.$APP_DOMAIN`.

Pipeline: `push to branch -> build-push (GHCR :<branch>, :<branch>-<sha>) -> rsync deploy/ -> ssh deploy.sh -> compose pull/up -> health check`.

The first deploy bootstraps the VPS side itself (creates `/docker/<app>/`, `data/`, `.env`) - there is no separate bootstrap script to run.

## 0. Preconditions (check once per VPS, not per project)

- Config loaded (`SKILL.md` §1). `scripts/vps-audit.sh` runs.
- Traefik is running and its entrypoint/resolver names match the config (`docker inspect <traefik> --format '{{json .Config.Cmd}}'`).
- The VPS can pull private GHCR images: `/root/.docker/config.json` has a `ghcr.io` entry (a classic PAT with `read:packages` from the owner covers all their private packages). If not, the user runs `docker login ghcr.io -u <owner>` on the VPS - never type the token yourself.
- `gh auth status` is logged in as an account that can create the repo and set secrets.

## 1. Decide the shape (ask only what you can't infer)

| Decision | Default / how to choose |
|---|---|
| App name | lowercase `[a-z0-9-]`; becomes container, compose project, image, `/docker/<app>`, subdomain |
| Ingress? | Web app -> yes. Worker/daemon/cron with no HTTP server -> `--no-ingress` |
| Container port | What the app listens on (`PORT` env is passed in) |
| Host loopback port | Unique on the VPS - run `vps-audit.sh` and pick a free one; note it in `notes.md` |
| Custom hostname | `<app>.$APP_DOMAIN` unless told otherwise (`--hostname` to override) |
| Deploy branch | `main` (`--branch production` for a gated flow) |
| Health path | `/health`; the app must return 2xx without auth. Workers: container state / image HEALTHCHECK |
| Data UID | UID the container runs as (node images: 1000). Owns `/docker/<app>/data` |
| Memory | `256m` default; check `vps-audit.sh` memory section - it's a small shared box |

The repo needs a `Dockerfile` at its root that builds a `linux/amd64` image, runs as non-root, and
stores state under `DATA_DIR=/data`. Add `.dockerignore` entries for `.git`, `data`, `deploy`, `.github`.

## 2. Scaffold

```bash
~/.claude/skills/hostinger/scripts/scaffold.sh <repo-dir> --app <app> --port 3000 --host-port <free>
# or: ... --app <app> --no-ingress
```

Review the rendered `deploy/docker-compose.yml`. Add app-specific env vars under `environment:`
(non-secret) - secrets go in `/docker/<app>/.env` on the VPS (step 6), never in git.

## 3. DNS - before the first push

Traefik requests the certificate as soon as the router appears. If the custom hostname doesn't
resolve yet, issuance fails, Traefik does not retry until the container is recreated, and every
failed attempt counts toward Let's Encrypt's failed-validation limit (5 per hostname per hour).

- Record: `CNAME <app>` -> `$VPS_HOST` in the `$APP_DOMAIN` zone.
- With an API token: `~/.claude/skills/hostinger/scripts/dns-cname.sh <app>` (touches only that record; public
  resolvers typically see it within seconds).
- Without one: hPanel -> Domains -> `$APP_DOMAIN` -> DNS / Nameservers -> add record.
- Verify: `dig +short <app>.$APP_DOMAIN` returns the VPS IP. The `<app>.$VPS_HOST` name needs no DNS work.

If the user wants to push before DNS exists, that's fine - the template uses one router per
hostname, so only the custom hostname lacks a certificate. After DNS resolves, recreate the container
(`docker compose up -d --force-recreate` in `/docker/<app>`) or just deploy again.

## 4. GitHub repo and deploy access - before the first push

Create the repo first if needed (`gh repo create <owner>/<app> --private`), then:

```bash
~/.claude/skills/hostinger/scripts/setup-deploy-access.sh <app> <owner>/<app>
```

This must happen before the first push, or the first deploy job fails for lack of secrets.
One key per repo, so a leaked key can be revoked without touching other projects.

## 5. Push and watch

```bash
git push -u origin main
gh run watch "$(gh run list -R <owner>/<app> -L1 --json databaseId -q '.[0].databaseId')" -R <owner>/<app> --exit-status
```

## 6. Verify

```bash
curl -sS -o /dev/null -w '%{http_code} verify=%{ssl_verify_result}\n' https://<app>.$VPS_HOST/
curl -sS -o /dev/null -w '%{http_code} verify=%{ssl_verify_result}\n' https://<app>.$APP_DOMAIN/
~/.claude/skills/hostinger/scripts/vps-audit.sh     # new hostnames listed once, port loopback-only
```

`verify=0` means a real certificate; `verify=20` means Traefik's self-signed default (see troubleshooting).
Runtime secrets: have the user add them to `/docker/<app>/.env` (or do it with their go-ahead), then
redeploy or `docker compose up -d` there. `deploy.sh` preserves every line except `IMAGE_TAG`.

Finally, record the app, its host port and hostnames in `~/.hostinger/notes.md`.

## Adapting an existing project that's already on the VPS

Projects created in the Docker Manager GUI typically have hand-edited compose files with
`${TRAEFIK_HOST}` in labels, public `ports:`, and sometimes stray `networks:`. To bring one under
this flow: scaffold into the repo, port over its real env vars/volume paths (check the live file -
e.g. data may mount at `/app/data`, not `/data`), keep the same app name so `/docker/<app>/data` and
`.env` are reused, and confirm with the user before the first deploy replaces the live compose file.

## Tearing a project down

Confirm scope with the user first. Then:

```bash
~/.claude/skills/hostinger/scripts/teardown.sh <app>            # dry run: shows what exists and what would go
~/.claude/skills/hostinger/scripts/teardown.sh <app> --apply
```

It stops the stack, removes every tag of the app's image (`compose down --rmi` only removes the
current one), archives `/docker/<app>` - including `data/` and `.env` secrets - to
`/root/teardown-archives/<app>-<stamp>.tgz` (`--no-archive` to skip; delete old archives when no longer
wanted), deletes the CNAME if it points at the VPS (`--keep-dns` to skip), and removes the deploy key
from `authorized_keys` (backup kept beside it).

Expect the hostname to keep resolving on public resolvers until the record's TTL expires; check the
authoritative nameservers (`dig +short NS $APP_DOMAIN`, then `dig +short <app>.$APP_DOMAIN @<ns>`).
`<app>.$VPS_HOST` keeps resolving forever (wildcard) and returns Traefik's 404.

Irreversible leftovers the script only prints - ask before doing any: delete the local key
(`~/.ssh/<app>_deploy*`), archive or delete the GitHub repo, delete the GHCR package (GitHub UI, or
`gh api -X DELETE /user/packages/container/<app>`). Both need scopes `gh` lacks by default - the user
runs `gh auth refresh -h github.com -s delete_repo,read:packages,delete:packages` (browser flow), then
confirm with `gh auth status`. Deleting the repo does not delete its package; delete both.
Update `~/.hostinger/notes.md`.

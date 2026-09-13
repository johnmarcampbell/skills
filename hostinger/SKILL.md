---
name: hostinger
description: Work with a Hostinger Docker VPS and Hostinger-managed DNS - deploy a GitHub project as a Docker Manager project behind the VPS's shared Traefik (compose file, GHCR image, deploy-on-merge GitHub Actions workflow, SSH deploy key, DNS CNAME, Let's Encrypt), audit or fix existing projects on the box, and use the Hostinger API (DNS records, VPS Docker Manager). Use when the user mentions Hostinger, hPanel, their VPS, srvNNNNNN.hstgr.cloud, Docker Manager, Traefik routing/certificates on the VPS, or deploying/hosting a project "on the VPS".
---

# Hostinger

## 1. Load the user's setup first

Nothing about the user's host lives in this skill. Read their config before doing anything:

- `~/.hostinger/config.env` (override the dir with `$HOSTINGER_HOME`) - VPS host/user, admin SSH key, GHCR owner, app domain, Traefik names. Scripts source it via `scripts/lib.sh`.
- `~/.hostinger/token` (optional, mode 600) - Hostinger API token for DNS/API work (or `$HOSTINGER_API_TOKEN`). Never print it.
- `~/.hostinger/notes.md` (optional) - free-form notes: what runs on the box, ports in use, quirks, history. Read it; append to it when you learn something durable about their setup.

If the config is missing, copy `config.example.env` there and fill it in with the user (ask for values you can't discover; `hostname -f` on the VPS gives `VPS_HOST`).

## 2. Ground rules

- **The VPS is shared production.** Read-only inspection (`scripts/vps-audit.sh`, `docker ps`, logs) is always fine. Changing or restarting a project other than the one you were asked about needs the user's explicit OK; back up a compose file (`cp -p f f.bak-YYYYMMDD`) before editing it.
- **Repo is the source of truth.** A project's `deploy/` dir is rsynced to `/docker/<app>/` on each deploy, so edits made on the VPS or in the Docker Manager GUI are silently reverted. Fix things in the repo.
- **No public ports, no shared networks.** Web apps publish only `127.0.0.1:<unique port>`; Traefik reaches containers directly. Not every project needs ingress - background workers get no Traefik labels and no ports at all.
- **DNS before first deploy** for any custom hostname (see certificates in the reference).

## 3. Pick the reference for the task

| Task | Read |
|---|---|
| Deploy a new GitHub project to the VPS / add deploy-on-merge to an existing one | [references/deploying-a-project.md](references/deploying-a-project.md) |
| Understand how the VPS, Docker Manager and Traefik fit together; certificates; conventions | [references/vps-and-traefik.md](references/vps-and-traefik.md) |
| Something is broken (404, bad cert, deploy fails, container unhealthy) | [references/troubleshooting.md](references/troubleshooting.md) |
| Automate DNS records or Docker Manager via the Hostinger API / CLI / MCP | [references/hostinger-api.md](references/hostinger-api.md) |

## 4. Scripts

All read `config.env`. Run from anywhere.

| Script | Does | Side effects |
|---|---|---|
| `scripts/vps-audit.sh` | Projects, routed hostnames (flags duplicates), published ports (flags public ones), networks, memory | none (read-only) |
| `scripts/scaffold.sh <repo> --app N --port P --host-port H` / `--no-ingress` | Renders `templates/` into a repo: `deploy/docker-compose.yml`, `deploy/scripts/deploy.sh`, `.github/workflows/deploy.yml`. Never overwrites | writes files in the repo |
| `scripts/dns-cname.sh <name> [--dry-run]` | Creates/updates CNAME `<name>.$APP_DOMAIN` -> `$VPS_HOST` via the API (only that record), waits for public resolution | DNS zone |
| `scripts/setup-deploy-access.sh <app> <owner/repo>` | Generates `~/.ssh/<app>_deploy`, authorizes it on the VPS, sets the 4 repo secrets | VPS `authorized_keys`, GitHub secrets |

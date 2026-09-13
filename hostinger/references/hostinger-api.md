# Hostinger API (DNS, VPS, Docker Manager)

Source: official OpenAPI spec v1.51.0 (`https://developers.hostinger.com/openapi/openapi.json`,
mirrored at `github.com/hostinger/api`). Items marked **UNVERIFIED** were not confirmed against the
live API - test with `validate` endpoints or read-only calls first.

## Auth

- Token: hPanel -> Profile -> API (`https://hpanel.hostinger.com/profile/api`). Tokens carry the
  owner's full permissions; set an expiry. The user creates it - never ask them to paste it in chat;
  have them export `HOSTINGER_API_TOKEN` in their shell or keep it in a secret store.
- Stored at `~/.hostinger/token` by convention (scripts read it); strip whitespace when reading.
- Headers: `Authorization: Bearer $HOSTINGER_API_TOKEN`, `Content-Type: application/json`.
- Base URL: `https://developers.hostinger.com`. Pagination `?page=N` (50/page).
- Errors: JSON `{error, correlation_id}`; 422 validation; 429 rate limited (limits not published;
  repeated violations can temporarily block the IP).

## DNS - `/api/dns/v1`

| Method | Path | Body |
|---|---|---|
| GET | `/api/dns/v1/zones/{domain}` | - -> `[{name, type, ttl, records:[{content, is_disabled}]}]` |
| PUT | `/api/dns/v1/zones/{domain}` | `{overwrite?: bool (default true), zone:[{name, type, ttl?, records:[{content}]}]}` |
| POST | `/api/dns/v1/zones/{domain}/validate` | same as PUT; 200 ok / 422 invalid |
| DELETE | `/api/dns/v1/zones/{domain}` | `{filters:[{name, type}]}` - deletes all records with that name+type |
| POST | `/api/dns/v1/zones/{domain}/reset` | resets zone to defaults - **never** without explicit user request |
| GET | `/api/dns/v1/snapshots/{domain}` | list snapshots (take note of the latest before changes) |
| POST | `/api/dns/v1/snapshots/{domain}/{snapshotId}/restore` | roll back |

- `name` is relative (`@` = apex). `ttl` is integer seconds.
- `overwrite: true` (the default!) replaces records matching each *name+type* you send; other
  records in the zone are untouched (verified live 2026-09: zone diff showed only the new record).
  `false` appends / updates TTLs. PUT returns `{"message":"Request accepted"}`; new records resolved on
  1.1.1.1 within ~10s. `scripts/dns-cname.sh` wraps this.
- CNAME target: spec examples use a trailing dot (`target.tld.`). Terraform provider normalizes
  both forms.

Add or update one CNAME (always validate, then PUT, then read back):

```bash
source ~/.hostinger/config.env
APP=myapp
BODY=$(printf '{"overwrite":true,"zone":[{"name":"%s","type":"CNAME","ttl":%s,"records":[{"content":"%s."}]}]}' "$APP" "$DNS_TTL" "$VPS_HOST")
H=(-H "Authorization: Bearer $HOSTINGER_API_TOKEN" -H "Content-Type: application/json")
API=https://developers.hostinger.com/api/dns/v1/zones/$APP_DOMAIN
curl -sS "${H[@]}" "$API" | jq --arg n "$APP" '.[] | select(.name==$n)'   # anything already there?
curl -sS "${H[@]}" -X POST "$API/validate" -d "$BODY"
curl -sS "${H[@]}" -X PUT  "$API" -d "$BODY"
curl -sS "${H[@]}" "$API" | jq --arg n "$APP" '.[] | select(.name==$n)'
```

Delete: `curl -sS "${H[@]}" -X DELETE "$API" -d '{"filters":[{"name":"myapp","type":"CNAME"}]}'`

## VPS - `/api/vps/v1`

- `GET /api/vps/v1/virtual-machines` -> `[{id, hostname, state, plan, ...}]`; match `hostname` to
  `$VPS_HOST` to get the numeric id. (`POST` on the same path *purchases* a VM - never call it.)
- `GET /api/vps/v1/virtual-machines/{id}/actions/{actionId}` - poll async actions
  (`state`: success/error/delayed/sent/created).

### Docker Manager - `/api/vps/v1/virtual-machines/{id}/docker`

| Method | Path | Notes |
|---|---|---|
| GET | `…/docker` | projects `[{name, status, state, path, containers[]}]` |
| POST | `…/docker` | create **or replace** a project: `{project_name, content, environment}` -> Action |
| GET | `…/docker/{project}` | `{content: compose YAML, environment: "K=V\n..."}` |
| GET | `…/docker/{project}/containers` | containers + stats |
| GET | `…/docker/{project}/logs` | last 300 lines per service |
| POST | `…/docker/{project}/start` / `stop` / `restart` | no body |
| POST | `…/docker/{project}/update` | no body; pull latest images + recreate (volumes kept) |
| DELETE | `…/docker/{project}/down` | removes containers, networks, **volumes and images** - destructive |

- `content` (max 8192 chars): compose YAML, a `https://github.com/user/repo` URL (reads
  `docker-compose.yaml` on the **master** branch), or any URL returning compose YAML.
- `environment` (max 8192 chars): dotenv string. Where it's written on disk is **UNVERIFIED**.
- Projects live at `/docker/<project>/` per the spec's example `path`.

Relevance to the SSH/rsync deploy flow: the API is an alternative for read-only status and logs
without SSH, and for projects whose whole config fits in one compose file. Creating with the same
name replaces the project, which would clobber files the rsync flow manages - don't mix the two for
one project.

## Tooling

- **CLI** `hostinger` (`brew install hostinger/tap/hostinger`; token via `HOSTINGER_API_TOKEN` or
  `~/.hostinger.yaml`): `hostinger vps vm list`, `hostinger dns records list|update|validate|delete <domain>`
  (`--zone '<json>' --overwrite`), `hostinger vps docker list|create|get|logs|restart|update|delete <vm-id>`.
  Exact positional args for project subcommands **UNVERIFIED** - check `--help`.
- **MCP server**: hosted `claude mcp add --transport http hostinger https://mcp.hostinger.com` (OAuth),
  or `npm i -g @hostinger/mcp` (Node 24+; `hostinger-dns-mcp`, `hostinger-vps-mcp`). Tools include
  `DNS_getDNSRecordsV1`, `DNS_updateDNSRecordsV1`, `DNS_validateDNSRecordsV1`, `VPS_getProjectListV1`,
  `VPS_getProjectLogsV1`, `VPS_createNewProjectV1`.
- **Terraform** `hostinger/terraform-provider-hostinger`: `hostinger_dns_record` (note: `overwrite`
  defaults to `false` there, opposite of the API). No Docker resource.

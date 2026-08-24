# Local Dev Setup (custom ports + Node fixes)

For plain copy-pasteable steps to get running, see [RUNNING_LOCALLY.md](RUNNING_LOCALLY.md). This doc covers the reasoning behind them.

This documents everything changed to get Openpanel running via `pnpm dev` on a
machine where common ports (5432, 6379, 3000, ...) are already taken by other
services, plus two unrelated bugs that were hit and fixed along the way.
Use this to reproduce the setup on another laptop or an EC2 box.

## 0. Prerequisites

- **pnpm**, not yarn/npm. This repo uses pnpm workspaces (`workspace:*` deps,
  `packageManager: pnpm@10.6.2` in root `package.json`) — other package
  managers won't resolve internal packages correctly.
- **Node 24.15.0** (see "Node version" section below for why this exact
  version matters). Install via nvm: `nvm install 24.15.0`.
- Docker (for Postgres/Redis/ClickHouse/Redpanda).

## 1. Node version

Two Node incompatibilities were found in this codebase's current dependencies:

- **Node 20.x / 22.1.x**: `apps/api` crashes on startup —
  `TypeError: webidl.util.markAsUncloneable is not a function` from
  `undici@8.10.0`. The internal Node webidl API it needs isn't present yet.
- **Node 26.x**: crashes differently — `Cannot read properties of undefined
  (reading 'prototype')` in `buffer-equal-constant-time` (used by `jwa` /
  JWT signing). `Buffer.SlowBuffer` was removed in this Node version and a
  legacy dependency still calls it.
- **Node 24.15.0**: confirmed working — API starts cleanly.

A root `.nvmrc` now pins `24.15.0`. Run `nvm use` (or `nvm install` if you
don't have it) in the repo root before anything else. CI uses Node 22.20.0,
a later patch than the broken 22.1.0 — that may also work, but wasn't tested
locally; 24.15.0 is the known-good version.

## 2. Ports — what changed and why

All of Docker's infra services had their **host-side** ports moved off the
defaults (container-internal ports are untouched, so nothing inside Docker
needed to change). The app processes (dashboard/api/worker, which run
natively via `pnpm dev`, not in Docker) got equivalent treatment.

| Service | Default port | New port | Where |
|---|---|---|---|
| Postgres | 5432 | **55432** | `docker-compose.yml` + `.env` |
| Redis | 6379 | **56379** | `docker-compose.yml` + `.env` |
| ClickHouse HTTP | 8123 | **58123** | `docker-compose.yml` + `.env` |
| ClickHouse native | 9000 | **59000** | `docker-compose.yml` |
| ClickHouse inter-server | 9009 | **59009** | `docker-compose.yml` |
| Redpanda Kafka | 19092 | **59092** | `docker-compose.yml` (+ advertised addr) |
| Redpanda Admin API | 9644 | **59644** | `docker-compose.yml` |
| Redpanda Console UI | 8091 | **58091** | `docker-compose.yml` |
| Dashboard (apps/start) | 3000 | **53000** | `.env` (`DASHBOARD_PORT`) |
| API (apps/api) | 3333 | **53333** | `.env` (`API_PORT`) |
| Worker (apps/worker) | 9999 | **59999** | `.env` (`WORKER_PORT`) |
| Docs site (apps/public) | 9090 | unchanged | not touched, wasn't conflicting |

If you hit a *different* port conflict on another machine, the pattern to
follow is: change the host side (`host:container`) in `docker-compose.yml`
for infra, or the matching `*_PORT` var in `.env` for the app processes.

### Files touched for ports

**`docker-compose.yml`** — host-side port remap for `op-db`, `op-kv`,
`op-ch`, `op-rp` (including its `--kafka-addr` / `--advertise-kafka-addr`
command args, which had to move together — Redpanda advertises that address
to clients, so container-internal and host port were kept equal to avoid a
mismatch), and `op-rp-console`.

**`.env` / `.env.example`** — updated to match:
```bash
REDIS_URL="redis://127.0.0.1:56379"
DATABASE_URL="postgresql://postgres:postgres@localhost:55432/postgres?schema=public"
CLICKHOUSE_URL="http://localhost:58123/openpanel"
NEXT_PUBLIC_DASHBOARD_URL="http://localhost:53000"
NEXT_PUBLIC_API_URL="http://localhost:53333"
DASHBOARD_PORT=53000
WORKER_PORT=59999
API_PORT=53333
# (REDPANDA_BROKERS example, if enabled: "localhost:59092")
```

**`apps/start/vite.config.ts`** — dashboard port was previously hardcoded via
a `--port 3000` CLI flag in `package.json`. Replaced with a `server.port`
config reading `DASHBOARD_PORT` from env (falls back to 3000), and added
`server.host: true`.

**`apps/start/package.json`** — `"dev"` script changed from
`pnpm with-env vite dev --port 3000` to `pnpm with-env vite dev` (port now
comes from vite config, not the CLI flag).

`apps/api` and `apps/worker` already read `API_PORT` / `WORKER_PORT` from
env — no code changes needed there, just the `.env` values.

**`vitest.shared.ts`** and **`test/global-setup.ts`** — these intentionally
hardcode DB URLs for the test suite (so `pnpm test` never touches
production, regardless of `.env`). They were pointing at the *old* default
ports, which after remapping Docker would have silently pointed the test
suite at unrelated services on this machine instead of erroring. Updated to
the new ports (55432/56379/58123).

## 3. `pnpm dev` was silently skipping the dashboard (real bug, not port-related)

Root `package.json`'s `"dev"` script is `pnpm -r --parallel testing` — it
runs each package's **`testing`** script, not `dev`. Before this fix:

- `apps/api`'s `testing` script was `API_PORT=3333 pnpm dev` — hardcoded,
  silently overriding whatever `.env` said.
- `apps/worker`'s was `WORKER_PORT=9999 pnpm dev` — same problem.
- `apps/start` had **no `testing` script at all**, so the dashboard never
  started under `pnpm dev`.

Fixed:
- `apps/api/package.json`: `"testing": "pnpm dev"` (no hardcoded port).
- `apps/worker/package.json`: `"testing": "pnpm dev"` (no hardcoded port).
- `apps/start/package.json`: added `"testing": "pnpm dev"`.

## 4. Dashboard hit `https://api.openpanel.dev` instead of localhost

`apps/start` runs its dev server through `@cloudflare/vite-plugin` (a local
Workers/Miniflare simulation) by default — not plain Node — unless `NITRO=1`
is set. Inside that sandbox, `process.env` is populated from the `vars`
block in `apps/start/wrangler.jsonc`, which hardcodes:

```json
"vars": { "API_URL": "https://api.openpanel.dev", "DASHBOARD_URL": "https://dashboard.openpanel.dev", ... }
```

`apps/start/src/server/get-envs.ts` checks `API_URL` *before*
`NEXT_PUBLIC_API_URL`, so the production URL always won locally regardless
of `.env`. Fixed with Wrangler's standard local-override mechanism — a
gitignored `apps/start/.dev.vars` file (created, not committed):

```
API_URL=http://localhost:53333
DASHBOARD_URL=http://localhost:53000
```

Also added `.dev.vars` to `.gitignore` (wasn't covered by the existing
`.env*` pattern). **This file needs to be created manually on every new
machine** — copy the two lines above into `apps/start/.dev.vars`.

## 5. `ENCRYPTION_KEY` must be set

`.env.example` ships with `ENCRYPTION_KEY=""`. `packages/db/src/encryption.ts`
throws `"ENCRYPTION_KEY environment variable is not set"` the moment
anything tries to use it (e.g. sign-up), which breaks account creation.
Generate one per machine and put it in `.env`:

```bash
openssl rand -hex 32
# put the output in .env as: ENCRYPTION_KEY="..."
```

## 6. Registration

`ALLOW_REGISTRATION=true` was added to `.env` / `.env.example` — without
`ALLOW_REGISTRATION` set at all it's actually *always* allowed by
`packages/db/src/services/registration.service.ts` (the check only
restricts things when the var is explicitly present and `!= 'true'`), but
setting it explicitly makes the intent unambiguous for a local/dev instance.

## Setup checklist for a fresh machine

```bash
git clone <repo>
cd openpanel
nvm install 24.15.0 && nvm use     # picks up .nvmrc
cp .env.example .env
# generate a real key:
openssl rand -hex 32               # paste into .env as ENCRYPTION_KEY
# create apps/start/.dev.vars (see section 4 above)
printf 'API_URL=http://localhost:53333\nDASHBOARD_URL=http://localhost:53000\n' > apps/start/.dev.vars

pnpm install
pnpm dock:up                       # starts Postgres/Redis/ClickHouse/Redpanda
pnpm migrate                       # apply Postgres schema
pnpm dev                           # starts api, worker, dashboard
```

Then:
- Dashboard: **http://localhost:53000** (redirects to `/login` → sign up for
  the first account)
- API: **http://localhost:53333**
- Worker/BullBoard: **http://localhost:59999**
- Redpanda Console: **http://localhost:58091**

### Tracking SDK config (for an app you want to track against this local instance)

```js
window.op('init', {
  apiUrl: 'http://localhost:53333',   // no /api or /track suffix — the SDK adds it
  clientId: 'YOUR_CLIENT_ID',          // from Dashboard → Project → Settings → Clients
});
```

## Notes for EC2 / a shared machine

- `docker-compose.yml` (root) only runs infra (Postgres/Redis/ClickHouse/
  Redpanda) — `pnpm dev` runs the app processes natively, not in Docker.
  If you actually want the apps containerized too (e.g. for a persistent
  EC2 deployment rather than a dev box), that's a different, separate stack:
  `self-hosting/docker-compose.yml` — it's production-oriented and none of
  the port/env changes above apply to it automatically.
- If EC2's default ports also collide with something else, follow the same
  pattern as section 2 (host-side port in `docker-compose.yml`, `*_PORT` in
  `.env`) rather than reusing these exact numbers blindly — check what's
  actually free with `lsof -nP -iTCP:<port> -sTCP:LISTEN` first.
- All of the above changes are currently uncommitted in this working tree.
  Commit them (or at least `.nvmrc`, `docker-compose.yml`, `.env.example`,
  the `package.json` script fixes, and `.gitignore`) if you want a fresh
  `git clone` on another machine to pick them up automatically — otherwise
  you'll need to re-apply the file changes manually per the sections above.

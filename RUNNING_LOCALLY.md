# Running OpenPanel Locally

Copy-pasteable steps to get the dashboard, API, and worker running on your machine. For the reasoning behind the custom ports and env values baked into this repo, see [LOCAL_DEV_SETUP.md](LOCAL_DEV_SETUP.md).

## Prerequisites

- Docker Desktop (or compatible), running
- [nvm](https://github.com/nvm-sh/nvm)
- pnpm

## 1. Clone and install

```bash
git clone <repo-url>
cd openpanel
nvm install    # reads .nvmrc, installs Node 24.15.0
nvm use
pnpm install
```

## 2. Configure environment

```bash
cp .env.example .env
printf 'API_URL=http://localhost:53333\nDASHBOARD_URL=http://localhost:53000\n' > apps/start/.dev.vars
```

Optional: `.env.example` ships with a shared `ENCRYPTION_KEY`. Generate your own for isolation:

```bash
openssl rand -hex 32
# paste the output into .env as ENCRYPTION_KEY="..."
```

## 3. Start infrastructure

```bash
pnpm dock:up
```

Starts Postgres, Redis, ClickHouse, and Redpanda in Docker.

## 4. Run database migrations

```bash
pnpm migrate
```

## 5. Start the app

```bash
pnpm dev
```

Starts the API, worker, and dashboard together.

## 6. Open it

- Dashboard: **http://localhost:53000** — redirects to `/login`, sign up for the first account
- API: **http://localhost:53333**
- Worker / BullBoard: **http://localhost:59999**
- Redpanda Console: **http://localhost:58091**

## 7. (Optional) Access from another device on your LAN

By default, login only works from the same machine — the dashboard's client bundle and the API's CORS allow-list are both pinned to `localhost`. To reach the dashboard from your phone or another computer on the same network:

```bash
# find your machine's LAN IP (macOS)
ipconfig getifaddr en0
```

Then, using that IP (example: `192.168.50.143`):

```bash
printf 'API_URL=http://192.168.50.143:53333\nDASHBOARD_URL=http://192.168.50.143:53000\n' > apps/start/.dev.vars
echo 'API_CORS_ORIGINS="http://192.168.50.143:53000"' >> .env
```

Restart `pnpm dev` (Ctrl+C, then `pnpm dev` again), then open `http://192.168.50.143:53000` from the other device.

This IP is tied to your current network — if it changes (different Wi-Fi, DHCP lease renewal), redo this step with the new IP.

## Stopping

```bash
# Ctrl+C the pnpm dev process, then:
pnpm dock:down
```

## Troubleshooting

**`EADDRINUSE` / port already in use** — a previous `pnpm dev` didn't shut down cleanly:

```bash
lsof -nP -iTCP:<port> -sTCP:LISTEN
kill <pid>
```

Ports to check: `53333` (api), `53000` (dashboard), `59999` (worker), `55432` (postgres), `56379` (redis), `58123` (clickhouse).

**`apps/api` crashes on startup** with a `webidl`/`undici` or `buffer-equal-constant-time` error — wrong Node version. Run `nvm use` in the repo root; this repo requires Node 24.15.0 exactly.

**Dashboard hits `api.openpanel.dev` instead of localhost** — `apps/start/.dev.vars` is missing. Recreate it (step 2).

**Sign-up fails with an encryption error** — `ENCRYPTION_KEY` isn't set in `.env` (step 2).

**Login fails / hangs when accessed via LAN IP** — see step 7. Without it, the browser on the other device tries to call the API at `localhost:53333`, which resolves to that device itself, not your machine.

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

By default, login only works from the same machine. Three things are pinned to `localhost`: the API only *binds* to `localhost` (refuses connections from other devices outright), and both the dashboard's client bundle and the API's CORS allow-list are pinned to `localhost` too. To reach the dashboard from your phone or another computer on the same network:

```bash
LAN_IP=$(ipconfig getifaddr en0)   # try en1 if this is empty — check `ifconfig` if unsure
echo "Using LAN IP: $LAN_IP"

cat > apps/start/.dev.vars <<EOF
API_URL=http://$LAN_IP:53333
DASHBOARD_URL=http://$LAN_IP:53000
API_URL_SSR=http://localhost:53333
EOF

cat >> .env <<EOF
API_HOST=0.0.0.0
API_CORS_ORIGINS="http://$LAN_IP:53000"
EOF
```

All three lines are required, not optional:
- **`API_HOST=0.0.0.0`** — without it, the API only accepts connections from this machine itself (see `apps/api/src/index.ts`), no matter what URL/CORS is configured. Symptom: "Load failed" / "Failed to fetch" in the other device's browser on login.
- **`API_URL_SSR=http://localhost:53333`** — the dev server's SSR runtime (a Cloudflare Workers/Miniflare sandbox) can only reach `localhost`, not this machine's own LAN IP. Without it, `/login` fails server-side with "Network connection lost", for *every* device including `localhost` — not just LAN clients.
- **`API_CORS_ORIGINS`** — without it, the API's CORS allow-list rejects the browser's request outright.

Restart `pnpm dev` (Ctrl+C, then `pnpm dev` again), then open `http://$LAN_IP:53000` from the other device.

This IP is tied to your current network and **can change** (DHCP lease renewal, switching Wi-Fi/Ethernet, machine reboot) — if login that was working suddenly breaks, re-run `ipconfig getifaddr en0` and compare against what's in `apps/start/.dev.vars`/`.env` before assuming anything else is wrong.

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

**Login on another device fails with "Load failed" / "Failed to fetch"** (dashboard page itself loads fine) — the API isn't accepting connections from other devices. Add `API_HOST=0.0.0.0` to `.env` (see step 7) and restart `pnpm dev`.

**`/login` shows "Something went wrong" / "Network connection lost" for everyone, including `localhost`** — either Docker isn't running (`docker ps` — restart Docker Desktop if it errors), or `apps/start/.dev.vars` has `API_URL` set to a LAN IP without `API_URL_SSR=http://localhost:53333` alongside it (see step 7) — the SSR runtime can't reach the LAN IP, only `localhost`.

**LAN access was working, then suddenly isn't** — the machine's LAN IP changed (DHCP renewal, network switch, reboot). Run `ipconfig getifaddr en0` and compare against `apps/start/.dev.vars`/`.env`; redo step 7 with the current IP if they differ.

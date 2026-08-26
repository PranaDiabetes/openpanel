# Self-hosting openpanel on ECS/ECR in the shared `habitnu` AWS account

Date: 2026-08-26
Status: Approved, ready for implementation planning

## Context

We want to self-host openpanel (this repo) rather than use the hosted product
or the public `lindesvard/openpanel-*` Docker Hub images. The org already has
two Terraform-managed apps in the shared `habitnu` AWS account —
`prana_console` (Rails) and `habitnu_hub` (static SPA on CloudFront) — whose
`infra/` directories establish the house style for how apps get deployed
there. This spec adapts that style to openpanel, which is a heavier stack
than either reference app: three deployable services plus three stateful
datastores, versus prana_console's single-image web+workers or hub's
S3+CloudFront static site.

Reference conventions pulled from `~/Work/prana_console/infra/` and
`~/Work/habitnu_hub/infra/`:
- Apps do **not** provision their own VPC, ECS cluster, or ALB — those already
  exist per environment in the habitnu account and are looked up via
  Terraform `data` sources.
- Naming: `<app>-<env>` for ECR repos and ECS service/task families,
  `ecs-execution-<app>-<env>` / `ecs-task-<app>-<env>` for IAM roles.
- Terraform state lives in an S3 backend (`backend "s3" {}` with the actual
  bucket/key supplied at `terraform init` time), one state file per app.
- ALB host-based listener rules route into each app's own target group on
  the shared HTTPS listener.
- `habitnu.com` is the persistent-environment domain.

## Scope decisions (confirmed with user)

1. **AWS target:** deploy into the existing shared `habitnu` account —
   reuse its VPC(s), ECS cluster(s), ALB(s), and Route53 zone. No new
   account, VPC, cluster, or load balancer.
2. **Environments:** two persistent environments, both under `habitnu.com`,
   mirroring `habitnu_hub`'s subdomain-suffix pattern:
   - `production` (deploys from `main`) — no subdomain suffix.
   - `develop` (deploys from `develop`) — `-develop` suffix.
   - No ephemeral/PR-preview environments, no `.net` zone involved.
   - Each environment has its **own** VPC (`production-vpc` / `develop-vpc`),
     ECS cluster (`habitnu` / `habitnu-develop`), ALB (`habitnu` /
     `habitnu-develop`), and fully separate datastores — no state is shared
     between production and develop.
   - The initial trial deploy happens on `develop`.
3. **Datastores:**
   - Postgres → dedicated RDS instance per environment (`db.t4g.micro` to
     start, single-AZ, engine `postgres` 14 to match the `postgres:14-alpine`
     image currently used in docker-compose).
   - Redis → dedicated ElastiCache instance per environment
     (`cache.t4g.micro`, single node, no replica, engine version in the 7.x
     line to match `redis:7.2.5`).
   - ClickHouse → **no EC2 instance.** Runs as its own single-task Fargate
     ECS service (`desired_count = 1` — not horizontally scaled; that would
     need ClickHouse Keeper/replication, out of scope) with persistent
     storage on an EFS volume mounted at `/var/lib/clickhouse`. This is the
     real analytics datastore (every event, session, chart/insight/realtime
     query reads from it — confirmed via
     `packages/trpc/src/routers/{chart,event,insight,realtime}.ts`), not a
     cache, so it must survive task restarts and redeploys.
   - Redpanda/Kafka is **dropped** — it's optional in this codebase; an
     empty `REDPANDA_BROKERS` makes both api and worker fall back to the
     Redis-backed `groupmq` queue, so omitting it loses no functionality at
     our scale and removes a whole stateful service.
4. **Secrets:** AWS Secrets Manager, not the S3-plaintext-env-file pattern
   `prana_console` uses. RDS gets Terraform-managed auto-generated master
   credentials; `ENCRYPTION_KEY` is a generated Secrets Manager secret.
   ECS task definitions pull these in via the task definition's `secrets`
   (`valueFrom`), not `environment`. Non-sensitive config stays as plain
   task `environment` entries set directly in Terraform.
5. **First deploy stays manual.** No GitHub Actions/OIDC wiring in this
   pass — that needs an IAM role provisioned in the shared account that
   can't be set up blind, and it's more debuggable to prove one deploy
   works by hand first. CI/CD is an explicit, separate follow-up after a
   successful manual `develop` deploy.

## Services

Three application services, each with its own ECR repo and Dockerfile
(already present in the repo), all listening on container port 3000
(per each `Dockerfile`'s `EXPOSE 3000`):

| Service | Source | Public? | Hostname (prod / develop) | Notes |
|---|---|---|---|---|
| `op-api` | `apps/api/Dockerfile` | Yes | `analytics-api.habitnu.com` / `analytics-api-develop.habitnu.com` | Event-ingestion endpoint; must be reachable from any website running the tracking SDK. Health check `/healthcheck`. Runs `pnpm -r run migrate:deploy` before `pnpm start`, same as the official self-hosting compose. |
| `op-dashboard` | `apps/start/Dockerfile` | Yes | `analytics.habitnu.com` / `analytics-develop.habitnu.com` | TanStack Start SSR app. Health check `/api/healthcheck`. `NEXT_PUBLIC_API_URL`/`NEXT_PUBLIC_DASHBOARD_URL` are read server-side at runtime (`apps/start/src/server/get-envs.ts`), not inlined at Vite build time — so **one image serves both environments**; the real URLs are plain ECS task environment variables, no per-env image builds needed. |
| `op-worker` | `apps/worker/Dockerfile` | No | — (internal only) | BullMQ/groupmq consumer. Health check `/healthcheck`. No ALB target group. `desired_count = 2` in production for headroom, `1` in develop (self-hosting compose runs 4 replicas on a single box; 2 is a reasonable starting point on ECS and is just a Terraform variable to tune). |

A fourth ECR repo holds a small custom ClickHouse image
(`FROM clickhouse/clickhouse-server:<pinned> ...`) that `COPY`s in
`docker/clickhouse/clickhouse-config.xml`,
`docker/clickhouse/clickhouse-user-config.xml`, and
`docker/clickhouse/init-db.sh` at build time — Fargate has no equivalent to
docker-compose's host bind-mounts, so static config has to be baked into the
image instead.

## Datastores in detail

- **RDS Postgres**: one instance per environment, in the environment's
  private subnets, security group scoped to allow 5432 only from the ECS
  task security groups. Terraform-managed master password via RDS's managed
  master user password feature (stored directly in Secrets Manager, no
  hand-off needed).
- **ElastiCache Redis**: one node per environment, private subnets only,
  security group scoped to 6379 from ECS task security groups.
- **ClickHouse on Fargate + EFS**:
  - EFS filesystem + one mount target per private subnet, access point
    matching the ClickHouse container's runtime uid/gid (verify exact uid
    during implementation — official image typically runs as a dedicated
    `clickhouse` user, not root).
  - Reached internally via Cloud Map service discovery
    (`clickhouse.habitnu-<env>.local` — reusing the same private DNS
    namespace `prana_console` already registers into), **not** a task IP,
    since Fargate task IPs change on every restart.
  - No ALB — nothing outside the VPC talks to ClickHouse directly.
  - `deployment_minimum_healthy_percent = 0` /
    `deployment_maximum_percent = 100` specifically for this service (unlike
    the other three, which use the org's usual 100/200): the old task must
    fully stop before the new one starts, because two ClickHouse processes
    must never write the same EFS-backed data directory concurrently.

## Terraform layout

New `infra/` directory at the openpanel repo root, following the
`prana_console` file-per-concern convention:

```
infra/
  config.tf                    # terraform block, S3 backend (bucket/key via -backend-config), provider, default_tags
  variables.tf                 # env_name, task-count variables per service
  locals.tf                    # naming (openpanel-<env>-<role>), per-env cpu/mem sizing, hostnames
  data.tf                      # existing VPC, subnets, ECS cluster, ALB, listener, Route53 zone, security groups, service discovery namespace
  ecr.tf                       # 4 repos: api, worker, dashboard, clickhouse
  roles.tf                     # ECS execution role + task role, Secrets Manager read policy
  rds.tf                       # Postgres instance + subnet group + security group
  elasticache.tf                # Redis node + subnet group + security group
  efs.tf                       # ClickHouse EFS filesystem + mount targets + access point
  secrets.tf                   # ENCRYPTION_KEY secret (+ any other generated secrets)
  alb.tf                       # target groups + host-based listener rules for api/dashboard
  clickhouse.tf                # ClickHouse task def + service + service discovery entry
  ecs_api_service.tf           # api task def + service + service discovery/ALB attachment
  ecs_worker_service.tf        # worker task def + service (no ALB)
  ecs_dashboard_service.tf     # dashboard task def + service + ALB attachment
  outputs.tf
  modules/
    ecs-task-definition/       # adapted from prana_console's module: family, container def, log group, secrets support
```

Naming follows the reference apps: ECR repos and ECS
service/task families as `openpanel-<env>-<role>` (e.g.
`openpanel-develop-api`), IAM roles as `ecs-execution-openpanel-<env>` /
`ecs-task-openpanel-<env>`.

## Build & first deploy (manual)

1. `terraform init`/`apply` (run by hand, with `-backend-config` pointing at
   the app's own state key) provisions everything above for `develop` first:
   ECR repos, IAM roles, RDS, ElastiCache, EFS, the ClickHouse service, and
   the api/worker/dashboard services (which will fail to start until images
   exist — expected on first apply).
2. A new `sh/ecr-build-push` script (sibling to the existing
   `sh/docker-build`, which builds and pushes to Docker Hub) builds and
   pushes the 4 images to their ECR repos for the target environment.
3. Re-run `terraform apply` (or `aws ecs update-service
   --force-new-deployment` for each of the 3 app services) to roll the now-
   published images out.
4. Verify `analytics-develop.habitnu.com` loads and event ingestion against
   `analytics-api-develop.habitnu.com` works end-to-end before touching
   production.

GitHub Actions (build + push + `terraform apply` on push to `develop`/`main`,
mirroring `prana_console`'s `terraform-apply.yml`) is an explicit follow-up
once step 4 above is verified working — not part of this pass.

## Out of scope for this spec

- GitHub Actions / OIDC deploy pipeline (follow-up).
- Production environment provisioning (develop first; production repeats
  the same Terraform with `env_name = "production"` once develop is
  verified).
- Redpanda/Kafka event streaming.
- ClickHouse horizontal scaling / replication.
- RDS/ElastiCache high availability (Multi-AZ, read replicas) — can be
  added later by changing instance parameters, no architecture change
  needed.

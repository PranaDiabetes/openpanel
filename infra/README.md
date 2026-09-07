# Deploying openpanel to the shared habitnu AWS account

This directory is Terraform for openpanel's ECS/ECR self-hosted deployment.
It **reuses the existing** habitnu VPC/ECS cluster/ALB/Route53 zone per
environment — it does not create any of those.

Full design rationale: `../docs/superpowers/specs/2026-08-26-openpanel-ecs-self-hosting-design.md`

## Before you start

You'll need:
- AWS CLI configured with credentials for the habitnu account.
- Terraform >= 1.2.0.
- Docker with `buildx` (or Docker Desktop, which includes it).
- The name of the S3 bucket this org already uses for Terraform state
  (same bucket `prana_console`/`habitnu_hub` use — check their CI
  workflows or ask in the team if you don't already know it).

Also note, both inherited from the existing shared account setup and not
created by this Terraform — verify them before applying, since either
being missing will break the deploy silently:
- The private subnets need NAT gateway or VPC endpoints for ECR, Secrets
  Manager, and CloudWatch Logs access, and the existing `ecs-web-<env>`
  security group must already allow inbound on port 3000 from the ALB.
- `sh/ecr-build-push` runs `docker build --platform linux/amd64` for every
  image. On an Apple Silicon Mac that runs the full pnpm/native-module
  build under QEMU emulation — expect it to be much slower than a native
  build.

Before the first `terraform apply`, also verify the ClickHouse container's
runtime user matches `infra/efs.tf`'s access point (`uid = 101, gid = 101`)
— that value was never actually confirmed against a real build (Docker
wasn't available while this infra was written):

```bash
docker build -f infra/clickhouse-image/Dockerfile -t openpanel-clickhouse-local .
docker run --rm openpanel-clickhouse-local id clickhouse
```

If the uid/gid differ from `101`/`101`, update `aws_efs_access_point.clickhouse`
in `infra/efs.tf` to match before applying — otherwise ClickHouse won't be
able to write to its EFS-backed data directory at container start.

## First deploy: `develop`

1. **Initialize Terraform against the real backend:**

   ```bash
   cd infra
   terraform init \
     -backend-config="bucket=<the org's terraform state bucket>" \
     -backend-config="key=openpanel.tfstate" \
     -backend-config="region=us-east-1"
   ```

2. **Plan and review before touching anything:**

   ```bash
   terraform plan -var="env_name=develop"
   ```

   Read the plan output carefully. It should only be *creating* new
   resources (ECR repos, IAM roles, RDS, ElastiCache, EFS, ECS services,
   ALB rules, Route53 records) — if it wants to *change* or *destroy*
   anything, stop and figure out why before proceeding (that would mean
   one of the `data` source lookups in `data.tf` matched something
   unexpected in the existing account).

3. **Apply.** There are no images in ECR yet, so the ECS services will
   actually attempt to launch tasks, fail the image pull, and trip the
   deployment circuit breaker. That's expected — different from "no
   running tasks", but not a problem — don't be alarmed by red/failed-
   looking output at this stage.

   ```bash
   terraform apply -var="env_name=develop"
   ```

4. **Build and push the images:**

   ```bash
   cd ..
   ./sh/ecr-build-push develop
   ```

5. **Roll the images out.** The task definitions reference images by the
   `:latest` tag, not a content hash, so re-applying Terraform with no
   other changes produces an identical task definition and triggers NO
   new ECS deployment — the new image would never get picked up. Force a
   fresh deployment directly instead. ClickHouse must come up first: the
   API's startup command needs ClickHouse reachable to create its tables,
   and if it isn't, the API container will exit non-zero repeatedly and
   the deployment circuit breaker will get stuck.

   ```bash
   aws ecs update-service --cluster habitnu-develop --service openpanel-develop-clickhouse --force-new-deployment
   aws ecs wait services-stable --cluster habitnu-develop --services openpanel-develop-clickhouse
   ```

   Once ClickHouse shows RUNNING/healthy, roll out the rest (any order):

   ```bash
   aws ecs update-service --cluster habitnu-develop --service openpanel-develop-api --force-new-deployment
   aws ecs update-service --cluster habitnu-develop --service openpanel-develop-worker --force-new-deployment
   aws ecs update-service --cluster habitnu-develop --service openpanel-develop-dashboard --force-new-deployment
   ```

6. **Verify:**

   ```bash
   curl -sf https://analytics-api-develop.habitnu.com/healthcheck
   curl -sf https://analytics-develop.habitnu.com/api/healthcheck
   ```

   Both should return successfully. Then open
   `https://analytics-develop.habitnu.com` in a browser and confirm the
   dashboard loads and you can register the first account
   (`ALLOW_REGISTRATION=true`).

## Production

Repeat the same steps with `-var="env_name=production"` and a
`key=production/openpanel.tfstate`-style state key (or `openpanel.tfstate`
if the org's convention is one state file per app regardless of
environment — check how `prana_console`'s state keys are organized first).
Only do this after `develop` has been verified end-to-end.

## Not set up yet

- GitHub Actions / automated deploys on push — this is all manual for now.
  See the design spec's "Out of scope" section.

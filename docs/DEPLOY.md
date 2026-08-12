# Production deploy

Deploys run through **AWS CodeBuild** on every push to `main`. GitHub Actions is not used.

## Provision (once)

```bash
export AWS_PROFILE=challengerate-mcp AWS_REGION=ap-south-1
bash scripts/aws/provision-codebuild-github.sh
```

## Manual deploy

```bash
aws codebuild start-build --project-name srjay --source-version main
```

## Flow

```
push to main → CodeBuild webhook → buildspec/deploy-production.yml
  → docker build/push (ECR srjay) → SSM deploy to EC2 (srjay-prod)
```

Production runs on EC2 instance `srjay-prod` with Caddy terminating TLS. Runtime env lives in `/opt/srjay/app.env` on the instance — not in the image.

Local dev uses `docker-compose.yml` (Mongo + hot reload). That compose file is not used in production.

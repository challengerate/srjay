# Production deploy

Production runs on **ECS Express Mode (Fargate)** behind **CloudFront** and **Route 53**. No GitHub Actions or CodeBuild.

| Resource | Value |
| --- | --- |
| Cluster | `express-sites` |
| Service | `srjay` |
| Domains | `srjay.dev`, `www.srjay.dev` |
| CloudFront | `E15GABHK78U34A` |
| ECR | `478186673715.dkr.ecr.ap-south-1.amazonaws.com/srjay` |

Runtime env is loaded from `/opt/srjay/app.env` on EC2 during provision/deploy (same keys as before). Edit that file on `srjay-prod` (`i-0a9f293dc762510c8`), then redeploy.

## Provision (once)

```bash
export AWS_PROFILE=challengerate-mcp AWS_REGION=ap-south-1
export CF_CERT_ARN=arn:aws:acm:us-east-1:478186673715:certificate/d90471a8-da19-4f40-a011-c7f8a333071e
bash scripts/aws/provision-express-cloudfront.sh
```

## Redeploy

```bash
export AWS_PROFILE=challengerate-mcp AWS_REGION=ap-south-1
bash scripts/aws/deploy-express.sh
```

Without local Docker, the deploy script builds on EC2 via SSM.

## Flow

```
docker build → ECR → update-express-gateway-service (env from app.env)
  → ECS Express ALB → CloudFront → Route 53
```

EC2/Caddy deploy has been removed; use `deploy-express.sh` only.

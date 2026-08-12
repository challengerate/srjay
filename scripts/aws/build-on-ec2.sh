#!/usr/bin/env bash
# Build and push a Docker image on an EC2 instance via SSM (when local Docker is unavailable).
set -euo pipefail

IMAGE="${1:?Usage: build-on-ec2.sh <account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>}"
INSTANCE_ID="${BUILD_INSTANCE_ID:-i-0a9f293dc762510c8}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
ACCOUNT_ID="${ACCOUNT_ID:-478186673715}"
BUILD_BUCKET="${BUILD_BUCKET:-challengerate-deploy-478186673715-ap-south-1}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_NAME="$(basename "$REPO_ROOT")"
IMAGE_TAG="${IMAGE##*:}"
ECR_REPO="${IMAGE#*/}"
ECR_REPO="${ECR_REPO%%:*}"
S3_KEY="express-builds/${REPO_NAME}/${IMAGE_TAG}-$(date +%s).tar.gz"

echo "Packaging ${REPO_ROOT}..."
TAR="/tmp/${REPO_NAME}-${IMAGE_TAG}.tar.gz"
tar -czf "$TAR" \
  --exclude node_modules \
  --exclude .next \
  --exclude .git \
  -C "$(dirname "$REPO_ROOT")" "$REPO_NAME"

echo "Uploading to s3://${BUILD_BUCKET}/${S3_KEY}..."
aws s3 cp "$TAR" "s3://${BUILD_BUCKET}/${S3_KEY}"
PRESIGNED_URL="$(aws s3 presign "s3://${BUILD_BUCKET}/${S3_KEY}" --expires-in 3600)"
rm -f "$TAR"

remote_script="$(cat <<EOF
set -euo pipefail
export AWS_REGION=$AWS_REGION
export ACCOUNT_ID=$ACCOUNT_ID
WORKDIR=/tmp/build-${REPO_NAME}-\$\$
mkdir -p "\$WORKDIR"
cd "\$WORKDIR"
aws ecr get-login-password --region \$AWS_REGION | docker login --username AWS --password-stdin \$ACCOUNT_ID.dkr.ecr.\$AWS_REGION.amazonaws.com
curl -fsSL "$PRESIGNED_URL" -o source.tar.gz
mkdir repo && tar -xzf source.tar.gz
cd ${REPO_NAME}
docker build -t "$IMAGE" .
docker push "$IMAGE"
docker image prune -f >/dev/null 2>&1 || true
rm -rf "\$WORKDIR"
echo "Pushed $IMAGE"
EOF
)"

ssm_params="$(jq -n --arg script "$remote_script" '{commands: [$script]}')"
command_id="$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --timeout-seconds 3600 \
  --parameters "$ssm_params" \
  --query 'Command.CommandId' \
  --output text)"

echo "EC2 build command: $command_id"
deadline=$(( $(date +%s) + 3600 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  status="$(aws ssm get-command-invocation \
    --command-id "$command_id" \
    --instance-id "$INSTANCE_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo Pending)"
  case "$status" in
    Success)
      echo "Built and pushed $IMAGE"
      exit 0
      ;;
    Failed|Cancelled|TimedOut)
      aws ssm get-command-invocation \
        --command-id "$command_id" \
        --instance-id "$INSTANCE_ID" \
        --query '[StandardOutputContent,StandardErrorContent]' \
        --output text >&2 || true
      exit 1
      ;;
  esac
  sleep 20
done
echo "Timed out waiting for EC2 build" >&2
exit 1

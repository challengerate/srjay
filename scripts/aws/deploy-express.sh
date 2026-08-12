#!/usr/bin/env bash
# Build, push to ECR, and roll out a new image on ECS Express Mode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

AWS_REGION="${AWS_REGION:-ap-south-1}"
ACCOUNT_ID="${ACCOUNT_ID:-478186673715}"
SERVICE_NAME="${SERVICE_NAME:-srjay}"
ECR_REPO="${ECR_REPO:-srjay}"
EXPRESS_CLUSTER="${EXPRESS_CLUSTER:-express-sites}"
SRJAY_INSTANCE_ID="${SRJAY_INSTANCE_ID:-i-0a9f293dc762510c8}"

if [ -z "${IMAGE_TAG:-}" ]; then
  IMAGE_TAG="$(git rev-parse --short=7 HEAD 2>/dev/null || date +%s)"
fi

IMAGE="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  docker build -t "$IMAGE" .
  docker push "$IMAGE"
else
  echo "Local Docker unavailable — building on EC2 ${SRJAY_INSTANCE_ID}..."
  BUILD_INSTANCE_ID="$SRJAY_INSTANCE_ID" bash "$ROOT/scripts/aws/build-on-ec2.sh" "$IMAGE"
fi

# shellcheck source=scripts/aws/express-cloudfront-lib.sh
source "$ROOT/scripts/aws/express-cloudfront-lib.sh"

SERVICE_ARN="$(aws ecs list-services --cluster "$EXPRESS_CLUSTER" \
  --query "serviceArns[?contains(@, \`${SERVICE_NAME}\`)] | [0]" --output text)"

if [ "$SERVICE_ARN" = "None" ] || [ -z "$SERVICE_ARN" ]; then
  echo "Image pushed to ${IMAGE}. No Express service yet — run provision-express-cloudfront.sh."
  exit 0
fi

ENV_FILE="/tmp/srjay-express.env"
fetch_ssm_file "$SRJAY_INSTANCE_ID" "/opt/srjay/app.env" "$ENV_FILE"
if [ ! -s "$ENV_FILE" ]; then
  echo "Empty env file from /opt/srjay/app.env on ${SRJAY_INSTANCE_ID}" >&2
  exit 1
fi

ENV_JSON="$(env_file_to_json "$ENV_FILE")"
rm -f "$ENV_FILE"

PRIMARY="$(jq -n --arg image "$IMAGE" --argjson env "$ENV_JSON" \
  '{
    image: $image,
    containerPort: 3000,
    environment: $env,
    awsLogsConfiguration: { logGroup: "/ecs/express/srjay", logStreamPrefix: "app" }
  }')"

aws ecs update-express-gateway-service \
  --service-arn "$SERVICE_ARN" \
  --primary-container "$PRIMARY"

wait_for_express_service "$SERVICE_ARN"

echo "Deployed ${IMAGE} to ${SERVICE_ARN}"

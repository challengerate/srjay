#!/usr/bin/env bash
# srjay: ECS Express Mode + CloudFront + Route 53
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
# shellcheck source=scripts/aws/express-cloudfront-lib.sh
source "$ROOT/scripts/aws/express-cloudfront-lib.sh"

SERVICE_NAME="srjay"
ECR_REPO="srjay"
ECR_TAG="${ECR_TAG:-705f6a2}"
IMAGE="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${ECR_TAG}"
CF_DISTRIBUTION_ID="${CF_DISTRIBUTION_ID:-E15GABHK78U34A}"
CF_ALIAS="srjay.dev"
HOSTED_ZONE_ID="Z060245932W0II48SYFIC"
SRJAY_INSTANCE_ID="${SRJAY_INSTANCE_ID:-i-0a9f293dc762510c8}"
HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/}"
ORIGIN_PATH="${ORIGIN_PATH:-}"

ensure_express_iam_roles
ensure_express_cluster
ensure_ecr_repo "$ECR_REPO"

echo "Requesting ACM certificate for srjay.dev + www.srjay.dev..."
if [ -n "${CF_CERT_ARN:-}" ]; then
  echo "Using existing cert: $CF_CERT_ARN"
else
  CF_CERT_ARN="$(request_acm_cert_route53 srjay.dev "$HOSTED_ZONE_ID" www.srjay.dev)"
fi
echo "ACM cert: $CF_CERT_ARN"

ENV_FILE="/tmp/srjay-express.env"
CMD_ID="$(aws ssm send-command \
  --instance-ids "$SRJAY_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cat /opt/srjay/app.env"]' \
  --query 'Command.CommandId' --output text)"
sleep 4
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$SRJAY_INSTANCE_ID" \
  --query 'StandardOutputContent' --output text >"$ENV_FILE"

ENV_JSON="$(env_file_to_json "$ENV_FILE")"

EXEC_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EXECUTION_ROLE}"
INFRA_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${INFRASTRUCTURE_ROLE}"

PRIMARY="$(jq -n \
  --arg image "$IMAGE" \
  --argjson env "$ENV_JSON" \
  '{
    image: $image,
    containerPort: 3000,
    environment: $env,
    awsLogsConfiguration: { logGroup: "/ecs/express/srjay", logStreamPrefix: "app" }
  }')"

EXISTING="$(aws ecs list-services --cluster "$EXPRESS_CLUSTER" --query "serviceArns[?contains(@, \`${SERVICE_NAME}\`)] | [0]" --output text 2>/dev/null || echo None)"

if [ "$EXISTING" = "None" ] || [ -z "$EXISTING" ]; then
  OUT="/tmp/create-express-${SERVICE_NAME}.json"
  aws ecs create-express-gateway-service \
    --service-name "$SERVICE_NAME" \
    --cluster "$EXPRESS_CLUSTER" \
    --execution-role-arn "$EXEC_ARN" \
    --infrastructure-role-arn "$INFRA_ARN" \
    --primary-container "$PRIMARY" \
    --health-check-path "$HEALTH_CHECK_PATH" \
    --scaling-target '{"minTaskCount":1,"maxTaskCount":4}' >"$OUT"
  SERVICE_ARN="$(jq -r '.service.serviceArn' "$OUT")"
else
  SERVICE_ARN="$EXISTING"
  aws ecs update-express-gateway-service \
    --service-arn "$SERVICE_ARN" \
    --primary-container "$PRIMARY" \
    --health-check-path "$HEALTH_CHECK_PATH" >/dev/null
fi

rm -f "$ENV_FILE"

wait_for_express_service "$SERVICE_ARN"
ORIGIN_HOST="$(express_service_url "$SERVICE_ARN")"
ORIGIN_HOST="${ORIGIN_HOST#https://}"
ORIGIN_HOST="${ORIGIN_HOST%/}"

read -r DIST_ID CF_DOMAIN < <(upsert_cloudfront_apprunner_style_origin \
  "$CF_DISTRIBUTION_ID" "$CF_ALIAS" "$CF_CERT_ARN" "$ORIGIN_HOST" "$HOSTED_ZONE_ID" "$ORIGIN_PATH")

# www alias → same CloudFront distribution
for alias in www.srjay.dev; do
  for rtype in A AAAA; do
    aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch "$(jq -n \
      --arg cf "$CF_DOMAIN" --arg alias "$alias" --arg rtype "$rtype" \
      '{
        Changes: [{
          Action: "UPSERT",
          ResourceRecordSet: {
            Name: $alias, Type: $rtype,
            AliasTarget: {
              HostedZoneId: "Z2FDTNDATAQYW2", DNSName: $cf, EvaluateTargetHealth: false
            }
          }
        }]
      }')" >/dev/null
  done
done

# Add www to CloudFront aliases if NEW distribution
if [ "$CF_DISTRIBUTION_ID" = "NEW" ]; then
  CFG="/tmp/cf-srjay-aliases.json"
  ETAG="$(AWS_REGION=us-east-1 aws cloudfront get-distribution-config --id "$DIST_ID" --query ETag --output text)"
  AWS_REGION=us-east-1 aws cloudfront get-distribution-config --id "$DIST_ID" --query 'DistributionConfig' --output json >"$CFG"
  jq '.Aliases = {Quantity: 2, Items: ["srjay.dev", "www.srjay.dev"]}' "$CFG" >"${CFG}.new"
  AWS_REGION=us-east-1 aws cloudfront update-distribution --id "$DIST_ID" --if-match "$ETAG" --distribution-config "file://${CFG}.new" >/dev/null
fi

# Legacy teardown (CodeBuild / EC2 deploy removed from repo)

cat <<EOF

srjay is on ECS Express Mode + CloudFront.

Express URL: https://${ORIGIN_HOST}
CloudFront:  https://${CF_ALIAS}
Distribution: ${DIST_ID}
Service ARN: ${SERVICE_ARN}

Redeploy: bash scripts/aws/deploy-express.sh
EOF

#!/usr/bin/env bash
set -euo pipefail

if [ -f /tmp/srjay-deploy-env.sh ]; then
  # shellcheck disable=SC1091
  source /tmp/srjay-deploy-env.sh
fi

for required in SRJAY_INSTANCE_ID IMAGE_TAG ACCOUNT_ID AWS_REGION ECR_REPOSITORY SRJAY_ENV_FILE; do
  if [ -z "${!required:-}" ]; then
    echo "$required is required" >&2
    exit 1
  fi
done

image="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG"

remote_script="$(cat <<EOF
set -euo pipefail
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
docker pull $image
docker stop srjay-app 2>/dev/null || true
docker rm srjay-app 2>/dev/null || true
docker run -d --name srjay-app --restart unless-stopped \\
  --env-file $SRJAY_ENV_FILE \\
  -p 127.0.0.1:3000:3000 \\
  $image
docker image prune -f >/dev/null 2>&1 || true
EOF
)"

ssm_params="$(jq -n --arg script "$remote_script" '{commands: [$script]}')"

command_id="$(aws ssm send-command \
  --instance-ids "$SRJAY_INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --parameters "$ssm_params" \
  --query 'Command.CommandId' \
  --output text)"

echo "SSM deploy command: $command_id"

wait_seconds="${SSM_WAIT_SECONDS:-900}"
started_at="$(date +%s)"

while true; do
  status="$(aws ssm get-command-invocation \
    --command-id "$command_id" \
    --instance-id "$SRJAY_INSTANCE_ID" \
    --query 'Status' \
    --output text 2>/dev/null || echo Pending)"

  case "$status" in
    Success)
      echo "Deployed $image to $SRJAY_INSTANCE_ID"
      exit 0
      ;;
    Failed|Cancelled|TimedOut)
      aws ssm get-command-invocation \
        --command-id "$command_id" \
        --instance-id "$SRJAY_INSTANCE_ID" \
        --query '[StandardOutputContent,StandardErrorContent]' \
        --output text >&2 || true
      echo "SSM deploy failed ($status)" >&2
      exit 1
      ;;
  esac

  if [ "$(( $(date +%s) - started_at ))" -ge "$wait_seconds" ]; then
    echo "Timed out waiting for SSM deploy" >&2
    exit 1
  fi

  sleep 10
done

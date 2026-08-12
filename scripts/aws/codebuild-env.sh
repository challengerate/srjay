#!/usr/bin/env bash
set -euo pipefail

export AWS_REGION="${AWS_REGION:-ap-south-1}"
export ACCOUNT_ID="${ACCOUNT_ID:-478186673715}"
export ECR_REPOSITORY="${ECR_REPOSITORY:-srjay}"
export SRJAY_INSTANCE_ID="${SRJAY_INSTANCE_ID:-i-0a9f293dc762510c8}"
export SRJAY_ENV_FILE="${SRJAY_ENV_FILE:-/opt/srjay/app.env}"

if [ -z "${IMAGE_TAG:-}" ]; then
  if [ -n "${CODEBUILD_RESOLVED_SOURCE_VERSION:-}" ]; then
    export IMAGE_TAG="${CODEBUILD_RESOLVED_SOURCE_VERSION:0:7}"
  else
    echo "IMAGE_TAG or CODEBUILD_RESOLVED_SOURCE_VERSION is required" >&2
    exit 1
  fi
fi

env_file="/tmp/srjay-deploy-env.sh"
{
  echo "export AWS_REGION=\"$AWS_REGION\""
  echo "export ACCOUNT_ID=\"$ACCOUNT_ID\""
  echo "export ECR_REPOSITORY=\"$ECR_REPOSITORY\""
  echo "export SRJAY_INSTANCE_ID=\"$SRJAY_INSTANCE_ID\""
  echo "export SRJAY_ENV_FILE=\"$SRJAY_ENV_FILE\""
  echo "export IMAGE_TAG=\"$IMAGE_TAG\""
} >"$env_file"

echo "Deploy env ready: instance=$SRJAY_INSTANCE_ID image_tag=$IMAGE_TAG"

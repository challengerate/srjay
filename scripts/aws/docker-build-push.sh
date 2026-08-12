#!/usr/bin/env bash
set -euo pipefail

if [ -f /tmp/srjay-deploy-env.sh ]; then
  # shellcheck disable=SC1091
  source /tmp/srjay-deploy-env.sh
fi

: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${ECR_REPOSITORY:?ECR_REPOSITORY is required}"
: "${ACCOUNT_ID:?ACCOUNT_ID is required}"
: "${AWS_REGION:?AWS_REGION is required}"

image="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY:$IMAGE_TAG"

echo "Building $image"
docker build \
  --build-arg "NEXT_PUBLIC_SERVER_URL=https://srjay.dev" \
  --tag "$image" \
  .
docker push "$image"

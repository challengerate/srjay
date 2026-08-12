#!/usr/bin/env bash
# Wire srjay.dev production deploy through CodeBuild GitHub webhook (no GitHub Actions).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

AWS_REGION="${AWS_REGION:-ap-south-1}"
ACCOUNT_ID="${ACCOUNT_ID:-478186673715}"
PROJECT_NAME="srjay"
CODEBUILD_ROLE="srjay-codebuild-deploy-role"
ECR_REPOSITORY="srjay"
GITHUB_REPO_URL="https://github.com/challengerate/srjay.git"
EC2_ROLE="srjay-ec2-ssm-role"

export AWS_REGION ACCOUNT_ID

iam_dir="$ROOT/scripts/aws/iam"

ensure_ecr_repo() {
  if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1; then
    aws ecr create-repository --repository-name "$ECR_REPOSITORY" >/dev/null
    echo "Created ECR repository $ECR_REPOSITORY"
  fi
}

ensure_ec2_ecr_pull() {
  aws iam put-role-policy \
    --role-name "$EC2_ROLE" \
    --policy-name "${EC2_ROLE}-ecr-pull" \
    --policy-document "$(jq -n \
      --arg repo "arn:aws:ecr:${AWS_REGION}:${ACCOUNT_ID}:repository/${ECR_REPOSITORY}" \
      '{
        Version: "2012-10-17",
        Statement: [
          { Effect: "Allow", Action: ["ecr:GetAuthorizationToken"], Resource: "*" },
          {
            Effect: "Allow",
            Action: [
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage"
            ],
            Resource: $repo
          }
        ]
      }')" >/dev/null
}

ensure_codebuild_role() {
  if ! aws iam get-role --role-name "$CODEBUILD_ROLE" >/dev/null 2>&1; then
    aws iam create-role \
      --role-name "$CODEBUILD_ROLE" \
      --assume-role-policy-document "file://${iam_dir}/codebuild-trust-policy.json" >/dev/null
  fi
  aws iam put-role-policy \
    --role-name "$CODEBUILD_ROLE" \
    --policy-name "${CODEBUILD_ROLE}-inline" \
    --policy-document "file://${iam_dir}/codebuild-deploy-policy.json" >/dev/null
}

if [ -z "${GITHUB_TOKEN:-}" ]; then
  if command -v gh >/dev/null 2>&1; then
    gh auth switch -u challengerate >/dev/null 2>&1 || true
    GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
  fi
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "Set GITHUB_TOKEN or run: gh auth switch -u challengerate" >&2
  exit 1
fi

aws codebuild import-source-credentials \
  --server-type GITHUB \
  --auth-type PERSONAL_ACCESS_TOKEN \
  --token "$GITHUB_TOKEN" >/dev/null 2>&1 || true

ensure_ecr_repo
ensure_ec2_ecr_pull
ensure_codebuild_role

role_arn="arn:aws:iam::${ACCOUNT_ID}:role/${CODEBUILD_ROLE}"
project_json="/tmp/${PROJECT_NAME}.json"

jq -n \
  --arg name "$PROJECT_NAME" \
  --arg role "$role_arn" \
  --arg repo "$GITHUB_REPO_URL" \
  '{
    name: $name,
    description: "srjay.dev production deploy on push to main",
    source: {
      type: "GITHUB",
      location: $repo,
      gitCloneDepth: 1,
      buildspec: "buildspec/deploy-production.yml",
      reportBuildStatus: true
    },
    sourceVersion: "main",
    artifacts: { type: "NO_ARTIFACTS" },
    environment: {
      type: "LINUX_CONTAINER",
      image: "aws/codebuild/amazonlinux-x86_64-standard:5.0",
      computeType: "BUILD_GENERAL1_MEDIUM",
      privilegedMode: true,
      environmentVariables: [
        { name: "AWS_REGION", value: "ap-south-1", type: "PLAINTEXT" },
        { name: "ACCOUNT_ID", value: "478186673715", type: "PLAINTEXT" }
      ]
    },
    serviceRole: $role,
    timeoutInMinutes: 60,
    queuedTimeoutInMinutes: 120,
    logsConfig: { cloudWatchLogs: { status: "ENABLED" } }
  }' >"$project_json"

if aws codebuild batch-get-projects --names "$PROJECT_NAME" --query 'projects[0].name' --output text 2>/dev/null | grep -qx "$PROJECT_NAME"; then
  aws codebuild update-project --cli-input-json "file://${project_json}" >/dev/null
  echo "Updated CodeBuild project $PROJECT_NAME"
else
  aws codebuild create-project --cli-input-json "file://${project_json}" >/dev/null
  echo "Created CodeBuild project $PROJECT_NAME"
fi

if aws codebuild batch-get-projects --names "$PROJECT_NAME" --query 'projects[0].webhook.url' --output text 2>/dev/null | grep -qv '^None$'; then
  aws codebuild delete-webhook --project-name "$PROJECT_NAME" >/dev/null 2>&1 || true
fi

aws codebuild create-webhook \
  --project-name "$PROJECT_NAME" \
  --filter-groups '[[{"type":"EVENT","pattern":"PUSH"},{"type":"HEAD_REF","pattern":"^refs/heads/main$"}]]' >/dev/null

build_id="$(aws codebuild start-build --project-name "$PROJECT_NAME" --source-version main --query 'build.id' --output text)"

cat <<EOF

srjay.dev deploy is wired through CodeBuild.

Project:  $PROJECT_NAME
Repo:     $GITHUB_REPO_URL (branch main)
Webhook:  push to main triggers build
Build:    $build_id

Monitor:
  aws codebuild batch-get-builds --ids $build_id --query 'builds[0].[buildStatus,currentPhase]' --output text
EOF

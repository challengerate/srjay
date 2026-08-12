#!/usr/bin/env bash
# Shared helpers for ECS Express Mode + CloudFront + Route 53 site deploys.
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
ACCOUNT_ID="${ACCOUNT_ID:-478186673715}"
export AWS_REGION ACCOUNT_ID

EXECUTION_ROLE="${EXECUTION_ROLE:-ecsTaskExecutionRole}"
INFRASTRUCTURE_ROLE="${INFRASTRUCTURE_ROLE:-ecsInfrastructureRoleForExpressServices}"
EXPRESS_CLUSTER="${EXPRESS_CLUSTER:-express-sites}"

ensure_express_iam_roles() {
  if ! aws iam get-role --role-name "$EXECUTION_ROLE" >/dev/null 2>&1; then
    aws iam create-role --role-name "$EXECUTION_ROLE" \
      --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Allow",
          "Principal": { "Service": "ecs-tasks.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }]
      }' >/dev/null
    aws iam attach-role-policy --role-name "$EXECUTION_ROLE" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy >/dev/null
  fi

  if ! aws iam get-role --role-name "$INFRASTRUCTURE_ROLE" >/dev/null 2>&1; then
    aws iam create-role --role-name "$INFRASTRUCTURE_ROLE" \
      --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
          "Sid": "AllowAccessInfrastructureForECSExpressServices",
          "Effect": "Allow",
          "Principal": { "Service": "ecs.amazonaws.com" },
          "Action": "sts:AssumeRole"
        }]
      }' >/dev/null
    aws iam attach-role-policy --role-name "$INFRASTRUCTURE_ROLE" \
      --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices >/dev/null
  fi
  sleep 15
}

ensure_express_cluster() {
  aws ecs describe-clusters --clusters "$EXPRESS_CLUSTER" --query 'clusters[0].status' --output text 2>/dev/null \
    | grep -qx ACTIVE \
    || aws ecs create-cluster --cluster-name "$EXPRESS_CLUSTER" >/dev/null
}

ensure_ecr_repo() {
  local repo="$1"
  aws ecr describe-repositories --repository-names "$repo" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "$repo" >/dev/null
}

env_file_to_json() {
  local file="$1"
  jq -Rn '[inputs | select(length>0 and (startswith("#")|not)) | split("=") | {name: .[0], value: (.[1:] | join("="))}]' "$file"
}

fetch_ssm_file() {
  local instance_id="$1" remote_path="$2" dest="$3"
  local cmd_id
  cmd_id="$(aws ssm send-command \
    --instance-ids "$instance_id" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"cat ${remote_path}\"]" \
    --query 'Command.CommandId' --output text)"
  local deadline=$(( $(date +%s) + 120 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local status
    status="$(aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$instance_id" \
      --query Status --output text 2>/dev/null || echo Pending)"
    case "$status" in
      Success)
        aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$instance_id" \
          --query StandardOutputContent --output text >"$dest"
        return 0
        ;;
      Failed|Cancelled|TimedOut)
        aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$instance_id" \
          --query '[Status,StandardErrorContent]' --output text >&2
        return 1
        ;;
    esac
    sleep 3
  done
  echo "Timed out waiting for SSM command $cmd_id" >&2
  return 1
}

require_express_service_arn() {
  local cluster="$1" service_name="$2"
  local arn
  arn="$(aws ecs list-services --cluster "$cluster" \
    --query "serviceArns[?contains(@, \`${service_name}\`)] | [0]" --output text)"
  if [ "$arn" = "None" ] || [ -z "$arn" ]; then
    echo "Express service ${service_name} not found in ${cluster}. Run provision-express-cloudfront.sh first." >&2
    exit 1
  fi
  echo "$arn"
}

ensure_ecr_image() {
  local repo="$1" tag="$2"
  aws ecr describe-images --repository-name "$repo" --image-ids "imageTag=${tag}" >/dev/null 2>&1 \
    || { echo "ECR image ${repo}:${tag} not found. Build and push first (deploy-express.sh)." >&2; exit 1; }
}

resolve_image_tag() {
  local repo="$1"
  if [ -n "${IMAGE_TAG:-}" ]; then echo "$IMAGE_TAG"; return; fi
  if [ -n "${ECR_TAG:-}" ]; then echo "$ECR_TAG"; return; fi
  if git rev-parse --short=7 HEAD >/dev/null 2>&1; then git rev-parse --short=7 HEAD; return; fi
  local latest
  latest="$(aws ecr describe-images --repository-name "$repo" \
    --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' --output text 2>/dev/null || true)"
  if [ -n "$latest" ] && [ "$latest" != "None" ]; then echo "$latest"; return; fi
  echo "IMAGE_TAG or ECR_TAG is required" >&2
  exit 1
}

amplify_env_to_json() {
  local app_id="$1"
  aws amplify get-app --app-id "$app_id" \
    --query 'app.environmentVariables' --output json \
    | jq '[(. // {}) | to_entries[] | {name: .key, value: (.value | tostring)}]'
}

wait_for_express_service() {
  local arn="$1"
  local deadline=$(( $(date +%s) + 1200 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local code
    code="$(aws ecs describe-express-gateway-service --service-arn "$arn" \
      --query 'service.status.statusCode' --output text 2>/dev/null || echo PENDING)"
    echo "Express status: $code"
    if [ "$code" = "ACTIVE" ]; then return 0; fi
    if [ "$code" = "FAILED" ]; then return 1; fi
    sleep 20
  done
  echo "Timed out waiting for Express service" >&2
  return 1
}

express_service_url() {
  local arn="$1"
  local endpoint
  endpoint="$(aws ecs describe-express-gateway-service --service-arn "$arn" \
    --query 'service.activeConfigurations[0].ingressPaths[0].endpoint' --output text)"
  if [ "$endpoint" = "None" ] || [ -z "$endpoint" ]; then
    endpoint="$(aws ecs describe-express-gateway-service --service-arn "$arn" \
      --query 'service.expressGatewayServiceConfiguration.applicationUrl' --output text)"
    endpoint="${endpoint#https://}"
  fi
  echo "$endpoint"
}

upsert_cloudfront_apprunner_style_origin() {
  # Args: distribution_id|NEW cf_alias cert_arn origin_host [route53_zone_id] [origin_path]
  local dist_id="$1"
  local cf_alias="$2"
  local cert_arn="$3"
  local origin_host="$4"
  local zone_id="${5:-}"
  local origin_path="${6:-}"

  if [ "$dist_id" = "NEW" ]; then
    local cfg="/tmp/cf-new-${cf_alias//./-}.json"
    jq -n \
      --arg origin "$origin_host" \
      --arg host "$origin_host" \
      --arg alias "$cf_alias" \
      --arg cert "$cert_arn" \
      --arg originPath "$origin_path" \
      '{
        CallerReference: (now | tostring),
        Comment: ("ECS Express + CloudFront for " + $alias),
        Enabled: true,
        Aliases: { Quantity: 1, Items: [$alias] },
        Origins: {
          Quantity: 1,
          Items: [{
            Id: "ExpressOrigin",
            DomainName: $origin,
            CustomOriginConfig: {
              HTTPPort: 443,
              HTTPSPort: 443,
              OriginProtocolPolicy: "https-only",
              OriginSslProtocols: { Quantity: 1, Items: ["TLSv1.2"] },
              OriginReadTimeout: 60,
              OriginKeepaliveTimeout: 5
            }
          }]
        },
        DefaultCacheBehavior: {
          TargetOriginId: "ExpressOrigin",
          ViewerProtocolPolicy: "redirect-to-https",
          AllowedMethods: {
            Quantity: 7,
            Items: ["GET","HEAD","OPTIONS","PUT","POST","PATCH","DELETE"],
            CachedMethods: { Quantity: 2, Items: ["GET","HEAD"] }
          },
          CachePolicyId: "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
          OriginRequestPolicyId: "b689b0a8-53d0-40ab-baf2-68738e2966ac",
          Compress: true
        },
        ViewerCertificate: {
          ACMCertificateArn: $cert,
          SSLSupportMethod: "sni-only",
          MinimumProtocolVersion: "TLSv1.2_2021"
        }
      }' >"$cfg"
    local cf_out="/tmp/cf-create-${cf_alias//./-}.json"
    AWS_REGION=us-east-1 aws cloudfront create-distribution --distribution-config "file://${cfg}" >"$cf_out"
    dist_id="$(jq -r '.Distribution.Id' "$cf_out")"
  else
    local cfg="/tmp/cf-upd-${dist_id}.json"
    local etag
    etag="$(AWS_REGION=us-east-1 aws cloudfront get-distribution-config --id "$dist_id" --query ETag --output text)"
    AWS_REGION=us-east-1 aws cloudfront get-distribution-config --id "$dist_id" --query 'DistributionConfig' --output json >"$cfg"
    jq \
      --arg origin "$origin_host" \
      --arg host "$origin_host" \
      --arg alias "$cf_alias" \
      --arg cert "$cert_arn" \
      --arg originPath "$origin_path" \
      '
      .Origins.Items[0].DomainName = $origin
      | .Origins.Items[0].Id = "ExpressOrigin"
      | if $originPath == "" then del(.Origins.Items[0].OriginPath) else .Origins.Items[0].OriginPath = $originPath end
      | del(.Origins.Items[0].S3OriginConfig)
      | del(.Origins.Items[0].OriginAccessControlId)
      | .Origins.Items[0].CustomOriginConfig = {
          HTTPPort: 443, HTTPSPort: 443, OriginProtocolPolicy: "https-only",
          OriginSslProtocols: { Quantity: 1, Items: ["TLSv1.2"] },
          OriginReadTimeout: 60, OriginKeepaliveTimeout: 5
        }
      | .Origins.Items[0].CustomHeaders = { Quantity: 0 }
      | .DefaultCacheBehavior.TargetOriginId = "ExpressOrigin"
      | .DefaultCacheBehavior.ViewerProtocolPolicy = "redirect-to-https"
      | .DefaultCacheBehavior.CachePolicyId = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      | .DefaultCacheBehavior.OriginRequestPolicyId = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
      | .Enabled = true
      | .ViewerCertificate = {
          ACMCertificateArn: $cert, SSLSupportMethod: "sni-only",
          MinimumProtocolVersion: "TLSv1.2_2021"
        }
      ' "$cfg" >"${cfg}.new"
    AWS_REGION=us-east-1 aws cloudfront update-distribution \
      --id "$dist_id" --if-match "$etag" \
      --distribution-config "file://${cfg}.new" >/dev/null
  fi

  local cf_domain
  cf_domain="$(AWS_REGION=us-east-1 aws cloudfront get-distribution --id "$dist_id" --query 'Distribution.DomainName' --output text)"
  echo "$dist_id $cf_domain"

  if [ -n "$zone_id" ]; then
    for rtype in A AAAA; do
      aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch "$(jq -n \
        --arg cf "$cf_domain" --arg alias "$cf_alias" --arg rtype "$rtype" \
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
  fi
}

request_acm_cert_route53() {
  # Args: domain zone_id [san1 san2...]
  local domain="$1"
  local zone_id="$2"
  shift 2
  local sans=("$@")
  local arn
  arn="$(AWS_REGION=us-east-1 aws acm request-certificate \
    --domain-name "$domain" \
    --subject-alternative-names $(printf '%s ' "${sans[@]:-}") \
    --validation-method DNS \
    --query CertificateArn --output text 2>/dev/null || true)"
  if [ -z "$arn" ] || [ "$arn" = "None" ]; then
    arn="$(AWS_REGION=us-east-1 aws acm list-certificates --query "CertificateSummaryList[?DomainName=='${domain}'].CertificateArn | [0]" --output text)"
  fi
  if [ "$arn" = "None" ] || [ -z "$arn" ]; then
    echo "Failed to obtain ACM cert for $domain" >&2
    return 1
  fi
  sleep 5
  local records
  records="$(AWS_REGION=us-east-1 aws acm describe-certificate --certificate-arn "$arn" --query 'Certificate.DomainValidationOptions' --output json)"
  echo "$records" | jq -c '.[]' | while read -r opt; do
    local name value
    name="$(echo "$opt" | jq -r '.ResourceRecord.Name')"
    value="$(echo "$opt" | jq -r '.ResourceRecord.Value')"
    [ "$name" = "null" ] && continue
    aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" --change-batch "$(jq -n \
      --arg name "$name" --arg value "$value" \
      '{Changes:[{Action:"UPSERT",ResourceRecordSet:{Name:$name,Type:"CNAME",TTL:300,ResourceRecords:[{Value:$value}]}}]}')" >/dev/null
  done
  local deadline=$(( $(date +%s) + 600 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local status
    status="$(AWS_REGION=us-east-1 aws acm describe-certificate --certificate-arn "$arn" --query 'Certificate.Status' --output text)"
    [ "$status" = "ISSUED" ] && { echo "$arn"; return 0; }
    sleep 15
  done
  echo "ACM cert not issued in time: $arn" >&2
  return 1
}

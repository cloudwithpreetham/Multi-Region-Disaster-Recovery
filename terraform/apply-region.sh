#!/usr/bin/env bash
# Usage: ./apply-region.sh primary
#        ./apply-region.sh secondary
#
# Mirrors destroy-region.sh — always reconfigures the backend to
# match the region before applying, then prints the outputs you
# usually need to copy into the OTHER region's tfvars or into
# terraform/global/terraform.tfvars (alb_dns_name, alb_zone_id,
# db_arn, assets_bucket_arn).

set -euo pipefail

REGION_ROLE="${1:-}"

if [[ "$REGION_ROLE" != "primary" && "$REGION_ROLE" != "secondary" ]]; then
  echo "Usage: $0 primary|secondary"
  exit 1
fi

echo "==> Reconfiguring backend to ${REGION_ROLE}'s state key"
terraform init -reconfigure -backend-config="key=multi-region-dr/${REGION_ROLE}/terraform.tfstate"

echo "==> Applying ${REGION_ROLE} (environments/${REGION_ROLE}.tfvars)"
terraform apply -var-file="environments/${REGION_ROLE}.tfvars"

echo ""
echo "==> Outputs (copy whichever you need into the other region's tfvars or global/terraform.tfvars):"
terraform output

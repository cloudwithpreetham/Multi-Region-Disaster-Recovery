#!/usr/bin/env bash
# Usage: ./destroy-region.sh primary
#        ./destroy-region.sh secondary
#
# Always reconfigures the backend to match the region you're
# destroying before running destroy — prevents the
# "not a valid load balancer ARN" / S3 AccessDenied errors that
# happen when the working dir's state key doesn't match the
# -var-file you're passing.

set -euo pipefail

REGION_ROLE="${1:-}"

if [[ "$REGION_ROLE" != "primary" && "$REGION_ROLE" != "secondary" ]]; then
  echo "Usage: $0 primary|secondary"
  exit 1
fi

echo "==> Reconfiguring backend to ${REGION_ROLE}'s state key"
terraform init -reconfigure -backend-config="key=multi-region-dr/${REGION_ROLE}/terraform.tfstate"

echo "==> Destroying ${REGION_ROLE} (environments/${REGION_ROLE}.tfvars)"
terraform destroy -var-file="environments/${REGION_ROLE}.tfvars"

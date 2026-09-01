#!/usr/bin/env bash
# Debug and fix Task 2 access routing checker
set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"

step() { echo; echo ">> $1"; echo "---"; }

step "Check backend service"
gcloud compute backend-services describe apigee-proxy-backend --global --project="$PROJECT_ID" 2>&1 | head -30

step "Check health checks"
gcloud compute health-checks list --project="$PROJECT_ID" 2>&1 | head -10

step "Check SSL cert status"
gcloud compute ssl-certificates describe apigee-cert --global --project="$PROJECT_ID" 2>&1 | head -20

step "Check if health check missing - creating HTTPS health check"
# Create health check if not exists
if ! gcloud compute health-checks describe apigee-health-check --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute health-checks create https apigee-health-check \
    --project="$PROJECT_ID" \
    --port=443 \
    --request-path=/hello-world \
    --global 2>&1 || echo "(failed to create)"
fi

step "Add health check to backend service"
gcloud compute backend-services update apigee-proxy-backend \
  --global --project="$PROJECT_ID" \
  --health-checks=apigee-health-check 2>&1 | head -10

step "Verify health check attached"
gcloud compute backend-services describe apigee-proxy-backend --global --project="$PROJECT_ID" 2>&1 | grep -A5 "healthChecks" || true

step "Check forwarding rules"
gcloud compute forwarding-rules list --global --project="$PROJECT_ID" \
  --format='table(name,IPAddress,portRange)' 2>&1

echo ""
echo ">>> Now click Check my progress for Task 2 again"

#!/usr/bin/env bash
# Task 2 manual LB setup - run this in YOUR Cloud Shell
set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "No project set"; exit 1; }
ORG="$PROJECT_ID"
INSTANCE="eval-instance"
NETWORK="api-vpc"
SUBNET="api-subnet"
REGION="us-west1"

step() { echo; echo ">> $1"; echo "---"; }

# Get fresh token
TOKEN="$(gcloud auth print-access-token)"

apigee_get() {
  curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
       -H "Content-Type: application/json" \
       "https://apigee.googleapis.com/v1/$1"
}

step "Check Org"
apigee_get "organizations/$ORG" | jq '{name, state}' 2>/dev/null

step "Check Environments"
apigee_get "organizations/$ORG/environments" | jq '.[]?.name' 2>/dev/null || echo "(none)"

step "Check EnvGroups + hostnames"
apigee_get "organizations/$ORG/envgroups" | jq '.environmentGroups[]? | {name, hostnames}' 2>/dev/null || echo "(none)"

step "Check Instances"
apigee_get "organizations/$ORG/instances" | jq '.instances[]? | {name, location, state, host}' 2>/dev/null || echo "(none)"

step "Check Instance attachments"
apigee_get "organizations/$ORG/instances/$INSTANCE/attachments" | jq . 2>/dev/null || echo "(none)"

step "Get serviceAttachment from instance"
SA="$(apigee_get "organizations/$ORG/instances/$INSTANCE" | jq -r '.serviceAttachment // empty' 2>/dev/null || echo "")"
echo "serviceAttachment: $SA"

step "Check existing LB"
gcloud compute forwarding-rules list --global --project="$PROJECT_ID" \
  --format='table(name,IPAddress,portRange,target.basename())' 2>/dev/null || echo "(none)"

gcloud compute backend-services list --global --project="$PROJECT_ID" \
  --format='table(name,protocol,loadBalancingScheme)' 2>/dev/null || echo "(none)"

step "Check PSC NEG"
gcloud compute network-endpoint-groups list --region="$REGION" --project="$PROJECT_ID" \
  --format='table(name,type)' 2>/dev/null || echo "(none)"

step "Check global IPs"
gcloud compute addresses list --global --project="$PROJECT_ID" \
  --format='table(name,ADDRESS,status)' 2>/dev/null || echo "(none)"

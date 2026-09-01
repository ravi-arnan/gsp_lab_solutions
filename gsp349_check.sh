#!/usr/bin/env bash
# Helper script to set up access routing manually (when wizard unavailable)
# Run this in Cloud Shell

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
ORG="$PROJECT_ID"
INSTANCE="eval-instance"
NETWORK="api-vpc"
SUBNET="api-subnet"
REGION="us-west1"

echo "Project: $PROJECT_ID"
echo "Getting instance info..."

# Get instance details
INSTANCE_RESP="$(gcloud apigee instances describe "$INSTANCE" \
  --organization="$ORG" --format=json 2>/dev/null || echo "{}")"

echo "$INSTANCE_RESP" | jq . 2>/dev/null | head -30

# Get service attachment
SA="$(echo "$INSTANCE_RESP" | jq -r '.serviceAttachment // empty' 2>/dev/null || echo "")"
echo "Service Attachment: $SA"

# Get instance IP
IP="$(echo "$INSTANCE_RESP" | jq -r '.host // .ipRange // empty' 2>/dev/null || echo "")"
echo "Instance IP: $IP"

# List forwarding rules
echo "--- Global Forwarding Rules ---"
gcloud compute forwarding-rules list --global --project="$PROJECT_ID" --format='table(name,IPAddress,portRange)' 2>/dev/null | head -10

# List backend services
echo "--- Global Backend Services ---"
gcloud compute backend-services list --global --project="$PROJECT_ID" --format='table(name,protocol)' 2>/dev/null | head -10

# List network endpoint groups
echo "--- PSC NEG ---"
gcloud compute network-endpoint-groups list --region="$REGION" --project="$PROJECT_ID" --format='table(name,type)' 2>/dev/null | head -10

# Check eval-group hostname
echo "--- Eval Group Hostnames ---"
TOKEN="$(gcloud auth print-access-token 2>/dev/null)"
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://apigee.googleapis.com/v1/organizations/$ORG/envgroups/eval-group" | jq '.hostnames' 2>/dev/null

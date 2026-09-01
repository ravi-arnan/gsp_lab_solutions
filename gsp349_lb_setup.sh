#!/usr/bin/env bash
# Task 2: Manual LB setup (when wizard unavailable)
# Creates PSC NEG + global HTTPS LB + nip.io hostname for eval-group

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
ORG="$PROJECT_ID"
INSTANCE="eval-instance"
NETWORK="api-vpc"
SUBNET="api-subnet"
# Auto-detect REGION/SA dari instance (lab kadang di us-west1, kadang us-central1)
DETECTED_SA="$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token 2>/dev/null)" "https://apigee.googleapis.com/v1/organizations/$ORG/instances/eval-instance" 2>/dev/null | grep -o '"serviceAttachment"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"
if [[ -n "$DETECTED_SA" ]]; then
  SA="$DETECTED_SA"
  DETECTED_REGION="$(echo "$SA" | sed -n 's|.*/regions/\([^/]*\)/.*|\1|p')"
  [[ -n "$DETECTED_REGION" ]] && REGION="$DETECTED_REGION"
else
  REGION="${REGION:-us-west1}"
  SA="${SA:-projects/ua7d6b9defb732eb4-tp/regions/us-west1/serviceAttachments/apigee-us-west1-2ii1}"
fi
# Fallback jika env sudah set (untuk lab yang region-nya beda)
REGION="${REGION:-us-west1}"
SA="${SA:-projects/ua7d6b9defb732eb4-tp/regions/us-west1/serviceAttachments/apigee-us-west1-2ii1}"
echo "Detected REGION=$REGION SA=$SA (dari instance eval-instance)"

step() { echo; echo ">> $1"; echo "---"; }

# Refresh token each time
TOKEN() { gcloud auth print-access-token 2>/dev/null; }

apigee_patch() {
  local path="$1" body="$2"
  curl -s -H "Authorization: Bearer $(TOKEN)" \
       -H "Content-Type: application/json" \
       -X PATCH "https://apigee.googleapis.com/v1/$path" -d "$body"
}

step "1. Create PSC NEG -> service attachment"
if ! gcloud compute network-endpoint-groups describe apigee-neg --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute network-endpoint-groups create apigee-neg \
    --region="$REGION" --project="$PROJECT_ID" \
    --network="$NETWORK" --subnet="$SUBNET" \
    --network-endpoint-type=private-service-connect \
    --psc-target-service="$SA"
  echo "NEG created."
else
  echo "NEG already exists."
fi

gcloud compute network-endpoint-groups describe apigee-neg --region="$REGION" --project="$PROJECT_ID" --format='table(name,type)' 2>/dev/null

step "2. Reserve global IP"
if ! gcloud compute addresses describe apigee-lb-ip --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute addresses create apigee-lb-ip --global --project="$PROJECT_ID"
fi
LB_IP="$(gcloud compute addresses describe apigee-lb-ip --global --project="$PROJECT_ID" --format='value(address)' 2>/dev/null)"
echo "LB IP: $LB_IP"
echo "Hostname will be: ${LB_IP}.nip.io"

step "3. Create backend service"
if ! gcloud compute backend-services describe apigee-proxy-backend --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute backend-services create apigee-proxy-backend \
    --global --project="$PROJECT_ID" \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTPS \
    --port-name=https
  echo "Backend service created."
else
  echo "Backend service already exists."
fi

# Add PSC NEG as backend
echo "Adding NEG to backend..."
gcloud compute backend-services add-backend apigee-proxy-backend \
  --global --project="$PROJECT_ID" \
  --network-endpoint-group=apigee-neg \
  --network-endpoint-group-region="$REGION" 2>/dev/null || echo "(already added or error)"

step "4. Create URL map"
if ! gcloud compute url-maps describe apigee-url-map --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute url-maps create apigee-url-map \
    --global --project="$PROJECT_ID" \
    --default-service=apigee-proxy-backend
else
  gcloud compute url-maps set-default-service apigee-url-map \
    --global --project="$PROJECT_ID" \
    --default-service=apigee-proxy-backend 2>/dev/null || true
fi

step "5. Create SSL certificate"
if ! gcloud compute ssl-certificates describe apigee-cert --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute ssl-certificates create apigee-cert \
    --global --project="$PROJECT_ID" \
    --domains="${LB_IP}.nip.io"
  echo "SSL cert created (Google-managed, may take a few minutes to provision)."
else
  echo "SSL cert already exists."
fi

step "6. Create target HTTPS proxy"
if ! gcloud compute target-https-proxies describe apigee-proxy --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute target-https-proxies create apigee-proxy \
    --global --project="$PROJECT_ID" \
    --url-map=apigee-url-map \
    --ssl-certificates=apigee-cert
else
  echo "Target proxy already exists."
fi

step "7. Create HTTPS forwarding rule"
if ! gcloud compute forwarding-rules describe apigee-https-fr --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute forwarding-rules create apigee-https-fr \
    --global --project="$PROJECT_ID" \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --network-tier=PREMIUM \
    --address=apigee-lb-ip \
    --target-https-proxy=apigee-proxy \
    --ports=443
  echo "HTTPS forwarding rule created."
else
  echo "HTTPS forwarding rule already exists."
fi

step "8. Create target HTTP proxy (for port 80)"
if ! gcloud compute target-http-proxies describe apigee-http-proxy --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute target-http-proxies create apigee-http-proxy \
    --global --project="$PROJECT_ID" \
    --url-map=apigee-url-map
fi

if ! gcloud compute forwarding-rules describe apigee-http-fr --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute forwarding-rules create apigee-http-fr \
    --global --project="$PROJECT_ID" \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --network-tier=PREMIUM \
    --address=apigee-lb-ip \
    --target-http-proxy=apigee-http-proxy \
    --ports=80
  echo "HTTP forwarding rule created."
else
  echo "HTTP forwarding rule already exists."
fi

step "9. Patch eval-group hostname to nip.io"
HOSTNAME="${LB_IP}.nip.io"
echo "Setting eval-group hostname to: $HOSTNAME"
apigee_patch "organizations/$ORG/envgroups/eval-group?updateMask=hostnames" \
  "{\"hostnames\":[\"$HOSTNAME\"]}" | jq . 2>/dev/null || echo "(patch sent)"

sleep 3

step "10. Verify"
echo "Eval-group hostnames:"
curl -s -H "Authorization: Bearer $(TOKEN)" \
  "https://apigee.googleapis.com/v1/organizations/$ORG/envgroups/eval-group" | jq '.hostnames' 2>/dev/null

echo ""
echo "Forwarding rules:"
gcloud compute forwarding-rules list --global --project="$PROJECT_ID" \
  --format='table(name,IPAddress,portRange,target.basename())' 2>/dev/null

echo ""
echo "Backend service backends:"
gcloud compute backend-services describe apigee-proxy-backend --global --project="$PROJECT_ID" \
  --format='yaml(name,backends)' 2>/dev/null | head -20

echo ""
echo "LB IP: $LB_IP"
echo "Hostname: ${LB_IP}.nip.io"
echo ""
echo "Test (may take 2-3 min for SSL provisioning):"
echo "  curl -k -i https://${LB_IP}.nip.io/hello-world"
echo ""
echo ">>> Run gsp349.sh after this to complete Tasks 3-5"

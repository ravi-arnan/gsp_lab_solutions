#!/usr/bin/env bash
# GSP349 Task 2 - Diagnosis (BUKAN fix health check)
# PSC NEG backend TIDAK boleh pakai health check, error sebelumnya itu wajar.
# Script ini: bersih-bersih health check nganggur + cek penyebab Task 2 merah.
set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
ORG="$PROJECT_ID"

step() { echo; echo ">> $1"; echo "---"; }

step "0. Cleanup health check nganggur (jika ada dari percobaan sebelumnya)"
if gcloud compute health-checks describe apigee-health-check --global --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Menghapus apigee-health-check global (orphan, tidak dipakai PSC)..."
  gcloud compute health-checks delete apigee-health-check --global --project="$PROJECT_ID" -q 2>&1 | head -5 || true
elif gcloud compute health-checks describe apigee-health-check --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud compute health-checks delete apigee-health-check --project="$PROJECT_ID" -q 2>&1 | head -5 || true
else
  echo "Tidak ada apigee-health-check, bagus (PSC memang tidak butuh health check)."
fi

step "1. Backend service apigee-proxy-backend"
gcloud compute backend-services describe apigee-proxy-backend --global --project="$PROJECT_ID" 2>&1 | head -40 || echo "BELUM ADA backend apigee-proxy-backend"

step "2. Forwarding rules global (harus ada 443 dan idealnya 80)"
gcloud compute forwarding-rules list --global --project="$PROJECT_ID" --format='table(name,IPAddress,portRange,target.basename())' 2>&1 | head -20

step "3. Global IP"
gcloud compute addresses list --global --project="$PROJECT_ID" --format='table(name,address,status)' 2>&1 | head -20

step "4. SSL cert apigee-cert"
gcloud compute ssl-certificates describe apigee-cert --global --project="$PROJECT_ID" 2>&1 | head -30 || echo "BELUM ADA cert"

step "5. PSC NEG apigee-neg (us-west1)"
gcloud compute network-endpoint-groups describe apigee-neg --region=us-west1 --project="$PROJECT_ID" 2>&1 | head -20 || echo "BELUM ADA NEG"

step "6. URL map + target proxy"
gcloud compute url-maps describe apigee-url-map --global --project="$PROJECT_ID" 2>&1 | head -10 || echo "BELUM ADA url map"
gcloud compute target-https-proxies list --global --project="$PROJECT_ID" --format='table(name,urlMap.basename(),sslCertificates.basename())' 2>&1 | head -10
gcloud compute target-http-proxies list --global --project="$PROJECT_ID" --format='table(name,urlMap.basename())' 2>&1 | head -10

step "7. Eval-group hostnames (HARUS IP.nip.io yang sama dengan forwarding rule IP)"
TOKEN="$(gcloud auth print-access-token 2>/dev/null)"
curl -s -H "Authorization: Bearer $TOKEN" "https://apigee.googleapis.com/v1/organizations/$ORG/envgroups/eval-group" | jq . 2>&1 | head -40

step "8. Cek kecocokan IP vs hostname"
LB_IP="$(gcloud compute forwarding-rules list --global --project="$PROJECT_ID" --format='value(IPAddress)' 2>/dev/null | head -1 || echo "")"
EVAL_HOST="$(curl -s -H "Authorization: Bearer $TOKEN" "https://apigee.googleapis.com/v1/organizations/$ORG/envgroups/eval-group" 2>/dev/null | jq -r '.hostnames[]?' 2>/dev/null | grep nip.io | head -1 || echo "")"
echo "LB_IP (dari forwarding rule): $LB_IP"
echo "EVAL_HOST (dari eval-group): $EVAL_HOST"
if [[ -n "$LB_IP" && -n "$EVAL_HOST" ]]; then
  if [[ "$EVAL_HOST" == "${LB_IP}.nip.io" ]]; then
    echo "✓ COCOK: hostname = IP.nip.io"
  else
    echo "✗ TIDAK COCOK! Checker Task 2 biasanya cek string exact IP.nip.io"
    echo "  Fix: jalankan patch di bawah:"
    echo "  HOSTNAME=\"\${LB_IP}.nip.io\"; curl -s -H \"Authorization: Bearer \$(gcloud auth print-access-token)\" -H \"Content-Type: application/json\" -X PATCH \"https://apigee.googleapis.com/v1/organizations/$ORG/envgroups/eval-group?updateMask=hostnames\" -d \"{\\\"hostnames\\\":[\\\"\$HOSTNAME\\\"]}\" | jq ."
  fi
elif [[ -z "$LB_IP" ]]; then
  echo "✗ LB_IP kosong, forwarding rule belum terbentuk. Task 2 wizard belum selesai."
elif [[ -z "$EVAL_HOST" ]]; then
  echo "✗ EVAL_HOST kosong/bukan nip.io. Patch hostname dari LB_IP seperti di atas."
fi

echo ""
echo ">>> Jika LB_IP dan EVAL_HOST sudah cocok tapi Task 2 masih merah, tunggu 2-3 menit lalu Check my progress lagi."
echo ">>> Jika tidak cocok, jalankan patch hostname di atas, tunggu 30 detik, lalu cek lagi."

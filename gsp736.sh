#!/usr/bin/env bash
# GSP736 - Debug Apps on Google Kubernetes Engine
#
#   bash gsp736.sh
#
# Checkpoint:
#   Task 2 - Deploy an application (Hipster Shop di cluster 'central')
#   Task 4 - Create a logs-based metric (Error_Rate_SLI)
#   Task 5 - Create an alerting policy (Error Rate SLI)
#   Task 1, 3, 6 - Tanpa checkpoint (setup, buka app, perbaiki bug)
#
# Task 6 tetap dikerjakan script: hapus env ENABLE_RELOAD dari manifest lalu
# apply ulang, supaya productcatalogservice berhenti crash.
#
# LAMA: ~10 menit, paling lama menunggu cluster RUNNING + pod siap.

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
#   ask <NAMA_VAR> <default> <pertanyaan>
ask() {
  local _cur="${!1:-}"
  if [[ -n "$_cur" ]]; then echo "$1 = $_cur (dari env)"; return; fi
  if [[ -t 0 ]]; then
    local _v
    read -rp "$3 [$2]: " _v
    printf -v "$1" '%s' "${_v:-$2}"
  else
    printf -v "$1" '%s' "$2"
  fi
  echo "$1 = ${!1}"
}

ask ZONE "us-central1-a" "Zone cluster (cocokkan dengan panel lab)"
ask CLUSTER "central" "Nama cluster (cocokkan dengan panel lab)"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

METRIC="Error_Rate_SLI"
ALERT_NAME="Error Rate SLI"
REPO="$HOME/microservices-demo"
API="https://monitoring.googleapis.com/v3/projects/$PROJECT"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable container.googleapis.com monitoring.googleapis.com \
  logging.googleapis.com --project="$PROJECT" || echo "Enable API gagal, lanjut saja."

# ----------------------------------------------------------------- Task 1
step "Task 1: Tunggu cluster '$CLUSTER' RUNNING lalu ambil credentials"
for i in $(seq 1 40); do
  STATUS="$(gcloud container clusters list --filter="name=$CLUSTER" \
    --format='value(status)' --project="$PROJECT" | head -1)"
  echo "  percobaan $i: status=${STATUS:-belum ada}"
  [[ "$STATUS" == "RUNNING" ]] && break
  sleep 20
done
[[ "$STATUS" == "RUNNING" ]] || { echo "Cluster tidak RUNNING."; exit 1; }

gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"
kubectl get nodes

# ----------------------------------------------------------------- Task 2
step "Task 2: Deploy Hipster Shop"
if [[ -d "$REPO" ]]; then
  echo "Repo sudah ada di $REPO, pakai yang ada."
else
  git clone https://github.com/xiangshen-dk/microservices-demo.git "$REPO"
fi
cd "$REPO"

kubectl apply -f release/kubernetes-manifests.yaml

echo "Menunggu semua deployment siap (bisa ~5 menit)..."
kubectl wait --for=condition=available --timeout=600s deployment --all || true
kubectl get pods

echo "Menunggu External IP frontend-external..."
for i in $(seq 1 30); do
  EXTERNAL_IP="$(kubectl get service frontend-external \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [[ -n "$EXTERNAL_IP" ]] && break
  echo "  percobaan $i: belum ada IP"
  sleep 15
done
[[ -n "$EXTERNAL_IP" ]] || { echo "External IP tidak muncul."; exit 1; }
echo "Frontend: http://$EXTERNAL_IP"
curl -o /dev/null -s -w "  HTTP %{http_code}\n" "http://$EXTERNAL_IP" || true

LOAD_IP="$(kubectl get service loadgenerator-external \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"

# ----------------------------------------------------------------- Task 4
step "Task 4: Logs-based metric '$METRIC'"
if gcloud logging metrics describe "$METRIC" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Metric sudah ada, lewati."
else
  # Filter ditulis persis seperti di instruksi lab, termasuk sintaks
  # labels."k8s-pod/app": "..." (operator ':' bukan '='), kalau-kalau grader
  # membandingkan teks filternya.
  gcloud logging metrics create "$METRIC" \
    --description="Error rate SLI untuk recommendationservice" \
    --log-filter='resource.type="k8s_container"
severity=ERROR
labels."k8s-pod/app": "recommendationservice"' \
    --project="$PROJECT"
fi

# ----------------------------------------------------------------- Task 5
step "Task 5: Alerting policy '$ALERT_NAME'"
TOKEN="$(gcloud auth print-access-token)"
if curl -s -H "Authorization: Bearer $TOKEN" "$API/alertPolicies" | grep -q "$ALERT_NAME"; then
  echo "Alerting policy sudah ada, lewati."
else
  cat > /tmp/gsp736_alert.json << 'EOF'
{
  "displayName": "Error Rate SLI",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Kubernetes Container - logging/user/Error_Rate_SLI",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/Error_Rate_SLI\" AND resource.type=\"k8s_container\"",
        "aggregations": [
          { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE" }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0.5,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    }
  ],
  "enabled": true
}
EOF
  curl -s -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/gsp736_alert.json "$API/alertPolicies" | head -c 400; echo
fi

# ----------------------------------------------------------------- Task 6
step "Task 6: Matikan catalog reloading (bug-nya)"
if grep -qi ENABLE_RELOAD release/kubernetes-manifests.yaml; then
  # Nomor baris dicari sendiri, jangan hardcode 373,374 seperti di instruksi lab
  # — manifestnya bisa bergeser kalau repo hulu berubah.
  LINE="$(grep -ni 'name: ENABLE_RELOAD' release/kubernetes-manifests.yaml | cut -d: -f1 | head -1)"
  echo "ENABLE_RELOAD di baris $LINE, hapus baris $LINE-$((LINE + 1))."
  sed -i -e "${LINE},$((LINE + 1))d" release/kubernetes-manifests.yaml
  kubectl apply -f release/kubernetes-manifests.yaml
  echo "Menunggu productcatalogservice stabil..."
  kubectl rollout status deployment/productcatalogservice --timeout=300s || true
else
  echo "ENABLE_RELOAD sudah tidak ada, lewati."
fi

step "Verifikasi"
kubectl get pods
gcloud logging metrics list --project="$PROJECT" --format="value(name)" | grep "$METRIC" || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 2, 4, dan 5.

  Toko    : http://$EXTERNAL_IP
  Locust  : http://${LOAD_IP:-<belum ada IP>}
  Metric  : logging.googleapis.com/user/$METRIC
  Alert   : $ALERT_NAME

Bug ENABLE_RELOAD sudah dimatikan, jadi productcatalogservice
tidak lagi crash. Kalau mau melihat error-nya lebih dulu seperti
alur lab, buka Locust dan swarm 300 user sebelum Task 6.
==============================================================
EOF

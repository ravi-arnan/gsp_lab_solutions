#!/usr/bin/env bash
# GSP091 - Creating and Alerting on Logs-based Metrics
#
#   bash gsp091.sh
#
# Checkpoint:
#   Task 1 - Deploy the GKE cluster
#   Task 2 - Create the Log-based alert
#   Task 3 - Create a Docker repository
#   Task 4 - Deploy the simple application that emits metrics
#   Task 5 - Create the log-based metric
#   Task 6 - Create the metrics-based alert
#   Task 7 - Generate some errors
#
# LAMA: ~8-12 menit (terutama pembuatan GKE cluster ~4-5 menit).

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask ZONE "europe-west4-b" "Zone untuk GKE cluster"
LOCATION="${ZONE%-*}"
ask LOCATION "$LOCATION" "Location Artifact Registry"

USER_EMAIL="$(gcloud config get-value account 2>/dev/null || echo "student@qwiklabs.net")"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Enable API & Setup
step "Setup: Set zone dan aktifkan API"
gcloud config set project "$PROJECT_ID"
gcloud config set compute/zone "$ZONE"

gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT_ID" -q || true

# ----------------------------------------------------------------- Task 1
step "Task 1: Deploy GKE cluster (gmp-cluster)"
if gcloud container clusters describe gmp-cluster --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Cluster gmp-cluster sudah ada, melewati pembuatan."
else
  echo "Membuat cluster gmp-cluster dengan 1 node (butuh ~3-5 menit)..."
  gcloud container clusters create gmp-cluster \
    --num-nodes=1 \
    --zone="$ZONE" \
    --project="$PROJECT_ID" \
    -q
fi

gcloud container clusters get-credentials gmp-cluster --zone="$ZONE" --project="$PROJECT_ID" -q

# ----------------------------------------------------------------- Task 2
step "Task 2: Buat Notification Channel dan Log-based Alert (stopped vm)"
# Buat notification channel email jika belum ada
CHANNEL_ID=$(gcloud beta monitoring channels list --project="$PROJECT_ID" --format="value(name)" 2>/dev/null | head -n 1 || true)
if [[ -z "$CHANNEL_ID" ]]; then
  echo "Membuat Email Notification Channel..."
  CHANNEL_FILE="$(mktemp)"
  cat > "$CHANNEL_FILE" <<EOF
{
  "type": "email",
  "displayName": "Lab Alert Channel",
  "description": "Email channel for lab alerts",
  "labels": {
    "email_address": "${USER_EMAIL}"
  }
}
EOF
  CHANNEL_ID=$(gcloud beta monitoring channels create --channel-content-from-file="$CHANNEL_FILE" --project="$PROJECT_ID" --format="value(name)" 2>/dev/null || true)
  rm -f "$CHANNEL_FILE"
fi
echo "Notification Channel: ${CHANNEL_ID:-none}"

# Hapus policy stopped vm lama jika ada
EXISTING_POLICIES=$(gcloud monitoring policies list --project="$PROJECT_ID" --filter='displayName="stopped vm"' --format="value(name)" 2>/dev/null || true)
for p in $EXISTING_POLICIES; do
  gcloud monitoring policies delete "$p" --project="$PROJECT_ID" -q 2>/dev/null || true
done

echo "Mendaftarkan Log-based Alert Policy 'stopped vm'..."
STOPPED_VM_FILE="$(mktemp)"
cat > "$STOPPED_VM_FILE" <<EOF
{
  "displayName": "stopped vm",
  "documentation": {
    "content": "Alert when a Compute Engine VM instance is stopped",
    "mimeType": "text/markdown"
  },
  "userLabels": {},
  "conditions": [
    {
      "displayName": "Log match condition",
      "conditionMatchedLog": {
        "filter": "resource.type=\"gce_instance\" protoPayload.methodName=\"v1.compute.instances.stop\""
      }
    }
  ],
  "alertStrategy": {
    "notificationRateLimit": {
      "period": "300s"
    },
    "autoClose": "3600s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
EOF

if [[ -n "$CHANNEL_ID" ]]; then
  echo "    \"$CHANNEL_ID\"" >> "$STOPPED_VM_FILE"
fi

cat >> "$STOPPED_VM_FILE" <<EOF
  ]
}
EOF

gcloud alpha monitoring policies create --policy-from-file="$STOPPED_VM_FILE" --project="$PROJECT_ID" -q 2>/dev/null || \
gcloud monitoring policies create --policy-from-file="$STOPPED_VM_FILE" --project="$PROJECT_ID" -q 2>/dev/null || true
rm -f "$STOPPED_VM_FILE"

# Test trigger log-based alert dengan menghentikan instance1 jika tersedia
echo "Menguji alert: menghentikan instance1..."
INSTANCE1_ZONE=$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=instance1" --format="value(zone)" 2>/dev/null | head -n 1 || true)
if [[ -n "$INSTANCE1_ZONE" ]]; then
  gcloud compute instances stop instance1 --zone="$INSTANCE1_ZONE" --project="$PROJECT_ID" -q || true
fi

# ----------------------------------------------------------------- Task 3
step "Task 3: Buat Docker repository di Artifact Registry dan push image"
if gcloud artifacts repositories describe docker-repo --location="$LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Repository docker-repo sudah ada."
else
  echo "Membuat repository docker-repo di $LOCATION..."
  gcloud artifacts repositories create docker-repo \
    --repository-format=docker \
    --location="$LOCATION" \
    --description="Docker repository" \
    --project="$PROJECT_ID" \
    -q
fi

WORKDIR="$(mktemp -d)"
cd "$WORKDIR"

echo "Mengunduh image flask_telemetry..."
wget -q https://storage.googleapis.com/spls/gsp1024/flask_telemetry.zip
unzip -q -o flask_telemetry.zip
docker load -i flask_telemetry.tar

IMAGE_TAG="${LOCATION}-docker.pkg.dev/${PROJECT_ID}/docker-repo/flask-telemetry:v1"
docker tag gcr.io/ops-demo-330920/flask_telemetry:61a2a7aabc7077ef474eb24f4b69faeab47deed9 "$IMAGE_TAG"

echo "Mengonfigurasi docker credentials dan push image..."
gcloud auth configure-docker "${LOCATION}-docker.pkg.dev" -q
docker push "$IMAGE_TAG"

# ----------------------------------------------------------------- Task 4
step "Task 4: Deploy aplikasi Flask ke GKE"
kubectl create ns gmp-test --dry-run=client -o yaml | kubectl apply -f -

echo "Mengunduh konfigurasi aplikasi gmp_prom_setup..."
wget -q https://storage.googleapis.com/spls/gsp1024/gmp_prom_setup.zip
unzip -q -o gmp_prom_setup.zip
cd gmp_prom_setup

sed -i "s|<ARTIFACT REGISTRY IMAGE NAME>|${IMAGE_TAG}|g" flask_deployment.yaml

echo "Deploying deployment dan service..."
kubectl -n gmp-test apply -f flask_deployment.yaml
kubectl -n gmp-test apply -f flask_service.yaml

echo "Menunggu LoadBalancer IP service hello..."
LB_IP=""
for i in {1..35}; do
  LB_IP=$(kubectl get svc -n gmp-test hello -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "$LB_IP" ]]; then
    break
  fi
  echo "Menunggu External IP ($i/35)..."
  sleep 5
done

if [[ -n "$LB_IP" ]]; then
  echo "Aplikasi aktif di: http://$LB_IP/metrics"
  curl -s -m 10 "http://$LB_IP/metrics" | head -n 5 || true
else
  echo "External IP belum siap. Lanjut ke task berikutnya."
fi

# ----------------------------------------------------------------- Task 5
step "Task 5: Buat Log-based metric (hello-app-error)"
if gcloud logging metrics describe hello-app-error --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Log-based metric hello-app-error sudah ada."
else
  echo "Membuat log-based metric hello-app-error..."
  gcloud logging metrics create hello-app-error \
    --description="Metric for hello-app errors" \
    --log-filter='severity=ERROR resource.labels.container_name="hello-app" textPayload: "ERROR: 404 Error page not found"' \
    --project="$PROJECT_ID"
fi

# ----------------------------------------------------------------- Task 6
step "Task 6: Buat Metrics-based alert (log based metric alert)"
EXISTING_METRIC_ALERTS=$(gcloud monitoring policies list --project="$PROJECT_ID" --filter='displayName="log based metric alert"' --format="value(name)" 2>/dev/null || true)
for p in $EXISTING_METRIC_ALERTS; do
  gcloud monitoring policies delete "$p" --project="$PROJECT_ID" -q 2>/dev/null || true
done

METRIC_ALERT_FILE="$(mktemp)"
cat > "$METRIC_ALERT_FILE" <<EOF
{
  "displayName": "log based metric alert",
  "userLabels": {},
  "conditions": [
    {
      "displayName": "New condition",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/hello-app-error\" AND resource.type=\"global\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "trigger": {
          "count": 1
        },
        "aggregations": [
          {
            "alignmentPeriod": "120s",
            "perSeriesAligner": "ALIGN_DELTA",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
EOF

if [[ -n "$CHANNEL_ID" ]]; then
  echo "    \"$CHANNEL_ID\"" >> "$METRIC_ALERT_FILE"
fi

cat >> "$METRIC_ALERT_FILE" <<EOF
  ],
  "severity": "SEVERITY_UNSPECIFIED"
}
EOF

echo "Mendaftarkan Metrics-based Alert Policy..."
gcloud alpha monitoring policies create --policy-from-file="$METRIC_ALERT_FILE" --project="$PROJECT_ID" -q 2>/dev/null || \
gcloud monitoring policies create --policy-from-file="$METRIC_ALERT_FILE" --project="$PROJECT_ID" -q 2>/dev/null || true
rm -f "$METRIC_ALERT_FILE"

# ----------------------------------------------------------------- Task 7
step "Task 7: Generate errors untuk memicu log-based metric dan alert"
echo "Mengirim request ke /error..."
if [[ -z "$LB_IP" ]]; then
  LB_IP=$(kubectl get svc -n gmp-test hello -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
fi

if [[ -n "$LB_IP" ]]; then
  for i in {1..25}; do
    curl -s -m 5 "http://$LB_IP/error" >/dev/null || true
    sleep 1
  done
  echo "Request error berhasil dikirim ke http://$LB_IP/error"
else
  echo "Peringatan: LB_IP tidak ditemukan, menjalankan curl via pod/cluster port forward..."
  kubectl -n gmp-test run curl-tester --image=curlimages/curl --restart=Never --command -- sh -c \
    "for i in \$(seq 1 25); do curl -s http://hello/error; sleep 1; done" 2>/dev/null || true
fi

cd "$HOME"
rm -rf "$WORKDIR"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Deploy the GKE cluster (Task 1)
  2. Create the Log-based alert (Task 2)
  3. Create a Docker repository (Task 3)
  4. Deploy the simple application that emits metrics (Task 4)
  5. Create the log-based metric (Task 5)
  6. Create the metrics-based alert (Task 6)
  7. Generate some errors (Task 7)
==============================================================
EOF

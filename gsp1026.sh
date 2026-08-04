#!/usr/bin/env bash
# GSP1026 - Collect Metrics from Exporters using the Managed Service for Prometheus
#
#   bash gsp1026.sh
#
# Checkpoint:
#   "Check if prometheus has been deployed"      - cluster + namespace + example app
#   "Check if config.yaml is configured correctly" - config.yaml publik di gs://$PROJECT
#
# Task 6 dan 7 (jalankan prometheus + node_exporter) tidak punya checkpoint,
# tapi tetap dijalankan di background supaya PromQL di Console ada isinya.
#
# LAMA: ~10 menit, paling lama pembuatan cluster GKE (~6-8 menit).

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

ask ZONE "us-east1-d" "Zone (cocokkan dengan panel lab)"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

CLUSTER="gmp-cluster"
NS="gmp-test"
WORKDIR="$HOME/gsp1026"
GMP_VERSION="v0.2.3"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable container.googleapis.com monitoring.googleapis.com \
  --project="$PROJECT" || echo "Enable API gagal, lanjut saja."

# ----------------------------------------------------------------- Task 1
step "Task 1: Cluster '$CLUSTER' dengan managed Prometheus (~6-8 menit)"
if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Cluster sudah ada, lewati."
else
  gcloud beta container clusters create "$CLUSTER" \
    --num-nodes=1 --zone="$ZONE" --enable-managed-prometheus --project="$PROJECT"
fi
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

# ----------------------------------------------------------------- Task 2-4
step "Task 2-4: Namespace, example app, dan PodMonitoring"
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

BASE="https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/$GMP_VERSION/examples"
kubectl -n "$NS" apply -f "$BASE/example-app.yaml"
kubectl -n "$NS" apply -f "$BASE/pod-monitoring.yaml"

kubectl -n "$NS" rollout status deployment/prom-example --timeout=300s || true
kubectl get podmonitoring -A
kubectl -n "$NS" get pods

# ----------------------------------------------------------------- Task 5
step "Task 5: Ambil binary prometheus"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
if [[ -x "$WORKDIR/prometheus" ]]; then
  echo "Binary sudah ada, lewati unduhan."
else
  wget -q https://storage.googleapis.com/kochasoft/gsp1026/prometheus
  chmod a+x prometheus
fi
./prometheus --version 2>&1 | head -2 || true

# ----------------------------------------------------------------- Task 7
step "Task 7: node_exporter di port 9100"
if [[ ! -x "$WORKDIR/node_exporter-1.3.1.linux-amd64/node_exporter" ]]; then
  wget -q https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-amd64.tar.gz
  tar xfz node_exporter-1.3.1.linux-amd64.tar.gz
fi
if pgrep -f 'node_exporter$' >/dev/null; then
  echo "node_exporter sudah jalan."
else
  nohup "$WORKDIR/node_exporter-1.3.1.linux-amd64/node_exporter" \
    > "$WORKDIR/node_exporter.log" 2>&1 &
  sleep 5
fi
curl -s -o /dev/null -w "  node_exporter: HTTP %{http_code}\n" http://localhost:9100/metrics || true

# ----------------------------------------------------------------- config.yaml
step "config.yaml + upload ke gs://$PROJECT (checkpoint kedua)"
cat > "$WORKDIR/config.yaml" << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['localhost:9100']
EOF
cat "$WORKDIR/config.yaml"

if gcloud storage buckets describe "gs://$PROJECT" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Bucket gs://$PROJECT sudah ada."
else
  gcloud storage buckets create "gs://$PROJECT" --project="$PROJECT"
fi

gcloud storage cp "$WORKDIR/config.yaml" "gs://$PROJECT/config.yaml" --project="$PROJECT"

# Lab memakai 'gsutil acl set public-read'. Itu gagal kalau bucket-nya uniform
# bucket-level access, jadi coba ACL dulu lalu jatuh ke IAM allUsers.
gcloud storage buckets update "gs://$PROJECT" --no-public-access-prevention \
  --project="$PROJECT" >/dev/null 2>&1 || true
if ! gsutil -m acl set -R -a public-read "gs://$PROJECT" >/dev/null 2>&1; then
  echo "ACL ditolak (uniform bucket-level access), pakai IAM allUsers."
  gcloud storage buckets add-iam-policy-binding "gs://$PROJECT" \
    --member=allUsers --role=roles/storage.objectViewer --project="$PROJECT" >/dev/null
fi

echo "Cek akses publik:"
curl -s -o /dev/null -w "  HTTP %{http_code}\n" \
  "https://storage.googleapis.com/$PROJECT/config.yaml" || true

# ----------------------------------------------------------------- Task 6
step "Task 6: Jalankan prometheus dengan config.yaml (background)"
if pgrep -f 'prometheus --config.file' >/dev/null; then
  echo "prometheus sudah jalan."
else
  cd "$WORKDIR"
  nohup ./prometheus --config.file=config.yaml \
    --export.label.project-id="$PROJECT" --export.label.location="$ZONE" \
    > "$WORKDIR/prometheus.log" 2>&1 &
  sleep 10
fi
curl -s -o /dev/null -w "  prometheus UI: HTTP %{http_code}\n" http://localhost:9090/ || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk kedua checkpoint:
  - Check if prometheus has been deployed
  - Check if config.yaml is configured correctly

Yang jalan di background (log di $WORKDIR):
  node_exporter  -> localhost:9100
  prometheus     -> localhost:9090

Untuk melihat grafiknya: klik ikon Web Preview di Cloud Shell,
Change Preview Port -> 9090, lalu query 'node_cpu_seconds_total'.

Menghentikan keduanya:
  pkill -f node_exporter; pkill -f 'prometheus --config.file'
==============================================================
EOF

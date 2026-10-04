#!/usr/bin/env bash
# GSP1024 - Using Prometheus for Monitoring on Google Cloud: Qwik Start
#
#   bash gsp1024.sh
#
# Checkpoint:
#   Task 1 - Create a Docker repository
#   Task 3 - Check if Prometheus has been deployed
#   Task 4 - Check if the Flask application has been deployed
#   Task 5 - Check if the dashboard is created
#
# LAMA: ~15 menit, paling lama pembuatan cluster GKE (~6-8 menit) dan menunggu
# LoadBalancer aplikasi Flask dapat IP eksternal.

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

ask REGION "europe-west1"   "Region Artifact Registry (cocokkan panel lab)"
ask ZONE   "europe-west1-b" "Zone cluster GKE (cocokkan panel lab)"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

REPO="docker-repo"
CLUSTER="gmp-cluster"
NS="gmp-test"
WORKDIR="$HOME/gsp1024"
MANIFEST_DIR="$WORKDIR/gmp_prom_setup"

# Image sumber dimuat dari flask_telemetry.tar (unduhan lab), lalu dipush ke
# Artifact Registry project sendiri.
SRC_IMAGE="gcr.io/ops-demo-330920/flask_telemetry:61a2a7aabc7077ef474eb24f4b69faeab47deed9"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO}/flask-telemetry:v1"

# Loop pembebanan: ~40 x 2 detik, cukup mengisi dashboard dengan data.
LOAD_ITER="${LOAD_ITER:-40}"

mkdir -p "$MANIFEST_DIR"

echo "Project: $PROJECT"
echo "Image  : $IMAGE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable \
  artifactregistry.googleapis.com \
  container.googleapis.com \
  monitoring.googleapis.com \
  --project="$PROJECT" -q || echo "Enable API gagal, lanjut saja."

# ══════════════════════════════════════════════════════════════
# Task 1 - Docker repository + push image
# ══════════════════════════════════════════════════════════════
step "Task 1: Artifact Registry '$REPO' di $REGION"
if gcloud artifacts repositories describe "$REPO" --location="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Repository $REPO sudah ada, lewati."
else
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker --location="$REGION" \
    --description="Docker repository" --project="$PROJECT"
fi

cd "$WORKDIR"
if docker image inspect "$SRC_IMAGE" >/dev/null 2>&1; then
  echo "Image sumber sudah ada di docker lokal."
else
  echo "Mengunduh & memuat image lab..."
  curl -sL -o flask_telemetry.zip \
    https://storage.googleapis.com/spls/gsp1024/flask_telemetry.zip
  unzip -o flask_telemetry.zip >/dev/null || true
  if [[ -f flask_telemetry.tar ]]; then
    docker load -i flask_telemetry.tar
  else
    echo "PERINGATAN: flask_telemetry.tar tidak ada, unduhan gagal?"
  fi
fi

gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
docker tag "$SRC_IMAGE" "$IMAGE"
docker push "$IMAGE"
echo "Image ter-push: $IMAGE"

# ══════════════════════════════════════════════════════════════
# Task 2 - GKE cluster dengan managed Prometheus
# ══════════════════════════════════════════════════════════════
step "Task 2: Cluster GKE '$CLUSTER' di $ZONE (~6-8 menit)"
if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Cluster sudah ada, lewati pembuatan."
  # Kalau cluster dibuat manual tanpa flag-nya, checkpoint Task 1 tetap merah.
  gcloud container clusters update "$CLUSTER" --zone="$ZONE" --project="$PROJECT" \
    --enable-managed-prometheus >/dev/null 2>&1 || true
else
  gcloud beta container clusters create "$CLUSTER" \
    --num-nodes=1 --zone="$ZONE" \
    --enable-managed-prometheus --project="$PROJECT"
fi

gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

# ══════════════════════════════════════════════════════════════
# Task 3 - Namespace kerja (checkpoint "Prometheus has been deployed")
# ══════════════════════════════════════════════════════════════
step "Task 3: Namespace $NS"
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

# ══════════════════════════════════════════════════════════════
# Task 4 - Deploy aplikasi Flask + PodMonitoring
# ══════════════════════════════════════════════════════════════
step "Task 4: Manifest aplikasi Flask + PodMonitoring"

# Manifest ditulis ulang dari gmp_prom_setup.zip, hanya image-nya diganti.
# Deployment/Service/PodMonitoring identik dengan yang ada di zip.
cat > "$MANIFEST_DIR/flask_deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: helloworld-gke
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello
  template:
    metadata:
      labels:
        app: hello
    spec:
      containers:
      - name: hello-app
        image: ${IMAGE}
        ports:
        - containerPort: 4000
          name: flaskport
        env:
          - name: PORT
            value: "4000"
EOF

cat > "$MANIFEST_DIR/flask_service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: hello
spec:
  type: LoadBalancer
  selector:
    app: hello
  ports:
  - port: 80
    targetPort: 4000
EOF

cat > "$MANIFEST_DIR/prom_deploy.yaml" <<'EOF'
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
metadata:
  name: prom-example
  labels:
    app.kubernetes.io/name: prom-example
spec:
  selector:
    matchLabels:
      app: hello
  endpoints:
  - port: flaskport
    interval: 30s
EOF

kubectl -n "$NS" apply -f "$MANIFEST_DIR/flask_deployment.yaml"
kubectl -n "$NS" apply -f "$MANIFEST_DIR/flask_service.yaml"
kubectl -n "$NS" rollout status deployment/helloworld-gke --timeout=300s || true

echo "Menunggu IP LoadBalancer service hello..."
SVC_IP=""
for i in $(seq 1 30); do
  SVC_IP="$(kubectl -n "$NS" get services hello \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [[ -n "$SVC_IP" ]] && break
  echo "  percobaan $i/30, tunggu 20 detik..."
  sleep 20
done

if [[ -n "$SVC_IP" ]]; then
  echo "IP LoadBalancer: $SVC_IP"
  echo "Cek endpoint /metrics:"
  curl -s "http://$SVC_IP/metrics" | head -5 || true
else
  echo "PERINGATAN: IP LoadBalancer belum keluar, lanjut saja."
fi

# PodMonitoring baru berguna setelah service bisa dijangkau, tapi apply-nya
# idempoten jadi aman di urutan mana pun.
kubectl -n "$NS" apply -f "$MANIFEST_DIR/prom_deploy.yaml"

step "Membebani aplikasi ($LOAD_ITER iterasi) supaya dashboard ada isinya"
if [[ -n "$SVC_IP" ]]; then
  for (( i = 1; i <= LOAD_ITER; i++ )); do
    curl -s "http://$SVC_IP/" >/dev/null 2>&1 || true
    sleep 2
  done
  echo "Selesai membebani aplikasi."
else
  echo "Dilewati: IP LoadBalancer tidak tersedia."
fi

# Checkpoint Task 4 bergantung pada metrik yang sudah ter-ingest ke Cloud
# Monitoring, bukan cuma PodMonitoring ada. Ingest-nya butuh beberapa menit;
# tunggu sampai benar-benar muncul supaya klik Check my progress tidak terlalu dini.
step "Tunggu metrik flask_http_request_total ter-ingest (~1-5 menit)"
TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
IF_START="$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
METRIC="prometheus.googleapis.com/flask_http_request_total/counter"
INGESTED=""
for i in $(seq 1 10); do
  IF_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  HIT="$(curl -s -G "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries" \
    -H "Authorization: Bearer $TOKEN" \
    --data-urlencode "filter=metric.type=\"$METRIC\"" \
    --data-urlencode "interval.startTime=$IF_START" \
    --data-urlencode "interval.endTime=$IF_END" 2>/dev/null \
    | grep -c '"timeSeries"' || true)"
  if [[ "${HIT:-0}" -gt 0 ]]; then
    echo "Metrik sudah ter-ingest ke Cloud Monitoring."
    INGESTED=1
    break
  fi
  echo "  belum terlihat (percobaan $i/10), tunggu 30 detik..."
  sleep 30
done
[[ -n "$INGESTED" ]] || echo "PERINGATAN: metrik belum terlihat; klik Task 4 mungkin perlu ditunggu lagi."

# ══════════════════════════════════════════════════════════════
# Task 5 - Dashboard Cloud Monitoring
# ══════════════════════════════════════════════════════════════
step "Task 5: Dashboard 'Prometheus Dashboard Example'"

DASH_NAME="Prometheus Dashboard Example"
DASHBOARD_JSON=$(cat <<'JSON'
{
  "category": "CUSTOM",
  "displayName": "Prometheus Dashboard Example",
  "mosaicLayout": {
    "columns": 12,
    "tiles": [
      {
        "height": 4,
        "widget": {
          "title": "prometheus/flask_http_request_total/counter [MEAN]",
          "xyChart": {
            "chartOptions": {
              "mode": "COLOR"
            },
            "dataSets": [
              {
                "minAlignmentPeriod": "60s",
                "plotType": "LINE",
                "targetAxis": "Y1",
                "timeSeriesQuery": {
                  "apiSource": "DEFAULT_CLOUD",
                  "timeSeriesFilter": {
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_NONE",
                      "perSeriesAligner": "ALIGN_RATE"
                    },
                    "filter": "metric.type=\"prometheus.googleapis.com/flask_http_request_total/counter\" resource.type=\"prometheus_target\"",
                    "secondaryAggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_MEAN",
                      "groupByFields": [
                        "metric.label.\"status\""
                      ],
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                }
              }
            ],
            "thresholds": [],
            "timeshiftDuration": "0s",
            "yAxis": {
              "label": "y1Axis",
              "scale": "LINEAR"
            }
          }
        },
        "width": 6,
        "xPos": 0,
        "yPos": 0
      }
    ]
  }
}
JSON
)

EXISTING_DASH="$(gcloud monitoring dashboards list \
  --filter='displayName="Prometheus Dashboard Example"' \
  --format='value(name)' --project="$PROJECT" 2>/dev/null | head -1 || true)"

if [[ -n "$EXISTING_DASH" ]]; then
  echo "Dashboard sudah ada: $EXISTING_DASH (lewati, agar tidak dobel)."
else
  gcloud monitoring dashboards create \
    --config="$DASHBOARD_JSON" --project="$PROJECT"
  echo "Dashboard dibuat."
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk keempat checkpoint:

  Task 1 - Create a Docker repository
  Task 3 - Check if Prometheus has been deployed
  Task 4 - Check if the Flask application has been deployed
  Task 5 - Check if the dashboard is created

PENTING - Task 4 & 5 memeriksa state di Cloud Monitoring, bukan di cluster.
Kalau masih 0/25 padahal resource benar:
  1. JANGAN End Lab dulu.
  2. Tunggu ~5-10 menit, lalu klik Check my progress LAGI.
  3. Hard refresh halaman lab (Ctrl+Shift+R) kalau status tetap 0.

Dashboard "Prometheus Dashboard Example" ada di Console:
  Search "Monitoring" -> Dashboards -> Prometheus Dashboard Example

Verifikasi cepat:
  kubectl -n $NS get pods,svc
  kubectl -n $NS get podmonitoring
  curl -s http://$SVC_IP/metrics | head
==============================================================
EOF

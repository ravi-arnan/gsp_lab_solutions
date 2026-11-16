#!/usr/bin/env bash
# GSP182 - Distributed Load Testing Using Kubernetes
#
#   bash gsp182.sh
#
# Checkpoint:
#   Task 2 (20 pts) - Get the sample code and build a Docker image for the application
#   Task 3 (20 pts) - Deploy Web Application
#   Task 4 (20 pts) - Deploy Kubernetes cluster
#   Task 6 (20 pts) - Load testing master
#   Task 7 (20 pts) - Load testing workers
#
# LAMA: ~8-12 menit (paling lama Cloud Build & pembuatan GKE cluster ~4-5 menit).

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ask REGION "us-east1" "Region (cocokkan dengan panel lab)"
ask ZONE "us-east1-c" "Zone (cocokkan dengan panel lab)"
ask CLUSTER "gke-load-test" "Nama GKE Cluster"

TARGET="${PROJECT}.appspot.com"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
step "Task 1: Set compute/region dan compute/zone"
gcloud config set project "$PROJECT"
gcloud config set compute/region "$REGION"
gcloud config set compute/zone "$ZONE"

# Enable API yang diperlukan
gcloud services enable \
  container.googleapis.com \
  cloudbuild.googleapis.com \
  appengine.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT" -q || true

# ----------------------------------------------------------------- Task 2
step "Task 2: Unduh sample code dan build Docker image"
WORKDIR="$HOME/distributed-load-testing-using-kubernetes"
if [[ ! -d "$WORKDIR" ]]; then
  cd "$HOME"
  gcloud storage cp -r gs://spls/gsp182/distributed-load-testing-using-kubernetes .
fi

cd "$WORKDIR/sample-webapp"
# Update python runtime ke python312 sesuai instruksi lab terbaru
if [[ -f app.yaml ]]; then
  sed -i "s/python37/python312/g" app.yaml
fi

cd "$WORKDIR"
gcloud builds submit --tag "gcr.io/$PROJECT/locust-tasks:latest" docker-image/. -q

# ----------------------------------------------------------------- Task 3
step "Task 3: Deploy web application ke App Engine"
cd "$WORKDIR"

# Mapping region untuk App Engine bila diperlukan
APP_REGION="$REGION"
case "$REGION" in
  us-central1) APP_REGION="us-central" ;;
  europe-west1) APP_REGION="europe-west" ;;
esac

if ! gcloud app describe --project="$PROJECT" >/dev/null 2>&1; then
  echo "Membuat App Engine app di region $APP_REGION..."
  gcloud app create --region="$APP_REGION" --project="$PROJECT" -q || true
fi

echo "Deploying sample-webapp ke App Engine..."
gcloud app deploy sample-webapp/app.yaml --project="$PROJECT" -q

# ----------------------------------------------------------------- Task 4
step "Task 4: Deploy Kubernetes cluster ($CLUSTER)"
if gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Cluster $CLUSTER sudah ada, melewati pembuatan cluster."
else
  echo "Membuat cluster $CLUSTER dengan 5 nodes..."
  gcloud container clusters create "$CLUSTER" \
    --zone "$ZONE" \
    --num-nodes=5 \
    --project="$PROJECT" \
    -q
fi

gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project="$PROJECT" -q

# ----------------------------------------------------------------- Task 5 & 6
step "Task 5 & 6: Deploy locust-master"
cd "$WORKDIR"

# Sesuaikan placeholder TARGET_HOST dan PROJECT_ID pada manifest
sed -i -e "s/\[TARGET_HOST\]/$TARGET/g" kubernetes-config/locust-master-controller.yaml
sed -i -e "s/\[TARGET_HOST\]/$TARGET/g" kubernetes-config/locust-worker-controller.yaml
sed -i -e "s/\[PROJECT_ID\]/$PROJECT/g" kubernetes-config/locust-master-controller.yaml
sed -i -e "s/\[PROJECT_ID\]/$PROJECT/g" kubernetes-config/locust-worker-controller.yaml

echo "Deploying locust-master deployment..."
kubectl apply -f kubernetes-config/locust-master-controller.yaml

echo "Deploying locust-master service (LoadBalancer)..."
kubectl apply -f kubernetes-config/locust-master-service.yaml

echo "Menunggu Locust master pod siap..."
kubectl rollout status deployment/locust-master --timeout=180s || true

# ----------------------------------------------------------------- Task 7
step "Task 7: Deploy dan scale locust-worker"
cd "$WORKDIR"

echo "Deploying locust-worker deployment..."
kubectl apply -f kubernetes-config/locust-worker-controller.yaml

echo "Scaling locust-worker menjadi 20 replicas..."
kubectl scale deployment/locust-worker --replicas=20

echo "Menunggu Locust worker pods..."
kubectl rollout status deployment/locust-worker --timeout=180s || true

# ----------------------------------------------------------------- Task 8
step "Task 8: Informasi Locust Web Interface"
echo "Mengambil External IP locust-master service..."
EXTERNAL_IP=""
for i in {1..30}; do
  EXTERNAL_IP=$(kubectl get svc locust-master -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n "$EXTERNAL_IP" ]]; then
    break
  fi
  echo "Menunggu IP eksternal dialokasikan ($i/30)..."
  sleep 5
done

if [[ -z "$EXTERNAL_IP" ]]; then
  EXTERNAL_IP=$(kubectl get svc locust-master -o yaml 2>/dev/null | grep ip: | awk -F": " '{print $NF}' | tr -d ' ' || true)
fi

echo
if [[ -n "$EXTERNAL_IP" ]]; then
  echo "Locust Master URL: http://$EXTERNAL_IP:8089"
else
  echo "External IP belum siap. Jalankan nanti: kubectl get svc locust-master"
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Get the sample code and build a Docker image for the application (Task 2)
  2. Deploy Web Application (Task 3)
  3. Deploy Kubernetes cluster (Task 4)
  4. Load testing master (Task 6)
  5. Load testing workers (Task 7)

(Opsional) Uji coba Load Testing:
  1. Buka browser: http://${EXTERNAL_IP:-<EXTERNAL_IP>}:8089
  2. Masukkan Number of users to simulate: 300
  3. Masukkan Hatch rate: 10
  4. Klik 'Start swarming' untuk melihat grafik request, lalu klik 'Stop'.
==============================================================
EOF

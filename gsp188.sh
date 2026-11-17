#!/usr/bin/env bash
# GSP188 - App Dev: Deploying the Application into Kubernetes Engine - Python
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp188.sh
#   bash gsp188.sh
#
# Checkpoint:
#   Task 1 (20 pts) - Configure the Quiz application
#   Task 2 (20 pts) - Create Kubernetes engine cluster
#   Task 3 (20 pts) - Create a Docker Repository
#   Task 4 (20 pts) - Build Docker Images using Cloud Build
#   Task 5 (20 pts) - Create Kubernetes Deployment and service resources

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

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

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

DEFAULT_ZONE="$(gcloud config get-value compute/zone 2>/dev/null || true)"
[[ -z "$DEFAULT_ZONE" ]] && DEFAULT_ZONE="europe-west1-c"

ask ZONE "$DEFAULT_ZONE" "Zone (cocokkan dengan panel lab)"
DEFAULT_REGION="${ZONE%-*}"
ask REGION "$DEFAULT_REGION" "Region (cocokkan dengan panel lab)"

case "$REGION" in
  us-central1) DEFAULT_APP_REGION="us-central" ;;
  europe-west1) DEFAULT_APP_REGION="europe-west" ;;
  *) DEFAULT_APP_REGION="$REGION" ;;
esac
ask APP_REGION "$DEFAULT_APP_REGION" "App Engine region"

echo "Project ID     : $PROJECT_ID"
echo "Zone           : $ZONE"
echo "Region         : $REGION"
echo "App Region     : $APP_REGION"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

# ----------------------------------------------------------------- API
step "Pastikan API yang dibutuhkan aktif"
gcloud services enable \
  container.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  appengine.googleapis.com \
  datastore.googleapis.com \
  firestore.googleapis.com \
  pubsub.googleapis.com \
  spanner.googleapis.com \
  storage.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT_ID" -q || true

# ----------------------------------------------------------------- Task 1
step "Task 1: Persiapan Aplikasi Quiz (Configure the Quiz application)"
cd ~
if [[ ! -d "$HOME/kubernetesengine/start" ]]; then
  echo "Mengunduh starter repository files..."
  if gcloud storage cp -r "gs://${PROJECT_ID}-assets/kubernetesengine" . 2>/dev/null; then
    echo "Starter files berhasil diunduh dari Cloud Storage project."
  elif gsutil -m cp -r "gs://${PROJECT_ID}-assets/kubernetesengine" . 2>/dev/null; then
    echo "Starter files berhasil diunduh via gsutil."
  else
    echo "Mengunduh starter files dari repositori training..."
    git clone --depth 1 https://github.com/GoogleCloudPlatform/training-data-analyst /tmp/tda 2>/dev/null || true
    mkdir -p ~/kubernetesengine
    if [[ -d /tmp/tda/courses/developingapps/v1.3/python/kubernetesengine ]]; then
      cp -r /tmp/tda/courses/developingapps/v1.3/python/kubernetesengine/* ~/kubernetesengine/
    elif [[ -d /tmp/tda/courses/developingapps/python/kubernetesengine ]]; then
      cp -r /tmp/tda/courses/developingapps/python/kubernetesengine/* ~/kubernetesengine/
    fi
  fi
fi

cd ~/kubernetesengine/start

PY_BIN="python3.12"
if ! command -v "$PY_BIN" >/dev/null 2>&1; then
  PY_BIN="python3"
fi

echo "Menyesuaikan region dan Python ($PY_BIN) di prepare_environment.sh..."
sed -i \
  -e "s/us-central1/${REGION}/g" \
  -e "s/us-central/${APP_REGION}/g" \
  prepare_environment.sh

if [[ "$PY_BIN" != "python3" ]] && ! grep -q "python3\.12" prepare_environment.sh; then
  sed -i -E "s/python3([^.]|$)/${PY_BIN}\1/g" prepare_environment.sh
fi

export APP_REGION REGION
echo "Menjalankan prepare_environment.sh..."
set +euo pipefail
. ./prepare_environment.sh || true
set -euo pipefail

export GCLOUD_PROJECT="${GCLOUD_PROJECT:-$PROJECT_ID}"
export GCLOUD_BUCKET="${GCLOUD_BUCKET:-${PROJECT_ID}-media}"
echo "GCLOUD_PROJECT = $GCLOUD_PROJECT"
echo "GCLOUD_BUCKET  = $GCLOUD_BUCKET"

# ----------------------------------------------------------------- Task 2
step "Task 2: Buat & Hubungkan Cluster GKE (quiz-cluster)"
if gcloud container clusters describe quiz-cluster --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Cluster quiz-cluster sudah ada, melewati pembuatan."
else
  echo "Membuat cluster quiz-cluster di $ZONE (butuh ~3-5 menit)..."
  gcloud container clusters create quiz-cluster \
    --zone="$ZONE" \
    --scopes=https://www.googleapis.com/auth/cloud-platform \
    --num-nodes=3 \
    --project="$PROJECT_ID" \
    -q
fi

gcloud container clusters get-credentials quiz-cluster --zone="$ZONE" --project="$PROJECT_ID" -q
kubectl get pods

# ----------------------------------------------------------------- Task 3
step "Task 3: Buat Docker Repository di Artifact Registry (container-dev-repo)"
if gcloud artifacts repositories describe container-dev-repo --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Repository container-dev-repo sudah ada."
else
  gcloud artifacts repositories create container-dev-repo \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for Container Dev Workshop" \
    --project="$PROJECT_ID" \
    -q
fi

# ----------------------------------------------------------------- Task 4
step "Task 4: Buat Dockerfile & Build Image dengan Cloud Build"
cd ~/kubernetesengine/start

cat > frontend/Dockerfile <<'EOF'
FROM gcr.io/google_appengine/python

RUN virtualenv -p python3.7 /env

ENV VIRTUAL_ENV /env
ENV PATH /env/bin:$PATH

ADD requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt

ADD . /app

CMD gunicorn -b 0.0.0.0:$PORT quiz:app
EOF

cat > backend/Dockerfile <<'EOF'
FROM gcr.io/google_appengine/python

RUN virtualenv -p python3.7 /env

ENV VIRTUAL_ENV /env
ENV PATH /env/bin:$PATH

ADD requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt

ADD . /app

CMD python -m quiz.console.worker
EOF

FRONTEND_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/container-dev-repo/quiz-frontend:v1"
BACKEND_IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/container-dev-repo/quiz-backend:v1"

echo "Build frontend image: $FRONTEND_IMAGE"
gcloud builds submit -t "$FRONTEND_IMAGE" ./frontend/ --project="$PROJECT_ID" -q

echo "Build backend image: $BACKEND_IMAGE"
gcloud builds submit -t "$BACKEND_IMAGE" ./backend/ --project="$PROJECT_ID" -q

# ----------------------------------------------------------------- Task 5
step "Task 5: Deploy Kubernetes Deployment & Service"
cd ~/kubernetesengine/start

sed -i \
  -e "s|\[GCLOUD_PROJECT\]|${GCLOUD_PROJECT}|g" \
  -e "s|\[GCLOUD_BUCKET\]|${GCLOUD_BUCKET}|g" \
  -e "s|\[FRONTEND_IMAGE_IDENTIFIER\]|${FRONTEND_IMAGE}|g" \
  frontend-deployment.yaml

sed -i \
  -e "s|\[GCLOUD_PROJECT\]|${GCLOUD_PROJECT}|g" \
  -e "s|\[GCLOUD_BUCKET\]|${GCLOUD_BUCKET}|g" \
  -e "s|\[BACKEND_IMAGE_IDENTIFIER\]|${BACKEND_IMAGE}|g" \
  backend-deployment.yaml

kubectl apply -f ./frontend-deployment.yaml
kubectl apply -f ./backend-deployment.yaml
kubectl apply -f ./frontend-service.yaml

echo
echo "Status deployment dan service:"
kubectl get deployments
kubectl get pods
kubectl get services

# ----------------------------------------------------------------- Selesai
echo
echo "=============================================================="
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  - Configure the Quiz application"
echo "  - Create Kubernetes engine cluster"
echo "  - Create a Docker Repository"
echo "  - Build Docker Images using Cloud Build"
echo "  - Create Kubernetes Deployment and service resources"
echo "=============================================================="

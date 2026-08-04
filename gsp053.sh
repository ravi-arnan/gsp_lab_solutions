#!/usr/bin/env bash
# GSP053 - Managing Deployments Using Kubernetes Engine
#
#   bash gsp053.sh
#
# Checkpoint:
#   1 - Create a Kubernetes cluster and deployments (fortune-app)
#   2 - Canary Deployment
#   3 - Blue-green deployment
#
# Rolling update di lab dikerjakan lewat 'kubectl edit' (buka vim). Di sini
# diganti 'kubectl set image' + 'kubectl set env' supaya tanpa interaksi,
# lalu 'rollout undo --to-revision=1' untuk kembali ke 1.0.0.
#
# LAMA: ~10 menit, paling lama pembuatan cluster (~5 menit).

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

ask ZONE "us-west4-a" "Zone (cocokkan dengan panel lab)"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

CLUSTER="bootcamp"
WORKDIR="$HOME/gsp053"
IMAGE_BASE="us-central1-docker.pkg.dev/qwiklabs-resources/spl-lab-apps/fortune-service"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

app_version() {  # panggil endpoint /version lewat External IP service
  local ip
  ip="$(kubectl get svc fortune-app -o=jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [[ -n "$ip" ]] && curl -s -m 15 "http://$ip/version" || echo "(IP belum ada)"
}

step "Enable API"
gcloud services enable container.googleapis.com --project="$PROJECT" || echo "Enable API gagal, lanjut saja."
gcloud config set compute/zone "$ZONE" >/dev/null 2>&1 || true

# ----------------------------------------------------------------- Setup
step "Ambil sample code + buat cluster '$CLUSTER' (~5 menit)"
mkdir -p "$WORKDIR"
cd "$WORKDIR"
[[ -d kubernetes ]] || gcloud storage cp -r gs://spls/gsp053/kubernetes .
cd kubernetes

if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Cluster sudah ada, lewati."
else
  gcloud container clusters create "$CLUSTER" \
    --machine-type e2-small \
    --num-nodes 3 \
    --zone "$ZONE" \
    --scopes "https://www.googleapis.com/auth/projecthosting,storage-rw" \
    --project="$PROJECT"
fi
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

# ----------------------------------------------------------------- Task 2
step "Task 2: Deployment fortune-app-blue + service fortune-app"
kubectl get deployment fortune-app-blue >/dev/null 2>&1 \
  || kubectl create -f deployments/fortune-app-blue.yaml
kubectl get svc fortune-app >/dev/null 2>&1 \
  || kubectl create -f services/fortune-app.yaml

kubectl rollout status deployment/fortune-app-blue --timeout=300s || true
kubectl get deployments
kubectl get replicasets

echo "Menunggu External IP service fortune-app..."
for i in $(seq 1 30); do
  IP="$(kubectl get svc fortune-app -o=jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [[ -n "$IP" ]] && break
  echo "  percobaan $i: belum ada IP"
  sleep 15
done
[[ -n "$IP" ]] || { echo "External IP tidak muncul."; exit 1; }
echo "Service: http://$IP"
echo -n "Versi: "; app_version; echo

# ----------------------------------------------------------------- Scale
step "Scale deployment: 5 lalu kembali 3"
kubectl scale deployment fortune-app-blue --replicas=5
kubectl rollout status deployment/fortune-app-blue --timeout=300s || true
echo "Jumlah pod: $(kubectl get pods -l app=fortune-app --no-headers | wc -l)"

kubectl scale deployment fortune-app-blue --replicas=3
kubectl rollout status deployment/fortune-app-blue --timeout=300s || true
echo "Jumlah pod: $(kubectl get pods -l app=fortune-app --no-headers | wc -l)"

# ----------------------------------------------------------------- Task 3
step "Task 3: Rolling update ke 2.0.0, lalu pause/resume/undo"
kubectl set image deployment/fortune-app-blue "fortune-app=${IMAGE_BASE}:2.0.0"
kubectl set env deployment/fortune-app-blue APP_VERSION=2.0.0

kubectl rollout pause deployment/fortune-app-blue
kubectl rollout status deployment/fortune-app-blue --timeout=120s || true
kubectl rollout resume deployment/fortune-app-blue
kubectl rollout status deployment/fortune-app-blue --timeout=300s || true

kubectl rollout history deployment/fortune-app-blue
echo -n "Versi setelah update: "; app_version; echo

# Kembali ke 1.0.0. Pakai --to-revision=1 karena set image dan set env membuat
# dua revisi; 'undo' polos cuma mundur satu langkah dan menyisakan 2.0.0.
kubectl rollout undo deployment/fortune-app-blue --to-revision=1
kubectl rollout status deployment/fortune-app-blue --timeout=300s || true
echo -n "Versi setelah rollback: "; app_version; echo

# ----------------------------------------------------------------- Task 4
step "Task 4: Canary deployment"
kubectl get deployment fortune-app-canary >/dev/null 2>&1 \
  || kubectl create -f deployments/fortune-app-canary.yaml
kubectl rollout status deployment/fortune-app-canary --timeout=300s || true
kubectl get deployments

echo "10 request ke service (sebagian besar 1.0.0, sedikit 2.0.0):"
for _ in $(seq 1 10); do app_version; echo; done

# ----------------------------------------------------------------- Task 5
step "Task 5: Blue-green deployment"
kubectl apply -f services/fortune-app-blue-service.yaml
kubectl get deployment fortune-app-green >/dev/null 2>&1 \
  || kubectl create -f deployments/fortune-app-green.yaml
kubectl rollout status deployment/fortune-app-green --timeout=300s || true
echo -n "Service masih menunjuk blue: "; app_version; echo

kubectl apply -f services/fortune-app-green-service.yaml
sleep 10
echo -n "Setelah switch ke green: "; app_version; echo

# Lab menutup Task 5 dengan rollback ke blue, jadi ikuti keadaan akhir itu.
kubectl apply -f services/fortune-app-blue-service.yaml
sleep 10
echo -n "Setelah rollback ke blue: "; app_version; echo

step "Verifikasi"
kubectl get deployments
kubectl get svc fortune-app

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk ketiga checkpoint:
  - Create a Kubernetes cluster and deployments (fortune-app)
  - Canary Deployment
  - Blue-green deployment

Service: http://$IP/version

Catatan: keadaan akhir mengikuti lab, yaitu service menunjuk
kembali ke blue (1.0.0). Kalau checkpoint blue-green menolak,
arahkan ke green lalu klik lagi:
  kubectl apply -f services/fortune-app-green-service.yaml
==============================================================
EOF

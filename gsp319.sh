#!/usr/bin/env bash
# GSP319 - Build a Website on Google Cloud: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp319.sh
#   bash gsp319.sh
#
# Nama image dan cluster diacak per peserta — script menanyakannya di awal.
# Kalau di-pipe (`curl ... | bash`) pertanyaan dilewati dan default dipakai,
# jadi untuk pola itu isi lewat env var:
#
#   MONOLITH=fancy-monolith-916 CLUSTER=fancy-prod-910 ORDERS=fancy-orders-432 \
#   PRODUCTS=fancy-products-402 FRONTEND=fancy-frontend-675 bash gsp319.sh
#
# Checkpoint:
#   Task 1 - Build monolith container            (otomatis)
#   Task 2 - Cluster + deploy monolith           (otomatis)
#   Task 3 - Container orders & products         (otomatis)
#   Task 4 - Deploy orders & products            (otomatis)
#   Task 5 - Konfigurasi frontend (.env + build) (otomatis, tidak ada checkpoint)
#   Task 6 - Container frontend                  (otomatis)
#   Task 7 - Deploy frontend                     (otomatis)
#
# Waktu jalan ~20-25 menit. Cluster dibuat paralel dengan build monolith supaya
# tidak menunggu dua kali. Script idempoten: aman diulang kalau gagal di tengah.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

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

ask ZONE     "us-central1-a"      "Zone cluster (cocokkan dengan panel lab)"
ask CLUSTER  "fancy-prod-910"     "Nama cluster"
ask MONOLITH "fancy-monolith-916" "Nama image monolith"
ask ORDERS   "fancy-orders-432"   "Nama image orders"
ask PRODUCTS "fancy-products-402" "Nama image products"
ask FRONTEND "fancy-frontend-675" "Nama image frontend"

VER="1.0.0"
SRC="$HOME/monolith-to-microservices"
LOGDIR="${TMPDIR:-/tmp}/gsp319"
mkdir -p "$LOGDIR"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

img() { echo "gcr.io/${PROJECT}/$1:${VER}"; }

# Build hanya kalau image belum ada, supaya rerun tidak membuang 3 menit.
build_image() {
  local name="$1" dir="$2"
  if gcloud container images describe "$(img "$name")" >/dev/null 2>&1; then
    echo "Image $(img "$name") sudah ada, lewati build."
    return
  fi
  ( cd "$dir" && gcloud builds submit --tag "$(img "$name")" . )
}

deploy_and_expose() {
  local name="$1" target_port="$2"
  kubectl get deployment "$name" >/dev/null 2>&1 || \
    kubectl create deployment "$name" --image="$(img "$name")"
  kubectl get service "$name" >/dev/null 2>&1 || \
    kubectl expose deployment "$name" --type=LoadBalancer --port 80 --target-port "$target_port"
}

# External IP LoadBalancer butuh ~1 menit muncul.
wait_ip() {
  local name="$1" ip=""
  for _ in $(seq 60); do
    ip="$(kubectl get service "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    [[ -n "$ip" ]] && { echo "$ip"; return; }
    sleep 10
  done
  echo "Timeout menunggu external IP service $name" >&2
  exit 1
}

# --------------------------------------------------------------------- Task 1
step "Enable API"
gcloud services enable container.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com --project="$PROJECT"

step "Task 2 (paralel): buat cluster $CLUSTER di $ZONE"
CLUSTER_PID=""
if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Cluster sudah ada."
else
  echo "Dibuat di latar belakang, log: $LOGDIR/cluster.log"
  gcloud container clusters create "$CLUSTER" \
    --zone="$ZONE" --num-nodes=3 --machine-type=e2-medium \
    --project="$PROJECT" >"$LOGDIR/cluster.log" 2>&1 &
  CLUSTER_PID=$!
fi

step "Task 1: clone repo + setup.sh"
[[ -d "$SRC" ]] || git clone https://github.com/googlecodelabs/monolith-to-microservices.git "$SRC"
if [[ -d "$SRC/react-app/node_modules" && -d "$SRC/microservices/src/frontend/public" ]]; then
  echo "Dependensi sudah terpasang, lewati setup.sh."
else
  ( cd "$SRC" && ./setup.sh )
fi

# nvm tidak ada di shell non-interaktif; muat dulu kalau ada.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh" && nvm install --lts >/dev/null 2>&1 || true
node --version

step "Task 1: build image monolith"
build_image "$MONOLITH" "$SRC/monolith"

# --------------------------------------------------------------------- Task 2
if [[ -n "$CLUSTER_PID" ]]; then
  step "Task 2: tunggu cluster selesai"
  wait "$CLUSTER_PID" || { echo "Pembuatan cluster gagal:"; cat "$LOGDIR/cluster.log"; exit 1; }
  tail -n 3 "$LOGDIR/cluster.log"
fi
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

step "Task 2: deploy + expose monolith (8080 -> 80)"
deploy_and_expose "$MONOLITH" 8080

# --------------------------------------------------------------------- Task 3
step "Task 3: build image orders dan products (paralel)"
build_image "$ORDERS"   "$SRC/microservices/src/orders"   >"$LOGDIR/orders.log"   2>&1 &
ORDERS_PID=$!
build_image "$PRODUCTS" "$SRC/microservices/src/products" >"$LOGDIR/products.log" 2>&1 &
PRODUCTS_PID=$!
wait "$ORDERS_PID"   || { cat "$LOGDIR/orders.log";   exit 1; }
wait "$PRODUCTS_PID" || { cat "$LOGDIR/products.log"; exit 1; }
tail -n 2 "$LOGDIR/orders.log" "$LOGDIR/products.log"

# --------------------------------------------------------------------- Task 4
step "Task 4: deploy + expose orders (8081) dan products (8082)"
deploy_and_expose "$ORDERS"   8081
deploy_and_expose "$PRODUCTS" 8082

ORDERS_IP="$(wait_ip "$ORDERS")"
PRODUCTS_IP="$(wait_ip "$PRODUCTS")"
echo "ORDERS_IP   = $ORDERS_IP"
echo "PRODUCTS_IP = $PRODUCTS_IP"

# --------------------------------------------------------------------- Task 5
step "Task 5: tulis ulang .env frontend dan build ulang react-app"
cat >"$SRC/react-app/.env" <<EOF
REACT_APP_ORDERS_URL=http://${ORDERS_IP}/api/orders
REACT_APP_PRODUCTS_URL=http://${PRODUCTS_IP}/api/products
EOF
cat "$SRC/react-app/.env"
# `npm run build` juga menyalin hasilnya ke microservices/src/frontend/public
# lewat postbuild, jadi image frontend ikut membawa URL baru.
( cd "$SRC/react-app" && npm run build )

# --------------------------------------------------------------------- Task 6
step "Task 6: build image frontend"
# Image lama (kalau ada dari percobaan sebelumnya) membawa URL localhost, hapus
# dulu supaya build_image tidak melewatinya.
gcloud container images delete "$(img "$FRONTEND")" --quiet --force-delete-tags >/dev/null 2>&1 || true
build_image "$FRONTEND" "$SRC/microservices/src/frontend"

# --------------------------------------------------------------------- Task 7
step "Task 7: deploy + expose frontend (8080 -> 80)"
deploy_and_expose "$FRONTEND" 8080
# Tag-nya tetap 1.0.0 padahal isinya berubah (URL microservice). Default
# imagePullPolicy untuk tag non-latest itu IfNotPresent, jadi pada rerun node
# akan memakai image lama yang masih menunjuk localhost. Paksa pull ulang.
kubectl patch deployment "$FRONTEND" -p \
  "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"${FRONTEND}\",\"imagePullPolicy\":\"Always\"}]}}}}"
kubectl rollout status deployment/"$FRONTEND" --timeout=180s
FRONTEND_IP="$(wait_ip "$FRONTEND")"

MONOLITH_IP="$(wait_ip "$MONOLITH")"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  Task 1 - Download the monolith code and build your container
  Task 2 - Create a kubernetes cluster and deploy the application
  Task 3 - Create a containerized version of orders and product Microservices
  Task 4 - Deploy the new microservices
  Task 6 - Create a containerized version of the Frontend microservice
  Task 7 - Deploy the Frontend microservice

Alamat:
  Monolith  http://${MONOLITH_IP}
  Orders    http://${ORDERS_IP}/api/orders
  Products  http://${PRODUCTS_IP}/api/products
  Frontend  http://${FRONTEND_IP}
==============================================================
EOF

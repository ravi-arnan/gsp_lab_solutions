#!/usr/bin/env bash
# GSP343 - Optimize Costs for Google Kubernetes Engine: Challenge Lab
#
#   bash gsp343.sh
#
# Checkpoint:
#   Task 1  - Create the cluster and deploy an app
#   Task 2  - Migrate to an optimized node pool
#   Task 3  - Apply a Frontend Update
#   Task 4  - Autoscale from estimated traffic
#
# Angka pada nama resource (cluster & node pool) bisa berbeda tiap instance lab.
# Skrip menanyakan nilai default yang disesuaikan atau membaca dari environment:
#   CLUSTER=onlineboutique-cluster-445 POOL=optimized-pool-6743 bash gsp343.sh

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

ask ZONE "europe-west4-c" "Zone (cocokkan dengan panel lab)"
ask CLUSTER "onlineboutique-cluster-445" "Nama cluster (cocokkan dengan teks task)"
ask POOL "optimized-pool-6743" "Nama node pool baru (cocokkan dengan teks task)"

PDB="${PDB:-onlineboutique-frontend-pdb}"
NEW_IMAGE="gcr.io/qwiklabs-resources/onlineboutique-frontend:v2.1"
REPO="$HOME/microservices-demo"

echo "Project : $PROJECT"
echo "Zone    : $ZONE"
echo "Cluster : $CLUSTER"
echo "Pool    : $POOL"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

warn_wait() { "$@" || echo "PERINGATAN: '$*' tidak selesai tepat waktu. Melanjutkan langkah berikutnya."; }

frontend_ip() {
  kubectl get service frontend-external -n dev \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
}

# ----------------------------------------------------------------- Task 1
step "Task 1a: Create cluster $CLUSTER (2 node, e2-standard-2, rapid channel)"
if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  echo "Cluster $CLUSTER sudah ada, dilewat."
else
  gcloud container clusters create "$CLUSTER" \
    --zone="$ZONE" \
    --num-nodes=2 \
    --machine-type=e2-standard-2 \
    --release-channel=rapid -q
fi
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

step "Task 1b: Create namespace dev dan prod"
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -

step "Task 1c: Deploy OnlineBoutique ke namespace dev"
if [ -d "$REPO" ]; then
  echo "Repo sudah ada di $REPO, dilewat clone."
else
  git clone https://github.com/GoogleCloudPlatform/microservices-demo.git "$REPO"
fi
kubectl apply -f "$REPO/release/kubernetes-manifests.yaml" --namespace dev

if [[ -z "${DRYRUN:-}" ]]; then
  echo "--- menunggu deployment di namespace dev siap:"
  warn_wait kubectl wait --for=condition=available --timeout=300s deployment --all -n dev
fi

# ----------------------------------------------------------------- Task 2
step "Task 2a: Create node pool $POOL (e2-custom-2-3584, 2 node)"
if gcloud container node-pools describe "$POOL" --cluster="$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  echo "Node pool $POOL sudah ada, dilewat."
else
  gcloud container node-pools create "$POOL" \
    --cluster="$CLUSTER" \
    --zone="$ZONE" \
    --machine-type=e2-custom-2-3584 \
    --num-nodes=2 -q 2>/dev/null \
    || gcloud container node-pools create "$POOL" \
         --cluster="$CLUSTER" \
         --zone="$ZONE" \
         --machine-type=custom-2-3584 \
         --num-nodes=2 -q
fi

step "Task 2b: Cordon dan drain default-pool"
DEFAULT_NODES="$(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o name 2>/dev/null || true)"
if [[ -z "$DEFAULT_NODES" ]]; then
  echo "default-pool sudah tidak ada node, dilewat."
else
  for node in $DEFAULT_NODES; do
    echo "--- cordon $node"
    kubectl cordon "$node" || true
  done
  for node in $DEFAULT_NODES; do
    echo "--- drain $node"
    kubectl drain "$node" --force --ignore-daemonsets --delete-emptydir-data --timeout=300s || true
  done
fi

step "Task 2c: Delete default-pool"
if gcloud container node-pools describe default-pool --cluster="$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  gcloud container node-pools delete default-pool \
    --cluster="$CLUSTER" --zone="$ZONE" --quiet
else
  echo "default-pool sudah dihapus, dilewat."
fi

if [[ -z "${DRYRUN:-}" ]]; then
  echo "--- menunggu deployment sehat kembali di node pool baru:"
  warn_wait kubectl wait --for=condition=available --timeout=300s deployment --all -n dev
fi

# ----------------------------------------------------------------- Task 3
step "Task 3a: Pod disruption budget $PDB (min-available 1)"
kubectl delete pdb "$PDB" -n dev --ignore-not-found 2>/dev/null || true
kubectl create poddisruptionbudget "$PDB" \
  --namespace=dev --selector app=frontend --min-available 1 \
  --dry-run=client -o yaml | kubectl apply -f -

step "Task 3b: Update image frontend + imagePullPolicy Always"
kubectl patch deployment frontend -n dev --type=strategic -p \
  "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"server\",\"image\":\"$NEW_IMAGE\",\"imagePullPolicy\":\"Always\"}]}}}}"

if [[ -z "${DRYRUN:-}" ]]; then
  echo "--- menunggu rollout deployment frontend selesai:"
  warn_wait kubectl rollout status deployment/frontend -n dev --timeout=180s
fi

# ----------------------------------------------------------------- Task 4
step "Task 4a: HPA frontend (cpu 50%, min 1, max 12)"
kubectl delete hpa frontend -n dev --ignore-not-found 2>/dev/null || true
kubectl autoscale deployment frontend -n dev --cpu-percent=50 --min=1 --max=12

step "Task 4b: Cluster autoscaler pada $POOL (1-6 node)"
gcloud container clusters update "$CLUSTER" \
  --zone="$ZONE" \
  --enable-autoscaling \
  --node-pool="$POOL" \
  --min-nodes=1 \
  --max-nodes=6 -q

step "Task 4c: HPA recommendationservice (cpu 50%, min 1, max 5)"
kubectl delete hpa recommendationservice -n dev --ignore-not-found 2>/dev/null || true
kubectl autoscale deployment recommendationservice -n dev --cpu-percent=50 --min=1 --max=5

echo "--- Status HPA di namespace dev:"
kubectl get hpa -n dev

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Create the cluster $CLUSTER and deploy an app
  2. Migrate to an optimized node pool
  3. Apply a Frontend Update
  4. Autoscale from estimated traffic
==============================================================
EOF

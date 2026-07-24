#!/usr/bin/env bash
# GSP343 - Optimize Costs for Google Kubernetes Engine: Challenge Lab
#
# Cara pakai (JANGAN di-pipe ke bash, script ini punya fase):
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp343.sh
#   bash gsp343.sh
#
# Angka pada nama resource bisa beda tiap instance lab. Cocokkan dengan
# halaman lab-mu, override lewat env kalau perlu:
#   CLUSTER=onlineboutique-cluster-111 POOL=optimized-pool-2515 bash gsp343.sh
#
# Checkpoint:
#   Task 1 - Create the cluster and deploy an app
#   Task 2 - Migrate to an optimized node pool
#   Task 3 - Apply a Frontend Update
#   Task 4 - Autoscale from estimated traffic
#
# Load test (Task 4, tidak di-score) dijalankan terpisah:
#   bash gsp343.sh loadtest

set -euo pipefail

ZONE="${ZONE:-us-west1-b}"
CLUSTER="${CLUSTER:-onlineboutique-cluster-111}"
POOL="${POOL:-optimized-pool-2515}"
PDB="${PDB:-onlineboutique-frontend-pdb}"
NEW_IMAGE="gcr.io/qwiklabs-resources/onlineboutique-frontend:v2.1"
REPO="$HOME/microservices-demo"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Wait yang gagal bukan alasan menghentikan script: checkpoint membaca spec
# deployment, bukan kesehatan pod. Cukup peringatkan.
warn_wait() { "$@" || echo "PERINGATAN: '$*' tidak selesai. Lanjut; cek 'kubectl get pods -n dev'."; }

frontend_ip() {
  kubectl get service frontend-external -n dev \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
}

# --------------------------------------------------------------- loadtest
# Fase terpisah: butuh IP frontend sudah keluar, dan blocking sampai Ctrl-C.
if [[ "${1:-}" == "loadtest" ]]; then
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"
  IP="$(frontend_ip)"
  [[ -n "$IP" ]] || { echo "IP frontend-external belum ada. Tunggu sebentar lalu ulangi."; exit 1; }
  echo "Load test ke http://$IP dengan 8000 user. Ctrl-C untuk berhenti."
  kubectl exec "$(kubectl get pod --namespace=dev | grep 'loadgenerator' | cut -f1 -d ' ')" \
    -it --namespace=dev -- sh -c "export USERS=8000; locust --host=\"http://$IP\" --headless -u \"8000\" 2>&1"
  exit 0
fi

echo "Project: $PROJECT"
echo "Zone   : $ZONE"
echo "Cluster: $CLUSTER"
echo "Pool   : $POOL"

# ----------------------------------------------------------------- Task 1
step "Task 1a: Create cluster $CLUSTER (2 node, e2-standard-2, rapid channel)"
if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  echo "Cluster sudah ada, dilewat."
else
  gcloud container clusters create "$CLUSTER" \
    --zone="$ZONE" \
    --num-nodes=2 \
    --machine-type=e2-standard-2 \
    --release-channel=rapid
fi
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

step "Task 1b: Create namespace dev dan prod"
kubectl create namespace dev 2>/dev/null || echo "dev sudah ada"
kubectl create namespace prod 2>/dev/null || echo "prod sudah ada"

step "Task 1c: Deploy OnlineBoutique ke namespace dev"
if [ -d "$REPO" ]; then
  echo "Repo sudah ada di $REPO, dilewat clone."
else
  git clone https://github.com/GoogleCloudPlatform/microservices-demo.git "$REPO"
fi
kubectl apply -f "$REPO/release/kubernetes-manifests.yaml" --namespace dev

echo "--- tunggu semua deployment siap (bisa 2-3 menit):"
warn_wait kubectl wait --for=condition=available --timeout=600s deployment --all -n dev

echo "--- tunggu external IP frontend:"
for _ in $(seq 60); do
  IP="$(frontend_ip)"
  [[ -n "$IP" ]] && break
  sleep 5
done
echo "Frontend: http://${IP:-<belum keluar>}"

echo ""
echo "Klik Check my progress: Task 1 - Create the cluster and deploy an app"

# ----------------------------------------------------------------- Task 2
step "Task 2a: Create node pool $POOL (custom-2-3584, 2 node)"
if gcloud container node-pools describe "$POOL" --cluster="$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  echo "Node pool sudah ada, dilewat."
else
  gcloud container node-pools create "$POOL" \
    --cluster="$CLUSTER" \
    --zone="$ZONE" \
    --machine-type=custom-2-3584 \
    --num-nodes=2
fi

step "Task 2b: Cordon dan drain default-pool"
DEFAULT_NODES="$(kubectl get nodes -l cloud.google.com/gke-nodepool=default-pool -o name || true)"
if [[ -z "$DEFAULT_NODES" ]]; then
  echo "default-pool sudah tidak ada node, dilewat."
else
  for node in $DEFAULT_NODES; do
    echo "--- cordon $node"
    kubectl cordon "$node"
  done
  for node in $DEFAULT_NODES; do
    echo "--- drain $node"
    # --force: pod loadgenerator dkk tanpa controller. --delete-emptydir-data: redis.
    kubectl drain "$node" --force --ignore-daemonsets --delete-emptydir-data --timeout=300s
  done
fi

step "Task 2c: Delete default-pool"
if gcloud container node-pools describe default-pool --cluster="$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  gcloud container node-pools delete default-pool \
    --cluster="$CLUSTER" --zone="$ZONE" --quiet
else
  echo "default-pool sudah dihapus, dilewat."
fi

echo "--- tunggu deployment sehat lagi di node pool baru:"
warn_wait kubectl wait --for=condition=available --timeout=600s deployment --all -n dev

echo ""
echo "Klik Check my progress: Task 2 - Migrate to an optimized node pool"

# ----------------------------------------------------------------- Task 3
step "Task 3a: Pod disruption budget $PDB (min-available 1)"
kubectl delete pdb "$PDB" -n dev --ignore-not-found
kubectl create poddisruptionbudget "$PDB" \
  --namespace=dev --selector app=frontend --min-available 1

step "Task 3b: Update image frontend + imagePullPolicy Always"
# Strategic merge patch: match container by name, ubah dua field sekaligus.
kubectl patch deployment frontend -n dev --type=strategic -p \
  "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"server\",\"image\":\"$NEW_IMAGE\",\"imagePullPolicy\":\"Always\"}]}}}}"

echo "--- tunggu rollout selesai:"
warn_wait kubectl rollout status deployment/frontend -n dev --timeout=300s

echo ""
echo "Klik Check my progress: Task 3 - Apply a Frontend Update"

# ----------------------------------------------------------------- Task 4
step "Task 4a: HPA frontend (cpu 50%, 1-11 pod)"
kubectl delete hpa frontend -n dev --ignore-not-found
kubectl autoscale deployment frontend -n dev --cpu-percent=50 --min=1 --max=11

step "Task 4b: Cluster autoscaler pada $POOL (1-6 node)"
gcloud container clusters update "$CLUSTER" \
  --zone="$ZONE" \
  --enable-autoscaling \
  --node-pool="$POOL" \
  --min-nodes=1 \
  --max-nodes=6

step "Task 4c: HPA recommendationservice (cpu 50%, 1-5 pod)"
kubectl delete hpa recommendationservice -n dev --ignore-not-found
kubectl autoscale deployment recommendationservice -n dev --cpu-percent=50 --min=1 --max=5

echo "--- HPA terpasang:"
kubectl get hpa -n dev

echo ""
echo "Klik Check my progress: Task 4 - Autoscale from estimated traffic"

IP="$(frontend_ip)"
cat <<EOF

==============================================================
SELESAI. Semua checkpoint yang di-score sudah dikerjakan.

Toko: http://${IP:-<cek: kubectl get svc frontend-external -n dev>}

Load test (tidak di-score, cuma untuk melihat autoscaling bekerja):

  bash gsp343.sh loadtest

Sambil jalan, pantau di tab lain:

  kubectl get hpa -n dev -w
  kubectl get nodes -w

Ctrl-C untuk menghentikan load test.
==============================================================
EOF

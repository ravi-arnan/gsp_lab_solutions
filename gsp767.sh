#!/usr/bin/env bash
# GSP767 - Exploring Cost-optimization for GKE Virtual Machines
#
#   bash gsp767.sh
#
# Checkpoint:
#   Task 2 (25 pts)  - Scale Up Hello App
#   Task 2 (25 pts)  - Create node pool
#   Task 3 (25 pts)  - Check Pod Creation
#   Task 3 (25 pts)  - Simulate Traffic
#
# Catatan:
#   Terdapat jeda interaktif singkat (read -r) setelah pod-1 dan pod-2 dibuat
#   agar pengguna sempat mengecek checkpoint "Check Pod Creation" sebelum pod-2
#   dimigrasikan ke node yang sama dengan pod-1.

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

# Deteksi otomatis zone dari cluster hello-demo-cluster yang sudah ada
DETECTED_ZONE="$(gcloud container clusters list --filter="name=hello-demo-cluster" --format="value(zone)" 2>/dev/null | head -n1 || true)"
if [[ -n "$DETECTED_ZONE" ]]; then
  DETECTED_REGION="${DETECTED_ZONE%-*}"
else
  DETECTED_ZONE="europe-west1-b"
  DETECTED_REGION="europe-west1"
fi

ask ZONE "$DETECTED_ZONE" "Zone (cocokkan dengan panel lab)"
ask REGION "${DETECTED_REGION:-europe-west1}" "Region (cocokkan dengan panel lab)"
ask CLUSTER "hello-demo-cluster" "Nama cluster (cocokkan dengan teks task)"

OLD_POOL="${OLD_POOL:-my-node-pool}"
NEW_POOL="${NEW_POOL:-larger-pool}"
RCLUSTER="${RCLUSTER:-regional-demo}"

echo "Project : $PROJECT"
echo "Zone    : $ZONE ($CLUSTER)"
echo "Region  : $REGION ($RCLUSTER)"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 2
step "Task 2a: Scale hello-server ke 2 replica"
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"
kubectl scale deployment hello-server --replicas=2

step "Task 2b: Resize $OLD_POOL ke 4 node"
# Replica kedua membutuhkan alokasi CPU tambahan; perbesar pool lama terlebih dahulu
gcloud container clusters resize "$CLUSTER" \
  --node-pool="$OLD_POOL" --num-nodes=4 --zone="$ZONE" --quiet

if [[ -z "${DRYRUN:-}" ]]; then
  echo "--- menunggu deployment hello-server siap:"
  kubectl wait --for=condition=available --timeout=300s deployment/hello-server || true
fi

step "Task 2c: Create node pool $NEW_POOL (e2-standard-2, 1 node)"
if gcloud container node-pools describe "$NEW_POOL" --cluster="$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  echo "Node pool $NEW_POOL sudah ada, dilewat."
else
  gcloud container node-pools create "$NEW_POOL" \
    --cluster="$CLUSTER" \
    --machine-type=e2-standard-2 \
    --num-nodes=1 \
    --zone="$ZONE" -q
fi

step "Task 2d: Cordon dan drain $OLD_POOL"
for node in $(kubectl get nodes -l "cloud.google.com/gke-nodepool=$OLD_POOL" -o=name 2>/dev/null || true); do
  kubectl cordon "$node" || true
done
for node in $(kubectl get nodes -l "cloud.google.com/gke-nodepool=$OLD_POOL" -o=name 2>/dev/null || true); do
  echo "--- drain $node"
  kubectl drain --force --ignore-daemonsets --delete-emptydir-data --grace-period=10 "$node" || true
done

echo "--- verifikasi pods berjalan di $NEW_POOL:"
kubectl get pods -o=wide

step "Task 2e: Delete $OLD_POOL"
if gcloud container node-pools describe "$OLD_POOL" --cluster="$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  gcloud container node-pools delete "$OLD_POOL" --cluster="$CLUSTER" --zone="$ZONE" --quiet
else
  echo "$OLD_POOL sudah dihapus, dilewat."
fi

# ----------------------------------------------------------------- Task 3
step "Task 3a: Create regional cluster $RCLUSTER"
if gcloud container clusters describe "$RCLUSTER" --region="$REGION" >/dev/null 2>&1; then
  echo "Cluster $RCLUSTER sudah ada, dilewat."
else
  gcloud container clusters create "$RCLUSTER" --region="$REGION" --num-nodes=1 -q
fi
gcloud container clusters get-credentials "$RCLUSTER" --region="$REGION" --project="$PROJECT"

step "Task 3b: Create pod-1 dan pod-2 (podAntiAffinity, beda node)"
cat > pod-1.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pod-1
  labels:
    security: demo
spec:
  containers:
  - name: container-1
    image: wbitt/network-multitool
EOF

cat > pod-2.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pod-2
spec:
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
          - key: security
            operator: In
            values:
            - demo
        topologyKey: "kubernetes.io/hostname"
  containers:
  - name: container-2
    image: us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
EOF

kubectl apply -f pod-1.yaml
kubectl apply -f pod-2.yaml

if [[ -z "${DRYRUN:-}" ]]; then
  echo "--- menunggu kedua pod siap:"
  kubectl wait --for=condition=ready --timeout=300s pod/pod-1 pod/pod-2 || true
fi
kubectl get pod pod-1 pod-2 --output wide

step "Task 3c: Enable VPC flow logs di subnet $REGION"
gcloud compute networks subnets update default --region="$REGION" \
  --enable-flow-logs \
  --logging-metadata=include-all \
  --logging-flow-sampling=1.0 \
  --logging-aggregation-interval=interval-5-sec -q 2>/dev/null || true

step "Task 3d: Sink FlowLogsSample ke BigQuery dataset us_flow_logs"
bq mk --location=US --dataset "${PROJECT}:us_flow_logs" 2>/dev/null || echo "Dataset sudah ada"
if gcloud logging sinks describe FlowLogsSample >/dev/null 2>&1; then
  echo "Sink FlowLogsSample sudah ada, dilewat."
else
  gcloud logging sinks create FlowLogsSample \
    "bigquery.googleapis.com/projects/${PROJECT}/datasets/us_flow_logs" \
    --log-filter="logName=\"projects/${PROJECT}/logs/compute.googleapis.com%2Fvpc_flows\"" -q
fi

SA="$(gcloud logging sinks describe FlowLogsSample --format='value(writerIdentity)' 2>/dev/null || true)"
if [[ -n "$SA" ]]; then
  bq show --format=prettyjson "${PROJECT}:us_flow_logs" > /tmp/ds.json 2>/dev/null || true
  if [[ -f /tmp/ds.json ]]; then
    jq --arg sa "${SA#serviceAccount:}" \
      'if any(.access[]; .userByEmail == $sa) then . else .access += [{"role":"WRITER","userByEmail":$sa}] end' \
      /tmp/ds.json > /tmp/ds2.json 2>/dev/null || true
    if [[ -f /tmp/ds2.json ]]; then
      bq update --source /tmp/ds2.json "${PROJECT}:us_flow_logs" 2>/dev/null || true
    fi
  fi
fi

POD2_IP="$(kubectl get pod pod-2 -o jsonpath='{.status.podIP}' 2>/dev/null || true)"
step "Task 3e: Ping lintas-zona (pod beda node)"
if [[ -n "$POD2_IP" ]]; then
  kubectl exec pod-1 -- ping -c 10 "$POD2_IP" || true
fi

cat <<EOF

==============================================================
BERHENTI SEBENTAR.

Silakan klik Check my progress di panel lab untuk:
  1. Scale Up Hello App
  2. Create node pool
  3. Check Pod Creation (SEKARANG selagi pod-1 dan pod-2 beda node)

Tekan ENTER untuk lanjut memindahkan pod-2 ke node yang sama...
==============================================================
EOF
read -r _

step "Task 3f: Ubah podAntiAffinity jadi podAffinity, recreate pod-2"
sed -i 's/podAntiAffinity/podAffinity/g' pod-2.yaml
kubectl delete pod pod-2 --ignore-not-found 2>/dev/null || true
kubectl create -f pod-2.yaml

if [[ -z "${DRYRUN:-}" ]]; then
  echo "--- menunggu pod-2 siap di node yang sama:"
  kubectl wait --for=condition=ready --timeout=300s pod/pod-2 || true
fi
kubectl get pod pod-1 pod-2 --output wide

POD2_IP="$(kubectl get pod pod-2 -o jsonpath='{.status.podIP}' 2>/dev/null || true)"
step "Task 3g: Ping satu node (latensi rendah / intra-node)"
if [[ -n "$POD2_IP" ]]; then
  kubectl exec pod-1 -- ping -c 5 "$POD2_IP" || true
fi

step "Task 3h: Query flow logs di BigQuery (wajib untuk penilaian Simulate Traffic)"
echo "--- menunggu sink Cloud Logging mengekspor data ke BigQuery:"
TABLE=""
if [[ -z "${DRYRUN:-}" ]]; then
  for _ in $(seq 30); do
    TABLE="$(bq ls --format=sparse "${PROJECT}:us_flow_logs" 2>/dev/null | grep -E 'vpc_flows' | awk '{print $1}' | head -n1 || true)"
    if [[ -n "$TABLE" ]]; then
      break
    fi
    sleep 3
  done
else
  TABLE="compute_googleapis_com_vpc_flows_dryrun"
fi

if [[ -n "$TABLE" ]]; then
  echo "Menjalankan kueri flow logs lintas-zona pada tabel $TABLE..."
  bq query --use_legacy_sql=false \
    "SELECT jsonPayload.src_instance.zone AS src_zone, jsonPayload.src_instance.vm_name AS src_vm, jsonPayload.dest_instance.zone AS dest_zone, jsonPayload.dest_instance.vm_name FROM \`${PROJECT}.us_flow_logs.${TABLE}\` LIMIT 50" 2>/dev/null || true
else
  echo "Tabel flow logs belum terbentuk. Silakan jalankan query manual di Console bila poin belum masuk."
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  4. Simulate Traffic
==============================================================
EOF

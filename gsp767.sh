#!/usr/bin/env bash
# GSP767 - Exploring Cost-optimization for GKE Virtual Machines
#
# Cluster hello-demo-cluster sudah di-provision lab di us-east1-d.
# Script ini mengerjakan 4 checkpoint yang di-score.
#
# Cara pakai (JANGAN di-pipe ke bash):
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp767.sh
#   bash gsp767.sh
#
# Checkpoint:
#   Task 2a - Scale Up Hello App
#   Task 2c - Create node pool
#   Task 3b - Check Pod Creation
#   Task 3h - Simulate Traffic (flow logs + sink + query)
#
# Script berhenti sekali dan menunggu ENTER (setelah Task 3e) supaya kamu
# sempat klik "Check Pod Creation" selagi pod-1 dan pod-2 masih beda node.

set -euo pipefail

ZONE="${ZONE:-us-east1-d}"
REGION="${REGION:-us-east1}"
CLUSTER="${CLUSTER:-hello-demo-cluster}"
OLD_POOL="${OLD_POOL:-my-node-pool}"
NEW_POOL="${NEW_POOL:-larger-pool}"
RCLUSTER="${RCLUSTER:-regional-demo}"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

echo "Project : $PROJECT"
echo "Zone    : $ZONE (hello-demo-cluster)"
echo "Region  : $REGION (regional-demo)"

# ----------------------------------------------------------------- Task 2
step "Task 2a: Scale hello-server ke 2 replica"
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"
kubectl scale deployment hello-server --replicas=2

echo ""
echo "Klik Check my progress: Scale Up Hello App"

step "Task 2b: Resize $OLD_POOL ke 4 node"
# Replica kedua butuh 400m cpu lagi; pool lama kehabisan. Resize dulu supaya
# hello-server sehat sebelum dimigrasi.
gcloud container clusters resize "$CLUSTER" \
  --node-pool="$OLD_POOL" --num-nodes=4 --zone="$ZONE" --quiet

echo "--- tunggu hello-server siap:"
kubectl wait --for=condition=available --timeout=300s deployment/hello-server \
  || echo "PERINGATAN: hello-server belum available, lanjut."

step "Task 2c: Create node pool $NEW_POOL (e2-standard-2, 1 node)"
if gcloud container node-pools describe "$NEW_POOL" --cluster="$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  echo "Node pool sudah ada, dilewat."
else
  gcloud container node-pools create "$NEW_POOL" \
    --cluster="$CLUSTER" \
    --machine-type=e2-standard-2 \
    --num-nodes=1 \
    --zone="$ZONE"
fi

echo ""
echo "Klik Check my progress: Create node pool"

step "Task 2d: Cordon dan drain $OLD_POOL"
for node in $(kubectl get nodes -l "cloud.google.com/gke-nodepool=$OLD_POOL" -o=name); do
  kubectl cordon "$node"
done
for node in $(kubectl get nodes -l "cloud.google.com/gke-nodepool=$OLD_POOL" -o=name); do
  echo "--- drain $node"
  kubectl drain --force --ignore-daemonsets --delete-emptydir-data --grace-period=10 "$node"
done

echo "--- pod sekarang jalan di $NEW_POOL:"
kubectl get pods -o=wide

step "Task 2e: Delete $OLD_POOL"
if gcloud container node-pools describe "$OLD_POOL" --cluster="$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  gcloud container node-pools delete "$OLD_POOL" --cluster="$CLUSTER" --zone="$ZONE" --quiet
else
  echo "$OLD_POOL sudah dihapus, dilewat."
fi

# ----------------------------------------------------------------- Task 3
step "Task 3a: Create regional cluster $RCLUSTER (butuh ~5 menit)"
if gcloud container clusters describe "$RCLUSTER" --region="$REGION" >/dev/null 2>&1; then
  echo "Cluster sudah ada, dilewat."
else
  gcloud container clusters create "$RCLUSTER" --region="$REGION" --num-nodes=1
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

echo "--- tunggu kedua pod Running:"
kubectl wait --for=condition=ready --timeout=300s pod/pod-1 pod/pod-2 \
  || echo "PERINGATAN: pod belum ready."
kubectl get pod pod-1 pod-2 --output wide

step "Task 3c: Enable VPC flow logs di subnet $REGION"
# Di-score (checkpoint "Simulate Traffic"), bukan sekadar langkah UI.
# --logging-metadata=include-all WAJIB: tanpa itu log cuma berisi bytes_sent
# dkk, tanpa src_instance/dest_instance, dan query Task 3g gagal. UI defaultnya
# include-all, gcloud tidak.
gcloud compute networks subnets update default --region="$REGION" \
  --enable-flow-logs \
  --logging-metadata=include-all \
  --logging-flow-sampling=1.0 \
  --logging-aggregation-interval=interval-5-sec
gcloud compute networks subnets describe default --region="$REGION" \
  --format='value(enableFlowLogs)'

step "Task 3d: Sink FlowLogsSample ke BigQuery dataset us_flow_logs"
# Juga di-score. Dibuat sebelum ping supaya trafiknya ikut terekspor.
bq mk --location=US --dataset "${PROJECT}:us_flow_logs" 2>/dev/null || echo "Dataset sudah ada"
if gcloud logging sinks describe FlowLogsSample >/dev/null 2>&1; then
  echo "Sink sudah ada, dilewat."
else
  gcloud logging sinks create FlowLogsSample \
    "bigquery.googleapis.com/projects/${PROJECT}/datasets/us_flow_logs" \
    --log-filter="logName=\"projects/${PROJECT}/logs/compute.googleapis.com%2Fvpc_flows\""
fi

# Akun student tidak punya setIamPolicy di level project, jadi izin writer
# diberikan di level dataset (memang scope yang benar).
SA="$(gcloud logging sinks describe FlowLogsSample --format='value(writerIdentity)')"
bq show --format=prettyjson "${PROJECT}:us_flow_logs" > /tmp/ds.json
jq --arg sa "${SA#serviceAccount:}" \
  'if any(.access[]; .userByEmail == $sa) then . else .access += [{"role":"WRITER","userByEmail":$sa}] end' \
  /tmp/ds.json > /tmp/ds2.json
bq update --source /tmp/ds2.json "${PROJECT}:us_flow_logs"

POD2_IP="$(kubectl get pod pod-2 -o jsonpath='{.status.podIP}')"
step "Task 3e: Ping lintas-zona (pod beda node)"
kubectl exec pod-1 -- ping -c 30 "$POD2_IP" || echo "PERINGATAN: ping gagal."

cat <<EOF

==============================================================
BERHENTI SEBENTAR.

Klik Check my progress: "Check Pod Creation" SEKARANG, selagi
pod-1 dan pod-2 masih di node berbeda.

Tekan ENTER kalau sudah hijau, script lanjut memindahkan pod-2.
==============================================================
EOF
read -r _

step "Task 3f: Ubah podAntiAffinity jadi podAffinity, recreate pod-2"
sed -i 's/podAntiAffinity/podAffinity/g' pod-2.yaml
kubectl delete pod pod-2
kubectl create -f pod-2.yaml

echo "--- tunggu pod-2 ready:"
kubectl wait --for=condition=ready --timeout=300s pod/pod-2 \
  || echo "PERINGATAN: pod-2 belum ready."
kubectl get pod pod-1 pod-2 --output wide

POD2_IP="$(kubectl get pod pod-2 -o jsonpath='{.status.podIP}')"
step "Task 3g: Ping satu node (bandingkan dengan Task 3e)"
kubectl exec pod-1 -- ping -c 10 "$POD2_IP" || echo "PERINGATAN: ping gagal."

step "Task 3h: Query flow logs, cari trafik lintas-zona"
# Sink baru menambah kolom ke schema BigQuery setelah log-nya benar-benar
# masuk, jadi tunggu src_instance muncul dulu.
echo "--- tunggu kolom src_instance muncul di BigQuery (bisa ~5 menit):"
TABLE=""
for _ in $(seq 40); do
  TABLE="$(bq ls --format=json "${PROJECT}:us_flow_logs" 2>/dev/null \
    | jq -r '.[0].tableReference.tableId // empty')"
  if [[ -n "$TABLE" ]] && bq show --schema "${PROJECT}:us_flow_logs.${TABLE}" 2>/dev/null \
      | jq -e '.[] | select(.name=="jsonPayload") | .fields[] | select(.name=="src_instance")' >/dev/null; then
    break
  fi
  sleep 15
done

if [[ -z "$TABLE" ]]; then
  echo "PERINGATAN: tabel flow logs belum terbentuk. Ulangi query ini nanti manual."
else
  bq query --use_legacy_sql=false \
"SELECT jsonPayload.src_instance.zone AS src_zone, jsonPayload.src_instance.vm_name AS src_vm, jsonPayload.dest_instance.zone AS dest_zone, jsonPayload.dest_instance.vm_name FROM \`${PROJECT}.us_flow_logs.${TABLE}\` WHERE jsonPayload.src_instance.zone != jsonPayload.dest_instance.zone LIMIT 50"
fi

cat <<EOF

==============================================================
SELESAI. Klik Check my progress: "Simulate Traffic"

Bandingkan angka rtt avg di Task 3e (beda node, lintas zona,
egress \$0.01/GB) dengan Task 3g (satu node, gratis).
==============================================================
EOF

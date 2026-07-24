#!/usr/bin/env bash
# GSP766 - Managing a GKE Multi-tenant Cluster with Namespaces
#
# Cluster multi-tenant-cluster sudah di-provision oleh lab di us-east1-d.
# Script ini mengerjakan Task 1-4 dan sebagian Task 5 (sampai cost breakdown table).
# Task 5 bagian Data Studio (dashboard) harus dikerjakan manual di Console.
#
# Cara pakai (JANGAN di-pipe ke bash):
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp766.sh
#   bash gsp766.sh
#
# Task 5d (bq query --schedule) minta paste version_info secara interaktif,
# jadi stdin harus terminal. `curl ... | bash` akan gagal di situ.
#
# Checkpoint:
#   Task 2  - Create namespaces
#   Task 3  - Access Control in namespaces
#   Task 4  - Resource quotas
#   Task 5  - Monitoring GKE and GKE usage metering (checkpoint di BigQuery setup)

set -euo pipefail

ZONE="us-east1-d"
CLUSTER="multi-tenant-cluster"
WORKDIR="$HOME/gke-qwiklab"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "Project: $PROJECT"
echo "Zone   : $ZONE"
echo "Cluster: $CLUSTER"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
step "Task 1: Download required files"
if [ -d "$WORKDIR" ]; then
  echo "Direktori $WORKDIR sudah ada, dilewat."
else
  gsutil -m cp -r gs://spls/gsp766/gke-qwiklab ~
fi
cd "$WORKDIR"
echo "Working directory: $(pwd)"

# ----------------------------------------------------------------- Task 2
step "Task 2: View and create namespaces"
gcloud config set compute/zone "$ZONE"
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

echo "--- namespaces saat ini:"
kubectl get namespace

echo "--- buat namespace team-a dan team-b:"
kubectl create namespace team-a 2>/dev/null || echo "team-a sudah ada"
kubectl create namespace team-b 2>/dev/null || echo "team-b sudah ada"

echo "--- deploy app-server di team-a dan team-b:"
kubectl run app-server --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity 2>/dev/null \
  || echo "app-server di team-a sudah ada"
kubectl run app-server --image=quay.io/centos/centos:9 --namespace=team-b -- sleep infinity 2>/dev/null \
  || echo "app-server di team-b sudah ada"

echo "--- semua pods:"
kubectl get pods -A

# Lab menyetel context ke team-a di sini. Tanpa ini, perintah kubectl tanpa
# --namespace mendarat di `default` dan checkpoint gagal.
kubectl config set-context --current --namespace=team-a

echo ""
echo "Klik Check my progress: Task 2 - Create namespaces"

# ----------------------------------------------------------------- Task 3
step "Task 3: Access Control in namespaces"

step "Task 3a: Grant IAM role Kubernetes Engine Cluster Viewer"
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:team-a-dev@${PROJECT}.iam.gserviceaccount.com" \
  --role=roles/container.clusterViewer 2>/dev/null \
  || echo "IAM binding sudah ada"

step "Task 3b: Create pod-reader role in team-a namespace"
kubectl delete role pod-reader --namespace=team-a --ignore-not-found 2>/dev/null || true
kubectl create role pod-reader --namespace=team-a \
  --resource=pods --verb=watch --verb=get --verb=list

step "Task 3c: Create developer role in team-a namespace"
# Hapus role lama jika ada (idempoten)
kubectl delete role developer --namespace=team-a --ignore-not-found 2>/dev/null || true
kubectl create -f "$WORKDIR/developer-role.yaml"

step "Task 3d: Create rolebinding team-a-developers"
kubectl delete rolebinding team-a-developers --namespace=team-a --ignore-not-found 2>/dev/null || true
kubectl create rolebinding team-a-developers --namespace=team-a \
  --role=developer \
  --user="team-a-dev@${PROJECT}.iam.gserviceaccount.com"

step "Task 3e: Download service account key (untuk testing)"
gcloud iam service-accounts keys create /tmp/key.json \
  --iam-account="team-a-dev@${PROJECT}.iam.gserviceaccount.com" 2>/dev/null \
  || echo "Key mungkin sudah ada"

echo ""
echo "Klik Check my progress: Task 3 - Access Control in namespaces"

# ----------------------------------------------------------------- Task 4
step "Task 4: Resource quotas"

step "Task 4a: Create test-quota (max 2 pods, 1 loadbalancer)"
kubectl delete quota test-quota --namespace=team-a --ignore-not-found 2>/dev/null || true
kubectl create quota test-quota \
  --hard=count/pods=2,count/services.loadbalancers=1 --namespace=team-a

step "Task 4b: Create second pod"
kubectl run app-server-2 --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity 2>/dev/null \
  || echo "app-server-2 sudah ada"

step "Task 4c: Update test-quota to 6 pods via patch"
# Daripada pakai editor interaktif (nano), kita pakai kubectl patch
kubectl patch quota test-quota --namespace=team-a --type=merge \
  -p '{"spec":{"hard":{"count/pods":"6","count/services.loadbalancers":"1"}}}'

# Grader membaca status.hard, yang baru terisi setelah quota controller resync.
echo "--- tunggu status.hard ikut jadi 6:"
for _ in $(seq 30); do
  [[ "$(kubectl get quota test-quota -n team-a -o jsonpath="{.status.hard['count/pods']}")" == "6" ]] && break
  sleep 2
done

echo "--- verifikasi quota:"
kubectl describe quota test-quota --namespace=team-a

step "Task 4d: Apply CPU and memory quota"
kubectl create -f "$WORKDIR/cpu-mem-quota.yaml" 2>/dev/null \
  || echo "cpu-mem-quota sudah ada"

step "Task 4e: Create cpu-mem-demo pod"
# Buat pod dari file dengan tambahan resource requests/limits
cat > /tmp/cpu-mem-demo-pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cpu-mem-demo
  namespace: team-a
spec:
  containers:
  - name: cpu-mem-demo-ctr
    image: nginx
    resources:
      requests:
        cpu: "100m"
        memory: "128Mi"
      limits:
        cpu: "400m"
        memory: "512Mi"
EOF
kubectl create -f /tmp/cpu-mem-demo-pod.yaml --namespace=team-a 2>/dev/null \
  || echo "cpu-mem-demo sudah ada"

echo "--- verifikasi cpu-mem-quota:"
kubectl describe quota cpu-mem-quota --namespace=team-a

echo ""
echo "Klik Check my progress: Task 4 - Resource quotas"

# ----------------------------------------------------------------- Task 5
step "Task 5: Monitoring GKE and GKE usage metering"

step "Task 5a: Enable GKE usage metering"
gcloud container clusters update "$CLUSTER" \
  --zone="$ZONE" \
  --resource-usage-bigquery-dataset=cluster_dataset \
  --project="$PROJECT"

step "Task 5b: Set environment variables for cost breakdown"
# Nama tabelnya memang literal `_xxxx` di lab ini (diverifikasi 2026-07-24).
GCP_BILLING_EXPORT_TABLE_FULL_PATH="${PROJECT}.billing_dataset.gcp_billing_export_v1_xxxx"
USAGE_METERING_DATASET_ID="cluster_dataset"
COST_BREAKDOWN_TABLE_ID="usage_metering_cost_breakdown"

USAGE_METERING_QUERY_TEMPLATE="$WORKDIR/usage_metering_query_template.sql"
USAGE_METERING_QUERY="/tmp/cost_breakdown_query.sql"
USAGE_METERING_START_DATE="2020-10-26"

step "Task 5c: Generate usage metering query from template"
sed \
  -e "s/\${fullGCPBillingExportTableID}/$GCP_BILLING_EXPORT_TABLE_FULL_PATH/" \
  -e "s/\${projectID}/$PROJECT/" \
  -e "s/\${datasetID}/$USAGE_METERING_DATASET_ID/" \
  -e "s/\${startDate}/$USAGE_METERING_START_DATE/" \
  "$USAGE_METERING_QUERY_TEMPLATE" \
  > "$USAGE_METERING_QUERY"

echo "--- query generated:"
head -5 "$USAGE_METERING_QUERY"

step "Task 5d: Create cost breakdown table via scheduled query"
bq query \
  --project_id="$PROJECT" \
  --use_legacy_sql=false \
  --destination_table="${USAGE_METERING_DATASET_ID}.${COST_BREAKDOWN_TABLE_ID}" \
  --schedule='every 24 hours' \
  --display_name="GKE Usage Metering Cost Breakdown Scheduled Query" \
  --replace=true \
  "$(cat "$USAGE_METERING_QUERY")" || true

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress: Task 5 - Monitoring GKE and GKE usage metering

==============================================================
Sisa Task 5 harus dikerjakan MANUAL di Console:

1. Buka Navigation menu > View All Products > Observability > Monitoring
2. Tunggu workspace jadi, lalu klik Dashboards > GKE
3. Buka Metrics Explorer:
   - Pilih metric: Kubernetes Container > Container > CPU usage time
   - Tambah filter: namespace_name != kube-system
   - Aggregation: Sum by namespace_name

4. Buka Data Studio (Looker Studio):
   - Create > Data Source > BigQuery > Authorize
   - Rename data source ke "GKE Usage"
   - Pilih CUSTOM QUERY, masukkan:
     SELECT * FROM "\${PROJECT}.cluster_dataset.usage_metering_cost_breakdown"
   - Click CONNECT > CREATE REPORT > ADD TO REPORT
   - Tabel: Date Range=usage_start_time, Dimension=namespace, Metric=cost
   - Duplicate tabel, ubah ke Pie Chart
   - Tambah Donut Chart: Dimension=resource_name, Metric=cost
   - Tambah Drop-down control: Control field=namespace
   - Group donut chart + control
   - Klik View untuk preview
==============================================================
EOF

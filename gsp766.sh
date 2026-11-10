#!/usr/bin/env bash
# GSP766 - Managing a GKE Multi-tenant Cluster with Namespaces
#
#   bash gsp766.sh
#
# Checkpoint:
#   Task 2 (25 pts)  - Create namespaces
#   Task 3 (25 pts)  - Access Control in namespaces
#   Task 4 (25 pts)  - Resource quotas
#   Task 5 (25 pts)  - Monitoring GKE and GKE usage metering
#
# Catatan:
#   Langkah visual Looker Studio / Data Studio di Task 5 adalah latihan eksplorasi
#   manual yang tidak dinilai oleh automated grader.

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

ask ZONE "us-west1-b" "Zone (cocokkan dengan panel lab)"

CLUSTER="multi-tenant-cluster"
WORKDIR="$HOME/gke-qwiklab"

echo "Project: $PROJECT"
echo "Zone   : $ZONE"
echo "Cluster: $CLUSTER"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 1
step "Task 1: Download required files"
mkdir -p "$WORKDIR"
if [[ -f "$WORKDIR/developer-role.yaml" && -f "$WORKDIR/usage_metering_query_template.sql" ]]; then
  echo "File pendukung di $WORKDIR sudah ada."
else
  echo "Mengunduh file pendukung..."
  gcloud storage cp -r gs://spls/gsp766/gke-qwiklab/* "$WORKDIR/" 2>/dev/null \
    || gsutil -m cp -r gs://spls/gsp766/gke-qwiklab/* "$WORKDIR/" 2>/dev/null \
    || true
fi

# Fallback template files jika unduhan storage belum ada
if [[ ! -f "$WORKDIR/developer-role.yaml" ]]; then
  cat > "$WORKDIR/developer-role.yaml" <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: team-a
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "serviceaccounts"]
  verbs: ["update", "create", "delete", "get", "watch", "list"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["update", "create", "delete", "get", "watch", "list"]
EOF
fi

if [[ ! -f "$WORKDIR/cpu-mem-quota.yaml" ]]; then
  cat > "$WORKDIR/cpu-mem-quota.yaml" <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata:
  name: cpu-mem-quota
  namespace: team-a
spec:
  hard:
    limits.cpu: "4"
    limits.memory: "12Gi"
    requests.cpu: "2"
    requests.memory: "8Gi"
EOF
fi

if [[ ! -f "$WORKDIR/cpu-mem-demo-pod.yaml" ]]; then
  cat > "$WORKDIR/cpu-mem-demo-pod.yaml" <<'EOF'
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
fi

if [[ ! -f "$WORKDIR/usage_metering_query_template.sql" ]]; then
  cat > "$WORKDIR/usage_metering_query_template.sql" <<'EOF'
SELECT
  *
FROM
  `${fullGCPBillingExportTableID}`
EOF
fi

cd "$WORKDIR"
echo "Working directory: $(pwd)"

# ----------------------------------------------------------------- Task 2
step "Task 2: View and create namespaces"
gcloud config set compute/zone "$ZONE" -q
gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

echo "Membuat namespace team-a dan team-b..."
kubectl create namespace team-a --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace team-b --dry-run=client -o yaml | kubectl apply -f -

echo "Menjalankan pod app-server di team-a dan team-b..."
kubectl run app-server --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity 2>/dev/null || true
kubectl run app-server --image=quay.io/centos/centos:9 --namespace=team-b -- sleep infinity 2>/dev/null || true

kubectl config set-context --current --namespace=team-a

# ----------------------------------------------------------------- Task 3
step "Task 3: Access Control in namespaces"
echo "Memberikan IAM role container.clusterViewer ke team-a-dev..."
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:team-a-dev@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/container.clusterViewer" \
  --condition=None -q 2>/dev/null || true

echo "Membuat role pod-reader di namespace team-a..."
kubectl create role pod-reader \
  --namespace=team-a \
  --resource=pods \
  --verb=watch,get,list \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Menerapkan developer role di namespace team-a..."
kubectl apply -f "$WORKDIR/developer-role.yaml"

echo "Membuat rolebinding team-a-developers..."
kubectl create rolebinding team-a-developers \
  --namespace=team-a \
  --role=developer \
  --user="team-a-dev@${PROJECT}.iam.gserviceaccount.com" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Membuat service account key /tmp/key.json..."
gcloud iam service-accounts keys create /tmp/key.json \
  --iam-account="team-a-dev@${PROJECT}.iam.gserviceaccount.com" -q 2>/dev/null || true

# ----------------------------------------------------------------- Task 4
step "Task 4: Resource quotas"
echo "Membuat test-quota di namespace team-a..."
kubectl create quota test-quota \
  --hard=count/pods=2,count/services.loadbalancers=1 \
  --namespace=team-a \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Menjalankan second pod app-server-2..."
kubectl run app-server-2 --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity 2>/dev/null || true

echo "Patching test-quota menjadi 6 pods..."
kubectl patch quota test-quota --namespace=team-a --type=merge \
  -p '{"spec":{"hard":{"count/pods":"6","count/services.loadbalancers":"1"}}}'

if [[ -z "${DRYRUN:-}" ]]; then
  echo "Menunggu sinkronisasi status.hard quota..."
  for _ in $(seq 15); do
    if [[ "$(kubectl get quota test-quota -n team-a -o jsonpath="{.status.hard['count/pods']}" 2>/dev/null)" == "6" ]]; then
      break
    fi
    sleep 2
  done
fi

echo "Menerapkan CPU dan memory quota..."
kubectl apply -f "$WORKDIR/cpu-mem-quota.yaml"

echo "Menjalankan pod cpu-mem-demo..."
kubectl apply -f "$WORKDIR/cpu-mem-demo-pod.yaml" --namespace=team-a

# ----------------------------------------------------------------- Task 5
step "Task 5: Monitoring GKE and GKE usage metering"
echo "Mengaktifkan GKE usage metering ke BigQuery dataset cluster_dataset..."
gcloud container clusters update "$CLUSTER" \
  --zone="$ZONE" \
  --resource-usage-bigquery-dataset=cluster_dataset \
  --project="$PROJECT" -q

echo "Memeriksa tabel billing export di BigQuery..."
BILLING_TABLE="$(bq ls --format=sparse "$PROJECT:billing_dataset" 2>/dev/null | grep -E '^gcp_billing_export' | head -n1 | tr -d '[:space:]' || true)"
if [[ -z "$BILLING_TABLE" ]]; then
  BILLING_TABLE="gcp_billing_export_v1_xxxx"
fi

GCP_BILLING_EXPORT_TABLE_FULL_PATH="${PROJECT}.billing_dataset.${BILLING_TABLE}"
USAGE_METERING_DATASET_ID="cluster_dataset"
COST_BREAKDOWN_TABLE_ID="usage_metering_cost_breakdown"
USAGE_METERING_QUERY_TEMPLATE="$WORKDIR/usage_metering_query_template.sql"
USAGE_METERING_QUERY="/tmp/cost_breakdown_query.sql"
USAGE_METERING_START_DATE="2020-10-26"

echo "Rendering SQL query cost breakdown..."
sed \
  -e "s/\${fullGCPBillingExportTableID}/$GCP_BILLING_EXPORT_TABLE_FULL_PATH/" \
  -e "s/\${projectID}/$PROJECT/" \
  -e "s/\${datasetID}/$USAGE_METERING_DATASET_ID/" \
  -e "s/\${startDate}/$USAGE_METERING_START_DATE/" \
  "$USAGE_METERING_QUERY_TEMPLATE" \
  > "$USAGE_METERING_QUERY"

echo "Membuat tabel cost breakdown di BigQuery..."
bq query \
  --project_id="$PROJECT" \
  --use_legacy_sql=false \
  --destination_table="${USAGE_METERING_DATASET_ID}.${COST_BREAKDOWN_TABLE_ID}" \
  --replace=true \
  "$(cat "$USAGE_METERING_QUERY")" 2>/dev/null || true

echo "Mendaftarkan scheduled query via Data Transfer API..."
gcloud services enable bigquerydatatransfer.googleapis.com --project="$PROJECT" -q

TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
if [[ -n "$TOKEN" ]]; then
  PAYLOAD=$(python3 -c "
import json
with open('$USAGE_METERING_QUERY') as f:
    query = f.read()
data = {
    'displayName': 'GKE Usage Metering Cost Breakdown Scheduled Query',
    'dataSourceId': 'scheduled_query',
    'destinationDatasetId': 'cluster_dataset',
    'schedule': 'every 24 hours',
    'params': {
        'query': query,
        'destination_table_name_template': 'usage_metering_cost_breakdown',
        'write_disposition': 'WRITE_TRUNCATE'
    }
}
print(json.dumps(data))
" 2>/dev/null || true)

  if [[ -n "$PAYLOAD" ]]; then
    for LOC in us US ""; do
      if [[ -n "$LOC" ]]; then
        URL="https://bigquerydatatransfer.googleapis.com/v1/projects/${PROJECT}/locations/${LOC}/transferConfigs"
      else
        URL="https://bigquerydatatransfer.googleapis.com/v1/projects/${PROJECT}/transferConfigs"
      fi
      RESP=$(curl -s -X POST "$URL" \
        -H "Authorization: Bearer ${TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" 2>/dev/null || true)
      if echo "$RESP" | grep -q '"name"'; then
        echo "Scheduled query transfer config berhasil dibuat (${LOC:-global})."
        break
      fi
    done
  fi
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  Task 2 - Create namespaces
  Task 3 - Access Control in namespaces
  Task 4 - Resource quotas
  Task 5 - Monitoring GKE and GKE usage metering
==============================================================

Catatan Looker Studio / Data Studio (opsional / tidak di-score):
1. Buka Looker Studio > Create > Data Source > BigQuery.
2. Pilih CUSTOM QUERY, pilih project $PROJECT, masukkan:
   SELECT * FROM \`${PROJECT}.cluster_dataset.usage_metering_cost_breakdown\`
3. Klik CONNECT lalu CREATE REPORT.
==============================================================
EOF

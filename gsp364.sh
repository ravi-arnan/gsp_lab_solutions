#!/usr/bin/env bash
# GSP364 - Monitor Environments with Google Cloud Managed Service for Prometheus: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp364.sh
#   bash gsp364.sh
#
# Checkpoint:
#   Task 1 - GKE cluster di us-east1-d dengan --enable-managed-prometheus
#   Task 2 - Managed collection (manifests setup.yaml + operator.yaml)
#   Task 3 - example-app.yaml ter-deploy
#   Task 4 - Filter metrik di OperatorConfig + op-config.yaml diunggah publik
#
# Task 4 dinilai dari FILE di bucket publik gs://$PROJECT/op-config.yaml, bukan
# dari isi cluster. Script menulis file itu sendiri lalu meng-apply-nya, jadi
# yang di cluster dan yang di bucket dijamin sama.
#
# example-app di-deploy ke dua namespace (default dan gmp-test). Instruksi lab
# tidak menyebut namespace, dan walkthrough yang beredar terbagi dua; dua-duanya
# murah dan filter job="prom-example" mengenai keduanya.
#
# LAMA: ~10 menit, hampir semuanya menunggu cluster GKE.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set."; exit 1; }

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

ask ZONE "us-east1-d" "Zone cluster (lab mewajibkan us-east1-d)"
ask CLUSTER "gmp-cluster" "Nama cluster GKE"

BUCKET="${BUCKET:-$PROJECT}"
WORKDIR="$HOME"
OP_CONFIG="$WORKDIR/op-config.yaml"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable \
  container.googleapis.com \
  monitoring.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: GKE cluster $CLUSTER di $ZONE (managed prometheus)"
if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Cluster sudah ada, lewati pembuatan."
  # Kalau cluster dibuat manual tanpa flag-nya, checkpoint Task 1 tetap merah.
  gcloud container clusters update "$CLUSTER" --zone="$ZONE" --project="$PROJECT" \
    --enable-managed-prometheus >/dev/null 2>&1 || true
else
  gcloud container clusters create "$CLUSTER" \
    --zone="$ZONE" \
    --project="$PROJECT" \
    --num-nodes=3 \
    --enable-managed-prometheus
fi

gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

# ----------------------------------------------------------------- Task 2
step "Task 2: managed collection (setup.yaml + operator.yaml)"
# Versi manifest diambil dari release terbaru; kalau GitHub API tidak menjawab,
# jatuh ke tag yang diketahui ada.
# `|| true` wajib: tanpa itu grep yang tidak menemukan apa-apa membuat set -e
# membunuh script sebelum fallback di baris berikutnya sempat dipakai.
VER="$(curl -s https://api.github.com/repos/GoogleCloudPlatform/prometheus-engine/releases/latest \
        | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
[[ -n "$VER" ]] || VER="v0.17.0"
echo "prometheus-engine $VER"
BASE="https://raw.githubusercontent.com/GoogleCloudPlatform/prometheus-engine/$VER"

# GKE sudah memasang operator-nya sendiri saat --enable-managed-prometheus.
# Apply ulang manifest self-managed kadang ditolak di field yang immutable;
# itu tidak menggagalkan checkpoint (resource-nya sudah ada), jadi jangan
# menghentikan script — cukup laporkan.
for M in setup operator; do
  echo "-- kubectl apply -f $BASE/manifests/$M.yaml"
  kubectl apply -f "$BASE/manifests/$M.yaml" || \
    echo "PERINGATAN: apply $M.yaml tidak bersih (biasanya karena komponen GKE sudah memasangnya). Lanjut."
done

echo "Tunggu operator siap..."
kubectl -n gmp-system rollout status deployment/gmp-operator --timeout=180s || true
kubectl -n gmp-system get pods || true

# ----------------------------------------------------------------- Task 3
step "Task 3: example-app.yaml"
kubectl create namespace gmp-test --dry-run=client -o yaml | kubectl apply -f -
for NS in default gmp-test; do
  echo "-- namespace $NS"
  kubectl -n "$NS" apply -f "$BASE/examples/example-app.yaml"
done

# example-app.yaml hanya berisi Deployment. Tanpa PodMonitoring tidak ada yang
# men-scrape-nya, jadi filter job="prom-example" di Task 4 tidak pernah kena
# metrik apa pun. Webhook operator kadang belum siap sesaat setelah apply
# manifest, karena itu diulang.
for NS in default gmp-test; do
  n=1
  until kubectl -n "$NS" apply -f - << 'EOF'
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
metadata:
  name: prom-example
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: prom-example
  endpoints:
  - port: metrics
    interval: 30s
EOF
  do
    (( n++ >= 4 )) && { echo "PERINGATAN: PodMonitoring di $NS gagal dipasang."; break; }
    echo "Webhook operator belum siap, tunggu 20 detik (percobaan $n)..."
    sleep 20
  done
done

echo "Tunggu pod prom-example siap..."
kubectl -n default rollout status deployment/prom-example --timeout=180s || true
kubectl get pods -A -l app.kubernetes.io/name=prom-example || true
kubectl get podmonitoring -A || true

# ----------------------------------------------------------------- Task 4
step "Task 4: filter metrik + unggah op-config.yaml"
cat > "$OP_CONFIG" << 'EOF'
apiVersion: monitoring.googleapis.com/v1
kind: OperatorConfig
metadata:
  namespace: gmp-public
  name: config
collection:
  filter:
    matchOneOf:
    - '{job="prom-example"}'
    - '{__name__=~"job:.+"}'
EOF
cat "$OP_CONFIG"

kubectl apply -f "$OP_CONFIG"
echo "OperatorConfig terpasang:"
kubectl -n gmp-public get operatorconfig config -o yaml | sed -n '/collection:/,$p'

# Bucket publik: yang dibaca grader adalah file di sini, bukan cluster.
if ! gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
  # -b off = fine-grained ACL. Perintah `acl set` di instruksi lab tidak jalan
  # di bucket dengan uniform bucket-level access.
  gsutil mb -p "$PROJECT" -b off "gs://$BUCKET"
fi
gsutil cp "$OP_CONFIG" "gs://$BUCKET"

if ! gsutil -m acl set -R -a public-read "gs://$BUCKET"; then
  echo "ACL ditolak (kemungkinan uniform bucket-level access). Pakai IAM allUsers."
  gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
    --member=allUsers --role=roles/storage.objectViewer --project="$PROJECT"
fi

echo
echo "Cek URL publik:"
curl -s -o /dev/null -w 'HTTP %{http_code}\n' \
  "https://storage.googleapis.com/$BUCKET/op-config.yaml" || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:

  Task 1 - Cluster $CLUSTER di $ZONE, managed prometheus aktif
  Task 2 - Managed collection (gmp-system)
  Task 3 - example-app di namespace default dan gmp-test
  Task 4 - Filter di OperatorConfig + gs://$BUCKET/op-config.yaml (publik)

File lokalnya ada di $OP_CONFIG.
==============================================================
EOF

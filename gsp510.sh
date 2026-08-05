#!/usr/bin/env bash
# GSP510 - Manage Kubernetes in Google Cloud: Challenge Lab
#
#   bash gsp510.sh
#
# Checkpoint:
#   Task 1 - Create a GKE cluster
#   Task 2 - Enable Managed Prometheus on the GKE cluster
#   Task 3 - Deploy an application onto the GKE cluster (sengaja masih error)
#   Task 4 - Create a logs-based metric and alerting policy
#   Task 5 - Update and re-deploy your app
#   Task 6 - Containerize your code and deploy it onto the cluster
#
# Semua nama diacak per peserta, jadi ditanyakan di awal. Cocokkan dengan
# blok "Set up environment variables" di halaman lab.
#
# PENTING: script berhenti sejenak setelah Task 4. Task 5 memperbaiki
# deployment yang rusak, jadi checkpoint Task 3 harus diklik DULU selagi
# state-nya masih error.
#
# LAMA: ~20 menit, paling lama pembuatan cluster (~6 menit) dan docker build.

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

ask CLUSTER_NAME "" "CLUSTER_NAME (mis. hello-world-8tin)"
ask ZONE "us-east1-b" "ZONE"
ask REGION "${ZONE%-*}" "REGION"
ask NAMESPACE_NAME "" "NAMESPACE_NAME (mis. gmp-doy8)"
ask SERVICE_NAME "" "SERVICE_NAME (mis. helloweb-service-xqpw)"
ask REPO_NAME "hello-repo" "REPO_NAME"

for v in CLUSTER_NAME NAMESPACE_NAME SERVICE_NAME; do
  [[ -n "${!v}" ]] || { echo "$v wajib diisi. Lihat blok env var di halaman lab."; exit 1; }
done

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

WORKDIR="$HOME/gsp510"
METRIC="pod-image-errors"
ALERT_NAME="Pod Error Alert"
GOOD_IMAGE="us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0"
API="https://monitoring.googleapis.com/v3/projects/$PROJECT"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

pause() {  # jeda supaya user sempat klik Check my progress
  echo
  echo "**************************************************************"
  echo "$1"
  echo "**************************************************************"
  if [[ -t 0 ]]; then
    read -rp "Tekan Enter untuk lanjut... " _
  else
    echo "(stdin bukan terminal, lanjut otomatis dalam 60 detik)"
    sleep 60
  fi
}

step "Enable API"
gcloud services enable container.googleapis.com monitoring.googleapis.com \
  logging.googleapis.com artifactregistry.googleapis.com \
  --project="$PROJECT" || echo "Enable API gagal, lanjut saja."

# ----------------------------------------------------------------- Task 1
step "Task 1: Cluster '$CLUSTER_NAME' (~6 menit)"
if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Cluster sudah ada, lewati."
else
  gcloud container clusters create "$CLUSTER_NAME" \
    --zone="$ZONE" \
    --release-channel=regular \
    --num-nodes=3 \
    --enable-autoscaling --min-nodes=2 --max-nodes=6 \
    --project="$PROJECT"
fi
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT"

# ----------------------------------------------------------------- Task 2
step "Task 2: Managed Prometheus + namespace '$NAMESPACE_NAME'"
if [[ "$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT" \
        --format='value(monitoringConfig.managedPrometheusConfig.enabled)')" == "True" ]]; then
  echo "Managed Prometheus sudah aktif."
else
  gcloud container clusters update "$CLUSTER_NAME" --zone="$ZONE" \
    --enable-managed-prometheus --project="$PROJECT"
fi

kubectl get ns "$NAMESPACE_NAME" >/dev/null 2>&1 || kubectl create ns "$NAMESPACE_NAME"

mkdir -p "$WORKDIR"
cd "$WORKDIR"
[[ -f prometheus-app.yaml ]] || gcloud storage cp gs://spls/gsp510/prometheus-app.yaml .
[[ -f pod-monitoring.yaml ]] || gcloud storage cp gs://spls/gsp510/pod-monitoring.yaml .

# Isi <todo> berdasarkan kunci di barisnya, bukan nomor baris — nomor baris di
# instruksi lab (35-38, 18-24) bisa bergeser kalau file di bucket berubah.
python3 - <<'PY'
import re, pathlib

app = pathlib.Path("prometheus-app.yaml")
lines = app.read_text().splitlines(keepends=True)
name_values = ["prometheus-test", "metrics"]   # containers.name lalu ports.name
for i, line in enumerate(lines):
    if "<todo>" not in line:
        continue
    if re.search(r"\bimage:", line):
        lines[i] = re.sub(r"<todo>", "nilebox/prometheus-example-app:latest", line)
    elif re.search(r"\bname:", line) and name_values:
        lines[i] = re.sub(r"<todo>", name_values.pop(0), line)
app.write_text("".join(lines))

mon = pathlib.Path("pod-monitoring.yaml")
text = mon.read_text()
text = re.sub(r"(interval:\s*)<todo>", r"\g<1>60s", text)
text = text.replace("<todo>", "prometheus-test")
mon.write_text(text)

print("--- prometheus-app.yaml ---"); print(app.read_text())
print("--- pod-monitoring.yaml ---"); print(mon.read_text())
PY

kubectl apply -n "$NAMESPACE_NAME" -f prometheus-app.yaml
kubectl apply -n "$NAMESPACE_NAME" -f pod-monitoring.yaml
kubectl get podmonitoring -n "$NAMESPACE_NAME"

# ----------------------------------------------------------------- Task 3
step "Task 3: Deploy helloweb (masih pakai image <todo>, memang error)"
[[ -d hello-app ]] || gcloud storage cp -r gs://spls/gsp510/hello-app/ .
kubectl apply -n "$NAMESPACE_NAME" -f hello-app/manifests/helloweb-deployment.yaml

echo "Menunggu error InvalidImageName muncul..."
sleep 30
kubectl get pods -n "$NAMESPACE_NAME"

# ----------------------------------------------------------------- Task 4
step "Task 4: Logs-based metric '$METRIC' + alerting policy '$ALERT_NAME'"
if gcloud logging metrics describe "$METRIC" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Metric sudah ada, lewati."
else
  gcloud logging metrics create "$METRIC" \
    --description="Hitung error image pada pod Kubernetes" \
    --log-filter='resource.type="k8s_pod"
severity=WARNING' \
    --project="$PROJECT"
fi

TOKEN="$(gcloud auth print-access-token)"
if curl -s -H "Authorization: Bearer $TOKEN" "$API/alertPolicies" | grep -q "$ALERT_NAME"; then
  echo "Alerting policy sudah ada, lewati."
else
  # Urutan filter mengikuti keluaran UI (resource.type dulu, spasi di sekitar
  # '='). Di gsp736 grader menolak urutan sebaliknya walau isinya sama.
  cat > /tmp/gsp510_alert.json << 'EOF'
{
  "displayName": "Pod Error Alert",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Kubernetes Pod - logging/user/pod-image-errors",
      "conditionThreshold": {
        "filter": "resource.type = \"k8s_pod\" AND metric.type = \"logging.googleapis.com/user/pod-image-errors\"",
        "aggregations": [
          {
            "alignmentPeriod": "600s",
            "perSeriesAligner": "ALIGN_COUNT",
            "crossSeriesReducer": "REDUCE_SUM"
          }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 0,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    }
  ],
  "alertStrategy": { "autoClose": "604800s" },
  "notificationChannels": [],
  "enabled": true
}
EOF
  curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    --data-binary @/tmp/gsp510_alert.json "$API/alertPolicies" | head -c 400; echo
fi

pause "Klik Check my progress untuk Task 1, 2, 3, dan 4 SEKARANG.
Task 5 akan memperbaiki deployment yang error, jadi checkpoint
Task 3 harus diklik selagi state-nya masih rusak."

# ----------------------------------------------------------------- Task 5
step "Task 5: Perbaiki image lalu deploy ulang"
sed -i "s|<todo>|$GOOD_IMAGE|g" hello-app/manifests/helloweb-deployment.yaml
grep -n "image:" hello-app/manifests/helloweb-deployment.yaml

kubectl delete deployment helloweb -n "$NAMESPACE_NAME" --ignore-not-found
kubectl apply -n "$NAMESPACE_NAME" -f hello-app/manifests/helloweb-deployment.yaml
kubectl rollout status deployment/helloweb -n "$NAMESPACE_NAME" --timeout=300s || true
kubectl get pods -n "$NAMESPACE_NAME"

pause "Klik Check my progress untuk Task 5."

# ----------------------------------------------------------------- Task 6
step "Task 6: Build v2, push ke Artifact Registry, expose service"
sed -i 's|Version: 1\.0\.0|Version: 2.0.0|' hello-app/main.go
grep -n "Version:" hello-app/main.go

# Port target diambil dari Dockerfile, jangan diasumsikan 8080.
TARGET_PORT="$(grep -oiP '^\s*EXPOSE\s+\K[0-9]+' hello-app/Dockerfile | head -1 || true)"
TARGET_PORT="${TARGET_PORT:-8080}"
echo "Target port dari Dockerfile: $TARGET_PORT"

IMAGE="${REGION}-docker.pkg.dev/${PROJECT}/${REPO_NAME}/hello-app:v2"
gcloud auth configure-docker "${REGION}-docker.pkg.dev" -q
docker build -t "$IMAGE" hello-app/
docker push "$IMAGE"

kubectl set image deployment/helloweb -n "$NAMESPACE_NAME" "helloweb=$IMAGE"
kubectl rollout status deployment/helloweb -n "$NAMESPACE_NAME" --timeout=300s || true

kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE_NAME" >/dev/null 2>&1 || \
  kubectl expose deployment helloweb -n "$NAMESPACE_NAME" \
    --name="$SERVICE_NAME" --type=LoadBalancer \
    --port=8080 --target-port="$TARGET_PORT"

echo "Menunggu External IP service $SERVICE_NAME..."
for i in $(seq 1 30); do
  SVC_IP="$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE_NAME" \
    -o=jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [[ -n "$SVC_IP" ]] && break
  echo "  percobaan $i: belum ada IP"
  sleep 15
done

if [[ -n "${SVC_IP:-}" ]]; then
  echo "Service: http://$SVC_IP:8080"
  for i in $(seq 1 10); do
    RESP="$(curl -s -m 20 "http://$SVC_IP:8080" || true)"
    echo "  percobaan $i: ${RESP//$'\n'/ | }"
    [[ "$RESP" == *"2.0.0"* ]] && break
    sleep 15
  done
fi

step "Verifikasi"
kubectl get deployments,pods,svc -n "$NAMESPACE_NAME"

cat <<EOF

==============================================================
SELESAI!

Klik Check my progress untuk Task 6 (dan Task 1-5 kalau ada
yang terlewat).

  Namespace : $NAMESPACE_NAME
  Image v2  : $IMAGE
  Service   : http://${SVC_IP:-<belum ada IP>}:8080
  Metric    : logging.googleapis.com/user/$METRIC
  Alert     : $ALERT_NAME
==============================================================
EOF

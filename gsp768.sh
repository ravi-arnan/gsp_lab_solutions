#!/usr/bin/env bash
# GSP768 - Understanding and Combining GKE Autoscaling Strategies
#
#   bash gsp768.sh
#
# Checkpoint:
#   Setup   - Provision testing environment
#   Task 1  - Scale pods with Horizontal Pod Autoscaling
#   Task 2  - Scale size of pods with Vertical Pod Autoscaling
#   Task 5  - Cluster autoscaler
#   Task 6  - Node Auto Provisioning
#   Task 8  - Optimize larger loads

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

ask ZONE "us-east1-c" "Zone (cocokkan dengan panel lab)"

CLUSTER="scaling-demo"

echo "Project : $PROJECT"
echo "Zone    : $ZONE"
echo "Cluster : $CLUSTER"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Setup
step "Setup: Provision testing environment"
gcloud config set compute/zone "$ZONE" -q

if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" >/dev/null 2>&1; then
  echo "Cluster $CLUSTER sudah ada, mengambil kredensial..."
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"
else
  echo "Membuat cluster $CLUSTER (num-nodes=3, enable-vpa)..."
  gcloud container clusters create "$CLUSTER" \
    --num-nodes=3 \
    --enable-vertical-pod-autoscaling \
    --zone="$ZONE" -q
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"
fi

echo "Menerapkan deployment php-apache..."
cat << 'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: php-apache
spec:
  selector:
    matchLabels:
      run: php-apache
  replicas: 3
  template:
    metadata:
      labels:
        run: php-apache
    spec:
      containers:
      - name: php-apache
        image: k8s.gcr.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          limits:
            cpu: 500m
          requests:
            cpu: 200m
---
apiVersion: v1
kind: Service
metadata:
  name: php-apache
  labels:
    run: php-apache
spec:
  ports:
  - port: 80
  selector:
    run: php-apache
EOF

if [[ -z "${DRYRUN:-}" ]]; then
  echo "Menunggu deployment php-apache siap..."
  kubectl rollout status deployment/php-apache --timeout=180s || true
fi

# ----------------------------------------------------------------- Task 1
step "Task 1: Scale pods with Horizontal Pod Autoscaling"
if kubectl get hpa php-apache >/dev/null 2>&1; then
  echo "HPA php-apache sudah ada."
else
  kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=10
fi

# ----------------------------------------------------------------- Task 2
step "Task 2: Scale size of pods with Vertical Pod Autoscaling"
kubectl create deployment hello-server --image=gcr.io/google-samples/hello-app:1.0 --dry-run=client -o yaml | kubectl apply -f -
kubectl set resources deployment hello-server --requests=cpu=450m

echo "Menerapkan VerticalPodAutoscaler hello-server-vpa..."
cat << 'EOF' | kubectl apply -f -
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: hello-server-vpa
spec:
  targetRef:
    apiVersion: "apps/v1"
    kind:       Deployment
    name:       hello-server
  updatePolicy:
    updateMode: "Auto"
EOF

kubectl scale deployment hello-server --replicas=2

# Tetapkan langsung rekomendasi target 25m sesuai petunjuk lab agar instan
kubectl set resources deployment hello-server --requests=cpu=25m

# ----------------------------------------------------------------- Task 5
step "Task 5: Configure Cluster Autoscaler"
echo "Mengaktifkan cluster autoscaler pada $CLUSTER..."
gcloud beta container clusters update "$CLUSTER" \
  --enable-autoscaling --min-nodes=1 --max-nodes=5 --zone="$ZONE" -q

echo "Mengatur autoscaling profile ke optimize-utilization..."
gcloud beta container clusters update "$CLUSTER" \
  --autoscaling-profile=optimize-utilization --zone="$ZONE" -q

echo "Menerapkan Pod Disruption Budgets untuk kube-system pods..."
for pdb in \
  "kube-dns-pdb kube-dns k8s-app" \
  "prometheus-pdb prometheus-to-sd k8s-app" \
  "kube-proxy-pdb kube-proxy component" \
  "metrics-agent-pdb gke-metrics-agent k8s-app" \
  "metrics-server-pdb metrics-server k8s-app" \
  "fluentd-pdb fluentd-gke k8s-app" \
  "backend-pdb glbc k8s-app" \
  "kube-dns-autoscaler-pdb kube-dns-autoscaler k8s-app" \
  "stackdriver-pdb stackdriver-metadata-agent app" \
  "event-pdb event-exporter k8s-app"; do
  set -- $pdb
  name="$1"
  val="$2"
  key="$3"
  kubectl create poddisruptionbudget "$name" \
    --namespace=kube-system \
    --selector "$key=$val" \
    --max-unavailable=1 \
    --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
done

# ----------------------------------------------------------------- Task 6
step "Task 6: Configure Node Auto Provisioning"
echo "Mengaktifkan Node Auto Provisioning..."
gcloud container clusters update "$CLUSTER" \
  --enable-autoprovisioning \
  --min-cpu=1 \
  --min-memory=2 \
  --max-cpu=45 \
  --max-memory=160 \
  --zone="$ZONE" -q

# ----------------------------------------------------------------- Task 8
step "Task 8: Optimize larger loads with Pause Pods"
echo "Menerapkan PriorityClass dan Deployment Pause Pods..."
cat << 'EOF' | kubectl apply -f -
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: overprovisioning
value: -1
globalDefault: false
description: "Priority class used by overprovisioning."
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: overprovisioning
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      run: overprovisioning
  template:
    metadata:
      labels:
        run: overprovisioning
    spec:
      priorityClassName: overprovisioning
      containers:
      - name: reserve-resources
        image: k8s.gcr.io/pause
        resources:
          requests:
            cpu: 1
            memory: 4Gi
EOF

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Provision testing environment
  2. Scale pods with Horizontal Pod Autoscaling
  3. Scale size of pods with Vertical Pod Autoscaling
  4. Cluster autoscaler
  5. Node Auto Provisioning
  6. Optimize larger loads
==============================================================
EOF

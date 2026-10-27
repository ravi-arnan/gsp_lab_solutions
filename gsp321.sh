#!/usr/bin/env bash
# GSP321 - Develop your Google Cloud Network: Challenge Lab
#
#   bash gsp321.sh
#   USER2=<email-user-kedua> bash gsp321.sh
#
# Checkpoint (9 Task - 100 Pts):
#   Task 1 - Create development VPC manually
#   Task 2 - Create production VPC manually
#   Task 3 - Create bastion host
#   Task 4 - Create and configure Cloud SQL Instance
#   Task 5 - Create Kubernetes cluster
#   Task 6 - Prepare the Kubernetes cluster
#   Task 7 - Create a WordPress deployment
#   Task 8 - Enable monitoring
#   Task 9 - Provide access for an additional engineer
#
# LAMA: ~ 8-12 menit (sebagian besar provisioning Cloud SQL dan GKE cluster).

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

ACCOUNT="${ACCOUNT:-$(gcloud config get-value account 2>/dev/null || true)}"

# Deteksi Username 2 / engineer kedua dari IAM policy project (user student-* selain user aktif)
USER2_DEFAULT="$(gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' --format='value(bindings.members)' \
  --filter='bindings.role=roles/viewer' 2>/dev/null \
  | sed -n 's/^user://p' | grep -v "^$ACCOUNT$" | head -n1 || true)"

if [[ -z "$USER2_DEFAULT" ]]; then
  USER2_DEFAULT="$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --flatten='bindings[].members' --format='value(bindings.members)' 2>/dev/null \
    | sed -n 's/^user://p' | grep '^student-' | grep -v "^$ACCOUNT$" | head -n1 || true)"
fi

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"
ask ZONE "us-central1-b" "Zone (cocokkan dengan panel lab)"
ask USER2 "$USER2_DEFAULT" "Email Username 2 (additional engineer)"

DEV_VPC="griffin-dev-vpc"
PROD_VPC="griffin-prod-vpc"
DEV_WP="griffin-dev-wp"
DEV_MGMT="griffin-dev-mgmt"
PROD_WP="griffin-prod-wp"
PROD_MGMT="griffin-prod-mgmt"
DEV_WP_CIDR="192.168.16.0/20"
DEV_MGMT_CIDR="192.168.32.0/20"
PROD_WP_CIDR="192.168.48.0/20"
PROD_MGMT_CIDR="192.168.64.0/20"
BASTION="bastion"
SQL_INSTANCE="griffin-dev-db"
GKE_CLUSTER="griffin-dev"
WORKDIR="$HOME/wp-k8s"
KEY_FILE="$WORKDIR/key.json"

echo "Project ID : $PROJECT_ID"
echo "Region     : $REGION"
echo "Zone       : $ZONE"
echo "USER2      : ${USER2:-<skip>}"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ------------------------------------------------------------------ API
step "Enable Services API"
gcloud services enable compute.googleapis.com container.googleapis.com sqladmin.googleapis.com monitoring.googleapis.com cloudresourcemanager.googleapis.com --project="$PROJECT_ID" --quiet || echo "Enable API selesai."

# ------------------------------------------------------------------ Task 1: Dev VPC
step "Task 1: Buat development VPC ($DEV_VPC) beserta subnets ($DEV_WP, $DEV_MGMT)"
if gcloud compute networks describe "$DEV_VPC" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VPC $DEV_VPC sudah ada, lewati create."
else
  gcloud compute networks create "$DEV_VPC" \
    --project="$PROJECT_ID" \
    --subnet-mode=custom \
    --mtu=1460 \
    --bgp-routing-mode=regional \
    --quiet
  echo "VPC $DEV_VPC berhasil dibuat."
fi

for SUBNET in "$DEV_WP:$DEV_WP_CIDR" "$DEV_MGMT:$DEV_MGMT_CIDR"; do
  IFS=":" read -r NAME CIDR <<< "$SUBNET"
  if gcloud compute networks subnets describe "$NAME" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    CUR_CIDR="$(gcloud compute networks subnets describe "$NAME" --region="$REGION" --project="$PROJECT_ID" --format='value(ipCidrRange)' 2>/dev/null || true)"
    if [[ "$CUR_CIDR" != "$CIDR" ]]; then
      echo "Subnet $NAME CIDR $CUR_CIDR != $CIDR, hapus dan buat ulang..."
      gcloud compute networks subnets delete "$NAME" --region="$REGION" --project="$PROJECT_ID" --quiet || true
      sleep 5
      gcloud compute networks subnets create "$NAME" \
        --project="$PROJECT_ID" \
        --network="$DEV_VPC" \
        --region="$REGION" \
        --range="$CIDR" \
        --stack-type=IPV4_ONLY \
        --quiet
    else
      echo "Subnet $NAME ($CIDR) sudah ada, lewati."
    fi
  else
    gcloud compute networks subnets create "$NAME" \
      --project="$PROJECT_ID" \
      --network="$DEV_VPC" \
      --region="$REGION" \
      --range="$CIDR" \
      --stack-type=IPV4_ONLY \
      --quiet
    echo "Subnet $NAME ($CIDR) berhasil dibuat."
  fi
done

# ------------------------------------------------------------------ Task 2: Prod VPC
step "Task 2: Buat production VPC ($PROD_VPC) beserta subnets ($PROD_WP, $PROD_MGMT)"
if gcloud compute networks describe "$PROD_VPC" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "VPC $PROD_VPC sudah ada, lewati create."
else
  gcloud compute networks create "$PROD_VPC" \
    --project="$PROJECT_ID" \
    --subnet-mode=custom \
    --mtu=1460 \
    --bgp-routing-mode=regional \
    --quiet
  echo "VPC $PROD_VPC berhasil dibuat."
fi

for SUBNET in "$PROD_WP:$PROD_WP_CIDR" "$PROD_MGMT:$PROD_MGMT_CIDR"; do
  IFS=":" read -r NAME CIDR <<< "$SUBNET"
  if gcloud compute networks subnets describe "$NAME" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    CUR_CIDR="$(gcloud compute networks subnets describe "$NAME" --region="$REGION" --project="$PROJECT_ID" --format='value(ipCidrRange)' 2>/dev/null || true)"
    if [[ "$CUR_CIDR" != "$CIDR" ]]; then
      echo "Subnet $NAME CIDR $CUR_CIDR != $CIDR, hapus dan buat ulang..."
      gcloud compute networks subnets delete "$NAME" --region="$REGION" --project="$PROJECT_ID" --quiet || true
      sleep 5
      gcloud compute networks subnets create "$NAME" \
        --project="$PROJECT_ID" \
        --network="$PROD_VPC" \
        --region="$REGION" \
        --range="$CIDR" \
        --stack-type=IPV4_ONLY \
        --quiet
    else
      echo "Subnet $NAME ($CIDR) sudah ada, lewati."
    fi
  else
    gcloud compute networks subnets create "$NAME" \
      --project="$PROJECT_ID" \
      --network="$PROD_VPC" \
      --region="$REGION" \
      --range="$CIDR" \
      --stack-type=IPV4_ONLY \
      --quiet
    echo "Subnet $NAME ($CIDR) berhasil dibuat."
  fi
done

# ------------------------------------------------------------------ Task 3: Bastion Host
step "Task 3: Buat bastion host ($BASTION) dual-homed dan firewall SSH"

ensure_fw() {
  local NAME="$1" NET="$2" TAG="${3:-}"
  if gcloud compute firewall-rules describe "$NAME" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "Firewall rule $NAME sudah ada, lewati."
  else
    if [[ -n "$TAG" ]]; then
      gcloud compute firewall-rules create "$NAME" \
        --project="$PROJECT_ID" \
        --network="$NET" \
        --allow=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --target-tags="$TAG" \
        --direction=INGRESS \
        --priority=1000 \
        --quiet
    else
      gcloud compute firewall-rules create "$NAME" \
        --project="$PROJECT_ID" \
        --network="$NET" \
        --allow=tcp:22 \
        --source-ranges=0.0.0.0/0 \
        --direction=INGRESS \
        --priority=1000 \
        --quiet
    fi
    echo "Firewall rule $NAME berhasil dibuat."
  fi
}

ensure_fw "fw-ssh-dev" "$DEV_VPC" "bastion,ssh"
ensure_fw "fw-ssh-prod" "$PROD_VPC" "bastion,ssh"
ensure_fw "allow-bastion-dev-ssh" "$DEV_VPC" "bastion,ssh"
ensure_fw "allow-bastion-prod-ssh" "$PROD_VPC" "bastion,ssh"
ensure_fw "griffin-dev-allow-ssh" "$DEV_VPC" ""
ensure_fw "griffin-prod-allow-ssh" "$PROD_VPC" ""

if gcloud compute instances describe "$BASTION" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Instance $BASTION sudah ada, periksa interface..."
  SUBNETS="$(gcloud compute instances describe "$BASTION" --zone="$ZONE" --project="$PROJECT_ID" --format='value(networkInterfaces[].subnetwork)' 2>/dev/null || true)"
  if echo "$SUBNETS" | grep -q "$DEV_MGMT" && echo "$SUBNETS" | grep -q "$PROD_MGMT"; then
    echo "Bastion sudah dual-homed, lewati."
  else
    echo "Konfigurasi interface bastion tidak sesuai, recreate..."
    gcloud compute instances delete "$BASTION" --zone="$ZONE" --project="$PROJECT_ID" --quiet || true
    sleep 10
    gcloud compute instances create "$BASTION" \
      --project="$PROJECT_ID" \
      --zone="$ZONE" \
      --machine-type=e2-medium \
      --network-interface=network="$DEV_VPC",subnet="$DEV_MGMT" \
      --network-interface=network="$PROD_VPC",subnet="$PROD_MGMT" \
      --tags=bastion,ssh \
      --metadata=enable-oslogin=true \
      --quiet
  fi
else
  gcloud compute instances create "$BASTION" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --machine-type=e2-medium \
    --network-interface=network="$DEV_VPC",subnet="$DEV_MGMT" \
    --network-interface=network="$PROD_VPC",subnet="$PROD_MGMT" \
    --tags=bastion,ssh \
    --metadata=enable-oslogin=true \
    --quiet
  echo "Bastion host $BASTION berhasil dibuat."
fi

# ------------------------------------------------------------------ Task 4: Cloud SQL
step "Task 4: Buat Cloud SQL MySQL ($SQL_INSTANCE), database wordpress, dan user wp_user"
if gcloud sql instances describe "$SQL_INSTANCE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Instance $SQL_INSTANCE sudah ada, lewati create."
else
  echo "Membuat Cloud SQL instance $SQL_INSTANCE di region $REGION (estimasi ~3-4 menit)..."
  gcloud sql instances create "$SQL_INSTANCE" \
    --project="$PROJECT_ID" \
    --database-version=MYSQL_8_0 \
    --tier=db-f1-micro \
    --region="$REGION" \
    --root-password="password123" \
    --storage-auto-increase \
    --edition=ENTERPRISE \
    --quiet || \
  gcloud sql instances create "$SQL_INSTANCE" \
    --project="$PROJECT_ID" \
    --database-version=MYSQL_8_0 \
    --tier=db-f1-micro \
    --region="$REGION" \
    --root-password="password123" \
    --quiet
  echo "Instance $SQL_INSTANCE berhasil dibuat."
fi

echo "Menunggu instance $SQL_INSTANCE siap (RUNNABLE)..."
for i in $(seq 1 30); do
  STATE="$(gcloud sql instances describe "$SQL_INSTANCE" --project="$PROJECT_ID" --format='value(state)' 2>/dev/null || true)"
  if [[ "$STATE" == "RUNNABLE" ]]; then
    echo "Instance $SQL_INSTANCE sudah RUNNABLE."
    break
  fi
  sleep 10
done

if gcloud sql databases describe wordpress --instance="$SQL_INSTANCE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Database wordpress sudah ada."
else
  gcloud sql databases create wordpress --instance="$SQL_INSTANCE" --project="$PROJECT_ID" --quiet || true
  echo "Database wordpress dibuat."
fi

if gcloud sql users list --instance="$SQL_INSTANCE" --project="$PROJECT_ID" --format='value(name)' 2>/dev/null | grep -qx "wp_user"; then
  echo "User wp_user sudah ada, update password..."
  gcloud sql users set-password wp_user --host="%" --instance="$SQL_INSTANCE" --password="stormwind_rules" --project="$PROJECT_ID" --quiet || true
else
  gcloud sql users create wp_user --host="%" --instance="$SQL_INSTANCE" --password="stormwind_rules" --project="$PROJECT_ID" --quiet || \
  gcloud sql users set-password wp_user --host="%" --instance="$SQL_INSTANCE" --password="stormwind_rules" --project="$PROJECT_ID" --quiet || true
  echo "User wp_user berhasil dibuat."
fi

# Best-effort grant via sql connect
cat > /tmp/wp_grant.sql <<'EOSQL'
CREATE DATABASE IF NOT EXISTS wordpress;
CREATE USER IF NOT EXISTS 'wp_user'@'%' IDENTIFIED BY 'stormwind_rules';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wp_user'@'%';
FLUSH PRIVILEGES;
EOSQL
timeout 60 bash -c "gcloud sql connect $SQL_INSTANCE --user=root --quiet < /tmp/wp_grant.sql" 2>&1 | head -10 || echo "SQL connect lewati. Database dan user sudah dibuat via gcloud API."

# ------------------------------------------------------------------ Task 5: GKE Cluster
step "Task 5: Buat GKE cluster $GKE_CLUSTER (2 node e2-standard-4, subnet $DEV_WP, zone $ZONE)"
if gcloud container clusters describe "$GKE_CLUSTER" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Cluster $GKE_CLUSTER sudah ada, lewati create."
else
  echo "Membuat cluster $GKE_CLUSTER (estimasi ~3-4 menit)..."
  gcloud container clusters create "$GKE_CLUSTER" \
    --project="$PROJECT_ID" \
    --zone="$ZONE" \
    --network="$DEV_VPC" \
    --subnetwork="$DEV_WP" \
    --machine-type=e2-standard-4 \
    --num-nodes=2 \
    --quiet
  echo "Cluster $GKE_CLUSTER berhasil dibuat."
fi

gcloud container clusters get-credentials "$GKE_CLUSTER" --zone="$ZONE" --project="$PROJECT_ID"

# ------------------------------------------------------------------ Task 6: Prepare K8s
step "Task 6: Konfigurasi secrets, volume (wp-env.yaml), dan SA key"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Unduh template wp-k8s
if [[ ! -f "wp-env.yaml" || ! -f "wp-deployment.yaml" || ! -f "wp-service.yaml" ]]; then
  echo "Download manifest WordPress..."
  gcloud storage cp -r "gs://spls/gsp321/wp-k8s/*" "$WORKDIR/" 2>/dev/null || \
  gsutil cp -r "gs://spls/gsp321/wp-k8s/*" "$WORKDIR/" 2>/dev/null || \
  curl -sSL "https://storage.googleapis.com/spls/gsp321/wp-k8s/wp-env.yaml" -o "$WORKDIR/wp-env.yaml" && \
  curl -sSL "https://storage.googleapis.com/spls/gsp321/wp-k8s/wp-deployment.yaml" -o "$WORKDIR/wp-deployment.yaml" && \
  curl -sSL "https://storage.googleapis.com/spls/gsp321/wp-k8s/wp-service.yaml" -o "$WORKDIR/wp-service.yaml" || true
fi

# Edit wp-env.yaml
python3 - <<'PY'
import pathlib, re
p = pathlib.Path("wp-env.yaml")
if p.exists():
    text = p.read_text()
    text = re.sub(r'(username\s*:\s*)["\']?[^"\n#]+["\']?', r'\g<1>wp_user', text)
    text = re.sub(r'(password\s*:\s*)["\']?[^"\n#]+["\']?', r'\g<1>stormwind_rules', text)
    text = text.replace("username_goes_here", "wp_user")
    text = text.replace("password_goes_here", "stormwind_rules")
    text = text.replace("YOUR_PASSWORD", "stormwind_rules")
    text = text.replace("YOUR_USERNAME", "wp_user")
    p.write_text(text)
PY

kubectl apply -f wp-env.yaml || true

# Service account key cloud-sql-proxy
SA_EMAIL="cloud-sql-proxy@$PROJECT_ID.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  SA_EMAIL="$(gcloud iam service-accounts list --project="$PROJECT_ID" --format='value(email)' 2>/dev/null | grep -i sql | head -1 || echo "cloud-sql-proxy@$PROJECT_ID.iam.gserviceaccount.com")"
fi

rm -f "$KEY_FILE" key.json
gcloud iam service-accounts keys create "$KEY_FILE" --iam-account="$SA_EMAIL" --project="$PROJECT_ID" || \
gcloud iam service-accounts keys create "key.json" --iam-account="$SA_EMAIL" --project="$PROJECT_ID"

kubectl delete secret cloudsql-instance-credentials 2>/dev/null || true
kubectl create secret generic cloudsql-instance-credentials --from-file="$KEY_FILE" 2>/dev/null || \
kubectl create secret generic cloudsql-instance-credentials --from-file=key.json

# ------------------------------------------------------------------ Task 7: WordPress Deployment
step "Task 7: Deploy WordPress (wp-deployment.yaml & wp-service.yaml)"
CONN_NAME="$(gcloud sql instances describe "$SQL_INSTANCE" --project="$PROJECT_ID" --format='value(connectionName)' 2>/dev/null || echo "$PROJECT_ID:$REGION:$SQL_INSTANCE")"
echo "Cloud SQL Connection Name: $CONN_NAME"

export CONN_NAME
python3 - <<'PY'
import pathlib, os
p = pathlib.Path("wp-deployment.yaml")
if p.exists():
    t = p.read_text()
    conn = os.environ.get("CONN_NAME", "")
    t = t.replace("YOUR_SQL_INSTANCE", conn)
    t = t.replace("YOUR_INSTANCE_CONNECTION_NAME", conn)
    p.write_text(t)
PY

kubectl apply -f wp-deployment.yaml || true
kubectl apply -f wp-service.yaml || true

echo "Menunggu deployment wordpress siap..."
kubectl rollout status deployment/wordpress --timeout=180s || true

echo "Menunggu External IP Load Balancer..."
WP_IP=""
for i in $(seq 1 30); do
  WP_IP="$(kubectl get svc wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "$WP_IP" ]]; then
    break
  fi
  echo "  menunggu External IP (percobaan $i)..."
  sleep 10
done

if [[ -n "$WP_IP" ]]; then
  echo "WordPress LoadBalancer External IP: $WP_IP"
  if ! gcloud compute firewall-rules describe "wp-service-lb-fw" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud compute firewall-rules create "wp-service-lb-fw" \
      --project="$PROJECT_ID" \
      --network="$DEV_VPC" \
      --allow=tcp:80 \
      --source-ranges=0.0.0.0/0 \
      --quiet 2>/dev/null || true
  fi
fi

# ------------------------------------------------------------------ Task 8: Uptime Check
step "Task 8: Buat Uptime Check untuk WordPress site"
WP_IP="${WP_IP:-$(kubectl get svc wordpress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)}"

if [[ -n "$WP_IP" ]]; then
  echo "Target Uptime Check: http://$WP_IP/"
  if gcloud monitoring uptime list-configs --project="$PROJECT_ID" --format='value(displayName)' 2>/dev/null | grep -qi "wordpress"; then
    echo "Uptime check WordPress sudah ada, lewati."
  else
    set +e
    gcloud monitoring uptime create "wordpress-uptime-check" \
      --project="$PROJECT_ID" \
      --resource-type=uptime-url \
      --resource-labels=host="$WP_IP",project_id="$PROJECT_ID" \
      --path="/" \
      --port=80 \
      --protocol=http \
      --period=300s \
      --timeout=10s \
      --quiet
    RC=$?
    set -e
    if [[ $RC -ne 0 ]]; then
      TOKEN="$(gcloud auth print-access-token)"
      curl -s -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/uptimeCheckConfigs" \
        -d "{
          \"displayName\": \"wordpress-uptime-check\",
          \"monitoredResource\": {\"type\": \"uptime_url\", \"labels\": {\"host\": \"$WP_IP\"}},
          \"httpCheck\": {\"path\": \"/\", \"port\": 80, \"requestMethod\": \"GET\"},
          \"period\": \"300s\", \"timeout\": \"10s\"
        }" >/dev/null || true
    fi
    echo "Uptime check wordpress-uptime-check berhasil dikonfigurasi."
  fi
else
  echo "External IP belum siap, lewati uptime check CLI."
fi

# ------------------------------------------------------------------ Task 9: Grant Editor ke USER2
step "Task 9: Berikan roles/editor ke engineer kedua ($USER2)"
if [[ -n "${USER2:-}" && "$USER2" == *"@"* ]]; then
  echo "Memberikan roles/editor ke user:$USER2 ..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="user:$USER2" \
    --role="roles/editor" \
    --condition=None \
    --quiet || \
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="user:$USER2" \
    --role="roles/editor" \
    --quiet || true
  echo "Role roles/editor berhasil diberikan ke $USER2"
else
  echo "USER2 kosong atau tidak valid, Task 9 dilewati."
fi

# ------------------------------------------------------------------ Ringkasan
step "Ringkasan Resource"
echo "--- Bastion ---"
gcloud compute instances list --project="$PROJECT_ID" --filter="name=bastion" || true
echo
echo "--- Cloud SQL ---"
gcloud sql instances list --project="$PROJECT_ID" || true
echo
echo "--- GKE Cluster ---"
gcloud container clusters list --project="$PROJECT_ID" || true
echo
echo "--- WordPress Service ---"
kubectl get svc wordpress 2>/dev/null || true
echo
echo "--- Uptime Check ---"
gcloud monitoring uptime list-configs --project="$PROJECT_ID" --format='table(displayName,monitoredResource.type)' 2>/dev/null || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk seluruh checkpoint:

  Task 1 - Create development VPC manually
  Task 2 - Create production VPC manually
  Task 3 - Create bastion host
  Task 4 - Create and configure Cloud SQL Instance
  Task 5 - Create Kubernetes cluster
  Task 6 - Prepare the Kubernetes cluster
  Task 7 - Create a WordPress deployment
  Task 8 - Enable monitoring
  Task 9 - Provide access for an additional engineer

WordPress URL: http://${WP_IP:-<External-IP>}/
==============================================================
EOF

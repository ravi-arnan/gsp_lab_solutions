#!/usr/bin/env bash
# GSP539 - Build Global and Regional Load Balancing Solutions: Challenge Lab
#
#   bash gsp539.sh
#
# Checkpoint:
#   Task 1 - Create a regional MIG and 2 firewall rules
#            Create a regional internal proxy NLB
#            Deploy a client VM and validate the access
#   Task 2 - Create two regional MIGs
#            Create global external application load balancer
#   Task 3 - Test failover and global distribution (stop/start nginx)
#
# Region A = backend ALB, Region B = internal proxy NLB (berisi proxy-only subnet).
# Script mendeteksi keduanya dari VPC lb-network; kalau tidak ketemu, tanyakan.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }
NETWORK="lb-network"

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

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ── Deteksi region + subnet dari VPC lb-network ───────────────────
PROXY_SUBNET="" ; PROXY_CIDR="" ; NETWORK_EXISTS=0
declare -A SUBNET_IN_REGION=()

if gcloud compute networks describe "$NETWORK" >/dev/null 2>&1; then
  NETWORK_EXISTS=1
fi

if [[ "$NETWORK_EXISTS" == "1" ]]; then
  while IFS=, read -r name region_url purpose; do
    [[ -z "$name" ]] && continue
    region="${region_url##*/}"
    case "$purpose" in
      *MANAGED_PROXY*) PROXY_SUBNET="$name" ; PROXY_REGION_D="$region" ;;
      PRIVATE|"")     [[ -z "${SUBNET_IN_REGION[$region]:-}" ]] && SUBNET_IN_REGION[$region]="$name" ;;
    esac
  done < <(gcloud compute networks subnets list --network="$NETWORK" --format="csv(no-heading)(name,region,purpose)" 2>/dev/null || true)
  if [[ -n "$PROXY_SUBNET" ]]; then
    PROXY_CIDR_D="$(gcloud compute networks subnets describe "$PROXY_SUBNET" --region="$PROXY_REGION_D" --format="value(ipCidrRange)" 2>/dev/null || true)"
  fi
fi

ask REGION_B "${PROXY_REGION_D:-us-central1}" "Region B (internal proxy NLB, proxy-only subnet ada di sini)"
DEF_A=""
for r in "${!SUBNET_IN_REGION[@]}"; do
  if [[ "$r" != "$REGION_B" ]]; then DEF_A="$r"; break; fi
done
ask REGION_A "${DEF_A:-us-west1}" "Region A (backend ALB)"

SUBNET_B="${SUBNET_B:-${SUBNET_IN_REGION[$REGION_B]:-}}"
[[ -n "$SUBNET_B" ]] || ask SUBNET_B "subnet-b" "Subnet biasa di Region B (backend + VIP + client VM)"
SUBNET_A="${SUBNET_A:-${SUBNET_IN_REGION[$REGION_A]:-}}"
[[ -n "$SUBNET_A" ]] || ask SUBNET_A "subnet-a" "Subnet biasa di Region A (backend ALB)"
PROXY_CIDR="${PROXY_CIDR:-${PROXY_CIDR_D:-}}"
[[ -n "$PROXY_CIDR" ]] || ask PROXY_CIDR "10.129.0.0/23" "CIDR proxy-only subnet di Region B"

ZONE_A="${ZONE_A:-$(gcloud compute zones list --filter="region:($REGION_A)" --format="value(name)" 2>/dev/null | head -1 || true)}"
ZONE_B="${ZONE_B:-$(gcloud compute zones list --filter="region:($REGION_B)" --format="value(name)" 2>/dev/null | head -1 || true)}"
ZONE_A="${ZONE_A:-${REGION_A}-a}" ; ZONE_B="${ZONE_B:-${REGION_B}-a}"

echo
echo "Project    : $PROJECT_ID"
echo "Network    : $NETWORK"
echo "Region A   : $REGION_A (subnet $SUBNET_A, zone $ZONE_A)"
echo "Region B   : $REGION_B (subnet $SUBNET_B, zone $ZONE_B)"
echo "Proxy-only: $PROXY_CIDR (${PROXY_SUBNET:-belum ada})"

# ── Startup script nginx (dipakai kalau template pre-provisioned tidak ada) ──
NGINX_TVS='#!/bin/bash
apt-get update -y
apt-get install -y nginx
echo "<h3>TVS backend: $(hostname)</h3>" > /var/www/html/index.html
systemctl restart nginx'

NGINX_ALB='#!/bin/bash
apt-get update -y
apt-get install -y nginx
ZONE=$(curl -s -H Metadata-Flavor:Google http://metadata.google.internal/computeMetadata/v1/instance/zone)
echo "Hello from ${ZONE##*/}" > /var/www/html/index.html
systemctl restart nginx'

template_exists() { # <template> <region>
  gcloud compute instance-templates describe "$1" >/dev/null 2>&1 || \
  gcloud compute instance-templates describe "$1" --region="$2" >/dev/null 2>&1
}

# ensure_template <name> <region|kosong=global> <subnet> <tags> <startup-script>
ensure_template() {
  if template_exists "$1" "$2"; then
    echo "  Template $1 sudah ada (pre-provisioned), dipakai apa adanya."
    return 0
  fi
  echo "  Template $1 tidak ada, membuat (nginx + tags $4)."
  # shellcheck disable=SC2086
  gcloud compute instance-templates create "$1" ${2:+--region=$2} \
    --network="$NETWORK" --subnet="$3" --tags="$4" \
    --machine-type=e2-small --image-family=debian-12 --image-project=debian-cloud \
    --metadata=startup-script="$5"
}

# ensure_mig <name> <region> <template> <portname:port> <subnet> <tags> <script>
ensure_mig() {
  if gcloud compute instance-groups managed describe "$1" --region="$2" >/dev/null 2>&1; then
    echo "  MIG $1 sudah ada."
  elif gcloud compute instance-groups managed create "$1" --region="$2" --size=1 \
         --template="$3" 2>/tmp/gsp539_mig.err; then
    :
  else
    echo "  Pembuatan MIG dengan template $3 ditolak, beralih ke template fallback:"
    sed 's/^/    /' /tmp/gsp539_mig.err || true
    local fb="${3}-${2}"
    ensure_template "$fb" "$2" "$5" "$6" "$7"
    gcloud compute instance-groups managed create "$1" --region="$2" --size=1 --template="$fb"
  fi
  gcloud compute instance-groups managed set-named-ports "$1" --region="$2" --named-ports="$4"
  gcloud compute instance-groups managed wait-until-stable "$1" --region="$2" --timeout=240 || true
}

# ensure_tag_on_instances <mig> <region> <tag>
# Template pre-provisioned seharusnya sudah bawa tag; asuransi kalau tidak.
ensure_tag_on_instances() {
  local inst zone tags
  for inst in $(gcloud compute instance-groups managed list-instances "$1" --region="$2" \
                  --format="value(instance)" 2>/dev/null || true); do
    zone="$(gcloud compute instances list --filter="name=$inst" --format="value(zone)" 2>/dev/null | head -1 || true)"
    tags="$(gcloud compute instances describe "$inst" --zone="$zone" --format="value(tags.items)" 2>/dev/null || true)"
    if [[ " $tags " != *" $3 "* ]]; then
      echo "  $inst belum punya tag $3, menambahkannya."
      gcloud compute instances add-tags "$inst" --zone="$zone" --tags="$3"
    fi
  done
}

# ensure_fw <name> <network> <source-ranges> <target-tag|kosong> <rules>
ensure_fw() {
  if gcloud compute firewall-rules describe "$1" >/dev/null 2>&1; then
    echo "  Firewall $1 sudah ada."
    return 0
  fi
  local tgt=()
  [[ -n "$4" ]] && tgt=(--target-tags="$4")
  gcloud compute firewall-rules create "$1" --network="$2" --action=allow --direction=ingress \
    --source-ranges="$3" "${tgt[@]}" --rules="$5"
}

# ════════════════════════════════════════════════════════════════
# Persiapan network (hanya kalau lb-network belum ada di project)
# ════════════════════════════════════════════════════════════════
if [[ "$NETWORK_EXISTS" != "1" ]]; then
  step "Buat VPC $NETWORK + subnet (tidak ditemukan di project ini)"
  gcloud compute networks create "$NETWORK" --subnet-mode=custom
  gcloud compute networks subnets create "$SUBNET_A" --network="$NETWORK" --region="$REGION_A" --range=10.1.2.0/24
  gcloud compute networks subnets create "$SUBNET_B" --network="$NETWORK" --region="$REGION_B" --range=10.3.4.0/24
fi

if [[ -z "$PROXY_SUBNET" ]]; then
  step "Buat proxy-only subnet di Region B (REGIONAL_MANAGED_PROXY)"
  gcloud compute networks subnets create proxy-only-subnet \
    --purpose=REGIONAL_MANAGED_PROXY --role=ACTIVE --region="$REGION_B" \
    --network="$NETWORK" --range="$PROXY_CIDR"
  PROXY_SUBNET=proxy-only-subnet
fi

# ════════════════════════════════════════════════════════════════
# TASK 1 - Secure internal transaction processor (regional internal proxy NLB)
# ════════════════════════════════════════════════════════════════
step "Task 1: Deploy internal backends (MIG mig-proxy-internal, zonal)"
ensure_template template-proxy-internal "$REGION_B" "$SUBNET_B" "tag-proxy-internal,allow-ssh" "$NGINX_TVS"
if ! gcloud compute instance-groups managed describe mig-proxy-internal --zone="$ZONE_B" >/dev/null 2>&1; then
  gcloud compute instance-groups managed create mig-proxy-internal \
    --zone="$ZONE_B" --size=1 --template=template-proxy-internal
fi
gcloud compute instance-groups managed set-named-ports mig-proxy-internal \
  --zone="$ZONE_B" --named-ports=tcp80:80
gcloud compute instance-groups managed wait-until-stable mig-proxy-internal \
  --zone="$ZONE_B" --timeout=240 || true

step "Task 1: Firewall rules untuk tag tag-proxy-internal"
ensure_fw fw-allow-hc-proxy-internal "$NETWORK" "130.211.0.0/22,35.191.0.0/16" tag-proxy-internal tcp:80
ensure_fw fw-allow-proxy-subnet-internal "$NETWORK" "$PROXY_CIDR" tag-proxy-internal tcp:80
ensure_fw fw-allow-ssh "$NETWORK" "0.0.0.0/0" allow-ssh tcp:22

step "Task 1: Reserve VIP + regional internal proxy NLB"
if ! gcloud compute addresses describe ip-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute addresses create ip-internal-proxy --region="$REGION_B" \
    --subnet="$SUBNET_B" --purpose=SHARED_LOADBALANCER_VIP
fi
INTERNAL_IP="$(gcloud compute addresses describe ip-internal-proxy --region="$REGION_B" --format="value(address)" 2>/dev/null || true)"
echo "  VIP internal: $INTERNAL_IP (port 110 -> backend tcp80)"

if ! gcloud compute health-checks describe hc-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute health-checks create tcp hc-internal-proxy --region="$REGION_B" --port=80
fi

if ! gcloud compute backend-services describe bs-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute backend-services create bs-internal-proxy \
    --load-balancing-scheme=INTERNAL_MANAGED --protocol=TCP --region="$REGION_B" \
    --port-name=tcp80 --health-checks=hc-internal-proxy --health-checks-region="$REGION_B"
fi
if ! gcloud compute backend-services describe bs-internal-proxy --region="$REGION_B" \
     --format="value(backends.group)" 2>/dev/null | grep -q mig-proxy-internal; then
  gcloud compute backend-services add-backend bs-internal-proxy --region="$REGION_B" \
    --instance-group=mig-proxy-internal --instance-group-zone="$ZONE_B"
fi

if ! gcloud compute target-tcp-proxies describe tgt-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute target-tcp-proxies create tgt-internal-proxy \
    --backend-service=bs-internal-proxy --proxy-header=NONE --region="$REGION_B"
fi

if ! gcloud compute forwarding-rules describe rule-internal-proxy --region="$REGION_B" >/dev/null 2>&1; then
  gcloud compute forwarding-rules create rule-internal-proxy \
    --load-balancing-scheme=INTERNAL_MANAGED --network="$NETWORK" --subnet="$SUBNET_B" \
    --region="$REGION_B" \
    --target-tcp-proxy=tgt-internal-proxy --target-tcp-proxy-region="$REGION_B" \
    --address=ip-internal-proxy --ports=110
fi

step "Task 1: Client VM vm-client-internal + validasi akses"
if ! gcloud compute instances describe vm-client-internal --zone="$ZONE_B" >/dev/null 2>&1; then
  gcloud compute instances create vm-client-internal --zone="$ZONE_B" \
    --network="$NETWORK" --subnet="$SUBNET_B" --tags=allow-ssh \
    --machine-type=e2-small --image-family=debian-12 --image-project=debian-cloud
fi
for _ in $(seq 1 20); do
  [[ "$(gcloud compute instances describe vm-client-internal --zone="$ZONE_B" --format="value(status)" 2>/dev/null || true)" == "RUNNING" ]] && break
  sleep 5
done
echo "  curl http://$INTERNAL_IP:110 dari dalam VPC:"
if ! timeout 150 gcloud compute ssh vm-client-internal --zone="$ZONE_B" -q \
     --command="curl -s --max-time 10 http://$INTERNAL_IP:110; echo" \
     --ssh-flag="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30" 2>&1 | tail -8; then
  echo "  (SSH/curl belum berhasil. Manual: SSH ke vm-client-internal di Console, lalu:"
  echo "     curl http://$INTERNAL_IP:110 )"
fi

# ════════════════════════════════════════════════════════════════
# TASK 2 - Global external market data feed (global external ALB, HTTPS)
# ════════════════════════════════════════════════════════════════
step "Task 2: Deploy global backends (mig-alb-api-a + mig-alb-api-b)"
ensure_template template-alb-api "$REGION_A" "$SUBNET_A" "allow-health-check" "$NGINX_ALB"
ensure_mig mig-alb-api-a "$REGION_A" template-alb-api "http80:80" \
  "$SUBNET_A" "allow-health-check" "$NGINX_ALB"
ensure_mig mig-alb-api-b "$REGION_B" template-alb-api "http80:80" \
  "$SUBNET_B" "allow-health-check" "$NGINX_ALB"

step "Task 2: Health check + global backend service (rate, max RPS 1 per region)"
if ! gcloud compute health-checks describe http-check-alb --global >/dev/null 2>&1; then
  gcloud compute health-checks create http http-check-alb --port=80 --global
fi
if ! gcloud compute backend-services describe service-alb-global --global >/dev/null 2>&1; then
  gcloud compute backend-services create service-alb-global --global \
    --load-balancing-scheme=EXTERNAL_MANAGED --protocol=HTTP --port-name=http80 \
    --health-checks=http-check-alb
fi
for pair in "mig-alb-api-a $REGION_A" "mig-alb-api-b $REGION_B"; do
  # shellcheck disable=SC2086
  set -- $pair
  if ! gcloud compute backend-services describe service-alb-global --global \
       --format="value(backends.group)" 2>/dev/null | grep -q "$1"; then
    gcloud compute backend-services add-backend service-alb-global --global \
      --instance-group="$1" --instance-group-region="$2" \
      --balancing-mode=RATE --max-rate-per-instance=1
  fi
done

step "Task 2: Sertifikat self-signed + IP global + frontend HTTPS:443"
if ! gcloud compute ssl-certificates describe cert-self-signed --global >/dev/null 2>&1; then
  CERT_DIR="$(mktemp -d)"
  openssl genrsa -out "$CERT_DIR/key.pem" 2048
  openssl req -new -x509 -key "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" -days 1 -subj "/CN=example.com"
  gcloud compute ssl-certificates create cert-self-signed \
    --certificate="$CERT_DIR/cert.pem" --private-key="$CERT_DIR/key.pem" --global
fi
if ! gcloud compute addresses describe ip-alb-global --global >/dev/null 2>&1; then
  gcloud compute addresses create ip-alb-global --ip-version=IPV4 --global
fi
ALB_IP="$(gcloud compute addresses describe ip-alb-global --global --format="value(address)" 2>/dev/null || true)"
if ! gcloud compute url-maps describe url-map-alb --global >/dev/null 2>&1; then
  gcloud compute url-maps create url-map-alb --default-service=service-alb-global --global
fi
if ! gcloud compute target-https-proxies describe target-proxy-alb --global >/dev/null 2>&1; then
  gcloud compute target-https-proxies create target-proxy-alb \
    --url-map=url-map-alb --ssl-certificates=cert-self-signed --global
fi
if ! gcloud compute forwarding-rules describe fr-alb-https --global >/dev/null 2>&1; then
  gcloud compute forwarding-rules create fr-alb-https --global \
    --load-balancing-scheme=EXTERNAL_MANAGED --network-tier=PREMIUM \
    --address=ip-alb-global --target-https-proxy=target-proxy-alb --ports=443
fi
ensure_fw fw-allow-health-check-and-proxy "$NETWORK" "130.211.0.0/22,35.191.0.0/16" tag-alb-api tcp:80
echo "  ALB IP: https://$ALB_IP"

# ════════════════════════════════════════════════════════════════
# TASK 3 - Test failover and global distribution
# ════════════════════════════════════════════════════════════════
step "Task 3: Distribusi global (Max RPS 1 -> traffic meluap ke region satunya)"
for _ in $(seq 1 12); do
  code="$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$ALB_IP" 2>/dev/null || true)"
  [[ "$code" == "200" ]] && break
  echo "  menunggu ALB siap... (HTTP $code)"
  sleep 20
done

lb_response() {
  local resp line
  resp="$(curl -k -s --max-time 10 "https://$ALB_IP" 2>/dev/null || true)"
  line="$(echo "$resp" | grep -o "Hello from [^<]*" | head -1 || true)"
  [[ -z "$line" ]] && line="$(echo "$resp" | head -c 120)"
  echo "  $line"
}
echo "  10 request berturut-turut (harus bergantian region A / B):"
for _ in $(seq 1 10); do lb_response; sleep 0.5; done

step "Task 3: Simulasi backend failure (stop nginx di mig-alb-api-a)"
INST="$(gcloud compute instance-groups managed list-instances mig-alb-api-a --region="$REGION_A" \
          --format="value(instance)" 2>/dev/null | head -1 || true)"
if [[ -z "$INST" ]]; then
  echo "  Tidak ada instance di mig-alb-api-a. Lewati failover otomatis."
else
  ZONE_INST="$(gcloud compute instances list --filter="name=$INST" --format="value(zone)" 2>/dev/null | head -1 || true)"
  echo "  Menghentikan nginx di $INST ($ZONE_INST)..."
  if ! timeout 150 gcloud compute ssh "$INST" --zone="$ZONE_INST" -q \
       --command="sudo systemctl stop nginx" \
       --ssh-flag="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30" 2>&1 | tail -5; then
    echo "  (SSH gagal. Manual: SSH ke instance mig-alb-api-a, jalankan: sudo systemctl stop nginx)"
  fi
  echo "  Tunggu health check mendeteksi (default ~10-15 detik)..."
  sleep 30
  echo "  Respon setelah failure (harusnya hanya region B):"
  for _ in $(seq 1 10); do lb_response; sleep 0.5; done
  echo "  Pantau grafiknya: Network Services > Load Balancing > service-alb-global > Monitoring."
  read -r -t 20 -p "  Tekan ENTER untuk merestore backend (20 detik)..." _ || true

  step "Task 3: Restore backend (start nginx)"
  if ! timeout 150 gcloud compute ssh "$INST" --zone="$ZONE_INST" -q \
       --command="sudo systemctl start nginx" \
       --ssh-flag="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30" 2>&1 | tail -5; then
    echo "  (SSH gagal. Manual: sudo systemctl start nginx di instance yang sama.)"
  fi
  echo "  Tunggu health check kembali HEALTHY..."
  sleep 40
  echo "  Respon setelah restore (kedua region kembali melayani):"
  for _ in $(seq 1 10); do lb_response; sleep 0.5; done
fi

# ════════════════════════════════════════════════════════════════
step "SELESAI! Klik Check my progress untuk verifikasi:"
cat <<EOT
  Task 1 - Create a regional MIG and 2 firewall rules
  Task 1 - Create a regional internal proxy NLB
  Task 1 - Deploy a client VM and validate the access
  Task 2 - Create two regional MIGs
  Task 2 - Create global external application load balancer
  Task 3 - Test failover and global distribution

  Ringkasan:
    Internal proxy NLB : $INTERNAL_IP:110  (Region $REGION_B)
    Global ALB (HTTPS) : https://$ALB_IP   (Region $REGION_A + $REGION_B)
EOT

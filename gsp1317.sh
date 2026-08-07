#!/usr/bin/env bash
# GSP1317 - Establish VPC to VPC Connectivity using NCC
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp1317.sh
#   bash gsp1317.sh            # Task 1-5
#   # klik Check my progress keempat checkpoint sampai hijau
#   bash gsp1317.sh delete     # Task 6 (bersih-bersih, tidak dinilai)
#
# Checkpoint:
#   Task 1 - Create the NCC hub
#   Task 2 - Configure VPCs as an NCC spoke
#   Task 4 - Setup Private Service Connect
#   Task 5 - Connect to Cloud SQL via Private Service Connect
#
# Task 3 (tcpdump + ping) tidak punya checkpoint; script tetap menguji ping
# secara best-effort. Task 6 MENGHAPUS hub dan spoke buatan Task 1-2, jadi
# fase delete wajib dijalankan terpisah setelah semua checkpoint hijau.
#
# Nilai yang diacak per peserta (nama instance Cloud SQL, region, IP endpoint,
# DNS record) dideteksi sendiri oleh script.

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

step() { echo; echo "=== $* ==="; }

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
gcloud config set project "$PROJECT" >/dev/null 2>&1
gcloud config set accessibility/screen_reader false >/dev/null 2>&1

PHASE="${1:-create}"
case "$PHASE" in
  create|delete) ;;
  *) echo "Fase tidak dikenal: $PHASE (pakai 'create' atau 'delete')"; exit 1 ;;
esac

HUB="ncc-hub"
SPOKE1="vpc1-spoke1"
SPOKE2="vpc2-spoke2"
VPC1="vpc1-ncc"
VPC2="vpc2-ncc"
SUBNET2="vpc2-ncc-subnet1"
PSC_ADDR_NAME="cloudsql-psc"
PSC_FR_NAME="cloudsql-psc-ep"
DNS_ZONE="cloudsql-dns"

step "Mengaktifkan Network Connectivity API"
gcloud services enable networkconnectivity.googleapis.com >/dev/null

# ------------------------------------------------------------------ deteksi
step "Mendeteksi resource bawaan lab"

SQL_INSTANCE_DEFAULT="$(gcloud sql instances list --format='value(name)' --limit=1)"
ask SQL_INSTANCE "$SQL_INSTANCE_DEFAULT" "Nama instance Cloud SQL"
[[ -n "$SQL_INSTANCE" ]] || { echo "Instance Cloud SQL tidak ditemukan."; exit 1; }

REGION_DEFAULT="$(gcloud sql instances describe "$SQL_INSTANCE" --format='value(region)')"
ask REGION "$REGION_DEFAULT" "Region (cocokkan dengan panel lab)"

# dnsName kadang kosong dan yang terisi dnsNames[0].name, tergantung versi API.
DNS_RECORD="$(gcloud sql instances describe "$SQL_INSTANCE" --format='value(dnsName)')"
[[ -n "$DNS_RECORD" ]] || DNS_RECORD="$(gcloud sql instances describe "$SQL_INSTANCE" --format='value(dnsNames[0].name)')"
[[ -n "$DNS_RECORD" ]] || { echo "DNS name Cloud SQL tidak terbaca. Cek PSC sudah aktif di instance."; exit 1; }
DNS_RECORD="${DNS_RECORD%.}."          # pastikan diakhiri titik
DNS_ZONE_NAME="$REGION.sql.goog."
echo "  DNS record : $DNS_RECORD"
echo "  DNS zone   : $DNS_ZONE_NAME"

# ------------------------------------------------------------------- delete
if [[ "$PHASE" == "delete" ]]; then
  step "Task 6 - hapus spoke, hub, DNS record, dan managed zone"
  gcloud network-connectivity spokes delete "$SPOKE1" --global --quiet 2>/dev/null || true
  gcloud network-connectivity spokes delete "$SPOKE2" --global --quiet 2>/dev/null || true
  gcloud network-connectivity hubs delete "$HUB" --quiet 2>/dev/null || true
  gcloud dns record-sets delete "$DNS_RECORD" --type=A --zone="$DNS_ZONE" 2>/dev/null || true
  gcloud dns managed-zones delete "$DNS_ZONE" --quiet 2>/dev/null || true
  echo
  echo "SELESAI! Task 6 tidak punya checkpoint."
  exit 0
fi

# ------------------------------------------------------------------- Task 1
step "Task 1 - membuat NCC hub $HUB"
gcloud network-connectivity hubs describe "$HUB" >/dev/null 2>&1 || \
  gcloud network-connectivity hubs create "$HUB"
gcloud network-connectivity hubs describe "$HUB" --format='value(name,state)'

# ------------------------------------------------------------------- Task 2
step "Task 2 - VPC sebagai NCC spoke"
gcloud compute networks subnets list --network="$VPC1" \
  --format='table(name,region.basename(),ipCidrRange)'

# Exclude range mengikuti instruksi lab: ringkasan /24 dari sepasang /25 di VPC1,
# dan /24 milik VPC2.
ask EXCLUDE1 "10.1.2.0/24" "Exclude export range untuk $VPC1"
ask EXCLUDE2 "10.3.3.0/24" "Exclude export range untuk $VPC2"

gcloud network-connectivity spokes describe "$SPOKE1" --global >/dev/null 2>&1 || \
  gcloud network-connectivity spokes linked-vpc-network create "$SPOKE1" \
    --hub="$HUB" --vpc-network="$VPC1" --exclude-export-ranges="$EXCLUDE1" --global

gcloud network-connectivity spokes describe "$SPOKE2" --global >/dev/null 2>&1 || \
  gcloud network-connectivity spokes linked-vpc-network create "$SPOKE2" \
    --hub="$HUB" --vpc-network="$VPC2" --exclude-export-ranges="$EXCLUDE2" --global

echo "Routing table hub:"
gcloud network-connectivity hubs route-tables routes list --hub="$HUB" --route_table=default

# ------------------------------------------------------------------- Task 3
step "Task 3 - uji data path IPv4 (tanpa checkpoint, best-effort)"
VM1_IP="$(gcloud compute instances list --filter="name=vm1-vpc1-ncc" \
  --format='value(networkInterfaces[0].networkIP)' | head -n1)"
VM2_ZONE="$(gcloud compute instances list --filter="name=vm2-vpc2-ncc" \
  --format='value(zone.basename())' | head -n1)"
if [[ -n "$VM1_IP" && -n "$VM2_ZONE" ]]; then
  echo "  vm2-vpc2-ncc -> $VM1_IP"
  timeout 150 gcloud compute ssh vm2-vpc2-ncc --zone="$VM2_ZONE" --tunnel-through-iap --quiet \
    --command="ping -c 3 -W 2 $VM1_IP" 2>&1 | tail -n 5 || echo "  (ping gagal/di-skip, tidak dinilai)"
else
  echo "  VM uji tidak ditemukan, dilewati."
fi

# ------------------------------------------------------------------- Task 4
step "Task 4 - Private Service Connect ke Cloud SQL"

CIDR="$(gcloud compute networks subnets describe "$SUBNET2" --region="$REGION" \
  --format='value(ipCidrRange)')"
echo "  CIDR $SUBNET2 : $CIDR"

if gcloud compute addresses describe "$PSC_ADDR_NAME" --region="$REGION" >/dev/null 2>&1; then
  PSC_IP="$(gcloud compute addresses describe "$PSC_ADDR_NAME" --region="$REGION" --format='value(address)')"
  echo "  alamat $PSC_ADDR_NAME sudah ada: $PSC_IP"
else
  # GCP memakai IP dari ujung bawah subnet dan mereservasi dua IP terakhir,
  # jadi kandidat diambil dari ujung atas, mundur beberapa host.
  CANDIDATES="$(python3 -c "
import ipaddress
h = list(ipaddress.ip_network('$CIDR').hosts())
print(' '.join(str(x) for x in h[-8:-2][::-1]))
")"
  PSC_IP=""
  for cand in $CANDIDATES; do
    if gcloud compute addresses create "$PSC_ADDR_NAME" --region="$REGION" \
         --subnet="$SUBNET2" --addresses="$cand" >/dev/null 2>&1; then
      PSC_IP="$cand"; echo "  alamat direservasi: $PSC_IP"; break
    fi
    echo "  $cand terpakai, coba berikutnya"
  done
  [[ -n "$PSC_IP" ]] || { echo "Tidak ada IP bebas di $CIDR. Set PSC_IP manual lalu ulangi."; exit 1; }
fi
gcloud compute addresses list --filter="name=$PSC_ADDR_NAME" \
  --format='table(name,address,status)'

SA_URI="$(gcloud sql instances describe "$SQL_INSTANCE" \
  --format='value(pscServiceAttachmentLink)')"
[[ -n "$SA_URI" ]] || { echo "Service attachment Cloud SQL kosong. PSC belum aktif di instance."; exit 1; }
echo "  service attachment: $SA_URI"

gcloud compute forwarding-rules describe "$PSC_FR_NAME" --region="$REGION" >/dev/null 2>&1 || \
  gcloud compute forwarding-rules create "$PSC_FR_NAME" \
    --address="$PSC_ADDR_NAME" \
    --region="$REGION" \
    --network="$VPC2" \
    --target-service-attachment="$SA_URI" \
    --allow-psc-global-access

echo -n "  status koneksi PSC: "
gcloud compute forwarding-rules describe "$PSC_FR_NAME" --region="$REGION" \
  --format='value(pscConnectionStatus)'

gcloud dns managed-zones describe "$DNS_ZONE" >/dev/null 2>&1 || \
  gcloud dns managed-zones create "$DNS_ZONE" \
    --description="DNS zone for the Cloud SQL instances" \
    --dns-name="$DNS_ZONE_NAME" \
    --networks="$VPC2" \
    --visibility=private

if [[ -z "$(gcloud dns record-sets list --zone="$DNS_ZONE" --name="$DNS_RECORD" --type=A --format='value(name)')" ]]; then
  gcloud dns record-sets create "$DNS_RECORD" --type=A --rrdatas="$PSC_IP" --zone="$DNS_ZONE"
fi
gcloud dns record-sets list --zone="$DNS_ZONE" --format='table(name,type,rrdatas)'

# ------------------------------------------------------------------- Task 5
step "Task 5 - buat database dan tabel lewat PSC"

CLIENT_ZONE="$(gcloud compute instances list --filter="name=cloudsql-client" \
  --format='value(zone.basename())' | head -n1)"
[[ -n "$CLIENT_ZONE" ]] || { echo "VM cloudsql-client tidak ditemukan."; exit 1; }

PGHOST="${DNS_RECORD%.}"

# SQL dikirim base64 supaya tidak perlu escaping berlapis lewat ssh.
run_psql() {
  local db="$1" sql="$2" b64
  b64="$(printf '%s' "$sql" | base64 -w0)"
  gcloud compute ssh cloudsql-client --zone="$CLIENT_ZONE" --tunnel-through-iap --quiet \
    --command="echo $b64 | base64 -d | PGPASSWORD=changeme psql 'sslmode=disable dbname=$db user=postgres host=$PGHOST'"
}

# CREATE DATABASE tidak punya IF NOT EXISTS, jadi kegagalan "already exists"
# sengaja diabaikan supaya script tetap idempoten.
run_psql postgres "CREATE DATABASE company;" || echo "  (database company sudah ada)"

run_psql company "
CREATE TABLE IF NOT EXISTS employees (
    id SERIAL PRIMARY KEY,
    first VARCHAR(255) NOT NULL,
    last VARCHAR(255) NOT NULL,
    salary DECIMAL (10, 2)
);
INSERT INTO employees (first, last, salary)
SELECT * FROM (VALUES
    ('Max', 'Mustermann', 5000.00),
    ('Anna', 'Schmidt', 7000.00),
    ('Peter', 'Mayer', 6000.00)
) AS v(first, last, salary)
WHERE NOT EXISTS (SELECT 1 FROM employees);
SELECT * FROM employees;
"

cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi:
  - Create the NCC hub                                (Task 1)
  - Configure VPCs as an NCC spoke                    (Task 2)
  - Setup Private Service Connect                     (Task 4)
  - Connect to Cloud SQL via Private Service Connect  (Task 5)

Setelah keempatnya HIJAU, bersih-bersih Task 6 (tidak dinilai):

  bash gsp1317.sh delete
EOF

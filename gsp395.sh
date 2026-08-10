#!/usr/bin/env bash
# GSP395 - Create and Manage AlloyDB Instances: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp395.sh
#   REGION=<region dari panel lab> bash gsp395.sh
#
# Checkpoint:
#   Task 1 - Cluster 'lab-cluster' + instance PRIMARY 'lab-instance'
#   Task 2 - Tabel regions, countries, departments
#   Task 3 - Data ketiga tabel
#   Task 4 - Read pool 'lab-instance-rp1' (2 node)
#   Task 5 - Backup 'lab-backup'
#
# Tabel dibuat lewat psql DI DALAM VM 'alloydb-client'. Private IP AlloyDB tidak
# terjangkau dari Cloud Shell (VPC peering-nya hanya menyentuh VPC lab), jadi
# SQL-nya dikirim lewat ssh, pola yang sama dengan gsp038.
#
# Read pool dibuat di latar belakang sementara tabel diisi — dua antrean ~5
# menit jadi tumpang tindih. Backup baru jalan setelah read pool selesai,
# karena cluster tidak menerima operasi lain saat ada yang berjalan.
#
# LAMA: ~20 menit, hampir semuanya menunggu AlloyDB.

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

ask REGION "us-central1" "GCP Region dari panel lab (WAJIB cocok)"
ask NETWORK "peering-network" "Network yang sudah dipeering lab"

CLUSTER="${CLUSTER:-lab-cluster}"
INSTANCE="${INSTANCE:-lab-instance}"
READPOOL="${READPOOL:-lab-instance-rp1}"
BACKUP="${BACKUP:-lab-backup}"
DBPASS="${DBPASS:-Change3Me}"
VM="${VM:-alloydb-client}"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable alloydb.googleapis.com compute.googleapis.com --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1a: cluster $CLUSTER (~5 menit)"
if gcloud beta alloydb clusters describe "$CLUSTER" --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Cluster sudah ada."
else
  gcloud beta alloydb clusters create "$CLUSTER" \
    --password="$DBPASS" \
    --network="$NETWORK" \
    --region="$REGION" \
    --project="$PROJECT"
fi

step "Task 1b: instance PRIMARY $INSTANCE (~7 menit)"
if gcloud beta alloydb instances describe "$INSTANCE" --cluster="$CLUSTER" \
     --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Instance sudah ada."
else
  gcloud beta alloydb instances create "$INSTANCE" \
    --instance-type=PRIMARY \
    --cpu-count=2 \
    --cluster="$CLUSTER" \
    --region="$REGION" \
    --project="$PROJECT"
fi

ALLOYDB_IP="$(gcloud beta alloydb instances describe "$INSTANCE" --cluster="$CLUSTER" \
  --region="$REGION" --project="$PROJECT" --format='value(ipAddress)')"
[[ -n "$ALLOYDB_IP" ]] || { echo "Private IP instance kosong."; exit 1; }
echo "Private IP: $ALLOYDB_IP"

# ----------------------------------------------------------------- Task 4 (latar)
step "Task 4: read pool $READPOOL dimulai di latar belakang"
if gcloud beta alloydb instances describe "$READPOOL" --cluster="$CLUSTER" \
     --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Read pool sudah ada."
  RP_PID=""
else
  gcloud beta alloydb instances create "$READPOOL" \
    --instance-type=READ_POOL \
    --cpu-count=2 \
    --read-pool-node-count=2 \
    --cluster="$CLUSTER" \
    --region="$REGION" \
    --project="$PROJECT" > "${TMPDIR:-/tmp}/gsp395-readpool.log" 2>&1 &
  RP_PID=$!
  echo "PID $RP_PID, log: ${TMPDIR:-/tmp}/gsp395-readpool.log"
fi

# ----------------------------------------------------------------- Task 2 + 3
step "Task 2 & 3: tabel dan data lewat psql di $VM"
ZONE="$(gcloud compute instances list --filter="name=$VM" \
  --format='value(zone)' --project="$PROJECT" | head -1)"
[[ -n "$ZONE" ]] || { echo "VM $VM tidak ditemukan."; exit 1; }
echo "Zone $VM: $ZONE"

REMOTE="${TMPDIR:-/tmp}/gsp395_remote.sh"
cat > "$REMOTE" << 'REMOTE_EOF'
#!/bin/bash
# Dijalankan DI DALAM alloydb-client. $1 = private IP, $2 = password.
set -euo pipefail
ALLOYDB="$1"
export PGPASSWORD="$2"

# Lab menyuruh menyimpan IP-nya di sini supaya bertahan antar sesi SSH.
echo "$ALLOYDB" > "$HOME/alloydbip.txt"

command -v psql >/dev/null || {
  echo "psql belum ada, dipasang."
  sudo apt-get update -qq && sudo apt-get install -y -qq postgresql-client
}

# ON_ERROR_STOP: tanpa ini psql tetap exit 0 walau DDL-nya gagal, dan script
# akan melapor SELESAI padahal tabelnya tidak pernah jadi.
psql -h "$ALLOYDB" -U postgres -v ON_ERROR_STOP=1 << 'SQL'
DROP TABLE IF EXISTS regions, countries, departments CASCADE;

CREATE TABLE regions (
    region_id bigint NOT NULL,
    region_name varchar(25)
);
ALTER TABLE regions ADD PRIMARY KEY (region_id);

CREATE TABLE countries (
    country_id char(2) NOT NULL,
    country_name varchar(40),
    region_id bigint
);
ALTER TABLE countries ADD PRIMARY KEY (country_id);

CREATE TABLE departments (
    department_id smallint NOT NULL,
    department_name varchar(30),
    manager_id integer,
    location_id smallint
);
ALTER TABLE departments ADD PRIMARY KEY (department_id);

INSERT INTO regions VALUES
  (1, 'Europe'),
  (2, 'Americas'),
  (3, 'Asia'),
  (4, 'Middle East and Africa');

INSERT INTO countries VALUES
  ('IT', 'Italy', 1),
  ('JP', 'Japan', 3),
  ('US', 'United States of America', 2),
  ('CA', 'Canada', 2),
  ('CN', 'China', 3),
  ('IN', 'India', 3),
  ('AU', 'Australia', 3),
  ('ZW', 'Zimbabwe', 4),
  ('SG', 'Singapore', 3);

INSERT INTO departments VALUES
  (10, 'Administration', 200, 1700),
  (20, 'Marketing', 201, 1800),
  (30, 'Purchasing', 114, 1700),
  (40, 'Human Resources', 203, 2400),
  (50, 'Shipping', 121, 1500),
  (60, 'IT', 103, 1400);
SQL

echo "== Isi tabel =="
psql -h "$ALLOYDB" -U postgres -c \
  "SELECT 'regions' t, count(*) FROM regions
   UNION ALL SELECT 'countries', count(*) FROM countries
   UNION ALL SELECT 'departments', count(*) FROM departments;"
REMOTE_EOF

n=1
until gcloud compute scp "$REMOTE" "$VM":~/gsp395_remote.sh \
        --zone="$ZONE" --project="$PROJECT" --quiet; do
  (( n++ >= 6 )) && { echo "SSH tidak siap setelah 5 percobaan."; exit 1; }
  echo "SSH belum siap, tunggu 15 detik (percobaan $n)..."
  sleep 15
done

gcloud compute ssh "$VM" --zone="$ZONE" --project="$PROJECT" --quiet \
  --command="bash ~/gsp395_remote.sh '$ALLOYDB_IP' '$DBPASS'"

# ----------------------------------------------------------------- tunggu Task 4
if [[ -n "$RP_PID" ]]; then
  step "Tunggu read pool $READPOOL selesai"
  if ! wait "$RP_PID"; then
    echo "Pembuatan read pool gagal. Log:"
    cat "${TMPDIR:-/tmp}/gsp395-readpool.log"
    exit 1
  fi
  cat "${TMPDIR:-/tmp}/gsp395-readpool.log"
fi

# ----------------------------------------------------------------- Task 5
step "Task 5: backup $BACKUP"
if gcloud beta alloydb backups describe "$BACKUP" --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Backup sudah ada."
else
  gcloud beta alloydb backups create "$BACKUP" \
    --cluster="$CLUSTER" \
    --region="$REGION" \
    --project="$PROJECT"
fi

step "Ringkasan"
gcloud beta alloydb instances list --cluster="$CLUSTER" --region="$REGION" \
  --project="$PROJECT" --format='table(name,instanceType,state,ipAddress)'
gcloud beta alloydb backups list --region="$REGION" --project="$PROJECT" \
  --format='table(name,state,clusterName)'

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:

  Task 1 - Cluster $CLUSTER + instance $INSTANCE (private IP $ALLOYDB_IP)
  Task 2 - Tabel regions, countries, departments
  Task 3 - Data ketiga tabel
  Task 4 - Read pool $READPOOL (2 node)
  Task 5 - Backup $BACKUP

Private IP juga tersimpan di ~/alloydbip.txt DI DALAM $VM.
==============================================================
EOF

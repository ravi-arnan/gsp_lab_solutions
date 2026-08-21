#!/usr/bin/env bash
# GSP351 - Migrate MySQL Data to Cloud SQL Using Database Migration Service: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp351.sh
#   bash gsp351.sh            # Task 1-4 -> checkpoint 1 sampai 4
#   # klik Check my progress 1-4 sampai hijau
#   bash gsp351.sh promote    # Task 5  -> checkpoint 5
#
# Checkpoint:
#   Task 1 - Connection profile untuk source MySQL (external IP)
#   Task 2 - One-time migration ke instance mysql-mkt-<xxx>
#   Task 3 - Continuous migration ke mysql-mkt-<xxx>-cont lewat VPC peering
#   Task 4 - Perubahan di source ikut tereplikasi
#   Task 5 - Promote instance continuous jadi stand-alone
#
# Nama VM dan Cloud SQL punya suffix acak per instance; script menemukannya
# sendiri dari daftar resource, jadi tidak ada yang perlu diketik.
#
# Kenapa dua fase: promote menghentikan replikasi. Kalau dijalankan sebelum
# checkpoint 4 diklik, tidak ada lagi job berstatus Running yang bisa dilihat
# grader.
#
# LAMA: fase 1 sekitar 15-25 menit (dump + restore dua kali), fase 2 sekitar 3 menit.

set -euo pipefail

PHASE="${1:-main}"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

REGION="${REGION:-us-central1}"
NETWORK="${NETWORK:-default}"
DB_USER="admin"
DB_PASS="changeme"

SRC_PROFILE="mysql-source-profile"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- discovery
# Instance Cloud SQL: yang berakhiran -cont dipakai job continuous, sisanya
# dipakai job one-time. Suffix di tengah nama diacak per lab.
CLOUDSQL_CONT=$(gcloud sql instances list --project="$PROJECT" \
  --format='value(name)' --filter="name~-cont$" | head -1)
CLOUDSQL_ONE=$(gcloud sql instances list --project="$PROJECT" \
  --format='value(name)' --filter="NOT name~-cont$" | head -1)
[[ -n "$CLOUDSQL_ONE" && -n "$CLOUDSQL_CONT" ]] || {
  echo "Cloud SQL instance lab tidak ketemu. Isinya:"; gcloud sql instances list; exit 1; }

echo "Project        : $PROJECT"
echo "Region         : $REGION"
echo "Cloud SQL 1x   : $CLOUDSQL_ONE"
echo "Cloud SQL cont : $CLOUDSQL_CONT"

# ================================================================= fase promote
if [[ "$PHASE" == "promote" ]]; then
  step "Task 5: promote $CLOUDSQL_CONT jadi stand-alone (checkpoint 5)"
  gcloud database-migration migration-jobs promote "$CLOUDSQL_CONT" \
    --region="$REGION" --project="$PROJECT" --no-async
  gcloud database-migration migration-jobs describe "$CLOUDSQL_CONT" \
    --region="$REGION" --project="$PROJECT" --format='value(state)'
  gcloud sql instances describe "$CLOUDSQL_CONT" --project="$PROJECT" \
    --format='value(instanceType)'
  cat <<EOF

--------------------------------------------------------------
SELESAI! Klik Check my progress untuk:
  5. Promote the destination Cloud SQL for MySQL database

instanceType harus CLOUD_SQL_INSTANCE (bukan READ_REPLICA_INSTANCE).
--------------------------------------------------------------
EOF
  exit 0
fi

SRC_VM=$(gcloud compute instances list --project="$PROJECT" --format='value(name)' | head -1)
SRC_IP=$(gcloud compute instances describe "$SRC_VM" --project="$PROJECT" \
  --zone="$(gcloud compute instances list --project="$PROJECT" --filter="name=$SRC_VM" --format='value(zone)')" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')
[[ -n "$SRC_IP" ]] || { echo "External IP $SRC_VM tidak ketemu."; exit 1; }
echo "Source VM      : $SRC_VM ($SRC_IP)"

# ----------------------------------------------------------------- Task 1
step "Task 1: connection profile source lewat external IP (checkpoint 1)"
if gcloud database-migration connection-profiles describe "$SRC_PROFILE" \
     --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Profile $SRC_PROFILE sudah ada, dilewat."
else
  gcloud database-migration connection-profiles create mysql "$SRC_PROFILE" \
    --region="$REGION" --project="$PROJECT" \
    --host="$SRC_IP" --port=3306 \
    --username="$DB_USER" --password="$DB_PASS" \
    --display-name="$SRC_PROFILE" \
    --no-async
fi

# ----------------------------------------------------------------- destination
step "Connection profile untuk dua Cloud SQL yang sudah ada"
# --cloudsql-instance menunjuk instance yang sudah ada, setara memilih
# "Existing instance" di console.
for INST in "$CLOUDSQL_ONE" "$CLOUDSQL_CONT"; do
  PROF="dest-$INST"
  if gcloud database-migration connection-profiles describe "$PROF" \
       --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
    echo "Profile $PROF sudah ada, dilewat."
  else
    gcloud database-migration connection-profiles create mysql "$PROF" \
      --region="$REGION" --project="$PROJECT" \
      --cloudsql-instance="$INST" \
      --display-name="$PROF" \
      --no-async
  fi
done

wait_state() {   # wait_state <job> <state yang diinginkan> <menit maksimal>
  local JOB=$1 WANT=$2 MAX=$((${3:-20} * 6)) I=0 ST
  while (( I++ < MAX )); do
    ST=$(gcloud database-migration migration-jobs describe "$JOB" \
      --region="$REGION" --project="$PROJECT" --format='value(state)' 2>/dev/null || true)
    echo "  [$JOB] state: ${ST:-?}"
    [[ "$ST" == "$WANT" ]] && return 0
    [[ "$ST" == "FAILED" ]] && { 
      gcloud database-migration migration-jobs describe "$JOB" \
        --region="$REGION" --project="$PROJECT" --format='yaml(error,phase,state)'
      return 1; }
    sleep 10
  done
  return 1
}

# ----------------------------------------------------------------- Task 2
step "Task 2: job one-time ke $CLOUDSQL_ONE lewat IP allowlist (checkpoint 2)"
# --static-ip = connectivity "IP allowlist", cara DMS memakai external IP source.
if gcloud database-migration migration-jobs describe "$CLOUDSQL_ONE" \
     --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Job $CLOUDSQL_ONE sudah ada, dilewat pembuatannya."
else
  gcloud database-migration migration-jobs create "$CLOUDSQL_ONE" \
    --region="$REGION" --project="$PROJECT" \
    --type=ONE_TIME \
    --source="$SRC_PROFILE" \
    --destination="dest-$CLOUDSQL_ONE" \
    --static-ip \
    --display-name="$CLOUDSQL_ONE" \
    --no-async
fi

gcloud database-migration migration-jobs start "$CLOUDSQL_ONE" \
  --region="$REGION" --project="$PROJECT" --no-async || true
wait_state "$CLOUDSQL_ONE" COMPLETED 25 || {
  echo "Job one-time belum COMPLETED. Cek statusnya sebelum lanjut."; }

# ----------------------------------------------------------------- Task 3
step "Task 3: job continuous ke $CLOUDSQL_CONT lewat VPC peering (checkpoint 3)"
if gcloud database-migration migration-jobs describe "$CLOUDSQL_CONT" \
     --region="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Job $CLOUDSQL_CONT sudah ada, dilewat pembuatannya."
else
  gcloud database-migration migration-jobs create "$CLOUDSQL_CONT" \
    --region="$REGION" --project="$PROJECT" \
    --type=CONTINUOUS \
    --source="$SRC_PROFILE" \
    --destination="dest-$CLOUDSQL_CONT" \
    --peer-vpc="projects/$PROJECT/global/networks/$NETWORK" \
    --display-name="$CLOUDSQL_CONT" \
    --no-async
fi

gcloud database-migration migration-jobs start "$CLOUDSQL_CONT" \
  --region="$REGION" --project="$PROJECT" --no-async || true
wait_state "$CLOUDSQL_CONT" RUNNING 25 || {
  echo "Job continuous belum RUNNING. Jangan lanjut ke Task 4 dulu."; exit 1; }

# ----------------------------------------------------------------- Task 4
step "Task 4: ubah data di source lalu tunggu replikasi (checkpoint 4)"
command -v mysql >/dev/null || { echo "Client mysql tidak ada, pasang: sudo apt-get install -y default-mysql-client"; exit 1; }

mysql -h "$SRC_IP" -u "$DB_USER" -p"$DB_PASS" -e "
use customers_data;
update customers set gender = 'FEMALE' where addressKey = 934;
select addressKey, gender from customers where addressKey = 934;
"

echo "Menunggu 90 detik supaya perubahan tereplikasi..."
sleep 90

cat <<EOF

--------------------------------------------------------------
Fase 1 selesai. Klik Check my progress untuk:
  1. Configure a Database Migration Service connection profile
  2. Perform a one-time migration
  3. Migrate using continuous migration
  4. Check that the updated source data has been migrated

Verifikasi manual kalau perlu (jumlah baris harus 5030):
  gcloud sql connect $CLOUDSQL_ONE --user=root
  use customers_data; select count(*) from customers;

Setelah keempatnya HIJAU, jalankan fase kedua:

  bash $0 promote
--------------------------------------------------------------
EOF

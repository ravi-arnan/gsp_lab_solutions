#!/usr/bin/env bash
# GSP1049 - Cloud Spanner - Loading Data and Performing Backups
#
#   bash gsp1049.sh
#   DF_REGION=us-east1 bash gsp1049.sh    # kalau panel lab menyebut endpoint lain
#
# Checkpoint:
#   Task 3 - Insert data through a client library       (insert.py)
#   Task 4 - Insert batch data through a client library (batch_insert.py)
#   Task 5 - Load data using Dataflow                   (~12-16 menit)
#   Task 6 - Backup your database                       (banking-backup-001, ~15 menit)
#
# Instance banking-instance + database banking-db + tabel Customer sudah dibuat
# oleh lab, script tidak membuatnya.

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Client library Spanner mencoba mengirim metrik internal ke Cloud Monitoring dan
# selalu ditolak 400 (label instance_id kosong). Tidak berpengaruh ke insert, cuma
# membanjiri output — matikan.
export SPANNER_DISABLE_BUILTIN_METRICS=true

# Regional endpoint Dataflow diacak per peserta — lihat instruksi Task 5 di lab.
ask DF_REGION "asia-south1" "Region Dataflow (cocokkan dengan panel lab)"
INSTANCE="banking-instance"
DATABASE="banking-db"
BUCKET="gs://$PROJECT"

echo "Project  : $PROJECT"
echo "Dataflow : $DF_REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Task 2
step "Task 2: Insert satu baris lewat DML"
gcloud spanner databases execute-sql banking-db --instance=banking-instance \
 --sql="INSERT INTO Customer (CustomerId, Name, Location) VALUES ('bdaaaa97-1b4b-4e58-b4ad-84030de92235', 'Richard Nelson', 'Ada Ohio')" \
  || echo "  (baris sudah ada, lanjut)"

# ----------------------------------------------------------------- Task 3
step "Task 3: Insert lewat client library Python (insert.py)"
# Cloud Shell biasanya sudah punya google-cloud-spanner; install kalau belum.
python3 -c 'import google.cloud.spanner' 2>/dev/null || pip3 install --quiet google-cloud-spanner

cat > insert.py <<'EOF'
from google.cloud import spanner
from google.cloud.spanner_v1 import param_types

INSTANCE_ID = "banking-instance"
DATABASE_ID = "banking-db"

spanner_client = spanner.Client()
instance = spanner_client.instance(INSTANCE_ID)
database = instance.database(DATABASE_ID)

def insert_customer(transaction):
    row_ct = transaction.execute_update(
        "INSERT INTO Customer (CustomerId, Name, Location)"
        "VALUES ('b2b4002d-7813-4551-b83b-366ef95f9273', 'Shana Underwood', 'Ely Iowa')"
    )
    print("{} record(s) inserted.".format(row_ct))

database.run_in_transaction(insert_customer)
EOF
python3 insert.py || echo "  (baris sudah ada, lanjut)"

# ----------------------------------------------------------------- Task 4
step "Task 4: Insert batch lewat client library (batch_insert.py)"
cat > batch_insert.py <<'EOF'
from google.cloud import spanner
from google.cloud.spanner_v1 import param_types

INSTANCE_ID = "banking-instance"
DATABASE_ID = "banking-db"

spanner_client = spanner.Client()
instance = spanner_client.instance(INSTANCE_ID)
database = instance.database(DATABASE_ID)

with database.batch() as batch:
    batch.insert(
        table="Customer",
        columns=("CustomerId", "Name", "Location"),
        values=[
        ('edfc683f-bd87-4bab-9423-01d1b2307c0d', 'John Elkins', 'Roy Utah'),
        ('1f3842ca-4529-40ff-acdd-88e8a87eb404', 'Martin Madrid', 'Ames Iowa'),
        ('3320d98e-6437-4515-9e83-137f105f7fbc', 'Theresa Henderson', 'Anna Texas'),
        ('6b2b2774-add9-4881-8702-d179af0518d8', 'Norma Carter', 'Bend Oregon'),

        ],
    )

print("Rows inserted")
EOF
python3 batch_insert.py || echo "  (baris sudah ada, lanjut)"

echo "Jumlah baris sekarang: $(row_count)"

# Checkpoint Task 3 dan 4 memeriksa jumlah baris tabel Customer, bukan cuma
# keberadaan baris tertentu: Task 3 menuntut tepat 2 baris, Task 4 tepat 6.
# Begitu Dataflow menambah 151k baris, keduanya langsung merah. Karena itu
# script berhenti di sini — persis urutan klik di lab manual.
step "Klik Check my progress dulu"
echo "  - Insert data through a client library      (butuh tepat 2 baris)"
echo "  - Insert batch data through a client library (butuh tepat 6 baris)"
echo
echo "JANGAN lanjut sebelum keduanya hijau. Dataflow di bawah menambah 151k baris"
echo "dan membuat kedua checkpoint itu tidak bisa lolos lagi tanpa hapus data."
echo
read -r -p "Sudah hijau dua-duanya? Tekan Enter untuk lanjut ke Dataflow..."

# ----------------------------------------------------------------- Task 5
step "Task 5: Load 150k+ baris lewat Dataflow"
COUNT=$(row_count)
if (( COUNT > 1000 )); then
  echo "Sudah ada $COUNT baris, data Dataflow kelihatannya sudah masuk. Lewati."
else
  gcloud storage buckets describe "$BUCKET" --project="$PROJECT" &>/dev/null ||
    gcloud storage buckets create "$BUCKET" --project="$PROJECT"
  : > emptyfile
  gcloud storage cp emptyfile "$BUCKET/tmp/emptyfile"

  # Persis langkah lab: siklus disable/enable memaksa service agent Dataflow
  # dibuat ulang dengan izin yang benar.
  # Cukup sekali. Kalau script diulang, siklus ini justru menghapus lagi binding
  # service agent yang baru dipasang di bawah.
  if gcloud services list --enabled --project="$PROJECT" \
       --filter='config.name:dataflow.googleapis.com' --format='value(config.name)' | grep -q dataflow; then
    echo "Dataflow API sudah aktif, lewati siklus disable/enable."
  else
    gcloud services disable dataflow.googleapis.com --force -q 2>/dev/null || true
    gcloud services enable dataflow.googleapis.com
  fi

  # Siklus di atas menghapus binding service agent, dan Google baru memulihkannya
  # beberapa menit kemudian. Job yang diluncurkan sebelum itu langsung FAILED:
  # "The Dataflow service agent cannot access the worker service account."
  # Di lab manual jeda ini terisi waktu mengisi wizard Console; lewat script
  # binding-nya dipasang sendiri.
  PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
  DF_AGENT="service-$PROJECT_NUMBER@dataflow-service-producer-prod.iam.gserviceaccount.com"
  WORKER_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

  step "Task 5a: Pastikan IAM Dataflow siap"
  # Service agent dibuat lazy setelah API aktif — binding bisa gagal beberapa
  # percobaan pertama dengan "does not exist".
  for i in 1 2 3 4 5 6; do
    if gcloud projects add-iam-policy-binding "$PROJECT" \
         --member="serviceAccount:$DF_AGENT" --role=roles/dataflow.serviceAgent \
         --condition=None >/dev/null 2>&1; then
      echo "Service agent Dataflow siap."
      break
    fi
    echo "  service agent belum ada, tunggu 30 detik (percobaan $i)..."
    sleep 30
  done

  for ROLE in roles/dataflow.worker roles/storage.objectAdmin roles/spanner.databaseUser; do
    gcloud projects add-iam-policy-binding "$PROJECT" \
      --member="serviceAccount:$WORKER_SA" --role="$ROLE" --condition=None >/dev/null
  done

  # Service agent harus bisa memakai worker SA — ini persis yang dikeluhkan
  # error di atas.
  gcloud iam service-accounts add-iam-policy-binding "$WORKER_SA" \
    --member="serviceAccount:$DF_AGENT" --role=roles/iam.serviceAccountTokenCreator \
    --project="$PROJECT" >/dev/null || true

  echo "Menunggu propagasi IAM (60 detik)..."
  sleep 60

  run_job() {
    local job_id state
    job_id=$(gcloud dataflow jobs run spanner-load \
      --gcs-location gs://dataflow-templates/latest/GCS_Text_to_Cloud_Spanner \
      --region="$DF_REGION" \
      --staging-location "$BUCKET/tmp" \
      --worker-machine-type=e2-medium \
      --parameters "instanceId=$INSTANCE,databaseId=$DATABASE,importManifest=gs://spls/gsp1049/manifest.json" \
      --project="$PROJECT" --format='value(id)')
    echo "Job Dataflow: $job_id"
    echo "Menunggu job selesai (12-16 menit)..."
    while true; do
      state=$(gcloud dataflow jobs describe "$job_id" --region="$DF_REGION" \
        --project="$PROJECT" --format='value(currentState)')
      echo "  $(date +%H:%M:%S) $state"
      case "$state" in
        JOB_STATE_DONE) return 0 ;;
        JOB_STATE_FAILED|JOB_STATE_CANCELLED)
          echo "--- log error job ---"
          # 'logs' cuma ada di release track beta, bukan gcloud dataflow biasa.
          gcloud beta dataflow logs list "$job_id" --region="$DF_REGION" --project="$PROJECT" \
            --importance=error 2>/dev/null | head -20
          echo "---------------------"
          return 1 ;;
      esac
      sleep 60
    done
  }

  # Kegagalan izin biasanya sembuh sendiri setelah binding sempat menyebar.
  OK=0
  for ATTEMPT in 1 2 3; do
    if run_job; then OK=1; break; fi
    (( $(row_count) > 1000 )) && { echo "Sebagian data sudah masuk, hentikan retry."; OK=1; break; }
    (( ATTEMPT < 3 )) && { echo "Percobaan $ATTEMPT gagal, ulangi dalam 2 menit..."; sleep 120; }
  done
  if (( OK == 0 )); then
    echo "Job gagal 3 kali. Kalau errornya soal worker tidak ter-provision (kuota),"
    echo "ulangi dengan region lain: DF_REGION=us-east1 bash gsp1049.sh"
    exit 1
  fi
  echo "Jumlah baris setelah Dataflow: $(row_count)"
fi

# ----------------------------------------------------------------- Task 6
step "Task 6: Backup banking-db jadi banking-backup-001"
if gcloud spanner backups describe banking-backup-001 --instance="$INSTANCE" \
     --project="$PROJECT" &>/dev/null; then
  echo "Backup sudah ada, lewati."
else
  # Retensi maksimum Spanner 1 tahun; wizard Console memakai pilihan yang sama.
  gcloud spanner backups create banking-backup-001 \
    --instance="$INSTANCE" --database="$DATABASE" \
    --retention-period=365d --project="$PROJECT"
fi
gcloud spanner backups list --instance="$INSTANCE" --project="$PROJECT"

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 3 - Insert data through a client library"
echo "  Task 4 - Insert batch data through a client library"
echo "  Task 5 - Load data using Dataflow"
echo "  Task 6 - Backup your database"

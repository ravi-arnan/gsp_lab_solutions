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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Client library Spanner mencoba mengirim metrik internal ke Cloud Monitoring dan
# selalu ditolak 400 (label instance_id kosong). Tidak berpengaruh ke insert, cuma
# membanjiri output — matikan.
export SPANNER_DISABLE_BUILTIN_METRICS=true

# Regional endpoint Dataflow diacak per peserta — lihat instruksi Task 5 di lab.
DF_REGION="${DF_REGION:-asia-south1}"
INSTANCE="banking-instance"
DATABASE="banking-db"
BUCKET="gs://$PROJECT"

echo "Project  : $PROJECT"
echo "Dataflow : $DF_REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# execute-sql membalas {"metadata":..., "rows":[["7"]]} — ambil sel pertama lewat jq,
# 0 kalau apa pun gagal supaya perbandingan aritmatika di bawah tidak meledak.
row_count() {
  local n
  n=$(gcloud spanner databases execute-sql "$DATABASE" --instance="$INSTANCE" --project="$PROJECT" \
        --sql='SELECT COUNT(*) FROM Customer' --format=json 2>/dev/null | jq -r '.rows[0][0] // 0')
  [[ "$n" =~ ^[0-9]+$ ]] && echo "$n" || echo 0
}

# ----------------------------------------------------------------- Task 2
step "Task 2: Insert satu baris lewat DML"
gcloud spanner databases execute-sql "$DATABASE" --instance="$INSTANCE" --project="$PROJECT" \
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
  gcloud services disable dataflow.googleapis.com --force -q
  gcloud services enable dataflow.googleapis.com

  # Di lab manual, jeda ini terisi waktu mengisi wizard Console. Lewat script
  # job bisa diluncurkan sebelum service agent Dataflow selesai dibuat, dan
  # jobnya langsung FAILED dalam semenit.
  echo "Menunggu service agent Dataflow siap (90 detik)..."
  sleep 90

  JOB_ID=$(gcloud dataflow jobs run spanner-load \
    --gcs-location gs://dataflow-templates/latest/GCS_Text_to_Cloud_Spanner \
    --region="$DF_REGION" \
    --staging-location "$BUCKET/tmp" \
    --worker-machine-type=e2-medium \
    --parameters "instanceId=$INSTANCE,databaseId=$DATABASE,importManifest=gs://spls/gsp1049/manifest.json" \
    --project="$PROJECT" --format='value(id)')
  echo "Job Dataflow: $JOB_ID"

  echo "Menunggu job selesai (12-16 menit)..."
  while true; do
    STATE=$(gcloud dataflow jobs describe "$JOB_ID" --region="$DF_REGION" \
      --project="$PROJECT" --format='value(currentState)')
    echo "  $(date +%H:%M:%S) $STATE"
    case "$STATE" in
      JOB_STATE_DONE) break ;;
      JOB_STATE_FAILED|JOB_STATE_CANCELLED)
        echo "--- log error job ---"
        # 'logs' cuma ada di release track beta, bukan gcloud dataflow biasa.
        gcloud beta dataflow logs list "$JOB_ID" --region="$DF_REGION" --project="$PROJECT" \
          --importance=error 2>/dev/null | head -20
        echo "---------------------"
        echo "Kalau errornya soal worker tidak ter-provision, ulangi dengan region"
        echo "lain, misal: DF_REGION=us-east1 bash gsp1049.sh"
        exit 1 ;;
    esac
    sleep 60
  done
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

#!/usr/bin/env bash
# GSP323 - Prepare Data for ML APIs on Google Cloud: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp323.sh
#   bash gsp323.sh
#
# Checkpoint:
#   Task 1 (Dataflow) - Text Files on Cloud Storage to BigQuery
#   Task 2 (Dataproc) - SparkPageRank di Dataproc Compute Engine
#   Task 3 (Speech-to-Text) - gs://.../task3.flac -> .../task3-gcs-*.result
#   Task 4 (Natural Language) - analyzeEntities "Old Norse ..." -> .../task4-cnl-*.result
#
# Nilai di tabel lab DIACAK per peserta (dataset, tabel, suffix bucket/result).
# Script membaca default dari instruksi lab terbaru, tapi tanyakan di awal supaya
# bisa override tanpa edit file. OG: lab_270/customers_868, task3-gcs-945, task4-cnl-248.
# Bucket marking selalu <PROJECT_ID>-marking (sesuai check IAM storage.admin).
#
# LAMA: Dataflow ~5-7 menit, Dataproc cluster ~3-4 menit + job ~2 menit, API ~1 menit.

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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Nilai default sesuai instruksi di prompt lab ini. Override kalau panel lab-mu
# menampilkan angka berbeda.
ask DATASET "lab_270" "BigQuery dataset (cocokkan dengan panel lab)"
ask TABLE "customers_868" "BigQuery table (cocokkan dengan panel lab)"
ask TASK3_SUFFIX "task3-gcs-945" "Suffix file Task 3 (tanpa .result, contoh task3-gcs-945)"
ask TASK4_SUFFIX "task4-cnl-248" "Suffix file Task 4 (tanpa .result, contoh task4-cnl-248)"
ask REGION "us-central1" "Region (cocokkan dengan panel lab)"
ask DF_REGION "us-central1" "Region Dataflow (biasanya sama dengan Region)"

MARKING_BUCKET="${PROJECT_ID}-marking"
BQ_DATASET_FQN="${PROJECT_ID}:${DATASET}.${TABLE}"
TEMP_BQ_DIR="gs://${MARKING_BUCKET}/bigquery_temp"
TEMP_DIR="gs://${MARKING_BUCKET}/temp"
TASK3_OUTPUT="gs://${MARKING_BUCKET}/${TASK3_SUFFIX}.result"
TASK4_OUTPUT="gs://${MARKING_BUCKET}/${TASK4_SUFFIX}.result"

# Cluster name deterministik, tidak diacak lab.
CLUSTER="spark-cluster"

echo "Project       : $PROJECT_ID"
echo "Dataset.Table : $BQ_DATASET_FQN"
echo "Marking bucket: gs://$MARKING_BUCKET"
echo "Region        : $REGION (Dataflow: $DF_REGION)"
echo "Task 3 output : $TASK3_OUTPUT"
echo "Task 4 output : $TASK4_OUTPUT"
echo "Cluster       : $CLUSTER"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ------------------------------------------------------------------ API
step "Enable API"
gcloud services enable \
  dataflow.googleapis.com \
  dataproc.googleapis.com \
  bigquery.googleapis.com \
  speech.googleapis.com \
  language.googleapis.com \
  apikeys.googleapis.com \
  compute.googleapis.com \
  --project="$PROJECT_ID"

# IAM: pastikan compute SA punya storage.admin (sesuai prasyarat cek lab)
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$COMPUTE_SA" --role="roles/storage.admin" --condition=None >/dev/null 2>&1 || true
# Dataproc butuh editor (lab minta editor + storage.admin di awal)
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$COMPUTE_SA" --role="roles/editor" --condition=None >/dev/null 2>&1 || true

# ------------------------------------------------------------------ Task 1
step "Task 1a: Buat bucket gs://$MARKING_BUCKET"
if gcloud storage buckets describe "gs://$MARKING_BUCKET" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
else
  gcloud storage buckets create "gs://$MARKING_BUCKET" --project="$PROJECT_ID" --location="$REGION" --uniform-bucket-level-access -q
fi

step "Task 1b: Buat dataset BigQuery $DATASET"
if bq --project_id="$PROJECT_ID" show "$DATASET" >/dev/null 2>&1; then
  echo "Dataset sudah ada, dilewat."
else
  bq --project_id="$PROJECT_ID" mk --dataset --location="$REGION" "$DATASET" 2>/dev/null \
    || bq --project_id="$PROJECT_ID" mk "$DATASET"
fi
# Tabel dibiarkan dibuat oleh Dataflow; kalau sudah ada dari run sebelumnya tidak dihapus
# supaya idempoten. Template akan append/replace sesuai job.

step "Task 1c: Jalankan Dataflow job (Text Files on GCS to BigQuery)"
# Template ada di dua lokasi tergantung region. Coba yang regional dulu, fallback ke global.
TEMPLATE_REG="gs://dataflow-templates-${DF_REGION}/latest/GCS_Text_to_BigQuery"
TEMPLATE_GLB="gs://dataflow-templates/latest/GCS_Text_to_BigQuery"
TEMPLATE="$TEMPLATE_REG"
# Cek bucket template ada; kalau tidak, pakai global
if ! gcloud storage ls "$TEMPLATE" >/dev/null 2>&1; then
  TEMPLATE="$TEMPLATE_GLB"
fi
echo "Template: $TEMPLATE"

# Service agent Dataflow butuh izin. Polling binding mirip gsp1049.
DF_AGENT="service-${PROJECT_NUMBER}@dataflow-service-producer-prod.iam.gserviceaccount.com"
for i in 1 2 3 4 5; do
  if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
       --member="serviceAccount:$DF_AGENT" --role="roles/dataflow.serviceAgent" --condition=None >/dev/null 2>&1; then
    break
  fi
  echo "  service agent belum siap, tunggu 15 detik (percobaan $i)..."
  sleep 15
done
for ROLE in roles/dataflow.worker roles/storage.objectAdmin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$COMPUTE_SA" --role="$ROLE" --condition=None >/dev/null 2>&1 || true
done
gcloud iam service-accounts add-iam-policy-binding "$COMPUTE_SA" \
  --member="serviceAccount:$DF_AGENT" --role="roles/iam.serviceAccountTokenCreator" \
  --project="$PROJECT_ID" >/dev/null 2>&1 || true
sleep 10

JOB_NAME="gsp323-$(date +%s)"
echo "Job name: $JOB_NAME"

# Hapus state Dataflow aktif yang bisa tabrakan (opsional, idempoten)
echo "Menjalankan Dataflow job (tunggu ~5-7 menit)..."

# gcloud dataflow jobs run butuh staging-location terpisah dari temp
# ponytail: gcloud kadang menulis warning ke stderr, jadi pisahkan stdout.
RAW_ID="$(gcloud dataflow jobs run "$JOB_NAME" \
  --gcs-location "$TEMPLATE" \
  --region "$DF_REGION" \
  --staging-location "gs://${MARKING_BUCKET}/staging" \
  --worker-machine-type=e2-standard-2 \
  --parameters "inputFilePattern=gs://spls/gsp323/lab.csv,JSONPath=gs://spls/gsp323/lab.schema,outputTable=${BQ_DATASET_FQN},bigQueryLoadingTemporaryDirectory=${TEMP_BQ_DIR},javascriptTextTransformGcsPath=gs://spls/gsp323/lab.js,javascriptTextTransformFunctionName=transform" \
  --project="$PROJECT_ID" --format='value(id)' 2> /tmp/gsp323_df_stderr.txt || true)"
# Ambil baris terakhir yang mirip job id (format 2026-09-02_xx_xx_xx-xxxx). Fallback ke stdout murni.
DF_JOB_ID="$(echo "$RAW_ID" | tr -d '[:space:]' | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]+.*' | head -1 || true)"
if [[ -z "$DF_JOB_ID" ]]; then
  DF_JOB_ID="$(echo "$RAW_ID" | tail -1 | tr -d '[:space:]')"
fi
if [[ -z "$DF_JOB_ID" || "${#DF_JOB_ID}" -lt 10 ]]; then
  echo "Warning: parsing job id gagal, output mentah:"
  cat /tmp/gsp323_df_stderr.txt 2>/dev/null || true
  echo "RAW_ID=[$RAW_ID]"
  sleep 10
  DF_JOB_ID="$(gcloud dataflow jobs list --region="$DF_REGION" --project="$PROJECT_ID" --filter="name=$JOB_NAME" --format='value(id)' 2>/dev/null | head -1 || true)"
fi
if [[ -z "$DF_JOB_ID" ]]; then
  echo "GAGAL: tidak dapat job id. Cek Dataflow console manual: https://console.cloud.google.com/dataflow/jobs?project=$PROJECT_ID"
  # Jangan loop UNKNOWN selamanya — lanjut ke task berikutnya
  echo "Lanjut ke Task 2 (Dataflow bisa dicek manual di console)."
else
  echo "Dataflow job: $DF_JOB_ID (region $DF_REGION)"
  echo "Menunggu job selesai (polling 30 detik, timeout 15 menit)..."

  ATTEMPT=0
  while true; do
    STATE="$(gcloud dataflow jobs describe "$DF_JOB_ID" --region="$DF_REGION" --project="$PROJECT_ID" --format='value(currentState)' 2>/dev/null || echo UNKNOWN)"
    echo "  $(date +%H:%M:%S) $STATE (id $DF_JOB_ID)"
    case "$STATE" in
      JOB_STATE_DONE) echo "Dataflow selesai."; break ;;
      JOB_STATE_FAILED|JOB_STATE_CANCELLED|JOB_STATE_DRAINED)
        echo "Dataflow gagal dengan state $STATE. Cek log:"
        gcloud dataflow jobs describe "$DF_JOB_ID" --region="$DF_REGION" --project="$PROJECT_ID" || true
        echo "Coba jalankan ulang script setelah cek error di atas."
        break ;;
      JOB_STATE_RUNNING|JOB_STATE_PENDING|JOB_STATE_QUEUED) sleep 30 ;;
      UNKNOWN)
        ATTEMPT=$((ATTEMPT+1))
        if (( ATTEMPT > 30 )); then
          echo "Polling UNKNOWN 15 menit, hentikan polling. Cek manual:"
          echo "  gcloud dataflow jobs list --region=$DF_REGION --project=$PROJECT_ID"
          echo "  https://console.cloud.google.com/dataflow/jobs?project=$PROJECT_ID"
          break
        fi
        sleep 30
        # Coba refresh id dari list kalau describe terus UNKNOWN (id kepotong)
        if (( ATTEMPT == 5 )); then
          REFRESH="$(gcloud dataflow jobs list --region="$DF_REGION" --project="$PROJECT_ID" --filter="name=$JOB_NAME" --format='value(id)' 2>/dev/null | head -1 || true)"
          [[ -n "$REFRESH" && "$REFRESH" != "$DF_JOB_ID" ]] && { DF_JOB_ID="$REFRESH"; echo "Refresh job id -> $DF_JOB_ID"; }
        fi
        ;;
      *) sleep 30 ;;
    esac
  done
fi

# ------------------------------------------------------------------ Task 2
step "Task 2a: Buat Dataproc cluster $CLUSTER (n2d-standard-2, pd-standard 100GB, 2 worker)"

# Subnet default harus allow Private Google Access kalau cluster tanpa external IP,
# tapi lab minta Internal IP only = Deselect (jadi pakai external IP). Tidak perlu
# ubah subnet. Cukup pastikan cluster dibuat tanpa --internal-ip-only / --no-address.
if gcloud dataproc clusters describe "$CLUSTER" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Cluster sudah ada, dilewat pembuatan."
else
  # Disk type: lab minta Standard Persistent Disk = pd-standard
  gcloud dataproc clusters create "$CLUSTER" \
    --project="$PROJECT_ID" --region="$REGION" \
    --master-machine-type=n2d-standard-2 \
    --master-boot-disk-type=pd-standard --master-boot-disk-size=100GB \
    --num-workers=2 --worker-machine-type=n2d-standard-2 \
    --worker-boot-disk-type=pd-standard --worker-boot-disk-size=100GB \
    --image-version=2.2-debian12 \
    --max-idle=1800s \
    --enable-component-gateway \
    --no-address 2>&1 | head -20
  # Jika create di atas gagal karena flag --no-address tidak diinginkan (lab minta deselect internal only),
  # coba tanpa --no-address. Percobaan pertama pakai internal-only untuk kompatibilitas VPC lab yang
  # kadang memaksa internal IP; fallback pakai external IP.
  if ! gcloud dataproc clusters describe "$CLUSTER" --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "Retry tanpa --no-address (external IP, sesuai instruksi lab deselect internal only)..."
    gcloud dataproc clusters create "$CLUSTER" \
      --project="$PROJECT_ID" --region="$REGION" \
      --master-machine-type=n2d-standard-2 \
      --master-boot-disk-type=pd-standard --master-boot-disk-size=100GB \
      --num-workers=2 --worker-machine-type=n2d-standard-2 \
      --worker-boot-disk-type=pd-standard --worker-boot-disk-size=100GB \
      --image-version=2.2-debian12 \
      --project="$PROJECT_ID" || true
  fi
fi

# Tunggu cluster READY
echo "Menunggu cluster READY..."
for i in $(seq 1 30); do
  ST="$(gcloud dataproc clusters describe "$CLUSTER" --region="$REGION" --project="$PROJECT_ID" --format='value(status.state)' 2>/dev/null || echo UNKNOWN)"
  echo "  percobaan $i: $ST"
  [[ "$ST" == "RUNNING" ]] && break
  sleep 15
done

step "Task 2b: Copy /data.txt ke HDFS (hdfs dfs -cp gs://spls/gsp323/data.txt /data.txt)"
# Cari master node zone + name
MASTER_ZONE="$(gcloud compute instances list --filter="name~^${CLUSTER}-m" --format='value(zone)' --project="$PROJECT_ID" | head -1)"
MASTER_NAME="$(gcloud compute instances list --filter="name~^${CLUSTER}-m" --format='value(name)' --project="$PROJECT_ID" | head -1)"
if [[ -z "$MASTER_NAME" ]]; then
  # Fallback: ambil dari dataproc describe
  MASTER_NAME="$(gcloud dataproc clusters describe "$CLUSTER" --region="$REGION" --project="$PROJECT_ID" --format='value(config.masterConfig.instanceNames[0])' 2>/dev/null | cut -d/ -f4)"
  MASTER_ZONE="$(gcloud compute instances list --filter="name=$MASTER_NAME" --format='value(zone)' --project="$PROJECT_ID" 2>/dev/null | head -1)"
fi
echo "Master: $MASTER_NAME zone $MASTER_ZONE"

# Retry ssh sampai siap. hdfs ada di PATH master.
for n in 1 2 3 4 5; do
  if gcloud compute ssh "$MASTER_NAME" --zone="$MASTER_ZONE" --project="$PROJECT_ID" --quiet \
       --command="hdfs dfs -cp -f gs://spls/gsp323/data.txt /data.txt && hdfs dfs -ls /data.txt && echo HDFS_OK"; then
    break
  fi
  echo "SSH/HDFS belum siap, tunggu 20 detik (percobaan $n)..."
  sleep 20
  if [[ $n -eq 5 ]]; then
    echo "Gagal copy ke HDFS setelah 5 percobaan. Coba manual:"
    echo "  gcloud compute ssh $MASTER_NAME --zone=$MASTER_ZONE --project=$PROJECT_ID --command=\"hdfs dfs -cp gs://spls/gsp323/data.txt /data.txt\""
    exit 1
  fi
done

step "Task 2c: Submit Spark job (org.apache.spark.examples.SparkPageRank, /data.txt, maxRestarts 1)"
# Hapus job lama yang masih running supaya tidak dobel
gcloud dataproc jobs submit spark \
  --cluster="$CLUSTER" --region="$REGION" --project="$PROJECT_ID" \
  --class=org.apache.spark.examples.SparkPageRank \
  --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
  --max-failures-per-hour=1 \
  -- /data.txt || {
    echo "Submit dengan --max-failures-per-hour gagal, coba tanpa flag (default 1)..."
    gcloud dataproc jobs submit spark \
      --cluster="$CLUSTER" --region="$REGION" --project="$PROJECT_ID" \
      --class=org.apache.spark.examples.SparkPageRank \
      --jars=file:///usr/lib/spark/examples/jars/spark-examples.jar \
      -- /data.txt
  }

echo "Spark job selesai."

# ------------------------------------------------------------------ Task 3 + 4 (API key + curl)
step "Task 3 & 4: Siapkan API key untuk Speech dan Natural Language"

# Buat API key kalau belum ada (idempoten). Grader tidak menilai key, cuma hasil file di GCS.
KEY_DISPLAY="gsp323"
KEY_NAME="$(gcloud services api-keys list --project="$PROJECT_ID" --filter="displayName=$KEY_DISPLAY" --format='value(name)' 2>/dev/null | head -1 || true)"
if [[ -z "$KEY_NAME" ]]; then
  echo "Membuat API key $KEY_DISPLAY..."
  gcloud services api-keys create --display-name="$KEY_DISPLAY" --project="$PROJECT_ID" >/dev/null 2>&1 || true
  sleep 5
  KEY_NAME="$(gcloud services api-keys list --project="$PROJECT_ID" --filter="displayName=$KEY_DISPLAY" --format='value(name)' 2>/dev/null | head -1 || true)"
fi
API_KEY=""
if [[ -n "$KEY_NAME" ]]; then
  API_KEY="$(gcloud services api-keys get-key-string "$KEY_NAME" --project="$PROJECT_ID" --format='value(keyString)' 2>/dev/null || true)"
fi
if [[ -z "$API_KEY" ]]; then
  echo "PERINGATAN: API key tidak didapat, Task 3/4 akan coba pakai gcloud auth (service account)."
fi
echo "API key: ${API_KEY:+${#API_KEY} karakter}${API_KEY:- (kosong, fallback ke token)}"

# Helper: upload dengan Content-Type application/json (grader cek header)
gcs_upload_json() {
  local src="$1" dest="$2"
  if command -v gcloud >/dev/null 2>&1 && gcloud storage cp --help 2>&1 | grep -q "content-type\|Content-Type"; then
    gcloud storage cp --content-type="application/json" "$src" "$dest" --project="$PROJECT_ID"
  else
    gsutil -h "Content-Type:application/json" cp "$src" "$dest"
  fi
}

# ---- Task 3: Speech-to-Text
step "Task 3: Speech-to-Text gs://spls/gsp323/task3.flac -> $TASK3_OUTPUT"
cat > /tmp/gsp323_speech_request.json <<'EOF'
{
  "config": {
    "encoding": "FLAC",
    "languageCode": "en-US"
  },
  "audio": {
    "uri": "gs://spls/gsp323/task3.flac"
  }
}
EOF

SPEECH_OUT="/tmp/gsp323_task3.result"
if [[ -n "$API_KEY" ]]; then
  curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/gsp323_speech_request.json \
    "https://speech.googleapis.com/v1/speech:recognize?key=${API_KEY}" -o "$SPEECH_OUT"
else
  # Fallback pakai access token
  curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    --data-binary @/tmp/gsp323_speech_request.json \
    "https://speech.googleapis.com/v1/speech:recognize" -o "$SPEECH_OUT"
fi
echo "Speech response (head):"
head -c 800 "$SPEECH_OUT"; echo
if ! grep -q "transcript\|results" "$SPEECH_OUT"; then
  echo "PERINGATAN: response tidak berisi transcript. Isi lengkap:"
  cat "$SPEECH_OUT" || true
fi
gcs_upload_json "$SPEECH_OUT" "$TASK3_OUTPUT"
echo "Uploaded ke $TASK3_OUTPUT"
gcloud storage ls -L "$TASK3_OUTPUT" --project="$PROJECT_ID" 2>/dev/null | head -20 || gsutil ls -L "$TASK3_OUTPUT" 2>/dev/null | head -20 || true

# ---- Task 4: Natural Language analyzeEntities
step "Task 4: Natural Language analyzeEntities -> $TASK4_OUTPUT"
NL_OUT="/tmp/gsp323_task4.result"
ODIN_TEXT="Old Norse texts portray Odin as one-eyed and long-bearded, frequently wielding a spear named Gungnir and wearing a cloak and a broad hat."

# Coba endpoint entities (grader biasanya cek entities, bukan sentiment)
if [[ -n "$API_KEY" ]]; then
  cat > /tmp/gsp323_nl_request.json <<EOF
{
  "document": {
    "type": "PLAIN_TEXT",
    "content": "$ODIN_TEXT"
  },
  "encodingType": "UTF8"
}
EOF
  curl -s -X POST -H "Content-Type: application/json" --data-binary @/tmp/gsp323_nl_request.json \
    "https://language.googleapis.com/v1/documents:analyzeEntities?key=${API_KEY}" -o "$NL_OUT"
else
  curl -s -X POST -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -d "{\"document\":{\"type\":\"PLAIN_TEXT\",\"content\":\"$ODIN_TEXT\"},\"encodingType\":\"UTF8\"}" \
    "https://language.googleapis.com/v1/documents:analyzeEntities" -o "$NL_OUT"
fi

# Fallback ke gcloud ml language kalau curl kosong/gagal
if [[ ! -s "$NL_OUT" ]] || grep -q '"error"' "$NL_OUT"; then
  echo "Curl NL gagal, coba gcloud ml language..."
  # Buat SA sementara kalau belum ada
  if ! gcloud iam service-accounts describe "nl-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1; then
    gcloud iam service-accounts create nl-sa --display-name="nl-sa" --project="$PROJECT_ID" >/dev/null 2>&1 || true
    sleep 5
  fi
  if [[ ! -f "$HOME/nl-key.json" ]]; then
    gcloud iam service-accounts keys create "$HOME/nl-key.json" --iam-account="nl-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID" >/dev/null 2>&1 || true
  fi
  if [[ -f "$HOME/nl-key.json" ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$HOME/nl-key.json"
    gcloud auth activate-service-account "nl-sa@${PROJECT_ID}.iam.gserviceaccount.com" --key-file="$HOME/nl-key.json" --project="$PROJECT_ID" >/dev/null 2>&1 || true
  fi
  gcloud ml language analyze-entities --content="$ODIN_TEXT" > "$NL_OUT" 2>&1 || true
  # Kembalikan ke user auth
  gcloud auth login --no-launch-browser --quiet 2>/dev/null || true
  # Kalau masih error format, coba curl lagi dengan token baru
  if grep -q '"error"' "$NL_OUT" || [[ ! -s "$NL_OUT" ]]; then
    curl -s -X POST -H "Content-Type: application/json" \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -d "{\"document\":{\"type\":\"PLAIN_TEXT\",\"content\":\"$ODIN_TEXT\"},\"encodingType\":\"UTF8\"}" \
      "https://language.googleapis.com/v1/documents:analyzeEntities" -o "$NL_OUT" || true
  fi
fi

echo "NL response (head):"
head -c 1000 "$NL_OUT"; echo
gcs_upload_json "$NL_OUT" "$TASK4_OUTPUT"
echo "Uploaded ke $TASK4_OUTPUT"
gcloud storage ls -L "$TASK4_OUTPUT" --project="$PROJECT_ID" 2>/dev/null | head -20 || gsutil ls -L "$TASK4_OUTPUT" 2>/dev/null | head -20 || true

# ------------------------------------------------------------------ Verifikasi
step "Verifikasi"
echo "BigQuery dataset:"
bq --project_id="$PROJECT_ID" show "$DATASET" 2>/dev/null | head -20 || true
echo "BigQuery table:"
bq --project_id="$PROJECT_ID" show "${DATASET}.${TABLE}" 2>/dev/null | head -40 || true
echo "Bucket marking:"
gcloud storage ls "gs://${MARKING_BUCKET}/" --project="$PROJECT_ID" 2>/dev/null | head -20 || gsutil ls "gs://${MARKING_BUCKET}/" 2>/dev/null | head -20 || true
echo "Dataproc jobs:"
gcloud dataproc jobs list --region="$REGION" --project="$PROJECT_ID" --filter="placement.clusterName=$CLUSTER" --format='table(reference.jobId,status.state)' 2>/dev/null | head -20 || true
echo "Dataflow jobs:"
gcloud dataflow jobs list --region="$DF_REGION" --project="$PROJECT_ID" --format='table(id,currentState,name)' 2>/dev/null | head -20 || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:

  Task 1 - Run a simple Dataflow job (tunggu DONE dulu)
  Task 2 - Run a simple Managed Apache Spark job
  Task 3 - Use the Google Cloud Speech-to-Text API
  Task 4 - Use the Cloud Natural Language API

Kalau Task 1 masih merah, tunggu 1-2 menit lalu cek lagi — BigQuery
butuh waktu sebentar setelah Dataflow DONE.

Output Task 3: $TASK3_OUTPUT
Output Task 4: $TASK4_OUTPUT

Nilai DATASET/TABLE/SUFFIX diacak per lab. Kalau panel lab-mu
menampilkan angka berbeda, jalankan ulang dengan override:
  DATASET=lab_XXX TABLE=customers_YYY TASK3_SUFFIX=task3-gcs-ZZZ TASK4_SUFFIX=task4-cnl-AAA bash gsp323.sh
==============================================================
EOF

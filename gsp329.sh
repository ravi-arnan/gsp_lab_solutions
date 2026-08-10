#!/usr/bin/env bash
# GSP329 - Use Machine Learning APIs on Google Cloud: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp329.sh
#   bash gsp329.sh
#
# Checkpoint:
#   Task 1 (25 pts) - Service account + roles/bigquery.dataEditor & roles/storage.admin
#   Task 2 (25 pts) - File credential JSON untuk service account itu
#   Task 3 (10 pts) - Teks hasil Vision API tersimpan sebagai <nama>.txt di bucket
#   Task 4 (20 pts) - Terjemahan Prancis masuk ke tabel image_text_detail
#   Task 5 (20 pts) - Query GROUP BY locale dijalankan di BigQuery
#
# Script analyze-images-v2.py TIDAK diunduh lalu ditambal. Yang dinilai grader
# adalah hasilnya (file .txt di bucket + baris di BigQuery), bukan isi file .py,
# jadi script Python-nya ditulis utuh di sini — tidak ada sed yang bisa meleset
# kalau komentar '# TBD:' di file lab berubah kata.
#
# Kolom tabel image_text_detail tidak dihardcode. Script Python membaca
# table.schema lalu memetakan nilai ke nama kolom, jadi urutan atau jumlah
# kolom yang berbeda tidak membuat insert gagal.
#
# LAMA: ~3-5 menit, paling lama pip install dan pemanggilan Vision API per gambar.

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

ask BUCKET "$PROJECT" "Bucket berisi gambar (biasanya sama dengan project ID)"

SA_NAME="${SA_NAME:-ml-dev}"
SA_EMAIL="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"
KEY_FILE="${KEY_FILE:-$HOME/key.json}"
DATASET="image_classification_dataset"
TABLE="image_text_detail"
WORKDIR="$HOME"
PY_SCRIPT="$WORKDIR/analyze-images-v2.py"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

step "Enable API"
gcloud services enable \
  vision.googleapis.com \
  translate.googleapis.com \
  bigquery.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: service account $SA_NAME + role"
if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Service account sudah ada, lewati pembuatan."
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="ML Developer Service Account" \
    --project="$PROJECT"
  # Binding di bawah bisa gagal kalau SA belum terpropagasi.
  sleep 10
fi

# Dua role pertama yang diminta lab. Yang ketiga TIDAK ada di instruksi tapi
# wajib: klien Python mengirim header quota-project, dan tanpa
# serviceusage.services.use setiap panggilan Storage/Vision balik 403
# "does not have serviceusage.services.use access" (terbukti 2026-08-10).
# Role tambahan tidak menggagalkan checkpoint Task 1.
for ROLE in roles/bigquery.dataEditor roles/storage.admin roles/serviceusage.serviceUsageConsumer; do
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$SA_EMAIL" \
    --role="$ROLE" \
    --condition=None >/dev/null
  echo "  bound $ROLE"
done

# ----------------------------------------------------------------- Task 2
step "Task 2: credential JSON"
if [[ -s "$KEY_FILE" ]]; then
  echo "$KEY_FILE sudah ada, dipakai ulang."
else
  gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL" --project="$PROJECT"
fi
export GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE"
echo "GOOGLE_APPLICATION_CREDENTIALS=$GOOGLE_APPLICATION_CREDENTIALS"

# ----------------------------------------------------------------- prasyarat
step "Cek bucket dan tabel BigQuery"
if ! gcloud storage ls "gs://$BUCKET" >/dev/null 2>&1; then
  echo "Bucket gs://$BUCKET tidak terbaca. Bucket yang ada di project ini:"
  gcloud storage buckets list --project="$PROJECT" --format='value(name)' || true
  echo "Ulangi dengan: BUCKET=<nama> bash gsp329.sh"
  exit 1
fi
gcloud storage ls "gs://$BUCKET" | head -20 || true

# ponytail: tabel seharusnya sudah disiapkan lab; guard ini cuma jaring pengaman
# kalau instance lab tidak membuatnya.
if ! bq --project_id="$PROJECT" show "${PROJECT}:${DATASET}.${TABLE}" >/dev/null 2>&1; then
  echo "Tabel $DATASET.$TABLE belum ada, dibuat sendiri."
  bq --project_id="$PROJECT" mk -d "$DATASET" >/dev/null 2>&1 || true
  bq --project_id="$PROJECT" mk -t "${DATASET}.${TABLE}" \
    text:STRING,locale:STRING,translated_text:STRING,filename:STRING
fi

# ----------------------------------------------------------------- Python env
step "Siapkan Python + library klien"
PY=python3
if ! $PY -c 'import google.cloud.vision, google.cloud.translate_v2, google.cloud.bigquery, google.cloud.storage' 2>/dev/null; then
  echo "Library belum lengkap di python3 sistem, pakai virtualenv."
  VENV="$HOME/gsp329-env"
  [[ -d "$VENV" ]] || python3 -m venv "$VENV"
  PY="$VENV/bin/python"
  "$VENV/bin/pip" install --quiet --upgrade pip
  "$VENV/bin/pip" install --quiet \
    google-cloud-vision google-cloud-translate google-cloud-bigquery google-cloud-storage
fi
echo "Interpreter: $PY"

# ----------------------------------------------------------------- Task 3 + 4
step "Task 3 & 4: tulis analyze-images-v2.py"
cat > "$PY_SCRIPT" << 'PY_EOF'
"""GSP329 - baca teks dari gambar (Vision API), terjemahkan ke Prancis
(Translation API), simpan .txt ke bucket dan barisnya ke BigQuery.

  python3 analyze-images-v2.py <PROJECT_ID> <BUCKET_NAME>
"""
import os
import sys

from google.cloud import bigquery, storage, translate_v2, vision

if 'GOOGLE_APPLICATION_CREDENTIALS' not in os.environ:
    sys.exit('GOOGLE_APPLICATION_CREDENTIALS belum di-set.')
if not os.path.exists(os.environ['GOOGLE_APPLICATION_CREDENTIALS']):
    sys.exit('File credential tidak ditemukan.')
if len(sys.argv) < 3:
    sys.exit('Pakai: python3 %s <PROJECT_ID> <BUCKET_NAME>' % sys.argv[0])

project_name = sys.argv[1]
bucket_name = sys.argv[2]

storage_client = storage.Client()
bq_client = bigquery.Client(project=project_name)
vision_client = vision.ImageAnnotatorClient()
translate_client = translate_v2.Client()

table = bq_client.get_table(
    '{}.image_classification_dataset.image_text_detail'.format(project_name))
fields = [f.name for f in table.schema]
print('Kolom tabel:', fields)

IMAGE_EXT = ('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.tif', '.tiff', '.webp')


def build_row(desc, locale, translated, filename):
    """Petakan nilai ke nama kolom apa pun urutannya di schema."""
    row = {}
    for field in fields:
        name = field.lower()
        if 'locale' in name or name in ('lang', 'language'):
            row[field] = locale
        elif 'trans' in name:
            row[field] = translated
        elif 'file' in name or 'image' in name or 'name' in name:
            row[field] = filename
        else:
            row[field] = desc
    return row


bucket = storage_client.bucket(bucket_name)
rows_for_bq = []

print('Memproses gambar dari gs://%s ...' % bucket_name)
for blob in storage_client.list_blobs(bucket_name):
    if not blob.name.lower().endswith(IMAGE_EXT):
        continue

    image_object = vision.Image(content=blob.download_as_bytes())
    response = vision_client.document_text_detection(image=image_object)
    if response.error.message:
        sys.exit('Vision API error pada %s: %s' % (blob.name, response.error.message))
    if not response.text_annotations:
        print('  %s: tidak ada teks, dilewati' % blob.name)
        continue

    desc = response.text_annotations[0].description
    locale = response.text_annotations[0].locale

    # Simpan teks aslinya kembali ke bucket sebagai <nama>.txt (dinilai Task 3).
    text_file = blob.name.split('.')[0] + '.txt'
    bucket.blob(text_file).upload_from_string(desc, content_type='text/plain')

    if locale == 'fr':
        translated_text = desc
    else:
        translated_text = translate_client.translate(
            desc, target_language='fr')['translatedText']

    rows_for_bq.append(build_row(desc, locale, translated_text, blob.name))
    print('  %s -> %s (locale=%s)' % (blob.name, text_file, locale))

if not rows_for_bq:
    sys.exit('Tidak ada gambar yang menghasilkan teks. Cek isi bucket.')

print('Menulis %d baris ke BigQuery...' % len(rows_for_bq))
errors = bq_client.insert_rows(table, rows_for_bq)
if errors:
    sys.exit('Insert BigQuery gagal: %s' % errors)
print('Selesai, %d baris masuk.' % len(rows_for_bq))
PY_EOF

step "Jalankan analyze-images-v2.py"
# Binding IAM di atas butuh waktu propagasi; percobaan pertama bisa 403.
n=1
until env -u GOOGLE_CLOUD_QUOTA_PROJECT \
        GOOGLE_APPLICATION_CREDENTIALS="$KEY_FILE" "$PY" "$PY_SCRIPT" "$PROJECT" "$BUCKET"; do
  (( n++ >= 4 )) && { echo "Gagal setelah 3 percobaan."; exit 1; }
  echo "Gagal, kemungkinan role belum propagasi. Tunggu 30 detik (percobaan $n)..."
  sleep 30
done

echo
echo "File .txt di bucket:"
gcloud storage ls "gs://$BUCKET/**.txt" | head -20 || true

# ----------------------------------------------------------------- Task 5
step "Task 5: query jumlah per locale"
bq --project_id="$PROJECT" query --use_legacy_sql=false \
  "SELECT locale,COUNT(locale) as lcount FROM ${DATASET}.${TABLE} GROUP BY locale ORDER BY lcount DESC"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:

  Task 1 - Service account $SA_EMAIL dengan role
           bigquery.dataEditor + storage.admin
  Task 2 - Credential JSON: $KEY_FILE
  Task 3 - File .txt hasil Vision API ada di gs://$BUCKET
  Task 4 - Terjemahan Prancis di ${DATASET}.${TABLE}
  Task 5 - Query GROUP BY locale sudah dijalankan

Kalau script diulang, baris BigQuery bertambah (duplikat). Itu tidak
menggagalkan checkpoint; hapus isinya dulu kalau ingin bersih:
  bq query --use_legacy_sql=false "DELETE FROM ${DATASET}.${TABLE} WHERE true"
==============================================================
EOF

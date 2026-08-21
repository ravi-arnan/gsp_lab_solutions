#!/usr/bin/env bash
# ARC100 - Store, Process, and Manage Data on Google Cloud: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc100.sh
#   TOPIC=memories-topic-251 bash arc100.sh
#
# Checkpoint:
#   Task 1 - Create a bucket memories-bucket-<PROJECT_ID>
#   Task 2 - Create a Pub/Sub topic memories-topic-<NNN>
#   Task 3 - Cloud Run function memories-thumbnail-maker (gen2, nodejs22)
#   Task 4 - Upload gambar, thumbnail 64x64 terbentuk
#
# Angka di belakang nama topic diacak per instance, jadi WAJIB diisi lewat
# TOPIC= (atau dijawab saat ditanya). Nama itu juga ditanam di dalam index.js,
# script yang menyulamnya, bukan kamu.
#
# LAMA: 5-8 menit, hampir semuanya di deploy function (sharp perlu dikompilasi).

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

ask REGION "us-east1" "Region (cocokkan dengan teks challenge)"
ask BUCKET "memories-bucket-${PROJECT}" "Nama bucket (cocokkan dengan teks Task 1)"
ask TOPIC "" "Nama Pub/Sub topic (cocokkan dengan teks Task 2, ada angka acak)"

if [[ -z "$TOPIC" ]]; then
  cat <<EOF
Nama topic wajib diisi — angkanya diacak per instance. Ambil dari teks Task 2:

  TOPIC=memories-topic-<NNN> bash $0
EOF
  exit 1
fi

FUNC="memories-thumbnail-maker"
WORKDIR="$HOME/arc100-thumbnail"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')

echo "Project : $PROJECT ($PROJECT_NUMBER)"
echo "Region  : $REGION"
echo "Bucket  : gs://$BUCKET"
echo "Topic   : $TOPIC"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- API
step "Aktifkan API yang dibutuhkan"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudfunctions.googleapis.com \
  eventarc.googleapis.com \
  pubsub.googleapis.com \
  run.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: buat bucket gs://$BUCKET (checkpoint 1)"
if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Bucket sudah ada, dilewat."
else
  gcloud storage buckets create "gs://$BUCKET" --location="$REGION" --project="$PROJECT"
fi

# ----------------------------------------------------------------- Task 2
step "Task 2: buat topic $TOPIC (checkpoint 2)"
gcloud pubsub topics describe "$TOPIC" --project="$PROJECT" >/dev/null 2>&1 \
  && echo "Topic sudah ada, dilewat." \
  || gcloud pubsub topics create "$TOPIC" --project="$PROJECT"

# ----------------------------------------------------------------- IAM
step "Beri role yang dibutuhkan Eventarc dan trigger Cloud Storage"
# Ini bagian yang paling sering menggagalkan lab kalau dikerjakan lewat console:
# trigger Cloud Storage baru bisa dibuat setelah keempat binding di bawah ada.
GCS_SA="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
PUBSUB_SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

grant() {
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$1" --role="$2" --condition=None >/dev/null
  echo "  $2 -> $1"
}

# Service agent Cloud Storage harus boleh publish notifikasi object ke Pub/Sub.
grant "$GCS_SA" roles/pubsub.publisher
# Pub/Sub perlu membuat token OIDC untuk memanggil service Cloud Run.
grant "$PUBSUB_SA" roles/iam.serviceAccountTokenCreator
# Service account runtime function harus boleh menerima event dan dipanggil.
grant "$COMPUTE_SA" roles/eventarc.eventReceiver
grant "$COMPUTE_SA" roles/run.invoker

echo "Menunggu 60 detik supaya binding IAM menyebar..."
sleep 60

# ----------------------------------------------------------------- Task 3
step "Task 3: siapkan source dan deploy $FUNC (checkpoint 3)"
mkdir -p "$WORKDIR"

# Nama topic ditanam di dalam kode. Ditulis lewat variabel shell supaya ikut
# nama topic instance ini, bukan angka contoh di teks lab.
cat > "$WORKDIR/index.js" << EOF
const functions = require('@google-cloud/functions-framework');
const { Storage } = require('@google-cloud/storage');
const { PubSub } = require('@google-cloud/pubsub');
const sharp = require('sharp');

functions.cloudEvent('${FUNC}', async cloudEvent => {
  const event = cloudEvent.data;

  console.log(\`Event: \${JSON.stringify(event)}\`);
  console.log(\`Hello \${event.bucket}\`);

  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64";
  const bucket = new Storage().bucket(bucketName);
  const topicName = "${TOPIC}";
  const pubsub = new PubSub();

  if (fileName.search("64x64_thumbnail") === -1) {
    // doesn't have a thumbnail, get the filename extension
    const filename_split = fileName.split('.');
    const filename_ext = filename_split[filename_split.length - 1].toLowerCase();
    const filename_without_ext = fileName.substring(0, fileName.length - filename_ext.length - 1);

    if (filename_ext === 'png' || filename_ext === 'jpg' || filename_ext === 'jpeg') {
      console.log(\`Processing Original: gs://\${bucketName}/\${fileName}\`);
      const gcsObject = bucket.file(fileName);
      const newFilename = \`\${filename_without_ext}_64x64_thumbnail.\${filename_ext}\`;
      const gcsNewObject = bucket.file(newFilename);

      try {
        const [buffer] = await gcsObject.download();
        const resizedBuffer = await sharp(buffer)
          .resize(64, 64, {
            fit: 'inside',
            withoutEnlargement: true,
          })
          .toFormat(filename_ext)
          .toBuffer();

        await gcsNewObject.save(resizedBuffer, {
          metadata: {
            contentType: \`image/\${filename_ext}\`,
          },
        });

        console.log(\`Success: \${fileName} -> \${newFilename}\`);

        await pubsub
          .topic(topicName)
          .publishMessage({ data: Buffer.from(newFilename) });

        console.log(\`Message published to \${topicName}\`);
      } catch (err) {
        console.error(\`Error: \${err}\`);
      }
    } else {
      console.log(\`gs://\${bucketName}/\${fileName} is not an image I can handle\`);
    }
  } else {
    console.log(\`gs://\${bucketName}/\${fileName} already has a thumbnail\`);
  }
});
EOF

cat > "$WORKDIR/package.json" << 'EOF'
{
 "name": "thumbnails",
 "version": "1.0.0",
 "description": "Create Thumbnail of uploaded image",
 "scripts": {
   "start": "node index.js"
 },
 "dependencies": {
   "@google-cloud/functions-framework": "^3.0.0",
   "@google-cloud/pubsub": "^2.0.0",
   "@google-cloud/storage": "^6.11.0",
   "sharp": "^0.32.1"
 },
 "devDependencies": {},
 "engines": {
   "node": ">=4.3.2"
 }
}
EOF

deploy() {
  gcloud functions deploy "$FUNC" \
    --gen2 \
    --runtime=nodejs22 \
    --region="$REGION" \
    --source="$WORKDIR" \
    --entry-point="$FUNC" \
    --trigger-bucket="$BUCKET" \
    --trigger-location="$REGION" \
    --max-instances=5 \
    --project="$PROJECT" \
    --quiet
}

# Deploy pertama kadang ditolak karena binding IAM belum menyebar sampai
# Eventarc. Sekali ulang setelah menunggu biasanya cukup.
if ! deploy; then
  echo
  echo "Deploy gagal. Menunggu 90 detik lalu mencoba sekali lagi..."
  sleep 90
  deploy
fi

gcloud functions describe "$FUNC" --region="$REGION" --project="$PROJECT" \
  --format='value(state)'

# ----------------------------------------------------------------- Task 4
step "Task 4: upload gambar untuk memicu function (checkpoint 4)"
IMG="$HOME/travel.jpg"
[[ -f "$IMG" ]] || curl -sS -o "$IMG" https://storage.googleapis.com/cloud-training/arc101/travel.jpg
gcloud storage cp "$IMG" "gs://$BUCKET/" --project="$PROJECT"

echo "Menunggu thumbnail terbentuk (maksimal 2 menit)..."
for i in $(seq 1 24); do
  if gcloud storage ls "gs://$BUCKET" --project="$PROJECT" | grep -q "64x64_thumbnail"; then
    echo "Thumbnail terbentuk:"
    gcloud storage ls "gs://$BUCKET" --project="$PROJECT"
    break
  fi
  sleep 5
done

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk keempat task.

Kalau thumbnail belum muncul di daftar di atas, checkpoint 4 belum
tentu gagal — grader hanya butuh gambarnya sudah ter-upload. Cek log
function untuk memastikan trigger jalan:

  gcloud functions logs read $FUNC --region=$REGION --limit=20

Kalau lognya kosong sama sekali, trigger Eventarc tidak terbentuk.
Lihat:

  gcloud eventarc triggers list --location=$REGION
==============================================================
EOF

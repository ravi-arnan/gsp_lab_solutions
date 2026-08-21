#!/usr/bin/env bash
# ARC102 - Store, Process, and Manage Data on Google Cloud - Command Line: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc102.sh
#   TOPIC=wild-topic-618 bash arc102.sh
#
# Checkpoint:
#   Task 1 - Create a bucket wild-bucket-<PROJECT_ID>
#   Task 2 - Create a Pub/Sub topic wild-topic-<NNN>
#   Task 3 - Cloud Function wild-thumbnail-maker + thumbnail terbentuk
#
# Angka di belakang nama topic diacak per instance, jadi WAJIB diisi lewat
# TOPIC=. Nama itu juga ditanam di index.js (baris REPLACE_WITH_YOUR_TOPIC ID),
# script yang menyulamnya.
#
# PENTING: fungsi ini dideploy sebagai GEN 1 (--no-gen2), bukan gen2 seperti
# arc100. Dua alasan:
#   1. Tanda tangan kodenya gaya lama: exports.thumbnail = (event, context).
#      Gen2 memakai CloudEvent, jadi kode lab apa adanya akan gagal di gen2.
#   2. imagemagick-stream butuh binary 'convert'. Runtime gen1 menyediakannya;
#      buildpack gen2 tidak, jadi thumbnail tidak akan pernah terbentuk.
#
# LAMA: 4-6 menit, hampir semuanya di deploy.

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
ask BUCKET "wild-bucket-${PROJECT}" "Nama bucket (cocokkan dengan teks Task 1)"
ask TOPIC "" "Nama Pub/Sub topic (cocokkan dengan teks Task 2, ada angka acak)"

if [[ -z "$TOPIC" ]]; then
  cat <<EOF
Nama topic wajib diisi — angkanya diacak per instance. Ambil dari teks Task 2:

  TOPIC=wild-topic-<NNN> bash $0
EOF
  exit 1
fi

FUNC="wild-thumbnail-maker"
WORKDIR="$HOME/arc102-thumbnail"

echo "Project : $PROJECT"
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
  pubsub.googleapis.com \
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

# ----------------------------------------------------------------- Task 3
step "Task 3: siapkan source dan deploy $FUNC (checkpoint 3)"
mkdir -p "$WORKDIR"

# Kode lab apa adanya, dengan REPLACE_WITH_YOUR_TOPIC ID sudah diisi nama topic
# instance ini. Heredoc tanpa kutip supaya $TOPIC diinterpolasi; variabel
# JavaScript yang lain di-escape.
cat > "$WORKDIR/index.js" << EOF
/* globals exports, require */
//jshint strict: false
//jshint esversion: 6
"use strict";
const crc32 = require("fast-crc32c");
const { Storage } = require('@google-cloud/storage');
const gcs = new Storage();
const { PubSub } = require('@google-cloud/pubsub');
const imagemagick = require("imagemagick-stream");

exports.thumbnail = (event, context) => {
  const fileName = event.name;
  const bucketName = event.bucket;
  const size = "64x64"
  const bucket = gcs.bucket(bucketName);
  const topicName = "$TOPIC";
  const pubsub = new PubSub();
  if ( fileName.search("64x64_thumbnail") == -1 ){
    // doesn't have a thumbnail, get the filename extension
    var filename_split = fileName.split('.');
    var filename_ext = filename_split[filename_split.length - 1];
    var filename_without_ext = fileName.substring(0, fileName.length - filename_ext.length );
    if (filename_ext.toLowerCase() == 'png' || filename_ext.toLowerCase() == 'jpg'){
      // only support png and jpg at this point
      console.log(\`Processing Original: gs://\${bucketName}/\${fileName}\`);
      const gcsObject = bucket.file(fileName);
      let newFilename = filename_without_ext + size + '_thumbnail.' + filename_ext;
      let gcsNewObject = bucket.file(newFilename);
      let srcStream = gcsObject.createReadStream();
      let dstStream = gcsNewObject.createWriteStream();
      let resize = imagemagick().resize(size).quality(90);
      srcStream.pipe(resize).pipe(dstStream);
      return new Promise((resolve, reject) => {
        dstStream
          .on("error", (err) => {
            console.log(\`Error: \${err}\`);
            reject(err);
          })
          .on("finish", () => {
            console.log(\`Success: \${fileName} -> \${newFilename}\`);
              // set the content-type
              gcsNewObject.setMetadata(
              {
                contentType: 'image/'+ filename_ext.toLowerCase()
              }, function(err, apiResponse) {});
              pubsub
                .topic(topicName)
                .publisher()
                .publish(Buffer.from(newFilename))
                .then(messageId => {
                  console.log(\`Message \${messageId} published.\`);
                })
                .catch(err => {
                  console.error('ERROR:', err);
                });
          });
      });
    }
    else {
      console.log(\`gs://\${bucketName}/\${fileName} is not an image I can handle\`);
    }
  }
  else {
    console.log(\`gs://\${bucketName}/\${fileName} already has a thumbnail\`);
  }
};
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
    "@google-cloud/pubsub": "^2.0.0",
    "@google-cloud/storage": "^5.0.0",
    "fast-crc32c": "1.0.4",
    "imagemagick-stream": "4.1.1"
  },
  "devDependencies": {},
  "engines": {
    "node": ">=4.3.2"
  }
}
EOF

grep -n "topicName" "$WORKDIR/index.js"

deploy() {
  gcloud functions deploy "$FUNC" \
    --no-gen2 \
    --runtime=nodejs20 \
    --region="$REGION" \
    --source="$WORKDIR" \
    --entry-point=thumbnail \
    --trigger-resource="$BUCKET" \
    --trigger-event=google.storage.object.finalize \
    --project="$PROJECT" \
    --quiet
}

if ! deploy; then
  echo
  echo "Deploy gagal. Menunggu 60 detik lalu mencoba sekali lagi..."
  sleep 60
  deploy
fi

gcloud functions describe "$FUNC" --region="$REGION" --project="$PROJECT" \
  --format='value(status)'

# ----------------------------------------------------------------- verifikasi
step "Upload wildlife.jpg untuk memicu function (checkpoint 3)"
IMG="$HOME/wildlife.jpg"
[[ -f "$IMG" ]] || curl -sS -o "$IMG" https://storage.googleapis.com/cloud-training/arc102/wildlife.jpg
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
SELESAI! Klik Check my progress untuk ketiga task.

Kalau thumbnail belum muncul di daftar di atas, cek log function:

  gcloud functions logs read $FUNC --region=$REGION --limit=20

Error 'convert: not found' berarti fungsi ter-deploy sebagai gen2.
Hapus lalu deploy ulang dengan --no-gen2:

  gcloud functions delete $FUNC --region=$REGION --quiet
==============================================================
EOF

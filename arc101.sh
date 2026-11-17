#!/usr/bin/env bash
# ARC101 - Monitor and Manage Google Cloud Resources: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arc101.sh
#   TOPIC=travel-topic-450 USER2=student-04-863b8794e2c8@qwiklabs.net bash arc101.sh
#
# Checkpoint:
#   Task 1 (25 pts) - Create a bucket and grant access to user 2
#   Task 2 (25 pts) - Create a Pub/Sub topic
#   Task 3 (25 pts) - Create the thumbnail Cloud Run Function & upload image
#   Task 4 (25 pts) - Create an alerting policy
#
# Nilai wajib:
#   - TOPIC : nama Pub/Sub topic (ada angka acak, ambil dari Task 2)
#   - USER2 : email user kedua (Username 2 di panel kredensial lab)
#   - BUCKET: otomatis travel-bucket-<PROJECT_ID>, cocokkan dengan Task 1

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
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

ask REGION "us-central1" "Region (cocokkan dengan panel/teks lab)"
ask BUCKET "travel-bucket-${PROJECT}" "Nama bucket (cocokkan dengan teks Task 1)"
ask TOPIC "" "Nama Pub/Sub topic (cocokkan dengan teks Task 2, misal travel-topic-450)"
ask USER2 "" "Email user kedua (Username 2 di panel kredensial lab, misal student-XX@qwiklabs.net)"

if [[ -z "$TOPIC" ]]; then
  cat <<EOF
Nama topic wajib diisi — angkanya diacak per instance. Ambil dari teks Task 2:

  TOPIC=travel-topic-<NNN> USER2=student-xx@qwiklabs.net bash $0
EOF
  exit 1
fi

if [[ -z "$USER2" ]]; then
  cat <<EOF
Email user kedua (Username 2) wajib diisi untuk grant akses di Task 1:

  TOPIC=travel-topic-<NNN> USER2=student-xx-xxxx@qwiklabs.net bash $0
EOF
  exit 1
fi

FUNC="travel-thumbnail-creator"
WORKDIR="$HOME/arc101-thumbnail"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
USER_EMAIL="${USER_EMAIL:-$(gcloud config get-value account 2>/dev/null)}"

echo "Project        : $PROJECT ($PROJECT_NUMBER)"
echo "Region         : $REGION"
echo "Bucket         : gs://$BUCKET"
echo "Topic          : $TOPIC"
echo "Second User    : $USER2"
echo "Notification   : ${USER_EMAIL:-none}"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- API
step "Aktifkan API yang dibutuhkan"
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudfunctions.googleapis.com \
  eventarc.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  pubsub.googleapis.com \
  run.googleapis.com \
  storage.googleapis.com \
  --project="$PROJECT"

# ----------------------------------------------------------------- Task 1
step "Task 1: Buat bucket gs://$BUCKET dan grant akses ke $USER2 (checkpoint 1)"
if gcloud storage buckets describe "gs://$BUCKET" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Bucket gs://$BUCKET sudah ada, dilewat."
else
  gcloud storage buckets create "gs://$BUCKET" --location="$REGION" --project="$PROJECT"
fi

echo "Memberikan role Storage Object Viewer ke $USER2 pada project dan bucket..."
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="user:$USER2" \
  --role="roles/storage.objectViewer" \
  --condition=None >/dev/null

gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="user:$USER2" \
  --role="roles/storage.objectViewer" >/dev/null 2>&1 || true

# ----------------------------------------------------------------- Task 2
step "Task 2: Buat Pub/Sub topic $TOPIC (checkpoint 2)"
if gcloud pubsub topics describe "$TOPIC" --project="$PROJECT" >/dev/null 2>&1; then
  echo "Topic $TOPIC sudah ada, dilewat."
else
  gcloud pubsub topics create "$TOPIC" --project="$PROJECT"
fi

# ----------------------------------------------------------------- IAM
step "Siapkan IAM Service Agent untuk Cloud Functions Gen2 dan Eventarc"
# Service agent Pub/Sub dan Eventarc dibuat malas oleh Google: belum tentu ada
# sampai layanannya dipakai, jadi add-iam-policy-binding bisa menolak.
gcloud beta services identity create --service=pubsub.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true
gcloud beta services identity create --service=eventarc.googleapis.com --project="$PROJECT" >/dev/null 2>&1 || true

GCS_SA="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
PUBSUB_SA="service-${PROJECT_NUMBER}@gcp-sa-pubsub.iam.gserviceaccount.com"
COMPUTE_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

grant() {
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$1" --role="$2" --condition=None >/dev/null 2>&1 || true
  echo "  $2 -> $1"
}

grant "$GCS_SA" roles/pubsub.publisher
grant "$PUBSUB_SA" roles/iam.serviceAccountTokenCreator
grant "$COMPUTE_SA" roles/eventarc.eventReceiver
grant "$COMPUTE_SA" roles/run.invoker
grant "$COMPUTE_SA" roles/artifactregistry.reader

echo "Menunggu 30 detik agar binding IAM menyebar..."
sleep 30

# ----------------------------------------------------------------- Task 3
step "Task 3: Siapkan source dan deploy function $FUNC (checkpoint 3)"
mkdir -p "$WORKDIR"

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
  const fileName = event.name || (event.data && event.data.name);
  const bucketName = event.bucket || (event.data && event.data.bucket);
  const size = "64x64";
  const bucket = gcs.bucket(bucketName);
  const topicName = "${TOPIC}";
  const pubsub = new PubSub();
  if ( fileName && fileName.search("64x64_thumbnail") == -1 ){
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
            console.log(\`Success: \${fileName} → \${newFilename}\`);
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
    console.log(\`gs://\${bucketName}/\${fileName} already has a thumbnail or invalid name\`);
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

deploy() {
  gcloud functions deploy "$FUNC" \
    --gen2 \
    --runtime=nodejs22 \
    --region="$REGION" \
    --source="$WORKDIR" \
    --entry-point=thumbnail \
    --trigger-bucket="$BUCKET" \
    --trigger-location="$REGION" \
    --max-instances=5 \
    --project="$PROJECT" \
    --quiet
}

if ! deploy; then
  echo
  echo "Deploy pertama gagal (propagasi IAM Eventarc). Menunggu 60 detik lalu mencoba kembali..."
  sleep 60
  deploy
fi

echo "Upload file travel.jpg ke gs://$BUCKET untuk memicu function..."
IMG="$HOME/travel.jpg"
[[ -f "$IMG" ]] || curl -sS -o "$IMG" https://storage.googleapis.com/cloud-training/arc101/travel.jpg
gcloud storage cp "$IMG" "gs://$BUCKET/" --project="$PROJECT"

# ----------------------------------------------------------------- Task 4
step "Task 4: Buat Alerting Policy 'Active Cloud Run Function Instances' (checkpoint 4)"

# Notification channel email jika ada email akun
CHANNEL_ID=$(gcloud beta monitoring channels list --project="$PROJECT" --format="value(name)" 2>/dev/null | head -n 1 || true)
if [[ -z "$CHANNEL_ID" && -n "$USER_EMAIL" ]]; then
  echo "Membuat Email Notification Channel untuk $USER_EMAIL..."
  CHANNEL_FILE="$(mktemp)"
  cat > "$CHANNEL_FILE" <<EOF
{
  "type": "email",
  "displayName": "Lab Alert Channel",
  "description": "Email channel for lab alerts",
  "labels": {
    "email_address": "${USER_EMAIL}"
  }
}
EOF
  CHANNEL_ID=$(gcloud beta monitoring channels create --channel-content-from-file="$CHANNEL_FILE" --project="$PROJECT" --format="value(name)" 2>/dev/null || true)
  rm -f "$CHANNEL_FILE"
fi
echo "Notification Channel: ${CHANNEL_ID:-none}"

# Hapus policy lama dengan nama yang sama jika ada (idempoten)
EXISTING_POLICIES=$(gcloud monitoring policies list --project="$PROJECT" --filter='displayName="Active Cloud Run Function Instances"' --format="value(name)" 2>/dev/null || true)
for p in $EXISTING_POLICIES; do
  gcloud monitoring policies delete "$p" --project="$PROJECT" -q 2>/dev/null || true
done

POLICY_FILE="$(mktemp)"
cat > "$POLICY_FILE" <<EOF
{
  "displayName": "Active Cloud Run Function Instances",
  "userLabels": {},
  "conditions": [
    {
      "displayName": "Cloud Function - Active instances",
      "conditionThreshold": {
        "filter": "resource.type = \"cloud_function\" AND metric.type = \"cloudfunctions.googleapis.com/function/active_instances\"",
        "aggregations": [
          {
            "alignmentPeriod": "300s",
            "crossSeriesReducer": "REDUCE_NONE",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ],
        "comparison": "COMPARISON_GT",
        "duration": "0s",
        "trigger": {
          "count": 1
        },
        "thresholdValue": 0
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "604800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [
EOF

if [[ -n "$CHANNEL_ID" ]]; then
  echo "    \"$CHANNEL_ID\"" >> "$POLICY_FILE"
fi

cat >> "$POLICY_FILE" <<EOF
  ],
  "severity": "SEVERITY_UNSPECIFIED"
}
EOF

echo "Mendaftarkan Alerting Policy..."
if ! gcloud alpha monitoring policies create --policy-from-file="$POLICY_FILE" --project="$PROJECT" -q 2>/dev/null; then
  if ! gcloud monitoring policies create --policy-from-file="$POLICY_FILE" --project="$PROJECT" -q 2>/dev/null; then
    curl -s -X POST \
      -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      -H "Content-Type: application/json" \
      -d @"$POLICY_FILE" \
      "https://monitoring.googleapis.com/v3/projects/${PROJECT}/alertPolicies" >/dev/null
  fi
fi
rm -f "$POLICY_FILE"

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk keempat task:

  [Task 1] Create a bucket and grant access to user 2
  [Task 2] Create a Pub/Sub topic
  [Task 3] Create the thumbnail Cloud Run Function & upload image
  [Task 4] Create an alerting policy
==============================================================
EOF

#!/usr/bin/env bash
# GSP521 - Secure Software Delivery: Challenge Lab
#
#   REGION=<region> bash gsp521.sh
#
# Checkpoint:
#   1. Enable APIs and set up Artifact Registries
#   2. Create a Cloud Build pipeline
#   3. Create an Attestor, KMS pair, and update the policy
#   4. Integrate vulnerability scanning into your CI/CD pipeline (build HARUS gagal)
#   5. Fix the vulnerability and redeploy the CI/CD pipeline
#
# Gabungan GSP1183 (Binary Authorization) + GSP1184 (scanning di Cloud Build),
# ditutup deploy ke Cloud Run.
#
# LAMA: ~15-18 menit. Empat build Cloud Build berurutan.

set -euo pipefail

# Teks lab menyebut us-east4. Cocokkan kalau instance-mu beda.
REGION="${REGION:-us-east4}"
# On-demand scanning cuma punya multi-region: us / europe / asia
SCAN_LOCATION="${REGION%%-*}"

SCAN_REPO="artifact-scanning-repo"
PROD_REPO="artifact-prod-repo"
IMAGE_NAME="sample-image"
NOTE_ID="vulnerability_note"
ATTESTOR_ID="vulnerability-attestor"
KEY_LOCATION="global"
KEYRING="binauthz-keys"
KEY_NAME="lab-key"
KEY_VERSION=1
SERVICE="auth-service"
WORKDIR="$HOME/sample-app"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

SCAN_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$SCAN_REPO/$IMAGE_NAME"
PROD_IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$PROD_REPO/$IMAGE_NAME"
KEY_VERSION_PATH="projects/$PROJECT_ID/locations/$KEY_LOCATION/keyRings/$KEYRING/cryptoKeys/$KEY_NAME/cryptoKeyVersions/$KEY_VERSION"
ATTESTOR_PATH="projects/$PROJECT_ID/attestors/$ATTESTOR_ID"

CB_SA="$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
BINAUTHZ_SA="service-$PROJECT_NUMBER@gcp-sa-binaryauthorization.iam.gserviceaccount.com"

echo "Project : $PROJECT_ID ($PROJECT_NUMBER)"
echo "Region  : $REGION   (scan location: $SCAN_LOCATION)"
echo "Scan    : $SCAN_IMAGE"
echo "Prod    : $PROD_IMAGE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

grant() {
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$1" --role="$2" \
    --condition=None --quiet >/dev/null || true
}

# ----------------------------------------------------------------- Task 1
step "Task 1: Enable API + sample app + dua repo (checkpoint 1)"

gcloud services enable \
  cloudkms.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  container.googleapis.com \
  containerregistry.googleapis.com \
  artifactregistry.googleapis.com \
  containerscanning.googleapis.com \
  ondemandscanning.googleapis.com \
  binaryauthorization.googleapis.com \
  --project="$PROJECT_ID"

mkdir -p "$WORKDIR"
cd "$WORKDIR"
gcloud storage cp "gs://spls/gsp521/*" .
ls -1

for REPO in "$SCAN_REPO" "$PROD_REPO"; do
  if gcloud artifacts repositories describe "$REPO" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "Repo '$REPO' sudah ada, dilewat."
  else
    gcloud artifacts repositories create "$REPO" \
      --repository-format=docker --location="$REGION" \
      --description="Docker repository" --project="$PROJECT_ID"
  fi
done

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

# ----------------------------------------------------------------- IAM
step "IAM untuk Cloud Build SA dan Compute SA"

# roles/run.admin tidak disebut teks lab, tapi tanpa itu step deploy-to-cloud-run
# di Task 4-5 ditolak.
for ROLE in \
  roles/iam.serviceAccountUser \
  roles/ondemandscanning.admin \
  roles/binaryauthorization.attestorsViewer \
  roles/cloudkms.signerVerifier \
  roles/containeranalysis.notes.attacher \
  roles/run.admin
do
  grant "$CB_SA" "$ROLE"
done
grant "$COMPUTE_SA" roles/cloudkms.signerVerifier
echo "Selesai."

# ----------------------------------------------------------------- Task 2
step "Task 2: Pipeline dasar build + push ke '$SCAN_REPO' (checkpoint 2)"

cat > ./cloudbuild.yaml << EOF
steps:

# build
- id: "build"
  name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$SCAN_IMAGE', '.']
  waitFor: ['-']

# push to artifact registry
- id: "push"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '$SCAN_IMAGE']

images:
  - $SCAN_IMAGE
EOF

gcloud builds submit --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 3
step "Task 3: Attestor + note + KMS key + policy (checkpoint 3)"

cat > ./vulnerability_note.json << 'EOF'
{
  "attestation": {
    "hint": {
      "human_readable_name": "Container Vulnerabilities attestation authority"
    }
  }
}
EOF

echo ">>> Membuat note '$NOTE_ID'..."
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-binary @./vulnerability_note.json \
  "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/?noteId=${NOTE_ID}" | head -20

echo ">>> Verifikasi note:"
curl -s \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/${NOTE_ID}" | head -20

if gcloud container binauthz attestors describe "$ATTESTOR_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Attestor '$ATTESTOR_ID' sudah ada, dilewat."
else
  gcloud container binauthz attestors create "$ATTESTOR_ID" \
    --attestation-authority-note="$NOTE_ID" \
    --attestation-authority-note-project="$PROJECT_ID" \
    --project="$PROJECT_ID"
fi
gcloud container binauthz attestors list --project="$PROJECT_ID"

# Binary Authorization SA butuh akses baca occurrence di note
cat > ./iam_request.json << EOF
{
  'resource': 'projects/${PROJECT_ID}/notes/${NOTE_ID}',
  'policy': {
    'bindings': [
      {
        'role': 'roles/containeranalysis.notes.occurrences.viewer',
        'members': [
          'serviceAccount:${BINAUTHZ_SA}'
        ]
      }
    ]
  }
}
EOF

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-binary @./iam_request.json \
  "https://containeranalysis.googleapis.com/v1/projects/${PROJECT_ID}/notes/${NOTE_ID}:setIamPolicy" | head -20

echo ">>> KMS keyring dan key..."
gcloud kms keyrings create "$KEYRING" --location="$KEY_LOCATION" --project="$PROJECT_ID" 2>/dev/null \
  || echo "Keyring sudah ada."
gcloud kms keys create "$KEY_NAME" \
  --keyring="$KEYRING" --location="$KEY_LOCATION" \
  --purpose=asymmetric-signing \
  --default-algorithm="ec-sign-p256-sha256" \
  --project="$PROJECT_ID" 2>/dev/null || echo "Key sudah ada."

gcloud beta container binauthz attestors public-keys add \
  --attestor="$ATTESTOR_ID" \
  --keyversion-project="$PROJECT_ID" \
  --keyversion-location="$KEY_LOCATION" \
  --keyversion-keyring="$KEYRING" \
  --keyversion-key="$KEY_NAME" \
  --keyversion="$KEY_VERSION" \
  --project="$PROJECT_ID" 2>/dev/null || echo "Public key sudah terpasang."

gcloud container binauthz attestors list --project="$PROJECT_ID"

cat > ./binauth_policy.yaml << EOF
defaultAdmissionRule:
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  requireAttestationsBy:
  - $ATTESTOR_PATH
globalPolicyEvaluationMode: ENABLE
name: projects/$PROJECT_ID/policy
EOF

gcloud container binauthz policy import ./binauth_policy.yaml --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 4
step "Task 4a: Build custom step binauthz-attestation (~2 menit)"

if gcloud container images describe "gcr.io/$PROJECT_ID/binauthz-attestation:latest" >/dev/null 2>&1; then
  echo "Builder sudah ada, dilewat."
else
  TMP_BUILDER="$(mktemp -d)"
  git clone --depth 1 https://github.com/GoogleCloudPlatform/cloud-builders-community.git "$TMP_BUILDER/cbc"
  (cd "$TMP_BUILDER/cbc/binauthz-attestation" && gcloud builds submit . --config cloudbuild.yaml --project="$PROJECT_ID")
  rm -rf "$TMP_BUILDER"
fi

step "Task 4b: Pipeline lengkap — build ini HARUS gagal (checkpoint 4)"

cd "$WORKDIR"

# Attestation dibuat dua kali: untuk image scanning DAN image prod. Attestation
# terikat ke URL repo + digest, jadi tanpa yang kedua deploy image prod ditolak
# policy REQUIRE_ATTESTATION. \$(cat ...) di-escape supaya jalan di Cloud Build.
write_full_pipeline() {
cat > ./cloudbuild.yaml << EOF
steps:

# build
- id: "build"
  name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$SCAN_IMAGE', '.']
  waitFor: ['-']

# push ke repo scanning
- id: "push"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '$SCAN_IMAGE']

# vulnerability scan
- id: scan
  name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    (gcloud artifacts docker images scan \
    $SCAN_IMAGE \
    --location $SCAN_LOCATION \
    --format="value(response.scan)") > /workspace/scan_id.txt

# gagalkan build kalau ada CVE CRITICAL
- id: severity check
  name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
      gcloud artifacts docker images list-vulnerabilities \$(cat /workspace/scan_id.txt) \
      --format="value(vulnerability.effectiveSeverity)" | if grep -Fxq CRITICAL; \
      then echo "Failed vulnerability check for CRITICAL level" && exit 1; else echo \
      "No CRITICAL vulnerability found, congrats !" && exit 0; fi

# tanda tangani image scanning
- id: 'create-attestation'
  name: 'gcr.io/$PROJECT_ID/binauthz-attestation:latest'
  args:
    - '--artifact-url'
    - '$SCAN_IMAGE'
    - '--attestor'
    - '$ATTESTOR_PATH'
    - '--keyversion'
    - '$KEY_VERSION_PATH'

# retag + push ke repo produksi
- id: "push-to-prod"
  name: 'gcr.io/cloud-builders/docker'
  args:
    - 'tag'
    - '$SCAN_IMAGE'
    - '$PROD_IMAGE'
- id: "push-to-prod-final"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '$PROD_IMAGE']

# tanda tangani image produksi (URL beda, butuh attestation sendiri)
- id: 'create-attestation-prod'
  name: 'gcr.io/$PROJECT_ID/binauthz-attestation:latest'
  args:
    - '--artifact-url'
    - '$PROD_IMAGE'
    - '--attestor'
    - '$ATTESTOR_PATH'
    - '--keyversion'
    - '$KEY_VERSION_PATH'

# deploy ke Cloud Run
- id: 'deploy-to-cloud-run'
  name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    gcloud run deploy $SERVICE --image=$PROD_IMAGE \
    --binary-authorization=default --region=$REGION --allow-unauthenticated

images:
  - $SCAN_IMAGE
EOF
}

write_full_pipeline

if gcloud builds submit --project="$PROJECT_ID"; then
  echo "!! Build malah SUKSES. Checkpoint 4 butuh build yang gagal karena CVE CRITICAL."
  echo "!! Cek apakah Dockerfile bawaan lab masih memakai base image rentan."
else
  echo ">>> Build gagal di step 'severity check'. Itu hasil yang benar."
fi

# ----------------------------------------------------------------- Task 5
step "Task 5: Perbaiki Dockerfile lalu build ulang (checkpoint 5)"

cat > ./Dockerfile << 'EOF'
FROM python:3.8-alpine

# App
WORKDIR /app
COPY . ./

RUN pip3 install Flask==3.0.3
RUN pip3 install gunicorn==23.0.0
RUN pip3 install Werkzeug==3.0.4

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app
EOF

gcloud builds submit --project="$PROJECT_ID"

echo ">>> Izinkan akses tanpa autentikasi (untuk validasi saja)"
gcloud beta run services add-iam-policy-binding "$SERVICE" \
  --region="$REGION" --member=allUsers --role=roles/run.invoker \
  --project="$PROJECT_ID" --quiet >/dev/null

URL="$(gcloud run services describe "$SERVICE" --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)')"
echo ">>> URL layanan: $URL"
curl -s "$URL" || true
echo

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk 5 checkpoint:
  1. Enable APIs and set up Artifact Registries
  2. Create a Cloud Build pipeline
  3. Create an Attestor, KMS pair, and update the policy
  4. Integrate vulnerability scanning into your CI/CD pipeline
  5. Fix the vulnerability and redeploy the CI/CD pipeline

Build ketiga memang GAGAL di step 'severity check'. Itu yang dinilai
checkpoint 4, bukan error script.
--------------------------------------------------------------
EOF

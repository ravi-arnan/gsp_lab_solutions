#!/usr/bin/env bash
# GSP1184 - Secure Builds with Cloud Build
#
#   REGION=<region> bash gsp1184.sh
#
# Checkpoint:
#   1. Enable the required APIs
#   2. Build the images with Cloud Build
#   3. Create Artifact Registry repository
#   4. Scan the images using On Demand Scanning
#   5. Verify that the build breaks when a CRITICAL vulnerability is found
#   6. Fix the Vulnerability
#
# Build ke-4 (Task 5) MEMANG gagal — itu yang dinilai checkpoint 5.
# LAMA: ~15 menit dari 20 menit jatah lab. Empat build Docker berurutan.

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

ask REGION "us-central1" "Region (cocokkan dengan panel lab)"
# Lokasi on-demand scanning cuma multi-region: us / europe / asia
SCAN_LOCATION="${REGION%%-*}"

REPO="artifact-scanning-repo"
WORKDIR="$HOME/vuln-scan"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/sample-image"
CB_SA="$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

echo "Project : $PROJECT_ID ($PROJECT_NUMBER)"
echo "Region  : $REGION"
echo "Scan loc: $SCAN_LOCATION"
echo "Image   : $IMAGE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- Checkpoint 1
step "Enable API (8 service, bisa ~2 menit)"
gcloud services enable \
  cloudkms.googleapis.com \
  cloudbuild.googleapis.com \
  container.googleapis.com \
  containerregistry.googleapis.com \
  artifactregistry.googleapis.com \
  containerscanning.googleapis.com \
  ondemandscanning.googleapis.com \
  binaryauthorization.googleapis.com \
  --project="$PROJECT_ID"

# ----------------------------------------------------------------- IAM
step "IAM untuk Cloud Build SA"
for SA in "$CB_SA" "$COMPUTE_SA"; do
  for ROLE in roles/iam.serviceAccountUser roles/ondemandscanning.admin; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:$SA" --role="$ROLE" \
      --condition=None --quiet >/dev/null || true
  done
done
echo "Selesai."

# ----------------------------------------------------------------- Task 1
step "Task 1: Sample app + build pertama (checkpoint 2)"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# Dockerfile sengaja pakai base image lama supaya ada CVE CRITICAL.
# Heredoc di-quote: \$PORT harus sampai ke file apa adanya.
cat > ./Dockerfile << 'EOF'
FROM gcr.io/google-appengine/debian11

# System
RUN apt update && apt install python3-pip -y

# App
WORKDIR /app
COPY . ./

RUN pip3 install Flask==1.1.4
RUN pip3 install gunicorn==20.1.0

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 --timeout 0 main:app
EOF

cat > ./main.py << 'EOF'
import os
from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello_world():
    name = os.environ.get("NAME", "Worlds")
    return "Hello {}!".format(name)

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
EOF

cat > ./cloudbuild.yaml << EOF
steps:

# build
- id: "build"
  name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$IMAGE', '.']
  waitFor: ['-']
EOF

gcloud builds submit --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 2
step "Task 2: Artifact Registry repo + build kedua (checkpoint 3)"

if gcloud artifacts repositories describe "$REPO" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Repo '$REPO' sudah ada, dilewat."
else
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker --location="$REGION" \
    --description="Docker repository" --project="$PROJECT_ID"
fi

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

cat > ./cloudbuild.yaml << EOF
steps:

# build
- id: "build"
  name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$IMAGE', '.']
  waitFor: ['-']

# push to artifact registry
- id: "push"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '$IMAGE']

images:
  - $IMAGE
EOF

gcloud builds submit --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 4
step "Task 4: On-demand scanning image lokal (checkpoint 4)"

docker build -t "$IMAGE" .

gcloud artifacts docker images scan "$IMAGE" \
  --location="$SCAN_LOCATION" \
  --format="value(response.scan)" > scan_id.txt
echo "Report: $(cat scan_id.txt)"

echo ">>> Ringkasan severity:"
gcloud artifacts docker images list-vulnerabilities "$(cat scan_id.txt)" \
  --format="value(vulnerability.effectiveSeverity)" | sort | uniq -c

SEVERITY=CRITICAL
gcloud artifacts docker images list-vulnerabilities "$(cat scan_id.txt)" \
  --format="value(vulnerability.effectiveSeverity)" \
  | if grep -Fxq "$SEVERITY"; then
      echo "Failed vulnerability check for $SEVERITY level"
    else
      echo "No $SEVERITY Vulnerabilities found"
    fi

# ----------------------------------------------------------------- Task 5
step "Task 5: Pipeline dengan gate severity — build ini HARUS gagal (checkpoint 5)"

# \$(cat ...) di-escape supaya dieksekusi Cloud Build, bukan shell ini.
cat > ./cloudbuild.yaml << EOF
steps:

# build
- id: "build"
  name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$IMAGE', '.']
  waitFor: ['-']

#Run a vulnerability scan at _SECURITY level
- id: scan
  name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    (gcloud artifacts docker images scan \
    $IMAGE \
    --location $SCAN_LOCATION \
    --format="value(response.scan)") > /workspace/scan_id.txt

#Analyze the result of the scan
- id: severity check
  name: 'gcr.io/cloud-builders/gcloud'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
      gcloud artifacts docker images list-vulnerabilities \$(cat /workspace/scan_id.txt) \
      --format="value(vulnerability.effectiveSeverity)" | if grep -Fxq CRITICAL; \
      then echo "Failed vulnerability check for CRITICAL level" && exit 1; else echo "No CRITICAL vulnerability found, congrats !" && exit 0; fi

#Retag
- id: "retag"
  name: 'gcr.io/cloud-builders/docker'
  args: ['tag', '$IMAGE', '$IMAGE:good']

#pushing to artifact registry
- id: "push"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '$IMAGE:good']

images:
  - $IMAGE
EOF

if gcloud builds submit --project="$PROJECT_ID"; then
  echo "!! Build malah SUKSES. Checkpoint 5 butuh build yang gagal karena CVE CRITICAL."
  echo "!! Cek apakah base image debian11 masih punya CVE CRITICAL."
else
  echo ">>> Build gagal di step 'severity check'. Itu hasil yang benar."
fi

# ----------------------------------------------------------------- Fix
step "Fix the Vulnerability: base image bersih, build harus sukses (checkpoint 6)"

cat > ./Dockerfile << 'EOF'
FROM python:3.12-alpine

# App
WORKDIR /app
COPY . ./

RUN pip3 install Flask==3.0.3
RUN pip3 install gunicorn==22.0.0
RUN pip3 install Werkzeug==3.0.3

CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app
EOF

gcloud builds submit --project="$PROJECT_ID"

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk 6 checkpoint:
  1. Enable the required APIs
  2. Build the images with Cloud Build
  3. Create Artifact Registry repository
  4. Scan the images using On Demand Scanning
  5. Verify that the build breaks when a CRITICAL vulnerability is found
  6. Fix the Vulnerability

Build ke-4 memang GAGAL. Itu yang dinilai checkpoint 5, bukan error script.
--------------------------------------------------------------
EOF

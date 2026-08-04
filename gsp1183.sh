#!/usr/bin/env bash
# GSP1183 - Gating Deployments with Binary Authorization
#
#   REGION=<region> ZONE=<zone> bash gsp1183.sh
#
# Seluruh lab ini berbasis CLI, jadi 7 checkpoint-nya bisa diotomasi penuh.
# Satu fase, idempoten, aman dijalankan ulang kalau gagal di tengah.
#
# LAMA: ~15-20 menit dari 35 menit jatah lab. Cluster GKE saja ~5 menit.
# Jalankan sedini mungkin.

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

# ----------------------------------------------------------------- parameter
ask REGION "us-central1" "Region (cocokkan dengan panel lab)"
ask ZONE "us-central1-a" "Zone (cocokkan dengan panel lab)"

REPO="artifact-scanning-repo"
NOTE_ID="vulnz_note"
ATTESTOR_ID="vulnz-attestor"
KEY_LOCATION="global"
KEYRING="binauthz-keys"
KEY_NAME="codelab-key"
KEY_VERSION=1
CLUSTER="binauthz"
WORKDIR="$HOME/vuln-scan"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

CONTAINER_PATH="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/sample-image"
CB_SA="$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
BINAUTHZ_SA="service-$PROJECT_NUMBER@gcp-sa-binaryauthorization.iam.gserviceaccount.com"

echo "Project: $PROJECT_ID ($PROJECT_NUMBER)"
echo "Region : $REGION"
echo "Zone   : $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# ----------------------------------------------------------------- services
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

# ----------------------------------------------------------------- Task 1
step "Task 1a: Artifact Registry repo '$REPO'"
if gcloud artifacts repositories describe "$REPO" --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Repo sudah ada, dilewat."
else
  gcloud artifacts repositories create "$REPO" \
    --repository-format=docker --location="$REGION" \
    --description="Docker repository" --project="$PROJECT_ID"
fi

step "Task 1b: konfigurasi docker auth"
gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet

step "Task 1c: siapkan source aplikasi contoh"
mkdir -p "$WORKDIR" && cd "$WORKDIR"
# \$PORT sengaja di-escape: harus literal di Dockerfile, bukan diisi shell sekarang.
cat > ./Dockerfile << 'EOF'
FROM python:3.8-alpine

# App
WORKDIR /app
COPY . ./

RUN pip3 install Flask==2.1.0
RUN pip3 install gunicorn==20.1.0
RUN pip3 install Werkzeug==2.2.2


CMD exec gunicorn --bind :$PORT --workers 1 --threads 8 main:app

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
echo "Dockerfile + main.py siap di $WORKDIR"

step "Task 1d: build & push sample-image (Cloud Build, ~2 menit)"
gcloud builds submit . -t "$CONTAINER_PATH" --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 2
step "Task 2a: Container Analysis note '$NOTE_ID'"
cat > ./vulnz_note.json << EOM
{
  "attestation": {
    "hint": {
      "human_readable_name": "Container Vulnerabilities attestation authority"
    }
  }
}
EOM
if curl -s -f -H "Authorization: Bearer $(gcloud auth print-access-token)" \
     "https://containeranalysis.googleapis.com/v1/projects/$PROJECT_ID/notes/$NOTE_ID" >/dev/null 2>&1; then
  echo "Note sudah ada, dilewat."
else
  curl -s -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    --data-binary @./vulnz_note.json \
    "https://containeranalysis.googleapis.com/v1/projects/$PROJECT_ID/notes/?noteId=$NOTE_ID"
  echo
fi
echo "--- verifikasi note:"
curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://containeranalysis.googleapis.com/v1/projects/$PROJECT_ID/notes/$NOTE_ID"
echo

step "Task 2b: attestor '$ATTESTOR_ID'"
if gcloud container binauthz attestors describe "$ATTESTOR_ID" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Attestor sudah ada, dilewat."
else
  gcloud container binauthz attestors create "$ATTESTOR_ID" \
    --attestation-authority-note="$NOTE_ID" \
    --attestation-authority-note-project="$PROJECT_ID" \
    --project="$PROJECT_ID"
fi
gcloud container binauthz attestors list --project="$PROJECT_ID"

step "Task 2c: beri Binary Authorization SA akses baca note"
cat > ./iam_request.json << EOM
{
  'resource': 'projects/$PROJECT_ID/notes/$NOTE_ID',
  'policy': {
    'bindings': [
      {
        'role': 'roles/containeranalysis.notes.occurrences.viewer',
        'members': [
          'serviceAccount:$BINAUTHZ_SA'
        ]
      }
    ]
  }
}
EOM
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  --data-binary @./iam_request.json \
  "https://containeranalysis.googleapis.com/v1/projects/$PROJECT_ID/notes/$NOTE_ID:setIamPolicy"
echo

# ----------------------------------------------------------------- Task 3
step "Task 3a: KMS keyring '$KEYRING'"
if gcloud kms keyrings describe "$KEYRING" --location="$KEY_LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Keyring sudah ada, dilewat."
else
  gcloud kms keyrings create "$KEYRING" --location="$KEY_LOCATION" --project="$PROJECT_ID"
fi

step "Task 3b: KMS key '$KEY_NAME' (asymmetric signing)"
if gcloud kms keys describe "$KEY_NAME" --keyring="$KEYRING" --location="$KEY_LOCATION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Key sudah ada, dilewat."
else
  gcloud kms keys create "$KEY_NAME" \
    --keyring="$KEYRING" --location="$KEY_LOCATION" \
    --purpose=asymmetric-signing \
    --default-algorithm="ec-sign-p256-sha256" \
    --project="$PROJECT_ID"
fi

step "Task 3c: pasang public key ke attestor"
if gcloud container binauthz attestors describe "$ATTESTOR_ID" --project="$PROJECT_ID" \
     --format='value(userOwnedGrafeasNote.publicKeys[].id)' 2>/dev/null | grep -q .; then
  echo "Public key sudah terpasang, dilewat."
else
  gcloud beta container binauthz attestors public-keys add \
    --attestor="$ATTESTOR_ID" \
    --keyversion-project="$PROJECT_ID" \
    --keyversion-location="$KEY_LOCATION" \
    --keyversion-keyring="$KEYRING" \
    --keyversion-key="$KEY_NAME" \
    --keyversion="$KEY_VERSION" \
    --project="$PROJECT_ID"
fi
gcloud container binauthz attestors list --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 4
step "Task 4: tanda tangani image (attestation)"
DIGEST="$(gcloud container images describe "$CONTAINER_PATH:latest" --format='get(image_summary.digest)')"
echo "Digest: $DIGEST"
if gcloud container binauthz attestations list --attestor="$ATTESTOR_ID" --attestor-project="$PROJECT_ID" \
     --project="$PROJECT_ID" 2>/dev/null | grep -q "$DIGEST"; then
  echo "Attestation sudah ada, dilewat."
else
  gcloud beta container binauthz attestations sign-and-create \
    --artifact-url="$CONTAINER_PATH@$DIGEST" \
    --attestor="$ATTESTOR_ID" \
    --attestor-project="$PROJECT_ID" \
    --keyversion-project="$PROJECT_ID" \
    --keyversion-location="$KEY_LOCATION" \
    --keyversion-keyring="$KEYRING" \
    --keyversion-key="$KEY_NAME" \
    --keyversion="$KEY_VERSION" \
    --project="$PROJECT_ID"
fi
gcloud container binauthz attestations list --attestor="$ATTESTOR_ID" --attestor-project="$PROJECT_ID" --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 5
step "Task 5a: cluster GKE '$CLUSTER' dgn binary authorization (~5 menit)"
if gcloud container clusters describe "$CLUSTER" --zone="$ZONE" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Cluster sudah ada, ambil credentials saja."
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT_ID"
else
  gcloud beta container clusters create "$CLUSTER" \
    --zone="$ZONE" \
    --binauthz-evaluation-mode=PROJECT_SINGLETON_POLICY_ENFORCE \
    --project="$PROJECT_ID"
fi

step "Task 5b: izinkan Cloud Build deploy ke cluster"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$CB_SA" \
  --role="roles/container.developer" --condition=None >/dev/null
echo "roles/container.developer -> $CB_SA"

step "Task 5c: policy ALWAYS_ALLOW, buktikan image apa pun bisa deploy"
gcloud container binauthz policy export --project="$PROJECT_ID"
kubectl delete pod hello-server --ignore-not-found >/dev/null 2>&1 || true
kubectl run hello-server --image gcr.io/google-samples/hello-app:1.0 --port 8080
kubectl get pods
kubectl delete pod hello-server --ignore-not-found

step "Task 5d: ubah ke ALWAYS_DENY, buktikan deploy DITOLAK"
gcloud container binauthz policy export --project="$PROJECT_ID" > policy.yaml
# Lab menyuruh 'edit policy.yaml' (editor Cloud Shell). Script pakai sed.
sed -i 's/evaluationMode: ALWAYS_ALLOW/evaluationMode: ALWAYS_DENY/' policy.yaml
grep evaluationMode policy.yaml
gcloud container binauthz policy import policy.yaml --project="$PROJECT_ID"
echo "Menunggu policy menyebar..."
sleep 20
echo "--- percobaan deploy berikut HARUS gagal (itu tujuannya):"
kubectl run hello-server --image gcr.io/google-samples/hello-app:1.0 --port 8080 \
  && { echo "PERINGATAN: deploy malah berhasil, policy ALWAYS_DENY belum menyebar?"; kubectl delete pod hello-server --ignore-not-found; } \
  || echo ">> Ditolak seperti yang diharapkan."

step "Task 5e: balikkan ke ALWAYS_ALLOW"
sed -i 's/evaluationMode: ALWAYS_DENY/evaluationMode: ALWAYS_ALLOW/' policy.yaml
gcloud container binauthz policy import policy.yaml --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 6
step "Task 6a: role untuk Cloud Build SA"
for role in \
  roles/binaryauthorization.attestorsViewer \
  roles/containeranalysis.notes.attacher \
  roles/iam.serviceAccountUser \
  roles/ondemandscanning.admin \
  roles/cloudkms.signerVerifier
do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$CB_SA" --role="$role" --condition=None >/dev/null
  echo "$role -> cloudbuild SA"
done
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$COMPUTE_SA" --role="roles/cloudkms.signerVerifier" --condition=None >/dev/null
echo "roles/cloudkms.signerVerifier -> compute SA"

step "Task 6b: build custom step binauthz-attestation (~3 menit)"
if gcloud container images describe "gcr.io/$PROJECT_ID/binauthz-attestation:latest" >/dev/null 2>&1; then
  echo "Image binauthz-attestation sudah ada, dilewat."
else
  rm -rf /tmp/cloud-builders-community
  git clone --depth 1 https://github.com/GoogleCloudPlatform/cloud-builders-community.git /tmp/cloud-builders-community
  ( cd /tmp/cloud-builders-community/binauthz-attestation && gcloud builds submit . --config cloudbuild.yaml --project="$PROJECT_ID" )
  rm -rf /tmp/cloud-builders-community
fi

step "Task 6c: cloudbuild.yaml dgn langkah attestation, lalu build"
cd "$WORKDIR"
# Variabel di-expand sekarang (heredoc tanpa kutip) supaya file berisi nilai jadi.
cat > ./cloudbuild.yaml << EOF
steps:

# build
- id: "build"
  name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$CONTAINER_PATH', '.']
  waitFor: ['-']

# additional CICD checks (not shown)

#Retag
- id: "retag"
  name: 'gcr.io/cloud-builders/docker'
  args: ['tag', '$CONTAINER_PATH', '$CONTAINER_PATH:good']

#pushing to artifact registry
- id: "push"
  name: 'gcr.io/cloud-builders/docker'
  args: ['push', '$CONTAINER_PATH:good']

#Sign the image only if the previous severity check passes
- id: 'create-attestation'
  name: 'gcr.io/$PROJECT_ID/binauthz-attestation:latest'
  args:
    - '--artifact-url'
    - '$CONTAINER_PATH:good'
    - '--attestor'
    - 'projects/$PROJECT_ID/attestors/$ATTESTOR_ID'
    - '--keyversion'
    - 'projects/$PROJECT_ID/locations/$KEY_LOCATION/keyRings/$KEYRING/cryptoKeys/$KEY_NAME/cryptoKeyVersions/$KEY_VERSION'

images:
  - $CONTAINER_PATH:good
EOF
cat ./cloudbuild.yaml
gcloud builds submit --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 7
step "Task 7a: policy REQUIRE_ATTESTATION"
# Kunci clusterAdmissionRules harus '<lokasi-cluster>.<nama-cluster>'. Cluster ini
# zonal, jadi pakai ZONE. Teks lab menulis COMPUTE_ZONE="REGION", itu keliru;
# kalau kuncinya tidak cocok, aturan cluster-nya diam-diam tidak terpakai.
cat > binauth_policy.yaml << EOM
defaultAdmissionRule:
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  evaluationMode: REQUIRE_ATTESTATION
  requireAttestationsBy:
  - projects/$PROJECT_ID/attestors/$ATTESTOR_ID
globalPolicyEvaluationMode: ENABLE
clusterAdmissionRules:
  $ZONE.$CLUSTER:
    evaluationMode: REQUIRE_ATTESTATION
    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
    requireAttestationsBy:
    - projects/$PROJECT_ID/attestors/$ATTESTOR_ID
EOM
cat binauth_policy.yaml
gcloud beta container binauthz policy import binauth_policy.yaml --project="$PROJECT_ID"
echo "Menunggu policy menyebar..."
sleep 20

step "Task 7b: deploy image BERTANDA TANGAN (harus berhasil)"
GOOD_DIGEST="$(gcloud container images describe "$CONTAINER_PATH:good" --format='get(image_summary.digest)')"
echo "Digest good: $GOOD_DIGEST"
write_deploy() {
  cat > deploy.yaml << EOM
apiVersion: v1
kind: Service
metadata:
  name: deb-httpd
spec:
  selector:
    app: deb-httpd
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deb-httpd
spec:
  replicas: 1
  selector:
    matchLabels:
      app: deb-httpd
  template:
    metadata:
      labels:
        app: deb-httpd
    spec:
      containers:
      - name: deb-httpd
        image: $CONTAINER_PATH@$1
        ports:
        - containerPort: 8080
        env:
          - name: PORT
            value: "8080"
EOM
}
write_deploy "$GOOD_DIGEST"
kubectl apply -f deploy.yaml
echo "Menunggu pod jalan..."
kubectl rollout status deployment/deb-httpd --timeout=120s || kubectl get pods
kubectl get pods

# ----------------------------------------------------------------- Task 8
step "Task 8a: build & push image TANPA tanda tangan (tag :bad)"
docker build -t "$CONTAINER_PATH:bad" .
docker push "$CONTAINER_PATH:bad"

step "Task 8b: deploy image tanpa tanda tangan (HARUS ditolak)"
BAD_DIGEST="$(gcloud container images describe "$CONTAINER_PATH:bad" --format='get(image_summary.digest)')"
echo "Digest bad: $BAD_DIGEST"
write_deploy "$BAD_DIGEST"
kubectl apply -f deploy.yaml
echo
echo "Menunggu, lalu cek alasan penolakan..."
sleep 30
kubectl get pods
echo "--- event replicaset (harus ada 'denied by attestor'):"
kubectl describe replicaset -l app=deb-httpd 2>/dev/null | grep -A3 -i "denied\|attestation" || \
  kubectl get events --sort-by=.lastTimestamp | tail -10

cat <<EOF

--------------------------------------------------------------
Selesai. Klik Check my progress untuk 7 checkpoint:
  1. Create Artifact Registry repository
  2. Create an Attestor
  3. Add a KMS key
  4. Create a GKE cluster and update the policies
  5. Add a signing step
  6. Deploy a signed image
  7. Deploy an unsigned image

Task 8 memang harus GAGAL deploy. Pod tidak jalan dan muncul
pesan penolakan attestor. Itu hasil yang benar, bukan error.
--------------------------------------------------------------
EOF

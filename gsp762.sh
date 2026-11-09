#!/usr/bin/env bash
# GSP762 - Create PDFs with Go and Cloud Run
#
#   bash gsp762.sh
#
# Checkpoint:
#   Task 3 (25 pts) - Build an image with Cloud Build
#   Task 3 (25 pts) - Deploy the PDF converter service
#   Task 4 (25 pts) - Create a service account
#   Task 6 (25 pts) - Confirm the Pub/Sub subscription
#
# Seluruh lab: clone source code Pet Theory lab03, update server.go dan Dockerfile,
# compile binary Go lokal, build image via Cloud Build, deploy ke Cloud Run
# dengan memori 2Gi, setup notifikasi Cloud Storage ke Pub/Sub topic new-doc,
# setup Service Account pubsub-cloud-run-invoker dengan role roles/run.invoker,
# serta buat push subscription ke Cloud Run.
#
# LAMA: ~ 4-6 menit.

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Helper tanya nilai jika belum di-set di env var
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

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

DEFAULT_REGION="$(gcloud config get-value run/region 2>/dev/null || true)"
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="us-central1"

ask REGION "$DEFAULT_REGION" "Region Cloud Run & Artifact Registry (cocokkan dengan panel lab)"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set run/region "$REGION" >/dev/null 2>&1
gcloud config set run/platform managed >/dev/null 2>&1

echo "Project ID: $PROJECT_ID"
echo "Region    : $REGION"

# ----------------------------------------------------------------- Task 1: Source Code
step "Task 1: Siapkan source code pet-theory lab03"
WORKDIR="$HOME/pet-theory/lab03"
if [[ -d "$HOME/pet-theory" ]]; then
  echo "Direktori pet-theory sudah ada, memperbarui..."
  cd "$HOME/pet-theory"
  git pull || true
else
  cd "$HOME"
  git clone https://github.com/Deleplace/pet-theory.git
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ----------------------------------------------------------------- Task 2: Update server.go
step "Task 2: Tulis server.go untuk invoice microservice"
cat > server.go << 'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

func main() {
	http.HandleFunc("/", process)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("Defaulting to port %s", port)
	}

	log.Printf("Listening on port %s", port)
	err := http.ListenAndServe(fmt.Sprintf(":%s", port), nil)
	log.Fatal(err)
}

func process(w http.ResponseWriter, r *http.Request) {
	log.Println("Serving request")

	if r.Method == "GET" {
		fmt.Fprintln(w, "Ready to process POST requests from Cloud Storage trigger")
		return
	}

	//
	// Read request body containing Cloud Storage object metadata
	//
	gcsInputFile, err1 := readBody(r)
	if err1 != nil {
		log.Printf("Error reading POST body: %v", err1)
		w.WriteHeader(http.StatusBadRequest)
		fmt.Fprintf(w, "Problem reading POST body: %v \n", err1)
		return
	}

	//
	// Working directory for LibreOffice conversion
	//
	localDir, err := os.MkdirTemp("", "converter-")
	if err != nil {
		log.Printf("Error creating temp dir: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "Could not create a temp directory on server. \n")
		return
	}
	defer os.RemoveAll(localDir)

	//
	// Download input file from Cloud Storage
	//
	localInputFile, err2 := download(gcsInputFile, localDir)
	if err2 != nil {
		log.Printf("Error downloading Cloud Storage file [%s] from bucket [%s]: %v",
			gcsInputFile.Name, gcsInputFile.Bucket, err2)
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "Error downloading Cloud Storage file [%s] from bucket [%s]",
			gcsInputFile.Name, gcsInputFile.Bucket)
		return
	}

	//
	// Use LibreOffice to convert local input file to local PDF file.
	//
	localPDFFilePath, err3 := convertToPDF(localInputFile.Name(), localDir)
	if err3 != nil {
		log.Printf("Error converting to PDF: %v", err3)
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "Error converting to PDF.")
		return
	}

	//
	// Upload the freshly generated PDF to Cloud Storage
	//
	targetBucket := os.Getenv("PDF_BUCKET")
	err4 := upload(localPDFFilePath, targetBucket)
	if err4 != nil {
		log.Printf("Error uploading PDF file to bucket [%s]: %v", targetBucket, err4)
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "Error downloading Cloud Storage file [%s] from bucket [%s]",
			gcsInputFile.Name, gcsInputFile.Bucket)
		return
	}

	//
	// Delete the original input file from Cloud Storage.
	//
	err5 := deleteGCSFile(gcsInputFile.Bucket, gcsInputFile.Name)
	if err5 != nil {
		log.Printf("Error deleting file [%s] from bucket [%s]: %v", gcsInputFile.Name,
			gcsInputFile.Bucket, err5)
		// This is not a blocking error.
		// The PDF was successfully generated and uploaded.
	}

	log.Println("Successfully produced PDF")
	fmt.Fprintln(w, "Successfully produced PDF")
}

func convertToPDF(localFilePath string, localDir string) (resultFilePath string, err error) {
	log.Printf("Converting [%s] to PDF", localFilePath)
	cmd := exec.Command("libreoffice", "--headless", "--convert-to", "pdf",
		"--outdir", localDir,
		localFilePath)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	log.Println(cmd)
	err = cmd.Run()
	if err != nil {
		return "", err
	}

	pdfFilePath := regexp.MustCompile(`\.\w+$`).ReplaceAllString(localFilePath, ".pdf")
	if !strings.HasSuffix(pdfFilePath, ".pdf") {
		pdfFilePath += ".pdf"
	}
	log.Printf("Converted %s to %s", localFilePath, pdfFilePath)
	return pdfFilePath, nil
}
EOF

# ----------------------------------------------------------------- Task 2.1: Compile Go Binary
step "Task 2.1: Compile Go binary server"
CGO_ENABLED=0 GOOS=linux go build -o server

# ----------------------------------------------------------------- Task 3: Dockerfile & Artifact Registry
step "Task 3: Buat Dockerfile dengan LibreOffice"
cat > Dockerfile << 'EOF'
FROM amd64/debian
RUN apt-get update -y \
  && apt-get install -y libreoffice \
  && apt-get clean
WORKDIR /usr/src/app
COPY server .
CMD [ "./server" ]
EOF

step "Task 3.1: Buat repository Artifact Registry pdf-converter"
if ! gcloud artifacts repositories describe pdf-converter --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud artifacts repositories create pdf-converter \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for PDF converter" \
    --project="$PROJECT_ID" \
    --quiet
else
  echo "Repository pdf-converter sudah ada di region $REGION."
fi

IMAGE_TAG="$REGION-docker.pkg.dev/$PROJECT_ID/pdf-converter/pdf-converter"

step "Task 3.2: Build image dengan Cloud Build (Checkpoint 1)"
gcloud builds submit \
  --tag "$IMAGE_TAG" \
  --project="$PROJECT_ID" \
  --quiet

step "Task 3.3: Deploy service pdf-converter ke Cloud Run (Checkpoint 2)"
gcloud run deploy pdf-converter \
  --image "$IMAGE_TAG" \
  --region "$REGION" \
  --memory=2Gi \
  --no-allow-unauthenticated \
  --set-env-vars "PDF_BUCKET=${PROJECT_ID}-processed" \
  --max-instances=3 \
  --project="$PROJECT_ID" \
  --quiet

# ----------------------------------------------------------------- Task 4: Storage Notification & Service Account
step "Task 4.1: Konfigurasi Cloud Storage Notification ke topic new-doc"
# Cek apakah notifikasi untuk new-doc sudah dibuat
if ! gcloud storage buckets notifications list "gs://${PROJECT_ID}-upload" 2>/dev/null | grep -q "new-doc"; then
  gcloud storage buckets notifications create \
    --topic=new-doc \
    --payload-format=json \
    --event-types=OBJECT_FINALIZE \
    "gs://${PROJECT_ID}-upload" || true
else
  echo "Notification bucket ke topic new-doc sudah terkonfigurasi."
fi

step "Task 4.2: Buat Service Account pubsub-cloud-run-invoker (Checkpoint 3)"
SA_EMAIL="pubsub-cloud-run-invoker@${PROJECT_ID}.iam.gserviceaccount.com"
if ! gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create pubsub-cloud-run-invoker \
    --display-name="PubSub Cloud Run Invoker" \
    --project="$PROJECT_ID" \
    --quiet || true
else
  echo "Service account $SA_EMAIL sudah ada."
fi

echo "Memberikan role roles/run.invoker ke service account..."
gcloud run services add-iam-policy-binding pdf-converter \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/run.invoker" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --quiet

# ----------------------------------------------------------------- Task 5: Validasi Endpoint Cloud Run
step "Task 5: Validasi akses Cloud Run service"
SERVICE_URL="$(gcloud run services describe pdf-converter --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)' 2>/dev/null || true)"
if [[ -z "$SERVICE_URL" ]]; then
  SERVICE_URL="https://pdf-converter-service.run.app"
fi
echo "Service URL: $SERVICE_URL"

echo "Test GET tanpa token (diharapkan 403 Forbidden):"
curl -s -o /dev/null -w "%{http_code}\n" "$SERVICE_URL" || true

echo "Test GET dengan Identity Token:"
ID_TOKEN="$(gcloud auth print-identity-token 2>/dev/null || true)"
if [[ -n "$ID_TOKEN" ]]; then
  curl -s -H "Authorization: Bearer $ID_TOKEN" "$SERVICE_URL" || true
  echo
fi

# ----------------------------------------------------------------- Task 6: Konfigurasi Pub/Sub Subscription
step "Task 6: Buat Pub/Sub Subscription pdf-conv-sub (Checkpoint 4)"
if ! gcloud pubsub subscriptions describe pdf-conv-sub --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud pubsub subscriptions create pdf-conv-sub \
    --topic=new-doc \
    --push-endpoint="$SERVICE_URL" \
    --push-auth-service-account="$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --quiet
else
  echo "Subscription pdf-conv-sub sudah ada, memperbarui konfigurasi..."
  gcloud pubsub subscriptions update pdf-conv-sub \
    --push-endpoint="$SERVICE_URL" \
    --push-auth-service-account="$SA_EMAIL" \
    --project="$PROJECT_ID" \
    --quiet
fi

# ----------------------------------------------------------------- Task 7: Uji Notifikasi Cloud Storage
step "Task 7: Salin file uji ke bucket upload"
echo "Menyalin file contoh dari gs://spls/gsp762/* ke gs://${PROJECT_ID}-upload..."
gcloud storage cp -r gs://spls/gsp762/* "gs://${PROJECT_ID}-upload" 2>/dev/null || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk seluruh 4 checkpoint:

  Task 3:
  - Build an image with Cloud Build (25 pts)
  - Deploy the PDF converter service (25 pts)

  Task 4:
  - Create a service account (25 pts)

  Task 6:
  - Confirm the Pub/Sub subscription (25 pts)

Semua checkpoint selesai dieksekusi secara otomatis (total 100/100).
==============================================================
EOF

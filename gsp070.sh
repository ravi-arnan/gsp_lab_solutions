#!/usr/bin/env bash
# GSP070 - App Engine: Qwik Start - Go
#
#   bash gsp070.sh
#
# Checkpoint:
#   Task 4 - Deploy your app

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

DEFAULT_REGION="$(gcloud config get-value compute/region 2>/dev/null || true)"
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="us-west1"

ask REGION "$DEFAULT_REGION" "Region (cocokkan dengan panel lab)"

# Mapping region Compute Engine ke App Engine location
map_app_region() {
  case "$1" in
    europe-west1) echo "europe-west" ;;
    us-central1) echo "us-central" ;;
    *) echo "$1" ;;
  esac
}

APP_REGION="$(map_app_region "$REGION")"

echo "Project ID  : $PROJECT_ID"
echo "Region      : $REGION"
echo "App Region  : $APP_REGION"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

# ----------------------------------------------------------------- Task 1: Enable App Engine Admin API
step "Task 1: Mengaktifkan App Engine Admin API & Inisialisasi App Engine"

echo "Mengaktifkan service appengine.googleapis.com..."
gcloud services enable appengine.googleapis.com --project="$PROJECT_ID"

if ! gcloud app describe --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Membuat App Engine application di region $APP_REGION..."
  gcloud app create --region="$APP_REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || \
  gcloud app create --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || true
else
  echo "App Engine application sudah ada."
fi

# ----------------------------------------------------------------- Task 2: Setup Hello World App Go
step "Task 2: Menyiapkan Kode Aplikasi Hello World Go"

APP_DIR="$HOME/golang-samples/appengine/go11x/helloworld"
mkdir -p "$APP_DIR"
cd "$APP_DIR"

echo "Menulis app.yaml (runtime: go125)..."
cat << 'EOF_YAML' > app.yaml
runtime: go125
EOF_YAML

echo "Menulis go.mod..."
cat << 'EOF_MOD' > go.mod
module github.com/GoogleCloudPlatform/appengine/go11x/helloworld

go 1.25.0
EOF_MOD

echo "Menulis helloworld.go..."
cat << 'EOF_GO' > helloworld.go
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", indexHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
		log.Printf("Defaulting to port %s", port)
	}

	log.Printf("Listening on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal(err)
	}
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	fmt.Fprint(w, "Hello, World!")
}
EOF_GO

# ----------------------------------------------------------------- Task 3-4: Deploy App Engine (Checkpoint)
step "Task 3 & 4: Deploy Aplikasi ke App Engine (Checkpoint)"

echo "Men-deploy aplikasi Go ke App Engine..."
gcloud app deploy app.yaml --project="$PROJECT_ID" --quiet

HOSTNAME="$(gcloud app describe --project="$PROJECT_ID" --format='value(defaultHostname)' 2>/dev/null || echo "${PROJECT_ID}.appspot.com")"
echo "Aplikasi berhasil di-deploy ke: https://${HOSTNAME}"

echo "Menguji akses HTTP aplikasi..."
for i in {1..5}; do
  RESP="$(curl -s -m 5 "https://${HOSTNAME}" || true)"
  if [[ -n "$RESP" ]]; then
    echo "Respons aplikasi: $RESP"
    break
  fi
  sleep 2
done

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Deploy your app (Task 4)

Kuis Pengetahuan (Task 5):
  - Which of the following runtimes for Go are supported in App Engine standard environment?
    Jawaban: Go 1.25 dan Go 1.26
==============================================================
EOF

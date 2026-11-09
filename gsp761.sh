#!/usr/bin/env bash
# GSP761 - Developing a REST API with Go and Cloud Run
#
#   bash gsp761.sh
#
# Checkpoint:
#   Task 2 (25 pts) - Build an image with Cloud Build
#   Task 2 (25 pts) - REST API service deployed
#   Task 3 (25 pts) - Firestore database created
#   Task 7 (25 pts) - Build image revision 0.2
#
# Seluruh lab: Build Go binary, Artifact Registry, Cloud Run deployment,
# Firestore standard database setup, data import, dan revision 0.2 deployment.
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
[[ -z "$DEFAULT_REGION" ]] && DEFAULT_REGION="europe-west4"

ask REGION "$DEFAULT_REGION" "Region Cloud Run & Firestore (cocokkan dengan panel lab)"

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
gcloud config set run/region "$REGION" >/dev/null 2>&1
gcloud config set run/platform managed >/dev/null 2>&1

echo "Project ID: $PROJECT_ID"
echo "Region    : $REGION"

# ----------------------------------------------------------------- Task 1: Enable APIs
step "Task 1: Enable Google APIs"
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  firestore.googleapis.com \
  artifactregistry.googleapis.com \
  --project="$PROJECT_ID"

# ----------------------------------------------------------------- Task 2: Developing REST API (Revisi 0.1)
step "Task 2.1: Siapkan source code pet-theory lab08"
WORKDIR="$HOME/pet-theory/lab08"
if [[ ! -d "$HOME/pet-theory" ]]; then
  git clone https://github.com/rosera/pet-theory.git "$HOME/pet-theory"
fi
mkdir -p "$WORKDIR"
cd "$WORKDIR"

step "Task 2.2: Buat main.go versi 0.1"
cat > main.go << 'EOF'
package main

import (
  "fmt"
  "log"
  "net/http"
  "os"
)

func main() {
  port := os.Getenv("PORT")
  if port == "" {
      port = "8080"
  }
  http.HandleFunc("/v1/", func(w http.ResponseWriter, r *http.Request) {
      fmt.Fprintf(w, "{status: 'running'}")
  })
  log.Println("Pets REST API listening on port", port)
  if err := http.ListenAndServe(":"+port, nil); err != nil {
      log.Fatalf("Error launching Pets REST API server: %v", err)
  }
}
EOF

step "Task 2.3: Buat Dockerfile"
cat > Dockerfile << 'EOF'
FROM gcr.io/distroless/base-debian12
WORKDIR /usr/src/app
COPY server .
CMD [ "/usr/src/app/server" ]
EOF

step "Task 2.4: Build executable binary server"
CGO_ENABLED=0 GOOS=linux go build -o server

step "Task 2.5: Buat repository Artifact Registry (my-repo)"
if ! gcloud artifacts repositories describe my-repo --location="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud artifacts repositories create my-repo \
    --repository-format=docker \
    --location="$REGION" \
    --description="Docker repository for REST API" \
    --project="$PROJECT_ID" \
    --quiet
  echo "Repository my-repo berhasil dibuat."
else
  echo "Repository my-repo sudah ada, lewati."
fi

step "Task 2.6: Build image rest-api:0.1 dengan Cloud Build (Checkpoint 1)"
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/my-repo/rest-api:0.1" \
  --project="$PROJECT_ID" \
  --quiet

step "Task 2.7: Deploy rest-api ke Cloud Run (Checkpoint 2)"
gcloud run deploy rest-api \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/my-repo/rest-api:0.1" \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances=2 \
  --project="$PROJECT_ID" \
  --quiet

URL="$(gcloud run services describe rest-api --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)' 2>/dev/null || true)"
echo "Service deployed: $URL"
if [[ -n "$URL" ]]; then
  echo "Tes endpoint /v1/:"
  curl -s "$URL/v1/" || true
  echo
fi

# ----------------------------------------------------------------- Task 3: Import Customer Test Data
step "Task 3.1: Buat Firestore database (default) (Checkpoint 3)"
if ! gcloud firestore databases describe --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Membuat database Firestore (default)..."
  gcloud firestore databases create \
    --location="$REGION" \
    --type=firestore-native \
    --project="$PROJECT_ID" \
    --quiet || true
else
  echo "Database Firestore sudah ada, lewati."
fi

step "Task 3.2: Buat bucket dan import data customer ke Firestore"
BUCKET_NAME="${PROJECT_ID}-customer"
if ! gcloud storage buckets describe "gs://$BUCKET_NAME" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://$BUCKET_NAME" \
    --default-storage-class=standard \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --quiet
  echo "Bucket gs://$BUCKET_NAME dibuat."
else
  echo "Bucket gs://$BUCKET_NAME sudah ada, lewati."
fi

gcloud storage cp -r gs://spls/gsp645/2019-10-06T20:10:37_43617 "gs://$BUCKET_NAME"
gcloud beta firestore import "gs://$BUCKET_NAME/2019-10-06T20:10:37_43617/" --project="$PROJECT_ID" --quiet
echo "Data customer berhasil di-import ke Firestore."

# ----------------------------------------------------------------- Task 4 & 7: Connect REST API to Firestore & Deploy Revisi 0.2
step "Task 4: Update main.go dengan Firestore integration"
cd "$WORKDIR"
cat > main.go << EOF
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	"cloud.google.com/go/firestore"
	"github.com/gorilla/handlers"
	"github.com/gorilla/mux"
	"google.golang.org/api/iterator"
)

var client *firestore.Client

func main() {
	var err error
	ctx := context.Background()
	client, err = firestore.NewClient(ctx, "$PROJECT_ID")
	if err != nil {
		log.Fatalf("Error initializing Cloud Firestore client: %v", err)
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	r := mux.NewRouter()
	r.HandleFunc("/v1/", rootHandler)
	r.HandleFunc("/v1/customer/{id}", customerHandler)

	log.Println("Pets REST API listening on port", port)
	cors := handlers.CORS(
		handlers.AllowedHeaders([]string{"X-Requested-With", "Authorization", "Origin"}),
		handlers.AllowedOrigins([]string{"https://storage.googleapis.com"}),
		handlers.AllowedMethods([]string{"GET", "HEAD", "POST", "OPTIONS", "PATCH", "CONNECT"}),
	)

	if err := http.ListenAndServe(":"+port, cors(r)); err != nil {
		log.Fatalf("Error launching Pets REST API server: %v", err)
	}
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, "{status: 'running'}")
}

func customerHandler(w http.ResponseWriter, r *http.Request) {
	id := mux.Vars(r)["id"]
	ctx := context.Background()
	customer, err := getCustomer(ctx, id)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "{\"status\": \"fail\", \"data\": '%s'}", err)
		return
	}
	if customer == nil {
		w.WriteHeader(http.StatusNotFound)
		msg := fmt.Sprintf("\`Customer \\\"%s\\\" not found\`", id)
		fmt.Fprintf(w, fmt.Sprintf("{\"status\": \"fail\", \"data\": {\"title\": %s}}", msg))
		return
	}
	amount, err := getAmounts(ctx, customer)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "{\"status\": \"fail\", \"data\": \"Unable to fetch amounts: %s\"}", err)
		return
	}
	data, err := json.Marshal(amount)
	if err != nil {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintf(w, "{\"status\": \"fail\", \"data\": \"Unable to fetch amounts: %s\"}", err)
		return
	}
	fmt.Fprintf(w, fmt.Sprintf("{\"status\": \"success\", \"data\": %s}", data))
}

type Customer struct {
	Email string \`firestore:"email"\`
	ID    string \`firestore:"id"\`
	Name  string \`firestore:"name"\`
	Phone string \`firestore:"phone"\`
}

func getCustomer(ctx context.Context, id string) (*Customer, error) {
	query := client.Collection("customers").Where("id", "==", id)
	iter := query.Documents(ctx)

	var c Customer
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		err = doc.DataTo(&c)
		if err != nil {
			return nil, err
		}
	}
	return &c, nil
}

func getAmounts(ctx context.Context, c *Customer) (map[string]int64, error) {
	if c == nil {
		return map[string]int64{}, fmt.Errorf("Customer should be non-nil: %v", c)
	}
	result := map[string]int64{
		"proposed": 0,
		"approved": 0,
		"rejected": 0,
	}
	query := client.Collection(fmt.Sprintf("customers/%s/treatments", c.Email))
	if query == nil {
		return map[string]int64{}, fmt.Errorf("Query is nil: %v", c)
	}
	iter := query.Documents(ctx)
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		treatment := doc.Data()
		result[treatment["status"].(string)] += treatment["cost"].(int64)
	}
	return result, nil
}
EOF

step "Task 7.1: Rebuild binary server"
CGO_ENABLED=0 GOOS=linux go build -o server

step "Task 7.2: Build image revisi 0.2 dengan Cloud Build (Checkpoint 4)"
gcloud builds submit \
  --tag "$REGION-docker.pkg.dev/$PROJECT_ID/my-repo/rest-api:0.2" \
  --project="$PROJECT_ID" \
  --quiet

step "Task 7.3: Deploy image revisi 0.2 ke Cloud Run"
gcloud run deploy rest-api \
  --image "$REGION-docker.pkg.dev/$PROJECT_ID/my-repo/rest-api:0.2" \
  --region "$REGION" \
  --allow-unauthenticated \
  --max-instances=2 \
  --project="$PROJECT_ID" \
  --quiet

echo
echo "--- Validasi Endpoint API ---"
URL="$(gcloud run services describe rest-api --region="$REGION" --project="$PROJECT_ID" --format='value(status.url)' 2>/dev/null || true)"
if [[ -n "$URL" ]]; then
  echo "URL: $URL"
  echo "Curl /v1/:"
  curl -s "$URL/v1/" || true
  echo
  echo "Curl /v1/customer/22530:"
  curl -s "$URL/v1/customer/22530" || true
  echo
fi

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk seluruh 4 checkpoint:

  Task 2:
  - Build an image with Cloud Build (25 pts)
  - REST API service deployed (25 pts)

  Task 3:
  - Firestore database created (25 pts)

  Task 7:
  - Build image revision 0.2 (25 pts)

Semua checkpoint selesai dieksekusi secara otomatis (total 100/100).
==============================================================
EOF

#!/usr/bin/env bash
# GSP330 - Implement DevOps Workflows in Google Cloud: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp330.sh
#   bash gsp330.sh setup      # Task 1  (~8 menit, cluster GKE)
#   # -- manual: gh auth login --
#   bash gsp330.sh repo       # Task 2
#   # -- manual: bikin 2 trigger di console (GitHub App butuh OAuth) --
#   bash gsp330.sh v1         # Task 4
#   bash gsp330.sh v2         # Task 5
#   bash gsp330.sh rollback   # Task 6
#
# Checkpoint:
#   Task 1 - Create the lab resources                  (otomatis)
#   Task 2 - Create a repository in GitHub             (otomatis, setelah gh auth login)
#   Task 3 - Create the Cloud Build Triggers           (MANUAL, console)
#   Task 4 - Deploy the first versions of the app      (otomatis)
#   Task 5 - Deploy the second versions of the app     (otomatis)
#   Task 6 - Roll back the production deployment       (otomatis)
#
# Jangan di-pipe ke bash: script butuh argumen fase dan filenya dipakai lagi
# di fase berikutnya.
#
# Task 3 tidak bisa di-CLI: `gcloud builds triggers create github` hanya jalan
# kalau repo sudah tersambung lewat Cloud Build GitHub App, dan pemasangan app
# itu alur OAuth di browser. Wizard console sekalian membuat trigger-nya, jadi
# lebih cepat manual.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

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
ask ZONE   "us-central1-a" "Zone (cocokkan dengan panel lab)"

CLUSTER="hello-cluster"
REPO_DIR="$HOME/sample-app"
AR="my-repository"
IMG_PROD="${REGION}-docker.pkg.dev/${PROJECT}/${AR}/hello-cloudbuild"
IMG_DEV="${REGION}-docker.pkg.dev/${PROJECT}/${AR}/hello-cloudbuild-dev"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

PHASE="${1:-}"
[[ -n "$PHASE" ]] || { echo "Pakai: bash gsp330.sh setup|repo|v1|v2|rollback"; exit 1; }

# --------------------------------------------------------------------- Task 1
do_setup() {
  step "Task 1: enable API"
  gcloud services enable container.googleapis.com cloudbuild.googleapis.com \
    artifactregistry.googleapis.com --project="$PROJECT"

  step "Task 1: role Kubernetes Developer untuk SA Cloud Build"
  local NUM
  NUM="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${NUM}@cloudbuild.gserviceaccount.com" \
    --role="roles/container.developer" --condition=None >/dev/null
  # Build juga butuh menulis ke Artifact Registry saat pakai SA legacy.
  gcloud projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:${NUM}@cloudbuild.gserviceaccount.com" \
    --role="roles/artifactregistry.writer" --condition=None >/dev/null

  step "Task 1: Artifact Registry $AR"
  gcloud artifacts repositories describe "$AR" --location="$REGION" --project="$PROJECT" >/dev/null 2>&1 || \
    gcloud artifacts repositories create "$AR" \
      --repository-format=docker --location="$REGION" \
      --description="Docker repository" --project="$PROJECT"

  step "Task 1: cluster $CLUSTER (butuh ~7 menit)"
  if ! gcloud container clusters describe "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1; then
    gcloud container clusters create "$CLUSTER" \
      --zone="$ZONE" \
      --release-channel=regular \
      --num-nodes=3 \
      --enable-autoscaling --min-nodes=2 --max-nodes=6 \
      --project="$PROJECT"
  else
    echo "Cluster sudah ada."
  fi

  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT"

  step "Task 1: namespace prod dan dev"
  kubectl get namespace prod >/dev/null 2>&1 || kubectl create namespace prod
  kubectl get namespace dev  >/dev/null 2>&1 || kubectl create namespace dev
  kubectl get namespace

  cat <<EOF

--------------------------------------------------------------
Task 1 selesai. Klik Check my progress: "Create the lab resources".

LANGKAH MANUAL berikutnya (Task 2 butuh ini):

  curl -sS https://webi.sh/gh | sh
  gh auth login          # pilih GitHub.com -> HTTPS -> Yes -> browser, ikuti kodenya

Setelah login sukses, lanjut:  bash gsp330.sh repo
--------------------------------------------------------------
EOF
}

# --------------------------------------------------------------------- Task 2
do_repo() {
  command -v gh >/dev/null || { echo "gh belum ada. Jalankan: curl -sS https://webi.sh/gh | sh"; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "Belum login GitHub. Jalankan: gh auth login"; exit 1; }

  local GH_USER
  GH_USER="$(gh api user -q '.login')"
  echo "GitHub user: $GH_USER"

  git config --global user.name "$GH_USER"
  git config --global user.email "${USER_EMAIL:-$GH_USER@users.noreply.github.com}"
  gh auth setup-git

  step "Task 2: repo sample-app"
  gh repo view "$GH_USER/sample-app" >/dev/null 2>&1 || \
    gh repo create sample-app --private

  rm -rf "$REPO_DIR"
  cd "$HOME"
  gh repo clone "$GH_USER/sample-app" sample-app

  step "Task 2: salin kode contoh"
  gsutil -m cp -r gs://spls/gsp330/sample-app/* "$REPO_DIR"

  step "Task 2: isi placeholder region dan zone"
  local f
  for f in "$REPO_DIR/cloudbuild-dev.yaml" "$REPO_DIR/cloudbuild.yaml"; do
    sed -i "s/<your-region>/${REGION}/g" "$f"
    sed -i "s/<your-zone>/${ZONE}/g" "$f"
  done

  step "Task 2: commit ke master lalu bikin branch dev"
  cd "$REPO_DIR"
  git checkout -B master
  git add .
  git commit -m "Add sample app source code"
  # -f: repo sample-app sering sudah ada dari percobaan sebelumnya (repo GitHub
  # hidup lebih lama dari project lab), riwayat remote-nya bisa berbeda.
  git push -f -u origin master

  git checkout -B dev
  git push -f -u origin dev
  git branch -a

  cat <<EOF

--------------------------------------------------------------
Task 2 selesai. Klik Check my progress: "Create a repository in GitHub Repositories".

LANGKAH MANUAL (Task 3) — di console, Cloud Build -> Triggers -> Create trigger.
Pemasangan Cloud Build GitHub App itu alur OAuth, tidak ada jalur CLI-nya.

Trigger 1
  Name    : sample-app-prod-deploy
  Event   : Push to a branch
  Source  : Connect new repository -> GitHub (Cloud Build GitHub App)
            -> pilih repo ${GH_USER}/sample-app
  Branch  : ^master\$
  Config  : Cloud Build configuration file -> cloudbuild.yaml

Trigger 2
  Name    : sample-app-dev-deploy
  Event   : Push to a branch
  Source  : repo yang sama (sudah tersambung)
  Branch  : ^dev\$
  Config  : Cloud Build configuration file -> cloudbuild-dev.yaml

Klik Check my progress: "Create the Cloud Build Triggers", lalu lanjut:
  bash gsp330.sh v1
--------------------------------------------------------------
EOF
}

# Tunggu build terbaru untuk sebuah branch sampai selesai.
wait_build() {  # $1 = label untuk pesan
  local n=0 status=""
  echo "Menunggu build $1 ..."
  sleep 15
  while (( n++ < 60 )); do
    status="$(gcloud builds list --limit=1 --project="$PROJECT" \
      --format='value(status)' 2>/dev/null || true)"
    case "$status" in
      SUCCESS) echo "Build $1: SUCCESS"; return 0 ;;
      FAILURE|TIMEOUT|CANCELLED|INTERNAL_ERROR)
        echo "Build $1: $status"
        gcloud builds list --limit=1 --project="$PROJECT"
        echo "Lihat lognya: gcloud builds log \$(gcloud builds list --limit=1 --format='value(id)')"
        return 1 ;;
      *) printf '.' ;;
    esac
    sleep 10
  done
  echo; echo "Build $1 tidak selesai dalam 10 menit."
  return 1
}

expose_svc() {  # $1 = namespace, $2 = deployment, $3 = nama service
  kubectl -n "$1" rollout status "deployment/$2" --timeout=180s
  kubectl -n "$1" get service "$3" >/dev/null 2>&1 || \
    kubectl -n "$1" expose deployment "$2" --name="$3" \
      --type=LoadBalancer --port=8080 --target-port=8080
}

# --------------------------------------------------------------------- Task 4
do_v1() {
  cd "$REPO_DIR"
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1

  local TRIGGERS
  TRIGGERS="$(gcloud builds triggers list --project="$PROJECT" --format='value(name)' 2>/dev/null || true)"
  grep -q sample-app-dev-deploy <<<"$TRIGGERS" || { echo "Trigger sample-app-dev-deploy belum ada. Selesaikan Task 3 dulu."; exit 1; }
  grep -q sample-app-prod-deploy <<<"$TRIGGERS" || { echo "Trigger sample-app-prod-deploy belum ada. Selesaikan Task 3 dulu."; exit 1; }

  step "Task 4 dev: versi v1.0 + image di dev/deployment.yaml"
  git checkout dev
  sed -i "s/<version>/v1.0/g" cloudbuild-dev.yaml
  sed -i "s|<todo>|${IMG_DEV}:v1.0|" dev/deployment.yaml
  grep -n 'hello-cloudbuild-dev' cloudbuild-dev.yaml dev/deployment.yaml
  git add . && git commit -m "Deploy dev v1.0" && git push origin dev
  wait_build "dev v1.0"

  step "Task 4 dev: service dev-deployment-service"
  expose_svc dev development-deployment dev-deployment-service

  step "Task 4 prod: versi v1.0 + image di prod/deployment.yaml"
  git checkout master
  sed -i "s/<version>/v1.0/g" cloudbuild.yaml
  sed -i "s|<todo>|${IMG_PROD}:v1.0|" prod/deployment.yaml
  grep -n 'hello-cloudbuild' cloudbuild.yaml prod/deployment.yaml
  git add . && git commit -m "Deploy prod v1.0" && git push origin master
  wait_build "prod v1.0"

  step "Task 4 prod: service prod-deployment-service"
  expose_svc prod production-deployment prod-deployment-service

  kubectl get svc -n dev; kubectl get svc -n prod
  echo
  echo "Task 4 selesai. Klik Check my progress: \"Deploy the first versions of the application\"."
  echo "Cek juga http://<EXTERNAL-IP>:8080/blue. Lanjut: bash gsp330.sh v2"
}

# main.go: tambahkan route /red dan handler-nya (idempoten).
patch_main_go() {
  grep -q 'redHandler' main.go && { echo "main.go sudah punya redHandler."; return; }
  sed -i 's|\thttp.ListenAndServe(":8080", nil)|\thttp.HandleFunc("/red", redHandler)\n\thttp.ListenAndServe(":8080", nil)|' main.go
  cat >> main.go << 'EOF'

func redHandler(w http.ResponseWriter, r *http.Request) {
	img := image.NewRGBA(image.Rect(0, 0, 100, 100))
	draw.Draw(img, img.Bounds(), &image.Uniform{color.RGBA{255, 0, 0, 255}}, image.ZP, draw.Src)
	w.Header().Set("Content-Type", "image/png")
	png.Encode(w, img)
}
EOF
  grep -q 'redHandler' main.go || { echo "Gagal menambal main.go."; exit 1; }
}

# --------------------------------------------------------------------- Task 5
do_v2() {
  cd "$REPO_DIR"
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1

  step "Task 5 dev: /red + versi v2.0"
  git checkout dev
  patch_main_go
  sed -i "s/:v1.0/:v2.0/g" cloudbuild-dev.yaml dev/deployment.yaml
  git add . && git commit -m "Add red handler, deploy dev v2.0" && git push origin dev
  wait_build "dev v2.0"
  kubectl -n dev rollout status deployment/development-deployment --timeout=180s

  step "Task 5 prod: /red + versi v2.0"
  git checkout master
  patch_main_go
  sed -i "s/:v1.0/:v2.0/g" cloudbuild.yaml prod/deployment.yaml
  git add . && git commit -m "Add red handler, deploy prod v2.0" && git push origin master
  wait_build "prod v2.0"
  kubectl -n prod rollout status deployment/production-deployment --timeout=180s

  kubectl -n dev get deployment development-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
  kubectl -n prod get deployment production-deployment -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
  echo
  echo "Task 5 selesai. Klik Check my progress: \"Deploy the second versions of the application\"."
  echo "Cek juga http://<EXTERNAL-IP>:8080/red. Lanjut: bash gsp330.sh rollback"
}

# --------------------------------------------------------------------- Task 6
do_rollback() {
  gcloud container clusters get-credentials "$CLUSTER" --zone="$ZONE" --project="$PROJECT" >/dev/null 2>&1

  step "Task 6: prod kembali ke v1.0"
  kubectl -n prod set image deployment/production-deployment \
    "production-container=${IMG_PROD}:v1.0"
  kubectl -n prod rollout status deployment/production-deployment --timeout=180s
  kubectl -n prod get deployment production-deployment \
    -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

  cat <<EOF

--------------------------------------------------------------
Task 6 selesai. Klik Check my progress: "Roll back the production deployment".

Verifikasi: http://<prod EXTERNAL-IP>:8080/red harus 404 (v1.0 belum punya
route /red), sedangkan /blue tetap tampil.
  kubectl -n prod get svc prod-deployment-service
--------------------------------------------------------------
EOF
}

case "$PHASE" in
  setup)    do_setup ;;
  repo)     do_repo ;;
  v1)       do_v1 ;;
  v2)       do_v2 ;;
  rollback) do_rollback ;;
  *) echo "Fase tidak dikenal: $PHASE. Pakai: setup|repo|v1|v2|rollback"; exit 1 ;;
esac

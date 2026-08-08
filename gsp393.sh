#!/usr/bin/env bash
# GSP393 - Implement CI/CD Pipelines on Google Cloud: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp393.sh
#   bash gsp393.sh              # Task 1-6
#   # klik SEMUA checkpoint sampai hijau
#   bash gsp393.sh rollback     # Task 7
#
# Checkpoint:
#   Task 2 - Validate that the container was created and added to the repository
#   Task 3 - Verify the delivery pipeline was created
#   Task 3 - Verify that the Cloud Deploy targets have been created
#   Task 4 - Verify the release to the Staging environment
#   Task 5 - Verify the release to the Production environment
#   Task 6 - Verify the new version has been deployed to staging
#   Task 7 - Verify the rollback ran successfully
#
# DUA FASE karena Task 7 mengembalikan cd-staging ke web-app-001, sedangkan
# checkpoint Task 6 memeriksa web-app-002 terpasang di cd-staging. Klik dulu
# checkpoint Task 6 sampai hijau, baru jalankan fase rollback.
#
# LAMA: fase utama 20-28 menit (dua cluster GKE, dua skaffold build, tiga
# rollout). Fase rollback ~2 menit.

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

step() { echo; echo "=============================================================="; echo ">> $*"; echo "=============================================================="; }

PHASE="${1:-main}"
case "$PHASE" in
  main|rollback) ;;
  *) echo "Fase tidak dikenal: $PHASE (main | rollback)"; exit 1 ;;
esac

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
export PROJECT_ID
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
export PROJECT_NUMBER

ask REGION "us-east1" "Region (standar Jooli Inc.)"
export REGION
ask NODE_ZONE "$REGION-b" "Zona node cluster"

REPO="cicd-challenge"
PIPELINE="web-app"
STAGING="cd-staging"
PROD="cd-production"
CONTEXTS=("$STAGING" "$PROD")
SRC="$HOME/cloud-deploy-tutorials/tutorials/base"
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

gcloud config set compute/region "$REGION" >/dev/null
gcloud config set deploy/region "$REGION" >/dev/null

rollout_state() { # $1 = release, $2 = target
  gcloud deploy rollouts list --delivery-pipeline "$PIPELINE" --release "$1" \
    --region="$REGION" --filter="targetId=$2" --format='value(state)' 2>/dev/null | head -n1
}

wait_rollout() { # $1 = release, $2 = target
  local st
  for _ in $(seq 1 90); do
    st="$(rollout_state "$1" "$2")"
    echo "  rollout $1 -> $2 : ${st:-(belum ada)}"
    case "$st" in
      SUCCEEDED|SUCCESS) return 0 ;;
      FAILED|CANCELLED)  echo "Rollout $1 -> $2 gagal."; return 1 ;;
    esac
    sleep 20
  done
  echo "Rollout $1 -> $2 tidak selesai dalam 30 menit."; return 1
}

# ---------------------------------------------------------------- fase rollback
if [[ "$PHASE" == "rollback" ]]; then
  step "Task 7 - rollback $STAGING ke web-app-001"
  cd "$SRC" 2>/dev/null || true

  # JANGAN pakai --rollout-id. Checkpoint mencari nama kanonik yang dibuat
  # Cloud Deploy sendiri (web-app-001-to-cd-staging-0002); rollout dengan nama
  # kustom tetap memulihkan aplikasinya tapi dinilai 0. Terbukti di lab.
  #
  # Idempotensi diukur dari jumlah rollout: cd-staging sudah punya satu rollout
  # web-app-001 dari Task 4, jadi rollback menambah yang kedua.
  COUNT="$(gcloud deploy rollouts list --delivery-pipeline "$PIPELINE" \
    --release web-app-001 --region="$REGION" --filter="targetId=$STAGING" \
    --format='value(name)' 2>/dev/null | wc -l)"
  if [[ "$COUNT" -ge 2 ]]; then
    echo "rollout rollback sudah ada ($COUNT rollout ke $STAGING)"
  else
    # --release menunjuk versi TUJUAN rollback, bukan versi yang sedang jalan.
    gcloud deploy targets rollback "$STAGING" \
      --delivery-pipeline="$PIPELINE" --release=web-app-001 --region="$REGION" -q
  fi
  wait_rollout web-app-001 "$STAGING"

  gcloud deploy rollouts list --delivery-pipeline "$PIPELINE" \
    --release web-app-001 --region="$REGION" \
    --format='table(name.basename(),state)' || true
  kubectl --context "$STAGING" get all -n web-app || true
  cat <<EOF

SELESAI. Klik Check my progress: "Verify the rollback ran successfully".
Nama rollout barunya harus web-app-001-to-$STAGING-0002.

Bukti manual kalau mau: port-forward lalu curl, teksnya harus kembali tanpa "v2".
  kubectl --context $STAGING -n web-app port-forward deployment/leeroy-web 9000:8080
EOF
  exit 0
fi

# ------------------------------------------------------------------- Task 1
step "Task 1 - API, IAM, bucket, Artifact Registry, dua cluster GKE"
gcloud services enable container.googleapis.com clouddeploy.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com >/dev/null

for role in roles/clouddeploy.jobRunner roles/container.developer; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$COMPUTE_SA" --role="$role" --condition=None >/dev/null
done
echo "clouddeploy.jobRunner + container.developer -> $COMPUTE_SA"

gcloud storage buckets describe "gs://${PROJECT_ID}_cloudbuild" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://${PROJECT_ID}_cloudbuild" --project="$PROJECT_ID" || true

if gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1; then
  echo "repository $REPO sudah ada"
else
  gcloud artifacts repositories create "$REPO" \
    --description="Image registry for tutorial web app" \
    --repository-format=docker --location="$REGION"
fi

for c in "${CONTEXTS[@]}"; do
  if gcloud container clusters describe "$c" --region "$REGION" >/dev/null 2>&1; then
    echo "cluster $c sudah ada"
  else
    gcloud container clusters create "$c" --node-locations="$NODE_ZONE" --num-nodes=1 --async
  fi
done
gcloud container clusters list --format="csv(name,status)"

# ------------------------------------------------------------------- Task 2
step "Task 2 - clone sumber dan build image ke $REPO"
if [[ -d "$SRC" ]]; then
  echo "repo tutorial sudah ada"
else
  cd "$HOME"
  git clone -q https://github.com/GoogleCloudPlatform/cloud-deploy-tutorials.git
  git -C "$HOME/cloud-deploy-tutorials" checkout c3cae80 --quiet
fi
cd "$SRC"

# envsubst mengisi PROJECT_ID ke template, makanya variabelnya harus di-export.
envsubst < clouddeploy-config/skaffold.yaml.template > web/skaffold.yaml
cat web/skaffold.yaml

if [[ -s web/artifacts.json ]]; then
  echo "artifacts.json sudah ada, skaffold build dilewati"
else
  (cd web && skaffold build --interactive=false \
    --default-repo "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO" \
    --file-output artifacts.json)
fi
gcloud artifacts docker images list \
  "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO" --include-tags --format='table(package,tags)'

# ------------------------------------------------------------------- Task 3
step "Task 3 - delivery pipeline (dua stage: $STAGING, $PROD)"
cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
sed -i "s/targetId: staging/targetId: $STAGING/" clouddeploy-config/delivery-pipeline.yaml
sed -i "s/targetId: prod/targetId: $PROD/"       clouddeploy-config/delivery-pipeline.yaml
sed -i "/targetId: test/d"                        clouddeploy-config/delivery-pipeline.yaml
cat clouddeploy-config/delivery-pipeline.yaml

gcloud beta deploy apply --file=clouddeploy-config/delivery-pipeline.yaml --region="$REGION"
gcloud beta deploy delivery-pipelines describe "$PIPELINE" --region="$REGION" || true

step "Task 3 - tunggu cluster RUNNING lalu buat target"
for c in "${CONTEXTS[@]}"; do
  until [[ "$(gcloud container clusters describe "$c" --region "$REGION" --format='value(status)' 2>/dev/null)" == "RUNNING" ]]; do
    echo "  $c belum RUNNING, tunggu ..."
    sleep 20
  done
  echo "  $c RUNNING"
done

for CONTEXT in "${CONTEXTS[@]}"; do
  gcloud container clusters get-credentials "$CONTEXT" --region "$REGION"
  kubectl config rename-context "gke_${PROJECT_ID}_${REGION}_${CONTEXT}" "$CONTEXT" 2>/dev/null || true
  kubectl --context "$CONTEXT" apply -f kubernetes-config/web-app-namespace.yaml
done

# Template target bawaan bernama staging dan prod; namanya diganti mengikuti
# nama cluster yang diminta lab.
envsubst < clouddeploy-config/target-staging.yaml.template > "clouddeploy-config/target-$STAGING.yaml"
envsubst < clouddeploy-config/target-prod.yaml.template    > "clouddeploy-config/target-$PROD.yaml"
sed -i "s/staging/$STAGING/" "clouddeploy-config/target-$STAGING.yaml"
sed -i "s/prod/$PROD/"       "clouddeploy-config/target-$PROD.yaml"
cat "clouddeploy-config/target-$STAGING.yaml"
cat "clouddeploy-config/target-$PROD.yaml"

for CONTEXT in "${CONTEXTS[@]}"; do
  gcloud beta deploy apply --file "clouddeploy-config/target-$CONTEXT.yaml" --region="$REGION"
done
gcloud beta deploy targets list --region="$REGION" --format='table(targetId,requireApproval)'

# ------------------------------------------------------------------- Task 4
step "Task 4 - release web-app-001 (otomatis rollout ke $STAGING)"
if gcloud deploy releases describe web-app-001 --delivery-pipeline "$PIPELINE" --region="$REGION" >/dev/null 2>&1; then
  echo "release web-app-001 sudah ada"
else
  gcloud deploy releases create web-app-001 \
    --delivery-pipeline "$PIPELINE" --region="$REGION" \
    --build-artifacts web/artifacts.json --source web/
fi
wait_rollout web-app-001 "$STAGING"

# ------------------------------------------------------------------- Task 5
step "Task 5 - promote ke $PROD (butuh approval)"
if [[ "$(rollout_state web-app-001 "$PROD")" =~ ^(SUCCEEDED|SUCCESS)$ ]]; then
  echo "$PROD sudah ter-deploy"
else
  [[ -n "$(rollout_state web-app-001 "$PROD")" ]] || \
    gcloud deploy releases promote --delivery-pipeline "$PIPELINE" \
      --release web-app-001 --region="$REGION" -q

  # Nama rollout diambil dari API, bukan ditebak — nomor urutnya bertambah
  # kalau promote pernah diulang.
  ROLLOUT=""
  for _ in $(seq 1 15); do
    ROLLOUT="$(gcloud deploy rollouts list --delivery-pipeline "$PIPELINE" \
      --release web-app-001 --region="$REGION" \
      --filter="targetId=$PROD AND state=PENDING_APPROVAL" \
      --format='value(name)' 2>/dev/null | head -n1)"
    [[ -n "$ROLLOUT" ]] && break
    echo "  menunggu rollout $PROD masuk PENDING_APPROVAL ..."
    sleep 10
  done
  [[ -n "$ROLLOUT" ]] || { echo "Rollout $PROD tidak muncul."; exit 1; }

  gcloud deploy rollouts approve "${ROLLOUT##*/}" \
    --delivery-pipeline "$PIPELINE" --release web-app-001 --region="$REGION" -q
  wait_rollout web-app-001 "$PROD"
fi

# ------------------------------------------------------------------- Task 6
step "Task 6 - ubah app.go jadi v2, build ulang, release web-app-002"
# Cocokkan dari 'fmt.Fprintf' ke kanan supaya indentasi tab di file Go tetap utuh.
sed -i 's|fmt.Fprintf(w, "leeroooooy app.*|fmt.Fprintf(w, "leeroooooy app v2!!\\n")|' \
  web/leeroy-app/app.go
grep -n 'leeroooooy app' web/leeroy-app/app.go

if gcloud deploy releases describe web-app-002 --delivery-pipeline "$PIPELINE" --region="$REGION" >/dev/null 2>&1; then
  echo "release web-app-002 sudah ada"
else
  (cd web && skaffold build --interactive=false \
    --default-repo "$REGION-docker.pkg.dev/$PROJECT_ID/$REPO" \
    --file-output artifacts.json)
  gcloud deploy releases create web-app-002 \
    --delivery-pipeline "$PIPELINE" --region="$REGION" \
    --build-artifacts web/artifacts.json --source web/
fi
wait_rollout web-app-002 "$STAGING"
kubectl --context "$STAGING" get all -n web-app

cat <<EOF

SELESAI fase utama. Klik Check my progress untuk enam checkpoint pertama:
  - Validate that the container was created and added to the repository
  - Verify the delivery pipeline was created
  - Verify that the Cloud Deploy targets have been created
  - Verify the release to the Staging environment
  - Verify the release to the Production environment
  - Verify the new version has been deployed to staging

PENTING: tunggu keenamnya HIJAU dulu. Fase berikutnya mengembalikan $STAGING
ke web-app-001, sedangkan checkpoint Task 6 memeriksa web-app-002 di sana.

  bash gsp393.sh rollback
EOF

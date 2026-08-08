#!/usr/bin/env bash
# GSP1079 - Continuous Delivery with Google Cloud Deploy
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp1079.sh
#   bash gsp1079.sh
#
# Checkpoint (8):
#   Task 2 - Create three GKE clusters
#   Task 3 - Create the web-app repository
#   Task 4 - Build and deploy the container images to the Artifact Registry
#   Task 5 - Create the delivery pipeline
#   Task 6 - Configure the deployment targets
#   Task 7 - Create a release
#   Task 8 - Promote the application to staging
#   Task 9 - Promote the application to prod
#
# Satu fase, 18-25 menit. Yang lama: tiga cluster GKE (dibuat --async lalu
# ditunggu), skaffold build lewat Cloud Build, dan tiga rollout berurutan.
# Semua checkpoint bisa diklik sekaligus di akhir.
#
# Idempoten: aman diulang kalau putus di tengah.

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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
export PROJECT_ID

ask REGION "europe-west1" "Region (cocokkan dengan panel lab)"
export REGION
ask NODE_ZONE "$REGION-c" "Zona node cluster"

RELEASE="web-app-001"
PIPELINE="web-app"
CONTEXTS=(test staging prod)
SRC="$HOME/cloud-deploy-tutorials/tutorials/base"

gcloud config set compute/region "$REGION" >/dev/null
gcloud config set deploy/region "$REGION" >/dev/null

# ------------------------------------------------------------------- Task 2
step "Task 2 - tiga cluster GKE (async)"
gcloud services enable container.googleapis.com clouddeploy.googleapis.com \
  artifactregistry.googleapis.com cloudbuild.googleapis.com >/dev/null

for c in "${CONTEXTS[@]}"; do
  if gcloud container clusters describe "$c" --region "$REGION" >/dev/null 2>&1; then
    echo "cluster $c sudah ada"
  else
    gcloud container clusters create "$c" --node-locations="$NODE_ZONE" --num-nodes=1 --async
  fi
done
gcloud container clusters list --format="csv(name,status)"

# ------------------------------------------------------------------- Task 3
step "Task 3 - Artifact Registry web-app"
if gcloud artifacts repositories describe web-app --location="$REGION" >/dev/null 2>&1; then
  echo "repository web-app sudah ada"
else
  gcloud artifacts repositories create web-app \
    --description="Image registry for tutorial web app" \
    --repository-format=docker --location="$REGION"
fi

# ------------------------------------------------------------------- Task 4
step "Task 4 - clone sumber dan build image lewat Skaffold"
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

# Bucket sumber dan log Cloud Build. Namanya global, jadi kegagalan "sudah ada"
# diabaikan — biasanya karena run sebelumnya.
gcloud storage buckets describe "gs://${PROJECT_ID}_cloudbuild" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://${PROJECT_ID}_cloudbuild" --project="$PROJECT_ID" || true

if [[ -s web/artifacts.json ]]; then
  echo "artifacts.json sudah ada, skaffold build dilewati"
else
  (cd web && skaffold build --interactive=false \
    --default-repo "$REGION-docker.pkg.dev/$PROJECT_ID/web-app" \
    --file-output artifacts.json)
fi
gcloud artifacts docker images list \
  "$REGION-docker.pkg.dev/$PROJECT_ID/web-app" --include-tags --format='table(package,tags)'

# ------------------------------------------------------------------- Task 5
step "Task 5 - delivery pipeline"
cp clouddeploy-config/delivery-pipeline.yaml.template clouddeploy-config/delivery-pipeline.yaml
gcloud beta deploy apply --file=clouddeploy-config/delivery-pipeline.yaml --region="$REGION"
# Wajar kalau describe mengeluh "Unable to get target ..." — targetnya memang
# baru dibuat di Task 6.
gcloud beta deploy delivery-pipelines describe "$PIPELINE" --region="$REGION" || true

# ------------------------------------------------------------------- Task 6
step "Task 6 - tunggu cluster RUNNING lalu buat target"
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
done

for CONTEXT in "${CONTEXTS[@]}"; do
  kubectl --context "$CONTEXT" apply -f kubernetes-config/web-app-namespace.yaml
done

for CONTEXT in "${CONTEXTS[@]}"; do
  envsubst < "clouddeploy-config/target-$CONTEXT.yaml.template" > "clouddeploy-config/target-$CONTEXT.yaml"
  gcloud beta deploy apply --file "clouddeploy-config/target-$CONTEXT.yaml" --region="$REGION"
done
gcloud beta deploy targets list --region="$REGION" --format='table(targetId,requireApproval)'

# --------------------------------------------------------------- helper poll
# Rollout pertama butuh beberapa menit: Cloud Deploy me-render manifest untuk
# semua target sekaligus saat release dibuat.
rollout_state() {
  gcloud beta deploy rollouts list --delivery-pipeline "$PIPELINE" --release "$RELEASE" \
    --region="$REGION" --filter="targetId=$1" --format='value(state)' 2>/dev/null | head -n1
}

wait_rollout() {
  local target="$1" st
  for _ in $(seq 1 90); do
    st="$(rollout_state "$target")"
    echo "  rollout -> $target : ${st:-(belum ada)}"
    case "$st" in
      SUCCEEDED|SUCCESS) return 0 ;;
      FAILED|CANCELLED)  echo "Rollout ke $target gagal."; return 1 ;;
    esac
    sleep 20
  done
  echo "Rollout ke $target tidak selesai dalam 30 menit."; return 1
}

# ------------------------------------------------------------------- Task 7
step "Task 7 - release $RELEASE"
if gcloud beta deploy releases describe "$RELEASE" --delivery-pipeline "$PIPELINE" --region="$REGION" >/dev/null 2>&1; then
  echo "release sudah ada, create dilewati"
else
  gcloud beta deploy releases create "$RELEASE" \
    --delivery-pipeline "$PIPELINE" --region="$REGION" \
    --build-artifacts web/artifacts.json --source web/
fi
wait_rollout test
kubectl --context test get all -n web-app

# ------------------------------------------------------------------- Task 8
step "Task 8 - promote ke staging"
if [[ "$(rollout_state staging)" =~ ^(SUCCEEDED|SUCCESS)$ ]]; then
  echo "staging sudah ter-deploy"
else
  gcloud beta deploy releases promote --delivery-pipeline "$PIPELINE" \
    --release "$RELEASE" --region="$REGION" -q
  wait_rollout staging
fi

# ------------------------------------------------------------------- Task 9
step "Task 9 - promote ke prod (butuh approval)"
if [[ "$(rollout_state prod)" =~ ^(SUCCEEDED|SUCCESS)$ ]]; then
  echo "prod sudah ter-deploy"
else
  [[ -n "$(rollout_state prod)" ]] || \
    gcloud beta deploy releases promote --delivery-pipeline "$PIPELINE" \
      --release "$RELEASE" --region="$REGION" -q

  # Nama rollout diambil dari API, bukan ditebak "web-app-001-to-prod-0001" —
  # nomor urutnya bertambah kalau promote pernah diulang.
  ROLLOUT=""
  for _ in $(seq 1 15); do
    ROLLOUT="$(gcloud beta deploy rollouts list --delivery-pipeline "$PIPELINE" \
      --release "$RELEASE" --region="$REGION" \
      --filter="targetId=prod AND state=PENDING_APPROVAL" \
      --format='value(name)' 2>/dev/null | head -n1)"
    [[ -n "$ROLLOUT" ]] && break
    echo "  menunggu rollout prod masuk PENDING_APPROVAL ..."
    sleep 10
  done
  [[ -n "$ROLLOUT" ]] || { echo "Rollout prod tidak muncul. Cek 'gcloud beta deploy rollouts list'."; exit 1; }

  gcloud beta deploy rollouts approve "${ROLLOUT##*/}" \
    --delivery-pipeline "$PIPELINE" --release "$RELEASE" --region="$REGION" -q
  wait_rollout prod
fi
kubectl --context prod get all -n web-app

cat <<EOF

SELESAI! Klik Check my progress untuk kedelapan checkpoint:
  - Create three GKE clusters                                  (Task 2)
  - Create the web-app repository                              (Task 3)
  - Build and deploy the container images to Artifact Registry (Task 4)
  - Create the delivery pipeline                               (Task 5)
  - Configure the deployment targets                           (Task 6)
  - Create a release                                           (Task 7)
  - Promote the application to staging                         (Task 8)
  - Promote the application to prod                            (Task 9)
EOF

#!/usr/bin/env bash
# GSP1077 - Google Kubernetes Engine Pipeline using Cloud Build
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp1077.sh
#   bash gsp1077.sh setup     # Task 1-3: API, Artifact Registry, cluster, repo GitHub, image pertama
#   #   -> install Cloud Build GitHub App lewat console (sekali, wajib manual)
#   bash gsp1077.sh ci        # Task 4: trigger CI + push pertama
#   bash gsp1077.sh deliver   # Task 5-6: SSH key, Secret Manager, repo env, trigger CD
#
# Checkpoint:
#   1 (20 pts) - Enable services, create an artifact registry and the GKE cluster  (setup)
#   2 (20 pts) - Create the container image with Cloud Build                       (setup)
#   3 (20 pts) - Create the Continuous Integration (CI) Pipeline                   (ci)
#   4 (20 pts) - Accessing GitHub from a build via SSH keys                        (deliver)
#   5 (20 pts) - Create the Test Environment and CD Pipeline                       (deliver)
#
# DUA langkah wajib manual, keduanya OAuth di browser dan tidak punya API:
#   1. `gh auth login`                  - script berhenti dan menyuruh menjalankannya
#   2. Install "Google Cloud Build" GitHub App ke kedua repo - lewat console,
#      di antara fase `setup` dan `ci`. Tanpa ini `triggers create github` menolak
#      dengan "Repository mapping does not exist".
#
# Task 8 (ubah teks jadi "Hello Cloud Build") dan Task 9 (rollback) tidak
# di-score. Perintahnya dicetak di akhir fase `deliver`.
#
# LAMA: setup ~10 menit (cluster GKE), ci ~3 menit, deliver ~6 menit.

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

PHASE="${1:-}"
case "$PHASE" in
  setup|ci|deliver) ;;
  *) echo "Pakai: bash gsp1077.sh <setup|ci|deliver>"; exit 1 ;;
esac

ask REGION "us-east4" "Region (cocokkan dengan panel lab)"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

REPO="my-repository"
CLUSTER="hello-cloudbuild"
APP_DIR="$HOME/hello-cloudbuild-app"
ENV_DIR="$HOME/hello-cloudbuild-env"
KEY_DIR="$HOME/workingdir"
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/hello-cloudbuild"
COMPUTE_SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"
CB_SA="$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"

echo "Fase    : $PHASE"
echo "Project : $PROJECT_ID ($PROJECT_NUMBER)"
echo "Region  : $REGION"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# gh dipakai untuk bikin repo, setup credential git, dan pasang deploy key.
# Cloud Shell biasanya sudah punya gh; kalau tidak, pasang lewat webi.
setup_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    step "Pasang GitHub CLI"
    curl -sS https://webi.sh/gh | sh
    # shellcheck disable=SC1090
    [[ -f "$HOME/.config/envman/PATH.env" ]] && source "$HOME/.config/envman/PATH.env"
  fi
  if ! gh auth status >/dev/null 2>&1; then
    cat <<'MSG'

GitHub CLI belum login. Jalankan sendiri (interaktif, buka browser):

    gh auth login

  Pilih: GitHub.com -> HTTPS -> Yes (authenticate Git) -> Login with a web browser

Lalu ulangi script ini.
MSG
    exit 1
  fi
  GITHUB_USERNAME="$(gh api user -q '.login')"
  git config --global user.name "$GITHUB_USERNAME"
  git config --global user.email "${USER_EMAIL:-$(gcloud config get-value account 2>/dev/null)}"
  gh auth setup-git
  echo "GitHub user: $GITHUB_USERNAME"
}

# Salin kode contoh lalu samakan region-nya dengan lab. $1 = direktori tujuan.
fetch_sample() {
  local dir="$1"
  mkdir -p "$dir"
  if [[ ! -f "$dir/app.py" ]]; then
    gcloud storage cp -r "gs://spls/gsp1077/gke-gitops-tutorial-cloudbuild/*" "$dir"
  fi
  local f
  for f in cloudbuild.yaml cloudbuild-delivery.yaml cloudbuild-trigger-cd.yaml kubernetes.yaml.tpl; do
    [[ -f "$dir/$f" ]] && sed -i "s/us-central1/$REGION/g" "$dir/$f"
  done
  # Cloud Build menolak build dengan service account custom kalau logging tidak
  # ditentukan. cloudbuild.yaml bawaan bucket belum tentu punya blok ini.
  grep -q 'logging:' "$dir/cloudbuild.yaml" || printf '\noptions:\n  logging: CLOUD_LOGGING_ONLY\n' >> "$dir/cloudbuild.yaml"
}

# git init + commit yang aman diulang. $1 = direktori, $2 = nama repo GitHub.
git_bootstrap() {
  local dir="$1" repo="$2"
  cd "$dir"
  [[ -d .git ]] || git init -q -b master
  git remote get-url google >/dev/null 2>&1 || \
    git remote add google "https://github.com/${GITHUB_USERNAME}/${repo}"
  git add -A
  git diff --cached --quiet || git commit -q -m "initial commit"
}

# ==================================================================== setup
if [[ "$PHASE" == "setup" ]]; then
  step "Task 1: Enable API (GKE, Cloud Build, Secret Manager, Artifact Analysis)"
  gcloud services enable container.googleapis.com \
    cloudbuild.googleapis.com \
    secretmanager.googleapis.com \
    containeranalysis.googleapis.com

  gcloud config set compute/region "$REGION" >/dev/null

  step "Task 1: Artifact Registry $REPO"
  if gcloud artifacts repositories describe "$REPO" --location="$REGION" >/dev/null 2>&1; then
    echo "sudah ada, dilewati"
  else
    gcloud artifacts repositories create "$REPO" --repository-format=docker --location="$REGION"
  fi

  step "Task 1: Cluster GKE $CLUSTER (dibuat async, ~7 menit)"
  if gcloud container clusters describe "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
    echo "sudah ada, dilewati"
  else
    gcloud container clusters create "$CLUSTER" --num-nodes 1 --region "$REGION" --async
  fi

  setup_gh

  step "Task 2: Repo GitHub hello-cloudbuild-app dan hello-cloudbuild-env"
  for r in hello-cloudbuild-app hello-cloudbuild-env; do
    if gh repo view "${GITHUB_USERNAME}/${r}" >/dev/null 2>&1; then
      echo "$r sudah ada"
    else
      gh repo create "$r" --private
    fi
  done

  step "Task 2: Ambil kode contoh"
  fetch_sample "$APP_DIR"
  git_bootstrap "$APP_DIR" hello-cloudbuild-app

  step "Task 3: Build image pertama lewat Cloud Build"
  COMMIT_ID="$(git -C "$APP_DIR" rev-parse --short=7 HEAD)"
  (cd "$APP_DIR" && gcloud builds submit --tag="${IMAGE}:${COMMIT_ID}" .)

  step "Tunggu cluster $CLUSTER siap"
  until [[ "$(gcloud container clusters describe "$CLUSTER" --region "$REGION" --format='value(status)' 2>/dev/null)" == "RUNNING" ]]; do
    echo "  status: $(gcloud container clusters describe "$CLUSTER" --region "$REGION" --format='value(status)' 2>/dev/null) ..."
    sleep 20
  done
  echo "cluster RUNNING"

  cat <<MSG

==============================================================
SELESAI fase setup. Klik Check my progress untuk verifikasi:
  - Enable services, create an artifact registry and the GKE cluster
  - Create the container image with Cloud Build

LANGKAH MANUAL sebelum fase berikutnya (OAuth, tidak ada API-nya):

  1. Buka console -> cari "Cloud Build" -> Triggers -> Region $REGION
  2. Create Trigger -> bagian Source -> Connect new repository
  3. Pilih "GitHub (Cloud Build GitHub App)" -> Continue -> login GitHub
  4. Kalau muncul "GitHub App is not installed": klik Install Google Cloud Build,
     pilih Only select repositories, centang KEDUA repo:
         ${GITHUB_USERNAME}/hello-cloudbuild-app
         ${GITHUB_USERNAME}/hello-cloudbuild-env
     lalu Install / Save.
  5. Centang "I understand that GitHub content..." -> Connect.
  6. TUTUP form Create Trigger (jangan diisi, biar dibuat script).

Lalu jalankan:  bash gsp1077.sh ci
==============================================================
MSG
fi

# ======================================================================= ci
if [[ "$PHASE" == "ci" ]]; then
  setup_gh

  step "Task 4: Trigger hello-cloudbuild (push ke branch apa pun)"
  if gcloud builds triggers describe hello-cloudbuild --region="$REGION" >/dev/null 2>&1; then
    echo "trigger sudah ada, dilewati"
  else
    gcloud builds triggers create github \
      --name=hello-cloudbuild \
      --region="$REGION" \
      --repo-owner="$GITHUB_USERNAME" \
      --repo-name=hello-cloudbuild-app \
      --branch-pattern='.*' \
      --build-config=cloudbuild.yaml \
      --service-account="projects/${PROJECT_ID}/serviceAccounts/${COMPUTE_SA}"
  fi

  step "Task 4: Push kode aplikasi supaya trigger jalan"
  cd "$APP_DIR"
  git add -A
  git diff --cached --quiet || git commit -q -m "Trigger CI pipeline"
  git push google master

  cat <<MSG

==============================================================
SELESAI fase ci. Cloud Build sedang menjalankan pipeline CI.
Pantau: Cloud Build -> Dashboard (region $REGION), atau

    gcloud builds list --region=$REGION --limit=3

Klik Check my progress:
  - Create the Continuous Integration (CI) Pipeline

Lanjut:  bash gsp1077.sh deliver
==============================================================
MSG
fi

# ================================================================== deliver
if [[ "$PHASE" == "deliver" ]]; then
  setup_gh

  step "Task 5: SSH key + Secret Manager + deploy key"
  HAS_SECRET=0; HAS_DEPLOYKEY=0
  gcloud secrets describe ssh_key_secret >/dev/null 2>&1 && HAS_SECRET=1
  gh repo deploy-key list -R "${GITHUB_USERNAME}/hello-cloudbuild-env" 2>/dev/null | grep -q 'SSH_KEY' && HAS_DEPLOYKEY=1

  if [[ "$HAS_SECRET" == 1 && "$HAS_DEPLOYKEY" == 1 ]]; then
    echo "secret dan deploy key sudah ada, dilewati"
  else
    # Pasangan kunci harus cocok. Kalau salah satu sisi hilang, buat ulang keduanya.
    [[ "$HAS_SECRET" == 1 ]] && gcloud secrets delete ssh_key_secret -q
    if [[ "$HAS_DEPLOYKEY" == 1 ]]; then
      { gh repo deploy-key list -R "${GITHUB_USERNAME}/hello-cloudbuild-env" \
          --json id,title -q '.[] | select(.title=="SSH_KEY") | .id' 2>/dev/null || true; } \
        | while read -r id; do
            gh repo deploy-key delete "$id" -R "${GITHUB_USERNAME}/hello-cloudbuild-env" || true
          done
    fi
    rm -rf "$KEY_DIR"
    mkdir -p "$KEY_DIR"
    ssh-keygen -t rsa -b 4096 -N '' -f "$KEY_DIR/id_github" -C "$(gcloud config get-value account 2>/dev/null)"
    gcloud secrets create ssh_key_secret --replication-policy=automatic --data-file="$KEY_DIR/id_github"
    gh repo deploy-key add "$KEY_DIR/id_github.pub" \
      -R "${GITHUB_USERNAME}/hello-cloudbuild-env" -t SSH_KEY -w
    rm -f "$KEY_DIR"/id_github*
  fi

  step "Task 5-6: IAM untuk service account build"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${COMPUTE_SA}" \
    --role=roles/secretmanager.secretAccessor --condition=None >/dev/null
  # Trigger memakai compute default SA, tapi lab juga memberi peran ini ke SA
  # cloudbuild lama. Diberikan ke keduanya supaya deploy tidak tergantung mana
  # yang dipakai build.
  for sa in "$COMPUTE_SA" "$CB_SA"; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${sa}" \
      --role=roles/container.developer --condition=None >/dev/null
  done
  echo "secretAccessor + container.developer terpasang"

  step "Task 6: Tunggu cluster $CLUSTER siap"
  until [[ "$(gcloud container clusters describe "$CLUSTER" --region "$REGION" --format='value(status)' 2>/dev/null)" == "RUNNING" ]]; do
    echo "  belum RUNNING, tunggu ..."
    sleep 20
  done

  step "Task 6: Siapkan repo hello-cloudbuild-env (master, production, candidate)"
  fetch_sample "$ENV_DIR"
  cd "$ENV_DIR"
  ssh-keyscan -t rsa github.com > known_hosts.github 2>/dev/null
  chmod +x known_hosts.github
  git_bootstrap "$ENV_DIR" hello-cloudbuild-env
  git push -q google master

  # cloudbuild.yaml versi CD: apply manifest ke cluster, lalu salin manifest
  # yang berhasil ke branch production.
  cat > "$ENV_DIR/cloudbuild.yaml" <<'YAML'
steps:
# Deploy versi baru image ke cluster hello-cloudbuild
- name: 'gcr.io/cloud-builders/kubectl'
  id: Deploy
  args:
  - 'apply'
  - '-f'
  - 'kubernetes.yaml'
  env:
  - 'CLOUDSDK_COMPUTE_REGION=LAB_REGION'
  - 'CLOUDSDK_CONTAINER_CLUSTER=hello-cloudbuild'

# Ambil private key dari Secret Manager dan siapkan SSH
- name: 'gcr.io/cloud-builders/git'
  id: Setup SSH
  secretEnv: ['SSH_KEY']
  entrypoint: 'bash'
  args:
  - -c
  - |
    echo "$$SSH_KEY" >> /root/.ssh/id_rsa
    chmod 400 /root/.ssh/id_rsa
    cp known_hosts.github /root/.ssh/known_hosts
  volumes:
  - name: 'ssh'
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/git'
  id: Clone env repo
  args:
  - clone
  - --recurse-submodules
  - git@github.com:LAB_GITHUB_USER/hello-cloudbuild-env.git
  volumes:
  - name: ssh
    path: /root/.ssh

# Salin manifest yang barusan berhasil di-apply ke branch production
- name: 'gcr.io/cloud-builders/gcloud'
  id: Copy to production branch
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    set -x && \
    cd hello-cloudbuild-env && \
    git config user.email $(gcloud auth list --filter=status:ACTIVE --format='value(account)') && \
    git config user.name "Cloud Build" && \
    git fetch origin production && \
    git checkout production && \
    git checkout $COMMIT_SHA kubernetes.yaml && \
    git commit -m "Manifest from commit $COMMIT_SHA
    $(git log --format=%B -n 1 $COMMIT_SHA)" && \
    git push origin production
  volumes:
  - name: ssh
    path: /root/.ssh

availableSecrets:
  secretManager:
  - versionName: projects/LAB_PROJECT_NUMBER/secrets/ssh_key_secret/versions/1
    env: 'SSH_KEY'

options:
  logging: CLOUD_LOGGING_ONLY
YAML

  # Branch production dan candidate sama-sama berisi cloudbuild.yaml versi CD.
  git checkout -q -B production
  sed -i -e "s/LAB_REGION/$REGION/g" -e "s/LAB_GITHUB_USER/$GITHUB_USERNAME/g" \
    -e "s/LAB_PROJECT_NUMBER/$PROJECT_NUMBER/g" "$ENV_DIR/cloudbuild.yaml"
  git add cloudbuild.yaml
  git diff --cached --quiet || git commit -q -m "Create cloudbuild.yaml for deployment"
  git checkout -q -B candidate
  git push -q google production
  git push -q google candidate
  echo "branch production dan candidate terkirim"

  # Trigger CD dibuat SETELAH push, supaya push branch candidate yang masih
  # tanpa kubernetes.yaml tidak menjalankan build yang pasti gagal.
  step "Task 6: Trigger hello-cloudbuild-deploy (branch ^candidate\$)"
  if gcloud builds triggers describe hello-cloudbuild-deploy --region="$REGION" >/dev/null 2>&1; then
    echo "trigger sudah ada, dilewati"
  else
    gcloud builds triggers create github \
      --name=hello-cloudbuild-deploy \
      --region="$REGION" \
      --repo-owner="$GITHUB_USERNAME" \
      --repo-name=hello-cloudbuild-env \
      --branch-pattern='^candidate$' \
      --build-config=cloudbuild.yaml \
      --service-account="projects/${PROJECT_ID}/serviceAccounts/${COMPUTE_SA}"
  fi

  step "Task 6: known_hosts.github di repo app"
  cd "$APP_DIR"
  ssh-keyscan -t rsa github.com > known_hosts.github 2>/dev/null
  chmod +x known_hosts.github
  git add known_hosts.github
  git diff --cached --quiet || git commit -q -m "Adding known_host file."
  git push -q google master

  # cloudbuild.yaml versi CI penuh: test, build, push, lalu render manifest baru
  # dan dorong ke branch candidate repo env — itu yang memicu pipeline CD.
  cat > "$APP_DIR/cloudbuild.yaml" <<'YAML'
steps:
# Unit test
- name: 'python:3.7-slim'
  id: Test
  entrypoint: /bin/sh
  args:
  - -c
  - 'pip install flask && python test_app.py -v'

- name: 'gcr.io/cloud-builders/docker'
  id: Build
  args:
  - 'build'
  - '-t'
  - 'LAB_REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:$SHORT_SHA'
  - '.'

- name: 'gcr.io/cloud-builders/docker'
  id: Push
  args:
  - 'push'
  - 'LAB_REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:$SHORT_SHA'

# Ambil private key dari Secret Manager dan siapkan SSH
- name: 'gcr.io/cloud-builders/git'
  id: Setup SSH
  secretEnv: ['SSH_KEY']
  entrypoint: 'bash'
  args:
  - -c
  - |
    echo "$$SSH_KEY" >> /root/.ssh/id_rsa
    chmod 400 /root/.ssh/id_rsa
    cp known_hosts.github /root/.ssh/known_hosts
  volumes:
  - name: 'ssh'
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/git'
  id: Clone env repo
  args:
  - clone
  - --recurse-submodules
  - git@github.com:LAB_GITHUB_USER/hello-cloudbuild-env.git
  volumes:
  - name: ssh
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/gcloud'
  id: Change directory
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    cd hello-cloudbuild-env && \
    git checkout candidate && \
    git config user.email $(gcloud auth list --filter=status:ACTIVE --format='value(account)') && \
    git config user.name "Cloud Build"
  volumes:
  - name: ssh
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/gcloud'
  id: Generate manifest
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
     sed "s/GOOGLE_CLOUD_PROJECT/${PROJECT_ID}/g" kubernetes.yaml.tpl | \
     sed "s/COMMIT_SHA/${SHORT_SHA}/g" > hello-cloudbuild-env/kubernetes.yaml
  volumes:
  - name: ssh
    path: /root/.ssh

- name: 'gcr.io/cloud-builders/gcloud'
  id: Push manifest
  entrypoint: /bin/sh
  args:
  - '-c'
  - |
    set -x && \
    cd hello-cloudbuild-env && \
    git add kubernetes.yaml && \
    git commit -m "Deploying image LAB_REGION-docker.pkg.dev/$PROJECT_ID/my-repository/hello-cloudbuild:${SHORT_SHA}
    Built from commit ${COMMIT_SHA} of repository hello-cloudbuild-app
    Author: $(git log --format='%an <%ae>' -n 1 HEAD)" && \
    git push origin candidate
  volumes:
  - name: ssh
    path: /root/.ssh

availableSecrets:
  secretManager:
  - versionName: projects/LAB_PROJECT_NUMBER/secrets/ssh_key_secret/versions/1
    env: 'SSH_KEY'

options:
  logging: CLOUD_LOGGING_ONLY
YAML
  sed -i -e "s/LAB_REGION/$REGION/g" -e "s/LAB_GITHUB_USER/$GITHUB_USERNAME/g" \
    -e "s/LAB_PROJECT_NUMBER/$PROJECT_NUMBER/g" "$APP_DIR/cloudbuild.yaml"

  step "Task 6: Push cloudbuild.yaml versi CI+CD (memicu pipeline penuh)"
  git add cloudbuild.yaml
  git diff --cached --quiet || git commit -q -m "Trigger CD pipeline"
  git push google master

  cat <<MSG

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  - Accessing GitHub from a build via SSH keys
  - Create the Test Environment and CD Pipeline

Pipeline penuh sedang jalan (CI ~3 menit, lalu CD ~2 menit):

    gcloud builds list --region=$REGION --limit=5

Task 7-8 (tidak di-score) — cek aplikasinya:
    kubectl get svc hello-cloudbuild -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  (butuh kredensial: gcloud container clusters get-credentials $CLUSTER --region $REGION)

    curl http://<EXTERNAL-IP>            # Hello World!
    cd $APP_DIR
    sed -i 's/Hello World/Hello Cloud Build/g' app.py test_app.py
    git commit -am "Hello Cloud Build" && git push google master
    curl http://<EXTERNAL-IP>            # Hello Cloud Build!

Task 9 rollback (manual, UI): Cloud Build > Dashboard > Build History repo
hello-cloudbuild-env > pilih build kedua terbaru > Rebuild.
==============================================================
MSG
fi

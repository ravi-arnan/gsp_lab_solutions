#!/usr/bin/env bash
# Arcade Buildathon (course_templates/1968) - Steps 1-3 Setup
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arcade-buildathon-7b4m.sh
#   bash arcade-buildathon-7b4m.sh
#
# Langkah yang dijalankan:
#   Step 1 - Buat ~/arcade-buildathon-7b4m/requirements.txt
#   Step 2 - Buat ~/arcade-buildathon-7b4m/Dockerfile
#   Step 3 - Enable APIs, tunggu service account, grant IAM & verifikasi billing

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"

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

if [[ -z "$PROJECT_ID" ]]; then
  ask PROJECT_ID "" "Masukkan Project ID (yang terhubung ke GDP Event Credit)"
fi
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <PROJECT_ID>"; exit 1; }

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
echo "Project ID : $PROJECT_ID"

WORKDIR="$HOME/arcade-buildathon-7b4m"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ----------------------------------------------------------------- Step 1
step "Step 1: Membuat requirements.txt di $WORKDIR"
cat <<'EOF' > "$WORKDIR/requirements.txt"
Flask==3.0.3
gunicorn==22.0.0
google-genai==2.28.0
requests==2.34.2
google-cloud-bigquery==3.46.1
pydantic==2.13.5
EOF
echo "requirements.txt selesai ditulis."

# ----------------------------------------------------------------- Step 2
step "Step 2: Membuat Dockerfile di $WORKDIR"
cat <<'EOF' > "$WORKDIR/Dockerfile"
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD exec gunicorn --bind 0.0.0.0:8080 --workers 1 --threads 8 --timeout 0 main:app
EOF
echo "Dockerfile selesai ditulis."

# ----------------------------------------------------------------- Step 3
step "Step 3: Enable APIs, IAM permissions, dan cek billing"
# Fungsi bawaan lab memakai unset vars ([ $G ]) dan ((n++)) saat n=0,
# sehingga harus berjalan dengan set +euo pipefail.
set +euo pipefail

sp() {
  m=$1; shift; touch /tmp/sp.on
  ( f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); i=0; while [ -f /tmp/sp.on ]; do printf "\r%s %s " "${f[i++%10]}" "$m"; sleep 0.2; done & )
  trap 'rm -f /tmp/sp.on' INT
  "$@" >/tmp/s3.log 2>&1; s=$?
  rm -f /tmp/sp.on; trap - INT; sleep 0.3; printf "\r\033[K"; return $s
}

s3() {
  ER=
  P=$(gcloud config get-value project 2>/dev/null)
  A=$(gcloud config get-value account 2>/dev/null)
  [ -z "$P" ] && { echo "[ERROR] No project selected. Select your project in Cloud Shell, then run this block again."; return 1; }
  if ! sp "Enabling the APIs for $P" gcloud services enable compute.googleapis.com aiplatform.googleapis.com cloudbilling.googleapis.com; then
    echo "[ERROR] Could not enable the APIs:"; tail -n 5 /tmp/s3.log
    echo "If it mentions billing, link your credit: https://console.cloud.google.com/billing/linkedaccount?project=$P"; return 1
  fi
  SA=$(gcloud projects describe "$P" --format='value(projectNumber)')-compute@developer.gserviceaccount.com
  wsa() { for i in {1..12}; do gcloud iam service-accounts describe "$SA" && return; sleep 5; done; }
  sp "Waiting for your agent's service account" wsa

  chk() {
    l=$1 m=$2; shift 2; n=0 x=
    for r; do
      if grep -qixF "$m $r" <<<"$T"; then ((n++)); else x+=" $r"
      [ $G ] && { O=$(gcloud projects add-iam-policy-binding "$P" --member="$m" --role="roles/$r" --condition=None 2>&1 >/dev/null) || ER=$O; }
      fi
    done
    [ -n "$x" ] && F=1; [ $G ] && return
    c=; (($#>1)) && c=" ($n/$#)"
    [ -z "$x" ] && echo "[OK] $l$c" || echo "[MISSING] $l${c:+, missing:$x}"
  }

  rd() {
    G=$1 F=
    T=$(gcloud projects get-iam-policy "$P" --flatten='bindings[].members' --format='value(bindings.members,bindings.role)' 2>/dev/null | sed 's#\troles/# #')
    if [ -z "$G" ]; then
      B=$(gcloud billing projects describe "$P" --format='value(billingAccountName)' 2>/dev/null | sed 's#.*/##')
      N=$([ -n "$B" ] && gcloud billing accounts describe "$B" --format='value(displayName)' 2>/dev/null)
      [ -n "$B" ] && echo "[OK] Billing linked: ${N:-$B}" || { echo "[MISSING] No billing account linked to $P"; F=1; }
      T+=$'\n'$(gcloud services list --enabled --format='value(config.name)' 2>/dev/null | sed 's/^/api /;s/\.googleapis\.com$//')
      chk "Your account is Owner" "user:$A" owner
      chk "APIs enabled" api compute aiplatform
    fi
    chk "Agent permissions" "serviceAccount:$SA" run.builder aiplatform.user
    chk "Review team access" "group:arcade-agent-verifier@google.com" serviceusage.serviceUsageViewer run.viewer browser
  }

  gr() { for t in {1..6}; do rd g; [ -z "$F" ] && return; ((t<6)) && sleep 10; done; }
  sp "Granting permissions" gr
  echo "Summary for project $P:"; rd
  [ -n "$F" ] && [ -n "$ER" ] && { echo "Last error:"; echo "$ER" | tail -n 3; }
  [ -z "$F" ] && echo "SELESAI Steps 1-3! Lanjut ke Step 4-7 di halaman course." || { echo "Ada item yang belum lengkap. Jalankan ulang script ini jika masih [MISSING]."; return 1; }
}

s3

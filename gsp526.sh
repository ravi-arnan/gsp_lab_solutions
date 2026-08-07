#!/usr/bin/env bash
# GSP526 - Privileged Access with IAM: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp526.sh
#
# Empat fase, dua di antaranya harus dijalankan sebagai user KEDUA:
#
#   bash gsp526.sh              # Task 1, 2, 3, dan permintaan grant (user 1)
#   # klik checkpoint Task 1, 2, 3
#   gcloud auth login           # login sebagai user 2 (Cymbal Security Lead)
#   bash gsp526.sh approve      # Task 4 (user 2)
#   # klik checkpoint Task 4, tunggu 1-2 menit dulu, log approval lambat
#   bash gsp526.sh revoke       # Task 5 (user 2)
#   # klik checkpoint Task 5
#   gcloud config set account <email user 1>
#   bash gsp526.sh delete       # Task 6 (user 1)
#
# Checkpoint:
#   Task 1 - Enable Privileged Access Manager
#   Task 2 - Create the entitlement
#   Task 3 - Update the entitlement
#   Task 4 - Request temporary elevated access
#   Task 5 - Revoke a grant
#   Task 6 - Delete the entitlement
#
# Persetujuan HARUS datang dari approver principal, dan itu user kedua. Tidak
# ada jalan pintas: PAM menolak approve dari siapa pun di luar daftar approver,
# termasuk owner project. Login user kedua boleh lewat 'gcloud auth login' di
# Cloud Shell (seperti di atas) atau lewat Console di jendela incognito.

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

step() { echo; echo "=== $* ==="; }

ENTITLEMENT="pam-entitlement"
LOCATION="global"
ROLE="roles/compute.admin"
MAX_DURATION_CREATE="36000s"   # 10 jam, Task 2
MAX_DURATION_UPDATE="14400s"   # 4 jam, Task 3
GRANT_DURATION="14400s"        # 4 jam, Task 4

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
echo "PROJECT = $PROJECT"
echo "ACCOUNT = $ACCOUNT"

PHASE="${1:-setup}"
case "$PHASE" in
  setup|approve|revoke|delete) ;;
  *) echo "Fase tidak dikenal: $PHASE (setup | approve | revoke | delete)"; exit 1 ;;
esac

pam() { gcloud pam "$@" --location="$LOCATION" --project="$PROJECT"; }

# --------------------------------------------------------- fase approve/revoke
# Dijalankan sebagai user kedua. 'grants search' dengan can-approve hanya
# mengembalikan grant yang memang boleh disetujui akun aktif, jadi sekaligus
# menjadi pemeriksaan bahwa login-nya sudah benar.
if [[ "$PHASE" == "approve" || "$PHASE" == "revoke" ]]; then
  [[ "$PHASE" == "approve" ]] && FILTER="can-approve" || FILTER="had-approved"

  GRANT="$(pam grants search --entitlement="$ENTITLEMENT" \
    --caller-relationship="$FILTER" --format='value(name)' | head -n1)"

  if [[ -z "$GRANT" ]]; then
    echo "Tidak ada grant yang bisa di-$PHASE oleh $ACCOUNT."
    echo "Pastikan sudah 'gcloud auth login' sebagai user kedua (Cymbal Security Lead),"
    echo "dan fase setup sudah membuat permintaan grant."
    exit 1
  fi
  echo "GRANT = $GRANT"

  if [[ "$PHASE" == "approve" ]]; then
    step "Task 4 - menyetujui grant"
    gcloud pam grants approve "$GRANT" --reason="Approved for scheduled maintenance" -q
    cat <<EOF

SELESAI. Klik Check my progress: "Request temporary elevated access".
Tunggu 1-2 menit dulu, log approval memang telat muncul.

Lanjut setelah checkpoint itu hijau:
  bash gsp526.sh revoke
EOF
  else
    step "Task 5 - mencabut grant"
    gcloud pam grants revoke "$GRANT" --reason="Task completed, restoring least privilege" -q
    cat <<EOF

SELESAI. Klik Check my progress: "Revoke a grant".

Lanjut sebagai user pertama:
  gcloud config set account <email user 1>
  bash gsp526.sh delete
EOF
  fi
  exit 0
fi

# ------------------------------------------------------------- fase delete
if [[ "$PHASE" == "delete" ]]; then
  step "Task 6 - menghapus entitlement"
  pam entitlements delete "$ENTITLEMENT" -q
  cat <<EOF

SELESAI. Klik Check my progress: "Delete the entitlement".

Task 6 juga menyuruh melihat audit log. Tidak ada checkpoint terpisah untuk
itu, tapi kalau mau memeriksanya:
  gcloud logging read \\
    'protoPayload.serviceName="privilegedaccessmanager.googleapis.com"' \\
    --project=$PROJECT --limit=20 --format='value(protoPayload.methodName)'
EOF
  exit 0
fi

# -------------------------------------------------------------- fase setup
step "Task 1 - mengaktifkan PAM dan memberi role ke service agent"
gcloud services enable privilegedaccessmanager.googleapis.com >/dev/null

# PAM SELALU memakai service agent tingkat organisasi, bahkan saat PAM dipakai
# di tingkat project. Formatnya service-org-<ORG_NUMBER>@..., bukan
# service-<PROJECT_NUMBER>@... seperti kebanyakan service agent lain.
ORG="$(gcloud projects get-ancestors "$PROJECT" --format='value(id,type)' \
  | awk '$2=="organization" {print $1; exit}')"
[[ -n "$ORG" ]] || { echo "Organization tidak terdeteksi dari ancestor project."; exit 1; }
PAM_SA="service-org-$ORG@gcp-sa-pam.iam.gserviceaccount.com"
echo "ORG = $ORG"
echo "PAM service agent = $PAM_SA"

# Service agent dibuat saat API diaktifkan, tapi kemunculannya bisa telat.
for i in 1 2 3 4 5; do
  if gcloud projects add-iam-policy-binding "$PROJECT" \
       --member="serviceAccount:$PAM_SA" \
       --role="roles/privilegedaccessmanager.serviceAgent" \
       --condition=None >/dev/null 2>&1; then
    echo "roles/privilegedaccessmanager.serviceAgent -> $PAM_SA"
    break
  fi
  echo "  service agent belum siap, menunggu (percobaan $i)"
  sleep 15
  [[ $i -lt 5 ]] || { echo "Gagal memberi role ke service agent."; exit 1; }
done

step "Task 2 - membuat entitlement $ENTITLEMENT"

# User kedua = principal user di IAM policy project yang bukan akun aktif.
SECONDARY_DEFAULT="$(gcloud projects get-iam-policy "$PROJECT" \
  --flatten='bindings[].members' --format='value(bindings.members)' 2>/dev/null \
  | sed -n 's/^user://p' | sort -u | grep -v "^$ACCOUNT$" | head -n1)"
ask PRIMARY "$ACCOUNT" "Requester principal (user 1)"
ask SECONDARY "$SECONDARY_DEFAULT" "Approver principal (user 2)"
[[ -n "$SECONDARY" ]] || { echo "User kedua tidak terdeteksi. Salin dari panel lab."; exit 1; }

# Argumen kedua opsional: etag. 'entitlements update' menolak dengan ABORTED
# kalau etag tidak ikut atau sudah basi, dan create baru saja mengubahnya.
write_entitlement() {
  cat > /tmp/pam-entitlement.yaml <<EOF
${2:+etag: '$2'}
privilegedAccess:
  gcpIamAccess:
    resourceType: cloudresourcemanager.googleapis.com/Project
    resource: //cloudresourcemanager.googleapis.com/projects/$PROJECT
    roleBindings:
    - role: $ROLE
maxRequestDuration: $1
eligibleUsers:
- principals:
  - user:$PRIMARY
requesterJustificationConfig:
  notMandatory: {}
approvalWorkflow:
  manualApprovals:
    requireApproverJustification: false
    steps:
    - approvalsNeeded: 1
      approvers:
      - principals:
        - user:$SECONDARY
EOF
}

if pam entitlements describe "$ENTITLEMENT" >/dev/null 2>&1; then
  echo "entitlement sudah ada, create dilewati"
else
  write_entitlement "$MAX_DURATION_CREATE"
  pam entitlements create "$ENTITLEMENT" --entitlement-file=/tmp/pam-entitlement.yaml
fi

step "Task 3 - mengubah maximum duration jadi 4 jam"
UPDATED=0
for i in 1 2 3; do
  ETAG="$(pam entitlements describe "$ENTITLEMENT" --format='value(etag)')"
  write_entitlement "$MAX_DURATION_UPDATE" "$ETAG"
  if pam entitlements update "$ENTITLEMENT" --entitlement-file=/tmp/pam-entitlement.yaml -q; then
    UPDATED=1; break
  fi
  echo "  etag basi, ambil ulang (percobaan $i)"
  sleep 10
done
[[ "$UPDATED" == 1 ]] || { echo "Gagal mengubah maxRequestDuration."; exit 1; }
pam entitlements describe "$ENTITLEMENT" --format='value(name,maxRequestDuration)'

step "Task 4 - meminta grant 4 jam sebagai user 1"
EXISTING="$(pam grants search --entitlement="$ENTITLEMENT" \
  --caller-relationship=had-created --format='value(name)' | head -n1)"
if [[ -n "$EXISTING" ]]; then
  echo "grant sudah pernah diminta: $EXISTING"
else
  pam grants create --entitlement="$ENTITLEMENT" \
    --requested-duration="$GRANT_DURATION" \
    --justification="Test justification for scheduled maintenance" -q
fi

cat <<EOF

Klik Check my progress untuk:
  - Enable Privileged Access Manager   (Task 1)
  - Create the entitlement             (Task 2)
  - Update the entitlement             (Task 3)

Lalu lanjutkan sebagai user kedua ($SECONDARY):

  gcloud auth login          <- login sebagai user kedua, butuh browser
  bash gsp526.sh approve     <- Task 4
  bash gsp526.sh revoke      <- Task 5, setelah checkpoint Task 4 hijau

Terakhir kembali ke user pertama:

  gcloud config set account $PRIMARY
  bash gsp526.sh delete      <- Task 6
EOF

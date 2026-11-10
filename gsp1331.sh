#!/usr/bin/env bash
# GSP1331 - Request Temporary Elevated Access with Privileged Access Manager
#
#   bash gsp1331.sh
#
# Alur eksekusi:
#   1. Cloud Shell Username 1 (Primary User):
#      curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp1331.sh
#      bash gsp1331.sh
#      -> Menyelesaikan Task 1 (Enable PAM), Task 2 (Create entitlement),
#         Task 3 (Update entitlement), dan request grant Task 4.
#      -> Klik Check my progress untuk Task 1, 2, dan 3.
#
#   2. Menyetujui grant (Task 4):
#      Cara termudah: Buka Console tab incognito sebagai Username 2 (Secondary User),
#      ke IAM & Admin > PAM > APPROVE GRANTS > klik Approve/Deny > klik Approve.
#      (Atau buka Cloud Shell sesi Username 2: bash gsp1331.sh approve)
#      -> Klik Check my progress untuk Task 4.
#
# Checkpoint:
#   Task 1 (25 pts) - Enable Privileged Access Manager.
#   Task 2 (25 pts) - Create the entitlement.
#   Task 3 (25 pts) - Update the entitlement
#   Task 4 (25 pts) - Request temporary elevated access.

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var. Kalau stdin bukan
# terminal (curl | bash, nohup), langsung pakai default supaya tidak menggantung.
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
ROLE="roles/resourcemanager.projectIamAdmin"
MAX_DURATION_CREATE="86400s"   # 1 Day (24 jam), Task 2
MAX_DURATION_UPDATE="36000s"   # 10 jam, Task 3
GRANT_DURATION="36000s"        # 10 jam, Task 4
JUSTIFICATION="pam-test"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
echo "PROJECT = $PROJECT"
echo "ACCOUNT = $ACCOUNT"

PHASE="${1:-setup}"
case "$PHASE" in
  setup|approve) ;;
  *) echo "Fase tidak dikenal: $PHASE (setup | approve)"; exit 1 ;;
esac

pam() { gcloud pam "$@" --location="$LOCATION" --project="$PROJECT"; }

# ------------------------------------------------------------- fase 'approve'
# Dijalankan oleh Secondary User jika memilih lewat CLI.
if [[ "$PHASE" == "approve" ]]; then
  step "Task 4 - menyetujui grant sebagai approver"
  GRANT="$(pam grants search --entitlement="$ENTITLEMENT" \
    --caller-relationship="can-approve" --format='value(name)' 2>/dev/null | head -n1 || true)"

  if [[ -z "$GRANT" ]]; then
    echo "Tidak ada grant yang bisa di-approve oleh $ACCOUNT."
    echo "Pastikan fase setup sudah dijalankan oleh Primary User,"
    echo "dan sesi ini menggunakan akun Secondary User (Approver)."
    exit 1
  fi
  echo "GRANT = $GRANT"

  gcloud pam grants approve "$GRANT" --reason="Approved $JUSTIFICATION" -q
  cat <<EOF

Persetujuan berhasil dikirim!
Tunggu 30-60 detik agar sinkronisasi log selesai,
lalu klik Check my progress: "Request temporary elevated access".
EOF
  exit 0
fi

# --------------------------------------------------------------- fase 'setup'
step "Task 1 - mengaktifkan PAM dan memberi role ke service agent"
gcloud services enable privilegedaccessmanager.googleapis.com >/dev/null

ORG="$(gcloud projects get-ancestors "$PROJECT" --format='value(id,type)' 2>/dev/null \
  | awk '$2=="organization" {print $1; exit}' || true)"
[[ -n "$ORG" ]] || { echo "Organization tidak terdeteksi dari ancestor project."; exit 1; }
PAM_SA="service-org-$ORG@gcp-sa-pam.iam.gserviceaccount.com"
echo "ORG = $ORG"
echo "PAM service agent = $PAM_SA"

# Service agent dibuat saat API diaktifkan, loop sampai siap
for i in 1 2 3 4 5; do
  if gcloud projects add-iam-policy-binding "$PROJECT" \
       --member="serviceAccount:$PAM_SA" \
       --role="roles/privilegedaccessmanager.serviceAgent" \
       --condition=None >/dev/null 2>&1; then
    echo "roles/privilegedaccessmanager.serviceAgent -> $PAM_SA"
    break
  fi
  echo "  service agent belum siap, menunggu (percobaan $i)"
  sleep 10
  [[ $i -lt 5 ]] || { echo "Gagal memberi role ke service agent."; exit 1; }
done

step "Task 2 - membuat entitlement $ENTITLEMENT"

# User kedua = principal user di IAM policy project yang bukan akun aktif.
SECONDARY_DEFAULT="$(gcloud projects get-iam-policy "$PROJECT" \
  --flatten='bindings[].members' --format='value(bindings.members)' 2>/dev/null \
  | sed -n 's/^user://p' | sort -u | grep -v "^$ACCOUNT$" | head -n1 || true)"
ask PRIMARY "$ACCOUNT" "Requester principal (user 1)"
ask SECONDARY "$SECONDARY_DEFAULT" "Approver principal (user 2)"
[[ -n "$SECONDARY" ]] || { echo "User kedua tidak terdeteksi. Salin dari panel lab."; exit 1; }

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

step "Task 3 - mengubah maximum duration jadi 10 jam"
UPDATED=0
for i in 1 2 3; do
  ETAG="$(pam entitlements describe "$ENTITLEMENT" --format='value(etag)' 2>/dev/null || true)"
  write_entitlement "$MAX_DURATION_UPDATE" "$ETAG"
  if pam entitlements update "$ENTITLEMENT" --entitlement-file=/tmp/pam-entitlement.yaml -q; then
    UPDATED=1; break
  fi
  echo "  etag basi, ambil ulang (percobaan $i)"
  sleep 10
done
[[ "$UPDATED" == 1 ]] || { echo "Gagal mengubah maxRequestDuration."; exit 1; }
pam entitlements describe "$ENTITLEMENT" --format='value(name,maxRequestDuration)'

step "Task 4 - meminta grant 10 jam sebagai user 1"
EXISTING="$(pam grants search --entitlement="$ENTITLEMENT" \
  --caller-relationship=had-created --format='value(name)' 2>/dev/null | head -n1 || true)"
if [[ -n "$EXISTING" ]]; then
  echo "grant sudah pernah diminta: $EXISTING"
else
  pam grants create --entitlement="$ENTITLEMENT" \
    --requested-duration="$GRANT_DURATION" \
    --justification="$JUSTIFICATION" -q
fi

cat <<EOF

SELESAI tahap setup!

Klik Check my progress untuk:
  - Enable Privileged Access Manager. (Task 1)
  - Create the entitlement.            (Task 2)
  - Update the entitlement            (Task 3)

Untuk menyelesaikan Task 4 (Request temporary elevated access):
Persetujuan harus diberikan oleh Secondary User ($SECONDARY):
  1. Buka Google Cloud Console di jendela browser incognito baru, login sebagai $SECONDARY
  2. Buka menu: IAM & Admin > PAM > APPROVE GRANTS
  3. Klik "Approve/Deny" pada grant yang muncul, lalu klik "Approve"
  (Atau buka Cloud Shell sesi $SECONDARY lalu jalankan: bash gsp1331.sh approve)

Setelah disetujui, tunggu ~30 detik lalu klik Check my progress untuk Task 4.
EOF

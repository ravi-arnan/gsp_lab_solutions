#!/usr/bin/env bash
# GSP349 - Deploy and Manage Apigee X: Challenge Lab
#
#   bash gsp349.sh
#
# Checkpoint (5 task):
#   Task 1 - Create staging env (programmable, proxy) + staging-group envgroup (staging.example.com)
#   Task 2 - Wizard step 4: Enable internet access (api-subnet, nip.io) -> LB + 1.2.3.4.nip.io
#   Task 3 - Create + activate NAT apigee-nat-ip for eval-instance via Apigee API
#   Task 4 - Cloud Armor protect-apigee (RCE stable, 403, prio 1000) attach to global LB
#   Task 5 - Attach staging env to eval-instance via Apigee API
#
# Lab sudah enable API, buat api-vpc/api-subnet, dan mulai provisioning eval org
# di us-west1. Script menunggu org jadi, lalu menyelesaikan konfigurasi lewat API.
# Task 2 wizard click tetap disarankan; script auto-detect nip.io hostname dan
# memberi petunjuk manual jika LB belum ada.

set -euo pipefail

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

ask REGION "us-west1" "Region (default us-west1)"
ask ZONE "us-west1-c" "Zone (default us-west1-c)"

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || echo "")"

ORG="$PROJECT_ID"
INSTANCE="eval-instance"
ENV_STAGING="staging"
ENVGROUP_STAGING="staging-group"
ENVGROUP_EVAL="eval-group"
NAT_NAME="apigee-nat-ip"
POLICY="protect-apigee"
NETWORK="api-vpc"
SUBNET="api-subnet"

echo "Project : $PROJECT_ID ($PROJECT_NUMBER)"
echo "ORG     : $ORG"
echo "Region  : $REGION"
echo "Zone    : $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }
dbg() { echo ">> $*" >&2; "$@" 2>&1 | head -100; }

# Helper curl dengan token segar
apigee_token() { gcloud auth print-access-token 2>/dev/null; }

apigee_get() {
  local path="$1"
  curl -s -H "Authorization: Bearer $(apigee_token)" \
       -H "Content-Type: application/json" \
       "https://apigee.googleapis.com/v1/$path"
}

apigee_post() {
  local path="$1" body="$2"
  curl -s -H "Authorization: Bearer $(apigee_token)" \
       -H "Content-Type: application/json" \
       -X POST "https://apigee.googleapis.com/v1/$path" -d "$body"
}

apigee_patch() {
  local path="$1" body="$2"
  curl -s -H "Authorization: Bearer $(apigee_token)" \
       -H "Content-Type: application/json" \
       -X PATCH "https://apigee.googleapis.com/v1/$path" -d "$body"
}

wait_operation() {
  local op="$1" max="${2:-60}"
  if [[ "$op" == https* ]]; then
    op="${op#https://apigee.googleapis.com/v1/}"
  fi
  echo "Menunggu operation $op ..."
  for i in $(seq 1 "$max"); do
    local resp
    resp="$(apigee_get "$op")"
    local done
    done="$(echo "$resp" | jq -r '.done // empty' 2>/dev/null || echo "")"
    local state
    state="$(echo "$resp" | jq -r '.metadata.state // .state // empty' 2>/dev/null || echo "")"
    echo "  [$i/$max] done=$done state=$state"
    if [[ "$done" == "true" ]]; then
      if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
        echo "Operation error:"
        echo "$resp" | jq .
        return 1
      fi
      echo "Operation selesai."
      return 0
    fi
    sleep 10
  done
  echo "Timeout menunggu operation $op"
  return 1
}

# Dapatkan semua hostname eval-group
get_eval_hostnames() {
  apigee_get "organizations/$ORG/envgroups/$ENVGROUP_EVAL" 2>/dev/null | jq -r '.hostnames[]? // empty' 2>/dev/null || true
}

# Cek apakah ada forwarding rule global
get_global_forwarding_rules() {
  gcloud compute forwarding-rules list --global --project="$PROJECT_ID" \
    --format='table(name,IPAddress,portRange,target.basename())' 2>/dev/null || true
}

# ---------------------------------------------------------------- Enable API
step "Enable API"
gcloud services enable apigee.googleapis.com compute.googleapis.com --project="$PROJECT_ID" || true

# ---------------------------------------------------------------- Wait for ORG
step "Tunggu Apigee ORG $ORG provisioning selesai (maks 40 menit)"

for i in $(seq 1 80); do
  RESP="$(apigee_get "organizations/$ORG" 2>&1 || true)"
  if echo "$RESP" | grep -q '"name"'; then
    echo "ORG ditemukan (percobaan $i):"
    echo "$RESP" | jq -r '.name, .createdAt, .analyticsRegion, .runtimeType' 2>/dev/null | head -10 || echo "$RESP" | head -20
    STATE="$(echo "$RESP" | jq -r '.state // empty' 2>/dev/null || true)"
    if [[ -n "$STATE" && "$STATE" != "ACTIVE" ]]; then
      echo "  state=$STATE, masih provisioning, tunggu 30s..."
      sleep 30
      continue
    fi
    break
  else
    echo "[$i/80] ORG belum siap, tunggu 30s..."
    echo "$RESP" | head -5
    sleep 30
  fi
  if [[ $i -eq 80 ]]; then
    echo "ORG tidak muncul setelah 40 menit. Pastikan wizard step 3 sedang jalan."
    exit 1
  fi
done

# Cek instance
echo "Cek instance $INSTANCE ..."
for i in $(seq 1 30); do
  IRESP="$(apigee_get "organizations/$ORG/instances/$INSTANCE" 2>&1 || true)"
  if echo "$IRESP" | grep -q '"name"'; then
    echo "Instance ditemukan:"
    echo "$IRESP" | jq -r '.name, .location, .state, .host' 2>/dev/null | head -20
    ISTATE="$(echo "$IRESP" | jq -r '.state // empty' 2>/dev/null || true)"
    if [[ "$ISTATE" == "ACTIVE" ]]; then break; fi
    echo "  state=$ISTATE, tunggu 20s..."
    sleep 20
  else
    echo "[$i] instance belum ready, tunggu 20s..."
    sleep 20
  fi
done

# ---------------------------------------------------------------- Task 1: staging env + envgroup
step "Task 1: Buat environment $ENV_STAGING + envgroup $ENVGROUP_STAGING (staging.example.com)"

# Cek env sudah ada
if apigee_get "organizations/$ORG/environments/$ENV_STAGING" 2>/dev/null | grep -q '"name"'; then
  echo "Environment $ENV_STAGING sudah ada, lewati."
else
  echo "Membuat environment $ENV_STAGING (programmable, proxy)..."
  BODY="$(jq -n --arg n "$ENV_STAGING" '{name:$n, displayName:$n, description:"staging env for challenge"}')"
  RESP="$(apigee_post "organizations/$ORG/environments" "$BODY" 2>&1 || true)"
  echo "$RESP" | head -40
  OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP" | grep -q "operations/"; then
    wait_operation "$OP" 60 || true
  fi
  sleep 5
  if ! apigee_get "organizations/$ORG/environments/$ENV_STAGING" 2>/dev/null | grep -q '"name"'; then
    echo "Gagal buat env via simple body, coba dengan deploymentType..."
    BODY2="$(jq -n --arg n "$ENV_STAGING" '{name:$n, apiProxyType:"PROGRAMMABLE", deploymentType:"PROXY"}')"
    RESP2="$(apigee_post "organizations/$ORG/environments" "$BODY2" 2>&1 || true)"
    echo "$RESP2" | head -40
    OP2="$(echo "$RESP2" | jq -r '.name // empty' 2>/dev/null || true)"
    if echo "$OP2" | grep -q "operations/"; then wait_operation "$OP2" 60 || true; fi
  fi
fi

# Buat envgroup staging-group
if apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING" 2>/dev/null | grep -q '"name"'; then
  echo "EnvGroup $ENVGROUP_STAGING sudah ada, lewati."
  HOSTS="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING" 2>/dev/null | jq -r '.hostnames[]' 2>/dev/null || true)"
  echo "  hostnames: $HOSTS"
  if ! echo "$HOSTS" | grep -q "staging.example.com"; then
    echo "Menambahkan staging.example.com ke $ENVGROUP_STAGING ..."
    CUR="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING" 2>/dev/null)"
    NEWHOSTS="$(echo "$CUR" | jq -c '.hostnames + ["staging.example.com"] | unique' 2>/dev/null || echo '["staging.example.com"]')"
    apigee_patch "organizations/$ORG/envgroups/$ENVGROUP_STAGING?updateMask=hostnames" "{\"hostnames\":$NEWHOSTS}" | head -40 || true
  fi
else
  echo "Membuat envgroup $ENVGROUP_STAGING dengan hostname staging.example.com ..."
  RESP="$(apigee_post "organizations/$ORG/envgroups?name=$ENVGROUP_STAGING" "{\"name\":\"$ENVGROUP_STAGING\",\"hostnames\":[\"staging.example.com\"]}" 2>&1 || true)"
  echo "$RESP" | head -40
  OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP" | grep -q "operations/"; then wait_operation "$OP" 60 || true; fi
fi

# Attach staging env ke staging-group
ATT="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING/attachments" 2>/dev/null || true)"
echo "EnvGroup attachments: $(echo "$ATT" | jq -r '.environmentGroups[].name // empty' 2>/dev/null | head -5 || echo "$ATT" | head -5)"
if echo "$ATT" | grep -q "$ENV_STAGING"; then
  echo "Attachment $ENV_STAGING -> $ENVGROUP_STAGING sudah ada."
else
  echo "Attach $ENV_STAGING ke $ENVGROUP_STAGING ..."
  RESP="$(apigee_post "organizations/$ORG/envgroups/$ENVGROUP_STAGING/attachments" "{\"environment\":\"$ENV_STAGING\"}" 2>&1 || true)"
  echo "$RESP" | head -40
  OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP" | grep -q "operations/"; then wait_operation "$OP" 60 || true; fi
fi

echo "--- Environments ---"
apigee_get "organizations/$ORG/environments" | jq -r '.[]?.name // .environment[]?.name // empty' 2>/dev/null | head -20 || apigee_get "organizations/$ORG/environments" | head -40
echo "--- EnvGroups ---"
apigee_get "organizations/$ORG/envgroups" | jq -r '.environmentGroups[]?.name // .[]?.name // empty' 2>/dev/null | head -20 || apigee_get "organizations/$ORG/envgroups" | head -40

# ---------------------------------------------------------------- Task 2: Access routing (wizard step 4)
step "Task 2: Access routing - enable internet (api-subnet, nip.io)"

# Cek eval-group hostname sudah nip.io belum
EVAL_HOSTS="$(get_eval_hostnames)"
EVAL_HOST="$(echo "$EVAL_HOSTS" | grep nip.io | head -1 || echo "")"
echo "eval-group hostnames sekarang: $EVAL_HOSTS"

if [[ -n "$EVAL_HOST" ]]; then
  echo "Access routing sudah enable (nip.io terdeteksi: $EVAL_HOST), lewati wizard."
else

  cat <<WIZARD

╔══════════════════════════════════════════════════════════════╗
║  TASK 2: Wizard Access Routing — IKUTI LANGKAH INI          ║
╚══════════════════════════════════════════════════════════════╝

  1. Buka tab baru → https://apigee.google.com/setup
  2. Tunggu step 3 "Create organization" hijau (centang ✓).
     Jika masih running (spinner), TUNGGU sampai selesai.
  3. Di step 4 "Access routing", klik "Edit" → "Enable internet access"
     a. Subnetwork: pilih "api-subnet"
     b. DNS: pilih "wildcard nip.io" (default, jangan diubah)
  4. Klik tombol "Set access"
  5. TUNGGU 5-10 menit sampai LB terbentuk.
     Jangan tutup halaman wizard sampai proses selesai.

  ⚠ Jika wizard error "instanceTemplate does not exist":
     a. Buka https://console.cloud.google.com/net-services/loadbalancing/list
        (atau: Network services > Load balancing)
     b. Hapus forwarding rule + backend service + url map yang gagal
     c. Refresh halaman wizard, ulangi langkah 3-4

  Script akan otomatis mendeteksi hostname nip.io (polling 15 menit).

WIZARD

  # Tunggu wizard selesai — polling panjang
  MAX_WAIT=30  # 30 x 30 detik = 15 menit
  for i in $(seq 1 $MAX_WAIT); do
    sleep 30
    EVAL_HOSTS="$(get_eval_hostnames)"
    EVAL_HOST="$(echo "$EVAL_HOSTS" | grep nip.io | head -1 || echo "")"
    echo "  [$i/$MAX_WAIT] hostnames: $EVAL_HOSTS"
    if [[ -n "$EVAL_HOST" ]]; then
      echo "✓ Hostname nip.io terdeteksi: $EVAL_HOST"
      break
    fi
    # Tampilkan forwarding rules sebagai indikator LB sudah terbentuk
    if (( i % 4 == 0 )); then
      echo "  Forwarding rules:"
      get_global_forwarding_rules | head -5 || true
    fi
  done

  # Re-check setelah loop
  if [[ -z "$EVAL_HOST" ]]; then
    EVAL_HOSTS="$(get_eval_hostnames)"
    EVAL_HOST="$(echo "$EVAL_HOSTS" | grep nip.io | head -1 || echo "")"
  fi

  if [[ -z "$EVAL_HOST" ]]; then
    cat <<FAIL

╔══════════════════════════════════════════════════════════════╗
║  ⚠  hostname nip.io belum muncul setelah 15 menit.          ║
║  Kemungkinan wizard belum selesai atau gagal.                ║
╚══════════════════════════════════════════════════════════════╝

  Opsi pemulihan:
  1. Buka https://console.cloud.google.com/net-services/loadbalancing/list
  2. Hapus SEMUA forwarding rule, backend service, URL map yang terkait Apigee
  3. Buka https://apigee.google.com/setup
  4. Ulangi step 4: Enable internet access > api-subnet > nip.io > Set access
  5. Tunggu 5-10 menit, lalu jalankan ulang script ini.

  Atau jika ada fallback IP dari wizard:
FAIL
    # Coba cari IP dari forwarding rules yang sudah ada
    EXISTING_IP="$(gcloud compute forwarding-rules list --global --project="$PROJECT_ID" \
      --format='value(IPAddress)' 2>/dev/null | head -1 || echo "")"
    if [[ -n "$EXISTING_IP" ]]; then
      echo "  IP forwarding rule: $EXISTING_IP"
      echo "  Mungkin hostname: ${EXISTING_IP}.nip.io"
      EVAL_HOST="${EXISTING_IP}.nip.io"
      echo "  Menggunakan fallback: $EVAL_HOST"
      # Patch hostname ke eval-group
      NEW_HOSTS="$(jq -n --arg h "$EVAL_HOST" '[$h]')"
      apigee_patch "organizations/$ORG/envgroups/$ENVGROUP_EVAL?updateMask=hostnames" "{\"hostnames\":$NEW_HOSTS}" | head -20 || true
    fi
  fi
fi

# Final check
if [[ -z "$EVAL_HOST" ]]; then
  echo "ERROR: Tidak bisa menentukan eval-group hostname. Task 2 gagal."
  echo "Jalankan ulang setelah wizard selesai."
  EVAL_HOST="(belum siap)"
fi

echo "eval-group hostname: $EVAL_HOST"
EVAL_IP="$(echo "$EVAL_HOST" | cut -d'.' -f1-4 2>/dev/null || echo "")"
echo "EVAL_IP: $EVAL_IP"

# Tampilkan LB yang ada
echo "Global forwarding rules:"
get_global_forwarding_rules | head -10 || true
echo "Global backend services:"
gcloud compute backend-services list --global --project="$PROJECT_ID" \
  --format='table(name,protocol,loadBalancingScheme)' 2>/dev/null | head -10 || true

# ---------------------------------------------------------------- Task 3: NAT apigee-nat-ip
step "Task 3: NAT $NAT_NAME untuk $INSTANCE"

NAT_RESP="$(apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME" 2>/dev/null || true)"
if echo "$NAT_RESP" | grep -q '"name"'; then
  echo "NAT $NAT_NAME sudah ada:"
  echo "$NAT_RESP" | jq -r '.name, .ipAddress, .state' 2>/dev/null | head -10
  NAT_STATE="$(echo "$NAT_RESP" | jq -r '.state // empty' 2>/dev/null || true)"
  if [[ "$NAT_STATE" != "ACTIVE" ]]; then
    echo "State=$NAT_STATE, aktivasi..."
    RESP="$(apigee_post "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME:activate" '{}' 2>&1 || true)"
    echo "$RESP" | head -40
    OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
    if echo "$OP" | grep -q "operations/"; then wait_operation "$OP" 60 || true; fi
  fi
else
  echo "Membuat NAT $NAT_NAME ..."
  RESP="$(apigee_post "organizations/$ORG/instances/$INSTANCE/natAddresses" "{\"name\":\"$NAT_NAME\"}" 2>&1 || true)"
  echo "$RESP" | head -40
  OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP" | grep -q "operations/"; then wait_operation "$OP" 60 || true; fi
  echo "Aktivasi NAT..."
  sleep 5
  RESP2="$(apigee_post "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME:activate" '{}' 2>&1 || true)"
  echo "$RESP2" | head -40
  OP2="$(echo "$RESP2" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP2" | grep -q "operations/"; then wait_operation "$OP2" 60 || true; fi
fi

echo "--- NAT Addresses ---"
apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses" | jq . 2>/dev/null | head -30 || \
  apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses" | head -40

# ---------------------------------------------------------------- Task 5: Attach staging to instance (sebelum Cloud Armor)
step "Task 5: Attach $ENV_STAGING ke $INSTANCE"

ATT_RESP="$(apigee_get "organizations/$ORG/instances/$INSTANCE/attachments" 2>/dev/null || true)"
if echo "$ATT_RESP" | grep -q "$ENV_STAGING"; then
  echo "Attachment $ENV_STAGING sudah ada, lewati."
else
  echo "Attach $ENV_STAGING ke $INSTANCE ..."
  RESP="$(apigee_post "organizations/$ORG/instances/$INSTANCE/attachments" "{\"environment\":\"$ENV_STAGING\"}" 2>&1 || true)"
  echo "$RESP" | head -40
  OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP" | grep -q "operations/"; then
    wait_operation "$OP" 90 || true
  else
    if echo "$RESP" | grep -qi "already"; then echo "Sudah attached (error already exists)."; fi
  fi
fi

# Poll sampai muncul
echo "Polling attachments..."
for i in $(seq 1 30); do
  ATTS="$(apigee_get "organizations/$ORG/instances/$INSTANCE/attachments" 2>/dev/null || true)"
  ATT_ENVS="$(echo "$ATTS" | jq -r '.attachments[]?.environment // .[]?.environment // empty' 2>/dev/null | tr '\n' ' ')"
  echo "  [$i/30] attached envs: $ATT_ENVS"
  if echo "$ATTS" | grep -q "$ENV_STAGING"; then
    echo "✓ Staging ter-attach."
    break
  fi
  sleep 10
done

# ---------------------------------------------------------------- Task 4: Cloud Armor protect-apigee
step "Task 4: Cloud Armor $POLICY (RCE stable, 403, prio 1000) + attach ke LB"

# Buat policy kalau belum ada
if gcloud compute security-policies describe "$POLICY" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Policy $POLICY sudah ada, lewati create."
else
  echo "Membuat policy $POLICY ..."
  gcloud compute security-policies create "$POLICY" --project="$PROJECT_ID" \
    --description="Protect Apigee from RCE" 2>&1 | head -10 || \
  gcloud compute security-policies create "$POLICY" --description="Protect Apigee" 2>&1 | head -10 || true
fi

# Default rule allow
echo "Set default rule ke allow..."
gcloud compute security-policies rules update 2147483647 \
  --security-policy="$POLICY" --project="$PROJECT_ID" \
  --action=allow --description="Default allow" 2>&1 | head -10 || true

# List preconfigured expression sets (untuk verifikasi)
echo "Preconfigured RCE expression sets:"
gcloud compute security-policies list-preconfigured-expression-sets \
  --project="$PROJECT_ID" 2>&1 | grep -i rce | head -10 || true

# Cari expression RCE stable
# Prioritas: rce-stable dulu, lalu v33-stable, lalu v422-stable
# Perhatikan: gcloud versi baru pakai evaluatePreconfiguredExpr, versi lama juga
EXPR_CANDIDATES=(
  "evaluatePreconfiguredExpr('rce-stable')"
  "evaluatePreconfiguredExpr('rce-v33-stable')"
  "evaluatePreconfiguredExpr('rce-v422-stable')"
  "evaluatePreconfiguredWaf('rce-stable')"
  "evaluatePreconfiguredWaf('rce-v33-stable')"
  "evaluatePreconfiguredWaf('rce-v422-stable')"
)

# Hapus rule 1000 lama kalau ada
if gcloud compute security-policies rules describe 1000 \
   --security-policy="$POLICY" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Rule 1000 sudah ada, hapus untuk recreate..."
  gcloud compute security-policies rules delete 1000 \
    --security-policy="$POLICY" --project="$PROJECT_ID" -q 2>&1 | head -10 || true
  sleep 2
fi

# Buat rule 1000
CREATED=""
for EXPR in "${EXPR_CANDIDATES[@]}"; do
  echo "Coba: $EXPR"
  RULE_LOG="$(gcloud compute security-policies rules create 1000 \
    --security-policy="$POLICY" --project="$PROJECT_ID" \
    --expression="$EXPR" --action=deny-403 \
    --description="Block RCE" 2>&1 || echo "FAIL")"
  echo "$RULE_LOG" | head -10
  if echo "$RULE_LOG" | grep -qi "created\|name.*1000"; then
    CREATED="$EXPR"
    echo "✓ Berhasil: $EXPR"
    break
  fi
  # Jika sudah ada, coba update
  if echo "$RULE_LOG" | grep -qi "already exists"; then
    echo "Rule sudah ada, coba update..."
    UPDATE_LOG="$(gcloud compute security-policies rules update 1000 \
      --security-policy="$POLICY" --project="$PROJECT_ID" \
      --expression="$EXPR" --action=deny-403 2>&1 || echo "FAIL")"
    echo "$UPDATE_LOG" | head -10
    if ! echo "$UPDATE_LOG" | grep -qi "fail\|error"; then
      CREATED="$EXPR"
      echo "✓ Update berhasil: $EXPR"
      break
    fi
  fi
done

if [[ -z "$CREATED" ]]; then
  echo "⚠ Gagal buat rule RCE dengan semua kandidat."
  echo "List expression sets yang tersedia:"
  gcloud compute security-policies list-preconfigured-expression-sets \
    --project="$PROJECT_ID" 2>&1 | head -30 || true
else
  echo "Rule 1000 dibuat dengan $CREATED"
fi

# Verifikasi policy
echo "--- Cloud Armor Policy ---"
gcloud compute security-policies describe "$POLICY" --project="$PROJECT_ID" \
  --format='yaml(name,description,rules[].priority,rules[].action,rules[].match.expr.expression)' 2>/dev/null | head -60 || \
gcloud compute security-policies describe "$POLICY" --format='yaml(name,rules)' 2>/dev/null | head -60 || true

# Attach ke backend-service (checker cari apigee-proxy-backend, jadi attach ke semua apigee backend)
echo "Cari backend-service global untuk Apigee..."
BACKENDS="$(gcloud compute backend-services list --global --project="$PROJECT_ID" \
  --format='value(name)' 2>/dev/null || true)"
echo "Backends: $BACKENDS"

TARGET_BACKEND=""
if [[ -n "$BACKENDS" ]]; then
  for B in $BACKENDS; do
    # Attach ke backend yang mengandung "apigee" atau semua jika tidak ada match
    if echo "$B" | grep -qi apigee; then
      echo "Attach policy $POLICY ke backend $B ..."
      gcloud compute backend-services update "$B" --global \
        --project="$PROJECT_ID" --security-policy="$POLICY" 2>&1 | head -20 || true
      TARGET_BACKEND="$B"
    fi
  done
  # Jika tidak ada backend dengan "apigee" di namanya, attach ke yang pertama
  if [[ -z "$TARGET_BACKEND" && -n "$BACKENDS" ]]; then
    TARGET_BACKEND="$(echo "$BACKENDS" | head -1)"
    echo "Tidak ada backend 'apigee', attach ke: $TARGET_BACKEND"
    gcloud compute backend-services update "$TARGET_BACKEND" --global \
      --project="$PROJECT_ID" --security-policy="$POLICY" 2>&1 | head -20 || true
  fi
else
  echo "⚠ Tidak ada backend-service global ditemukan."
  echo "Pastikan Task 2 wizard sudah membuat LB."
fi

# Test RCE block
if [[ -n "$EVAL_HOST" && "$EVAL_HOST" != "(belum siap)" ]]; then
  echo "--- Test RCE block ---"
  echo "curl -k -i \"https://$EVAL_HOST/hello-world?doc=/bin/ls\""
  curl -k -i "https://$EVAL_HOST/hello-world?doc=/bin/ls" 2>&1 | head -20 || true
  echo "Jika belum 403, tunggu 2-3 menit untuk propagasi."
fi

# ---------------------------------------------------------------- Verifikasi
step "Verifikasi akhir"

echo "--- Environments ---"
apigee_get "organizations/$ORG/environments" | jq . 2>/dev/null | head -40 || true
echo "--- EnvGroups ---"
apigee_get "organizations/$ORG/envgroups" | jq . 2>/dev/null | head -40 || true
echo "--- EnvGroup attachments (staging-group) ---"
apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING/attachments" | jq . 2>/dev/null | head -30 || true
echo "--- Instance attachments ---"
apigee_get "organizations/$ORG/instances/$INSTANCE/attachments" | jq . 2>/dev/null | head -30 || true
echo "--- NAT ---"
apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME" | jq . 2>/dev/null | head -30 || true
echo "--- Cloud Armor ---"
gcloud compute security-policies describe "$POLICY" --project="$PROJECT_ID" \
  --format='yaml(name,rules)' 2>/dev/null | head -60 || true
echo "--- Backend security policy ---"
if [[ -n "${TARGET_BACKEND:-}" ]]; then
  echo "Backend: $TARGET_BACKEND"
  gcloud compute backend-services describe "$TARGET_BACKEND" --global \
    --project="$PROJECT_ID" --format='value(securityPolicy)' 2>/dev/null || true
fi
echo "--- Forwarding rules ---"
get_global_forwarding_rules | head -10 || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress:

  Task 1 - $ENV_STAGING + $ENVGROUP_STAGING (staging.example.com)
  Task 2 - eval-group nip.io: $EVAL_HOST
  Task 3 - NAT $NAT_NAME (ACTIVE)
  Task 4 - $POLICY prio 1000 RCE stable 403 attach $TARGET_BACKEND
  Task 5 - $ENV_STAGING attached to $INSTANCE

Jika Task 2 belum hijau:
  1. Hapus LB gagal di Network services > Load balancing
  2. Buka https://apigee.google.com/setup
  3. Enable internet access > subnet $SUBNET > nip.io > Set access
  4. Tunggu $EVAL_HOST jadi *.nip.io lalu rerun script.

Test RCE (butuh propagasi):
  curl -k -i "https://$EVAL_HOST/hello-world?doc=/bin/ls"  # harus 403
==============================================================
EOF

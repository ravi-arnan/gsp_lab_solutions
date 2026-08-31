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

# Helper curl dengan token segar (token expire 1 jam, ambil tiap call)
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
  # op bisa short name organizations/.../operations/... atau full URL? Kita pakai path setelah v1/
  # apigee_post mengembalikan {"name":"organizations/.../operations/..."}
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
      # cek error
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
    # cek state org kalau ada
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
  # ponytail: Apigee API terbaru butuh body dengan name; apiProxyType dan deploymentType opsional tapi kita set jika didukung
  BODY="$(jq -n --arg n "$ENV_STAGING" '{name:$n, displayName:$n, description:"staging env for challenge"}')"
  # Coba dengan proxy type field kalau API support (ignore error fallback)
  RESP="$(apigee_post "organizations/$ORG/environments" "$BODY" 2>&1 || true)"
  echo "$RESP" | head -40
  # Jika response operation, tunggu
  OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP" | grep -q "operations/"; then
    wait_operation "$OP" 60 || true
  fi
  # Verifikasi
  sleep 5
  if apigee_get "organizations/$ORG/environments/$ENV_STAGING" 2>/dev/null | grep -q '"name"'; then
    echo "Environment $ENV_STAGING berhasil dibuat."
  else
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
  # Pastikan hostname staging.example.com ada
  HOSTS="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING" 2>/dev/null | jq -r '.hostnames[]' 2>/dev/null || true)"
  echo "  hostnames: $HOSTS"
  if ! echo "$HOSTS" | grep -q "staging.example.com"; then
    echo "Menambahkan staging.example.com ke $ENVGROUP_STAGING ..."
    # PATCH butuh updateMask=hostnames dan full list
    CUR="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING" 2>/dev/null)"
    # Gabungkan existing + new
    NEWHOSTS="$(echo "$CUR" | jq -c '.hostnames + ["staging.example.com"] | unique' 2>/dev/null || echo '["staging.example.com"]')"
    apigee_patch "organizations/$ORG/envgroups/$ENVGROUP_STAGING?updateMask=hostnames" "{\"hostnames\":$NEWHOSTS}" | head -40 || true
  fi
else
  echo "Membuat envgroup $ENVGROUP_STAGING dengan hostname staging.example.com ..."
  RESP="$(apigee_post "organizations/$ORG/envgroups?name=$ENVGROUP_STAGING" '{"name":"'"$ENVGROUP_STAGING"'","hostnames":["staging.example.com"]}' 2>&1 || true)"
  echo "$RESP" | head -40
  OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP" | grep -q "operations/"; then wait_operation "$OP" 60 || true; fi
fi

# Attach staging env ke staging-group (prasyarat routing)
if apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING" 2>/dev/null | jq -e --arg e "$ENV_STAGING" '.hostnames' >/dev/null 2>&1; then
  ATT="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING/attachments" 2>/dev/null || true)"
  echo "EnvGroup attachments: $ATT" | head -20
  if echo "$ATT" | grep -q "$ENV_STAGING"; then
    echo "Attachment $ENV_STAGING -> $ENVGROUP_STAGING sudah ada."
  else
    echo "Attach $ENV_STAGING ke $ENVGROUP_STAGING ..."
    RESP="$(apigee_post "organizations/$ORG/envgroups/$ENVGROUP_STAGING/attachments" '{"environment":"'"$ENV_STAGING"'"}' 2>&1 || true)"
    echo "$RESP" | head -40
    OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
    if echo "$OP" | grep -q "operations/"; then wait_operation "$OP" 60 || true; fi
  fi
fi

apigee_get "organizations/$ORG/environments" | jq -r '.[]?.name // .environment[]?.name // empty' 2>/dev/null | head -20 || apigee_get "organizations/$ORG/environments" | head -40
apigee_get "organizations/$ORG/envgroups" | jq -r '.environmentGroups[]?.name // .[]?.name // empty' 2>/dev/null | head -20 || apigee_get "organizations/$ORG/envgroups" | head -40

# ---------------------------------------------------------------- Task 2: Access routing (wizard step 4)
step "Task 2: Access routing - enable internet (api-subnet, nip.io)"

# Cek eval-group hostname sudah nip.io belum
EVAL_HOST="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_EVAL" 2>/dev/null | jq -r '.hostnames[0] // empty' 2>/dev/null || true)"
echo "eval-group hostname sekarang: $EVAL_HOST"

if echo "$EVAL_HOST" | grep -q "nip.io"; then
  echo "Access routing sudah enable (nip.io terdeteksi), lewati wizard."
else
  cat <<EOF

Access routing BELUM nip.io. Lakukan wizard manual:

  1. Buka https://apigee.google.com/setup (Provisoning wizard)
  2. Tunggu step 3 (Create organization) hijau. Jika masih running, tunggu.
  3. Di step 4 "Access routing" klik Edit > Enable internet access
     - Subnetwork: $SUBNET (api-subnet)
     - DNS: wildcard nip.io (default)
  4. Klik Set access, tunggu LB terbentuk (~5-10 menit)

Jika wizard error "instanceTemplate does not exist", hapus LB yang gagal:
  Network services > Load balancing > hapus forwarding rule + backend + url map
  lalu refresh wizard dan coba lagi.

Script akan menunggu hostname jadi nip.io (maks 15 menit).
EOF
  if [[ -t 0 ]]; then
    read -rp "Tekan Enter setelah klik Set access di wizard (atau kosongkan untuk tunggu otomatis)..." _ || true
  fi
  for i in $(seq 1 30); do
    EVAL_HOST="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_EVAL" 2>/dev/null | jq -r '.hostnames[0] // empty' 2>/dev/null || true)"
    echo "  [$i/30] host=$EVAL_HOST"
    if echo "$EVAL_HOST" | grep -q "nip.io"; then
      echo "Hostname nip.io sudah terpasang!"
      break
    fi
    # Juga cek LB global ada belum
    gcloud compute forwarding-rules list --global --project="$PROJECT_ID" --format='table(name,IPAddress,target.basename())' 2>/dev/null | head -10 || true
    sleep 30
  done
  EVAL_HOST="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_EVAL" 2>/dev/null | jq -r '.hostnames[0] // empty' 2>/dev/null || true)"
  echo "Final eval-group hostname: $EVAL_HOST"
fi

# Fallback manual jika wizard redirect / error instanceTemplate (tanpa LB)
if ! echo "$EVAL_HOST" | grep -q "nip.io"; then
  echo "Fallback: wizard tidak jadi nip.io, coba buat via PSC NEG manual (best-effort)..."
  set +e
  SA="$(apigee_get "organizations/$ORG/instances/$INSTANCE" 2>/dev/null | jq -r '.serviceAttachment // empty' 2>/dev/null || true)"
  echo "serviceAttachment: $SA"
  if [[ -n "$SA" && "$SA" != "null" ]]; then
    # NEG
    if ! gcloud compute network-endpoint-groups describe apigee-neg --region="$REGION" --project="$PROJECT_ID" >/dev/null 2>&1; then
      echo "Buat NEG apigee-neg -> $SA ..."
      gcloud compute network-endpoint-groups create apigee-neg \
        --region="$REGION" --project="$PROJECT_ID" \
        --network="$NETWORK" --subnet="$SUBNET" \
        --network-endpoint-type=private-service-connect \
        --psc-target-service="$SA" 2>&1 | head -20 || true
    else
      echo "NEG apigee-neg sudah ada"
    fi
    # Reserve IP global
    if ! gcloud compute addresses describe apigee-ip --global --project="$PROJECT_ID" >/dev/null 2>&1; then
      gcloud compute addresses create apigee-ip --global --project="$PROJECT_ID" 2>&1 | head -20 || true
    fi
    IP_FALLBACK="$(gcloud compute addresses describe apigee-ip --global --project="$PROJECT_ID" --format='value(address)' 2>/dev/null || true)"
    echo "Fallback IP: $IP_FALLBACK"
    if [[ -n "$IP_FALLBACK" ]]; then
      HOST_FALLBACK="$IP_FALLBACK.nip.io"
      echo "Set eval-group hostname ke $HOST_FALLBACK ..."
      # PATCH hostnames (replace list, wizard biasanya append, kita replace full list dengan fallback + keep existing jika ada)
      CUR_HOST="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_EVAL" 2>/dev/null | jq -r '.hostnames // []' 2>/dev/null || echo '[]')"
      # Jika CUR_HOST sudah array, merge
      NEW_HOSTS="$(echo "$CUR_HOST" | jq -c --arg h "$HOST_FALLBACK" '(. + [$h]) | unique' 2>/dev/null || echo "[\"$HOST_FALLBACK\"]")"
      echo "PATCH hostnames=$NEW_HOSTS"
      apigee_patch "organizations/$ORG/envgroups/$ENVGROUP_EVAL?updateMask=hostnames" "{\"hostnames\":$NEW_HOSTS}" | head -40 || true
      # Backend service
      if ! gcloud compute backend-services describe apigee-backend --global --project="$PROJECT_ID" >/dev/null 2>&1; then
        gcloud compute backend-services create apigee-backend --global --project="$PROJECT_ID" \
          --load-balancing-scheme=EXTERNAL_MANAGED --protocol=HTTPS 2>&1 | head -20 || true
      fi
      gcloud compute backend-services add-backend apigee-backend --global --project="$PROJECT_ID" \
        --network-endpoint-group=apigee-neg --network-endpoint-group-region="$REGION" 2>&1 | head -20 || true
      # URL map
      if ! gcloud compute url-maps describe apigee-url-map --global --project="$PROJECT_ID" >/dev/null 2>&1; then
        gcloud compute url-maps create apigee-url-map --global --project="$PROJECT_ID" \
          --default-service=apigee-backend 2>&1 | head -20 || true
      fi
      # Cert
      if ! gcloud compute ssl-certificates describe apigee-cert --global --project="$PROJECT_ID" >/dev/null 2>&1; then
        gcloud compute ssl-certificates create apigee-cert --global --project="$PROJECT_ID" \
          --domains="$HOST_FALLBACK" 2>&1 | head -20 || true
      fi
      # Proxy
      if ! gcloud compute target-https-proxies describe apigee-proxy --global --project="$PROJECT_ID" >/dev/null 2>&1; then
        gcloud compute target-https-proxies create apigee-proxy --global --project="$PROJECT_ID" \
          --url-map=apigee-url-map --ssl-certificates=apigee-cert 2>&1 | head -20 || true
      fi
      # Forwarding rule
      if ! gcloud compute forwarding-rules describe apigee-forwarding --global --project="$PROJECT_ID" >/dev/null 2>&1; then
        gcloud compute forwarding-rules create apigee-forwarding --global --project="$PROJECT_ID" \
          --load-balancing-scheme=EXTERNAL_MANAGED --network-tier=PREMIUM \
          --address=apigee-ip --target-https-proxy=apigee-proxy --ports=443 2>&1 | head -30 || true
      fi
      # Refresh EVAL_HOST
      sleep 5
      EVAL_HOST="$(apigee_get "organizations/$ORG/envgroups/$ENVGROUP_EVAL" 2>/dev/null | jq -r '.hostnames[]' 2>/dev/null | grep nip.io | head -1 || echo "$HOST_FALLBACK")"
      echo "Fallback EVAL_HOST: $EVAL_HOST"
    fi
  else
    echo "serviceAttachment kosong, fallback manual tidak bisa, perlu wizard."
  fi
  set -e
fi

# Simpan IP dari nip.io hostname untuk Task 4 test
EVAL_IP="$(echo "$EVAL_HOST" | cut -d'.' -f1-4 2>/dev/null || echo "")"
echo "EVAL_IP (dari nip.io): $EVAL_IP"

# Tunggu LB backend siap (optional)
echo "Cek global backend-services..."
gcloud compute backend-services list --global --project="$PROJECT_ID" --format='table(name,protocol,loadBalancingScheme)' 2>/dev/null | head -20 || true
gcloud compute forwarding-rules list --global --project="$PROJECT_ID" --format='table(name,IPAddress,portRange,target.basename())' 2>/dev/null | head -20 || true

# ---------------------------------------------------------------- Task 3: NAT apigee-nat-ip
step "Task 3: NAT $NAT_NAME untuk $INSTANCE"

if apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME" 2>/dev/null | grep -q '"name"'; then
  echo "NAT $NAT_NAME sudah ada:"
  apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME" | jq -r '.name, .ipAddress, .state' 2>/dev/null | head -10
  STATE="$(apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME" 2>/dev/null | jq -r '.state // empty' 2>/dev/null || true)"
  if [[ "$STATE" != "ACTIVE" ]]; then
    echo "State=$STATE, aktivasi..."
    RESP="$(apigee_post "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME:activate" '{}' 2>&1 || true)"
    echo "$RESP" | head -40
    OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
    if echo "$OP" | grep -q "operations/"; then wait_operation "$OP" 60 || true; fi
  fi
else
  echo "Membuat NAT $NAT_NAME ..."
  RESP="$(apigee_post "organizations/$ORG/instances/$INSTANCE/natAddresses" '{"name":"'"$NAT_NAME"'"}' 2>&1 || true)"
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

# Verifikasi
apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses" | jq -r '.natAddresses[]?.name // .[]?.name // empty' 2>/dev/null | head -10 || apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses" | head -40
apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME" | jq . 2>/dev/null | head -20 || true

# ---------------------------------------------------------------- Task 5: Attach staging to instance (dikerjakan sebelum Cloud Armor agar tidak race)
step "Task 5: Attach $ENV_STAGING ke $INSTANCE"

if apigee_get "organizations/$ORG/instances/$INSTANCE/attachments" 2>/dev/null | grep -q "$ENV_STAGING"; then
  echo "Attachment $ENV_STAGING sudah ada, lewati."
else
  # Coba endpoint instances attachments
  echo "Attach $ENV_STAGING ke $INSTANCE ..."
  RESP="$(apigee_post "organizations/$ORG/instances/$INSTANCE/attachments" '{"environment":"'"$ENV_STAGING"'"}' 2>&1 || true)"
  echo "$RESP" | head -40
  OP="$(echo "$RESP" | jq -r '.name // empty' 2>/dev/null || true)"
  if echo "$OP" | grep -q "operations/"; then
    wait_operation "$OP" 90 || true
  else
    # Fallback cek error already exists
    if echo "$RESP" | grep -qi "already"; then echo "Sudah attached (error already exists)."; fi
  fi
fi

# Poll sampai state ACTIVE
for i in $(seq 1 30); do
  ATTS="$(apigee_get "organizations/$ORG/instances/$INSTANCE/attachments" 2>/dev/null || true)"
  echo "[$i] attachments: $(echo "$ATTS" | jq -r '.attachments[]?.environment // .[]?.environment // empty' 2>/dev/null | tr '\n' ' ' || echo "$ATTS" | head -5)"
  if echo "$ATTS" | grep -q "$ENV_STAGING"; then
    echo "Staging ter-attach."
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
  gcloud compute security-policies create "$POLICY" --project="$PROJECT_ID" --description="Protect Apigee from RCE" || \
  gcloud compute security-policies create "$POLICY" --description="Protect Apigee" || true
fi

# Default rule allow (agar allow all kecuali RCE)
# Default rule ada di priority 2147483647, pastikan allow
echo "Set default rule ke allow..."
gcloud compute security-policies rules update 2147483647 --security-policy="$POLICY" --project="$PROJECT_ID" --action=allow --description="Default allow" 2>&1 | head -20 || \
gcloud compute security-policies rules update 2147483647 --security-policy="$POLICY" --action=allow --description="Default allow" 2>&1 | head -20 || true

# Cari expression stable untuk RCE
# List preconfigured sets untuk verifikasi (best-effort)
echo "List preconfigured RCE sets..."
gcloud compute security-policies list-preconfigured-expression-sets --project="$PROJECT_ID" 2>&1 | grep -i rce | head -20 || true

# Pilih expression: coba evaluatePreconfiguredExpr('rce-stable') dulu (compat lama), fallback ke Waf
EXPR_CANDIDATES=(
  "evaluatePreconfiguredExpr('rce-stable')"
  "evaluatePreconfiguredExpr('rce-v33-stable')"
  "evaluatePreconfiguredExpr('rce-v422-stable')"
  "evaluatePreconfiguredWaf('rce-stable')"
  "evaluatePreconfiguredWaf('rce-v33-stable')"
  "evaluatePreconfiguredWaf('rce-v422-stable')"
)

# Hapus rule 1000 lama kalau ada agar bisa recreate dengan expr yang benar
if gcloud compute security-policies rules describe 1000 --security-policy="$POLICY" --project="$PROJECT_ID" >/dev/null 2>&1; then
  echo "Rule 1000 sudah ada, hapus untuk recreate..."
  gcloud compute security-policies rules delete 1000 --security-policy="$POLICY" --project="$PROJECT_ID" -q 2>&1 | head -20 || true
  sleep 2
fi

# Buat rule 1000 dengan kandidat pertama yang berhasil
CREATED=""
for EXPR in "${EXPR_CANDIDATES[@]}"; do
  echo "Coba create rule 1000 dengan expr: $EXPR"
  if gcloud compute security-policies rules create 1000 --security-policy="$POLICY" --project="$PROJECT_ID" --expression="$EXPR" --action=deny-403 --description="Block RCE" 2>&1 | tee /tmp/ca_rule.log | head -30; then
    CREATED="$EXPR"
    echo "Berhasil dengan $EXPR"
    break
  else
    cat /tmp/ca_rule.log | head -20
    # coba update jika create gagal karena sudah ada
    if grep -q "already exists" /tmp/ca_rule.log; then
      gcloud compute security-policies rules update 1000 --security-policy="$POLICY" --project="$PROJECT_ID" --expression="$EXPR" --action=deny-403 2>&1 | head -20 && CREATED="$EXPR" && break || true
    fi
    echo "Gagal dengan $EXPR, coba kandidat berikutnya..."
  fi
done

if [[ -z "$CREATED" ]]; then
  echo "Gagal buat rule RCE dengan semua kandidat, cek log:"
  cat /tmp/ca_rule.log | head -40
else
  echo "Rule 1000 dibuat dengan $CREATED"
fi

gcloud compute security-policies describe "$POLICY" --project="$PROJECT_ID" --format='yaml(name,description,rules[].priority,rules[].action,rules[].match.expr.expression)' 2>/dev/null | head -60 || \
gcloud compute security-policies describe "$POLICY" --format='yaml(name,rules)' 2>/dev/null | head -60 || true

# Attach ke global LB backend-service
echo "Cari backend-service global untuk Apigee..."
BACKENDS="$(gcloud compute backend-services list --global --project="$PROJECT_ID" --format='value(name)' 2>/dev/null || true)"
echo "Backends: $BACKENDS"

TARGET_BACKEND=""
for B in $BACKENDS; do
  if echo "$B" | grep -qi apigee; then TARGET_BACKEND="$B"; break; fi
done
if [[ -z "$TARGET_BACKEND" && -n "$BACKENDS" ]]; then
  # fallback ambil yang pertama yang punya global loadBalancingScheme EXTERNAL_MANAGED
  TARGET_BACKEND="$(echo "$BACKENDS" | head -1)"
  echo "Fallback backend: $TARGET_BACKEND"
fi

if [[ -n "$TARGET_BACKEND" ]]; then
  echo "Attach policy $POLICY ke backend $TARGET_BACKEND ..."
  gcloud compute backend-services update "$TARGET_BACKEND" --global --project="$PROJECT_ID" --security-policy="$POLICY" 2>&1 | head -30 || \
  gcloud compute backend-services update "$TARGET_BACKEND" --global --security-policy="$POLICY" 2>&1 | head -30 || true

  # Verifikasi
  gcloud compute backend-services describe "$TARGET_BACKEND" --global --project="$PROJECT_ID" --format='value(securityPolicy)' 2>/dev/null | head -5 || \
  gcloud compute backend-services describe "$TARGET_BACKEND" --global --format='value(securityPolicy)' 2>/dev/null | head -5 || true
else
  echo "Tidak ada backend-service global ditemukan. Pastikan Task 2 wizard sudah membuat LB."
  echo "Coba list LB:"
  gcloud compute forwarding-rules list --global --project="$PROJECT_ID" 2>/dev/null | head -20 || true
fi

# Test RCE block (best-effort, butuh hostname nip.io)
if [[ -n "$EVAL_HOST" && "$EVAL_HOST" != "" ]]; then
  echo "Test RCE block (butuh propagasi beberapa menit):"
  echo "curl -i https://$EVAL_HOST/hello-world?doc=/bin/ls"
  curl -k -i "https://$EVAL_HOST/hello-world?doc=/bin/ls" 2>&1 | head -20 || true
  echo "Jika belum 403, tunggu 2-3 menit dan ulang:"
  echo "curl -k -i \"https://$EVAL_HOST/hello-world?doc=/bin/ls\""
fi

# ---------------------------------------------------------------- Verifikasi
step "Verifikasi akhir"

echo "--- Env ---"
apigee_get "organizations/$ORG/environments" | jq . 2>/dev/null | head -60 || true
echo "--- EnvGroups ---"
apigee_get "organizations/$ORG/envgroups" | jq . 2>/dev/null | head -80 || true
apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING" | jq . 2>/dev/null | head -40 || true
echo "--- EnvGroup attachments staging-group ---"
apigee_get "organizations/$ORG/envgroups/$ENVGROUP_STAGING/attachments" | jq . 2>/dev/null | head -40 || true
echo "--- Instance attachments ---"
apigee_get "organizations/$ORG/instances/$INSTANCE/attachments" | jq . 2>/dev/null | head -40 || true
echo "--- NAT ---"
apigee_get "organizations/$ORG/instances/$INSTANCE/natAddresses/$NAT_NAME" | jq . 2>/dev/null | head -40 || true
echo "--- Cloud Armor ---"
gcloud compute security-policies describe "$POLICY" --project="$PROJECT_ID" --format='yaml(name,rules)' 2>/dev/null | head -80 || true
echo "--- Backend attachment ---"
if [[ -n "${TARGET_BACKEND:-}" ]]; then
  gcloud compute backend-services describe "$TARGET_BACKEND" --global --project="$PROJECT_ID" --format='value(securityPolicy)' 2>/dev/null || true
fi
echo "--- LB ---"
gcloud compute forwarding-rules list --global --project="$PROJECT_ID" --format='table(name,IPAddress,target.basename())' 2>/dev/null | head -20 || true

cat <<EOF

==============================================================
SELESAI! Klik Check my progress:

  Task 1 - $ENV_STAGING + $ENVGROUP_STAGING (staging.example.com)
  Task 2 - eval-group nip.io: $EVAL_HOST
  Task 3 - NAT $NAT_NAME (ACTIVE)
  Task 4 - $POLICY prio 1000 RCE stable 403 attach $TARGET_BACKEND
  Task 5 - $ENV_STAGING attached to $INSTANCE

Jika Task 2 belum hijau: buka https://apigee.google.com/setup
  Enable internet access > subnet $SUBNET > nip.io > Set access
  tunggu $EVAL_HOST jadi *.nip.io lalu rerun script.

Test RCE (butuh propagasi):
  curl -k -i "https://$EVAL_HOST/hello-world?doc=/bin/ls"  # harus 403
==============================================================
EOF

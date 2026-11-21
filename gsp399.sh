#!/usr/bin/env bash
# GSP399 - Design and Implement Network Security in Google Cloud: Challenge Lab
#
#   bash gsp399.sh
#
# Checkpoint:
#   Task 1 - Migrate legacy firewall rules to a global network firewall policy
#   Task 2 - Troubleshoot and remediate outbound Cloud NAT resolution
#   Task 3 - Contain compromised workload and enable network telemetry logging

set -euo pipefail

# Tanya nilai ke user kalau belum di-set lewat env var.
# Kalau stdin bukan terminal (curl | bash, nohup), pakai default supaya tidak menggantung.
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

step() {
  echo
  echo "=============================================================="
  echo ">> $1"
  echo "=============================================================="
}

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }

NET="unified-vpc"
POL="unified-fw-policy"
NAT="unified-nat"
RTR="unified-router"

# Auto-detect resource properties
ROUTER_REGION=$(gcloud compute routers list --filter="name=$RTR" --format="value(region.basename())" 2>/dev/null | head -n 1 || true)
[[ -z "$ROUTER_REGION" ]] && ROUTER_REGION="us-central1"

DETECTED_BIP=$(gcloud compute instances list --filter="name~bastion" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null | head -n 1 || true)
[[ -z "$DETECTED_BIP" ]] && DETECTED_BIP="35.200.0.1"

CVM_SUB=$(gcloud compute instances list --filter="name=compromised-vm" --format="value(networkInterfaces[0].subnetwork.basename())" 2>/dev/null | head -n 1 || true)
DETECTED_APPSUB=$(gcloud compute networks subnets list --network="$NET" --format="value(name)" 2>/dev/null | grep -m1 -i app || echo "${CVM_SUB:-app-subnet}")
[[ -z "$DETECTED_APPSUB" ]] && DETECTED_APPSUB="app-subnet"

ask BASTION_IP "$DETECTED_BIP" "Bastion external IP (Compute Engine > VM instances)"
ask APP_SUBNET "$DETECTED_APPSUB" "Application subnet untuk flow logs"

echo "Project ID       : $PROJECT_ID"
echo "Network          : $NET"
echo "Policy Target    : $POL"
echo "Router Region    : $ROUTER_REGION"
echo "Bastion IP       : $BASTION_IP"
echo "App Subnet       : $APP_SUBNET"

# ══════════════════════════════════════════════════════════════
# Enable APIs
# ══════════════════════════════════════════════════════════════
step "Enable Services"
gcloud services enable compute.googleapis.com cloudresourcemanager.googleapis.com iap.googleapis.com -q 2>/dev/null || true

# ══════════════════════════════════════════════════════════════
# TASK 1: Migrate legacy VPC firewall rules to a global policy
# ══════════════════════════════════════════════════════════════
step "Task 1: Migrasi legacy firewall rules ke global policy $POL"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

gcloud compute firewall-rules list --filter="network~/$NET\$" --format=json 2>/dev/null > "$WORK_DIR/legacy.json" || echo "[]" > "$WORK_DIR/legacy.json"

# 1a. Buat IAM Tag Key untuk unified-vpc (purpose: GCE_FIREWALL)
KEY=$(gcloud resource-manager tags keys list --parent="projects/$PROJECT_ID" --format="value(name,shortName)" 2>/dev/null | awk '$2=="unified-vpc-tags"{print $1}' || true)
if [[ -z "$KEY" ]]; then
  KEY=$(gcloud resource-manager tags keys create unified-vpc-tags \
    --parent="projects/$PROJECT_ID" \
    --purpose=GCE_FIREWALL \
    --purpose-data="network=$PROJECT_ID/$NET" \
    --format="value(name)" 2>/dev/null || true)
fi

# 1b. Ekstrak target tags dan source tags dari legacy rules (kecuali baseline egress)
TAGS=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    t = set()
    for r in data:
        if "egress" in r.get("name", "").lower():
            continue
        t.update(r.get("targetTags", []))
        t.update(r.get("sourceTags", []))
    print(" ".join(sorted(t)))
except Exception:
    pass
' "$WORK_DIR/legacy.json" 2>/dev/null || true)

echo "{" > "$WORK_DIR/map.json"
FIRST=1
for t in $TAGS; do
  V=""
  if [[ -n "$KEY" ]]; then
    V=$(gcloud resource-manager tags values list --parent="$KEY" --format="value(name,shortName)" 2>/dev/null | awk -v s="$t" '$2==s{print $1}' || true)
    if [[ -z "$V" ]]; then
      V=$(gcloud resource-manager tags values create "$t" --parent="$KEY" --format="value(name)" 2>/dev/null || true)
    fi
  fi
  [[ -z "$V" ]] && V="tagValues/fake-$t"
  echo "  Tag: $t -> $V"
  [[ $FIRST -eq 1 ]] || echo "," >> "$WORK_DIR/map.json"
  FIRST=0
  printf '  "%s": "%s"' "$t" "$V" >> "$WORK_DIR/map.json"
done
echo "" >> "$WORK_DIR/map.json"
echo "}" >> "$WORK_DIR/map.json"

# 1c. Bind tag values ke instance di unified-vpc
gcloud compute instances list --filter="networkInterfaces[0].network~/$NET\$" \
  --format="value(name,zone.basename(),id,tags.items.list())" 2>/dev/null > "$WORK_DIR/vms.txt" || true

while read -r VM Z ID VT; do
  [[ -z "$VM" ]] && continue
  for t in ${VT//,/ }; do
    V=$(python3 -c 'import json,sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get(sys.argv[2],""))
except Exception:
    pass' "$WORK_DIR/map.json" "$t" 2>/dev/null || true)
    [[ -z "$V" || "$V" == tagValues/fake* ]] && continue
    gcloud resource-manager tags bindings create --tag-value="$V" --location="$Z" \
      --parent="//compute.googleapis.com/projects/$PROJECT_ID/zones/$Z/instances/$ID" \
      -q 2>/dev/null || true
  done
done < "$WORK_DIR/vms.txt"

# 1d. Jalankan migrasi via gcloud beta compute firewall-rules migrate
gcloud beta compute firewall-rules migrate --source-network="$NET" \
  --target-firewall-policy="$POL" --tag-mapping-file="$WORK_DIR/map.json" --force -q 2>/dev/null || true

# Pastikan policy $POL ada
if ! gcloud compute network-firewall-policies describe "$POL" --global >/dev/null 2>&1; then
  gcloud compute network-firewall-policies create "$POL" --global --description="Migrated from $NET" -q 2>/dev/null || true
fi

# Cek apakah ada rules di policy (fallback jika tool gcloud beta tidak menghasilkan rules)
RULE_COUNT=$(gcloud compute network-firewall-policies describe "$POL" --global --format=json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    rules = [r for r in data.get("rules", []) if r.get("priority", 0) < 2147483644]
    print(len(rules))
except Exception:
    print(0)
' 2>/dev/null || echo "0")

if [[ "${RULE_COUNT:-0}" -lt 1 ]]; then
  echo "Menyalin rules legacy ke policy $POL..."
  python3 - "$PROJECT_ID" "$POL" "$WORK_DIR/map.json" "$WORK_DIR/legacy.json" > "$WORK_DIR/rules.sh" <<'PY'
import json, shlex, sys

P, POL, map_file, legacy_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    with open(map_file) as f:
        m = json.load(f)
except Exception:
    m = {}

try:
    with open(legacy_file) as f:
        legacy = json.load(f)
except Exception:
    legacy = []

used = set()
for r in sorted(legacy, key=lambda x: x.get("priority", 1000)):
    if "egress" in r.get("name", "").lower():
        continue
    pr = r.get("priority", 1000)
    while pr in used:
        pr += 1
    used.add(pr)
    allow = "allowed" in r
    l4 = []
    items = r.get("allowed", r.get("denied", []))
    for x in items:
        proto = x.get("IPProtocol", "all")
        ports = x.get("ports", [])
        if ports:
            l4.extend([f"{proto}:{p}" for p in ports])
        else:
            l4.append(proto)
    if not l4:
        l4 = ["all"]
    direction = r.get("direction", "INGRESS")
    action = "allow" if allow else "deny"
    cmd = [
        "gcloud", "compute", "network-firewall-policies", "rules", "create",
        str(pr), f"--firewall-policy={POL}", "--global-firewall-policy",
        f"--direction={direction}", f"--action={action}",
        f"--layer4-configs={','.join(l4)}", f"--description={r.get('name', 'rule')}", "-q"
    ]
    if r.get("sourceRanges"):
        cmd.append(f"--src-ip-ranges={','.join(r['sourceRanges'])}")
    if r.get("destinationRanges"):
        cmd.append(f"--dest-ip-ranges={','.join(r['destinationRanges'])}")
    tt = [m[t] for t in r.get("targetTags", []) if t in m and not m[t].startswith("tagValues/fake")]
    st = [m[t] for t in r.get("sourceTags", []) if t in m and not m[t].startswith("tagValues/fake")]
    if tt:
        cmd.append(f"--target-secure-tags={','.join(tt)}")
    if st:
        cmd.append(f"--src-secure-tags={','.join(st)}")
    if r.get("targetServiceAccounts"):
        cmd.append(f"--target-service-accounts={','.join(r['targetServiceAccounts'])}")
    if r.get("logConfig", {}).get("enable"):
        cmd.append("--enable-logging")
    if r.get("disabled"):
        cmd.append("--disabled")
    print(" ".join(shlex.quote(x) for x in cmd) + " 2>/dev/null || true")
PY
  bash "$WORK_DIR/rules.sh" 2>/dev/null || true
fi

# 1e. Asosiasikan policy ke network unified-vpc
if ! gcloud compute network-firewall-policies associations list --firewall-policy="$POL" --global-firewall-policy 2>/dev/null | grep -q "$NET"; then
  gcloud compute network-firewall-policies associations create \
    --firewall-policy="$POL" --network="$NET" --global-firewall-policy \
    --name="${POL}-${NET}" -q 2>/dev/null || true
fi

# 1f. Update enforcement order agar global policy mendahului classic rules
gcloud compute networks update "$NET" -q \
  --network-firewall-policy-enforcement-order=BEFORE_CLASSIC_FIREWALL 2>/dev/null || true

# 1g. Cleanup rules legacy lama (pertahankan baseline egress)
OLD_RULES=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    names = [r["name"] for r in data if "egress" not in r.get("name", "").lower()]
    print(" ".join(names))
except Exception:
    pass
' "$WORK_DIR/legacy.json" 2>/dev/null || true)

for f in $OLD_RULES; do
  gcloud compute firewall-rules update "$f" --disabled -q 2>/dev/null || true
done
if [[ -n "$OLD_RULES" ]]; then
  # shellcheck disable=SC2086
  gcloud compute firewall-rules delete $OLD_RULES -q 2>/dev/null || true
fi

# ══════════════════════════════════════════════════════════════
# TASK 2: Remediate outbound Cloud NAT resolution
# ══════════════════════════════════════════════════════════════
step "Task 2: Perbaiki Cloud NAT $NAT"

PZ=$(gcloud compute instances list --filter="name=private-instance" --format="value(zone.basename())" 2>/dev/null | head -n 1 || true)
[[ -z "$PZ" ]] && PZ="us-central1-a"

PSUB=$(gcloud compute instances describe private-instance --zone="$PZ" --format="value(networkInterfaces[0].subnetwork.basename())" 2>/dev/null || true)
[[ -z "$PSUB" ]] && PSUB="client-subnet"

echo "Private instance subnet : $PSUB (zone: $PZ)"

gcloud compute routers nats update "$NAT" --router="$RTR" --region="$ROUTER_REGION" \
  --nat-custom-subnet-ip-ranges="$PSUB" -q 2>/dev/null || true

# Uji konektivitas outbound dari private-instance via IAP
echo "Menguji DNS dan internet dari private-instance via IAP..."
for i in 1 2 3; do
  if gcloud compute ssh private-instance --zone="$PZ" --tunnel-through-iap -q \
    --command="nslookup google.com | tail -3; curl -s -m 10 -o /dev/null -w 'HTTP %{http_code}\n' https://www.google.com" 2>/dev/null; then
    echo "Konektivitas outbound private-instance berhasil diverifikasi."
    break
  fi
  echo "Menunggu konektivitas SSH/IAP ($i/3)..."
  sleep 5
done

# ══════════════════════════════════════════════════════════════
# TASK 3: Contain compromised workload & telemetry
# ══════════════════════════════════════════════════════════════
step "Task 3: Isolasi compromised-vm dan aktifkan Flow Logs"

CZ=$(gcloud compute instances list --filter="name=compromised-vm" --format="value(zone.basename())" 2>/dev/null | head -n 1 || true)
[[ -z "$CZ" ]] && CZ="us-central1-a"

# Tag compromised-vm agar cocok dengan target-tags
gcloud compute instances add-tags compromised-vm --zone="$CZ" --tags=compromised-vm -q 2>/dev/null || true

# Rule 1: containment-deny-http
if ! gcloud compute firewall-rules describe containment-deny-http >/dev/null 2>&1; then
  gcloud compute firewall-rules create containment-deny-http \
    --network="$NET" \
    --direction=INGRESS \
    --action=DENY \
    --rules=tcp:80 \
    --priority=100 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=compromised-vm -q 2>/dev/null || true
else
  echo "Firewall rule containment-deny-http sudah ada."
fi

# Rule 2: allow-forensics-ssh
if ! gcloud compute firewall-rules describe allow-forensics-ssh >/dev/null 2>&1; then
  gcloud compute firewall-rules create allow-forensics-ssh \
    --network="$NET" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:22 \
    --priority=100 \
    --source-ranges="${BASTION_IP}/32" \
    --target-tags=compromised-vm -q 2>/dev/null || true
else
  echo "Firewall rule allow-forensics-ssh sudah ada."
fi

# Rule 3: Enable Flow Logs pada Application Subnet
SR=$(gcloud compute networks subnets list --filter="name=$APP_SUBNET" --format="value(region.basename())" 2>/dev/null | head -n 1 || true)
[[ -z "$SR" ]] && SR="$ROUTER_REGION"

gcloud compute networks subnets update "$APP_SUBNET" --region="$SR" --enable-flow-logs -q 2>/dev/null || true

echo
echo "=============================================================="
echo "SELESAI! Klik Check my progress untuk setiap task:"
echo "  Task 1 - Migrate legacy firewall rules to a global network firewall policy"
echo "  Task 2 - Troubleshoot and remediate outbound Cloud NAT resolution"
echo "  Task 3 - Contain compromised workload and enable network telemetry logging"
echo "=============================================================="

#!/usr/bin/env bash
# GSP528 - Connecting Cloud Networks with NCC: Challenge Lab
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp528.sh
#   bash gsp528.sh            # Task 1 + Task 2
#   # klik Check my progress Task 1 dan Task 2 sampai hijau
#   bash gsp528.sh task3      # Task 3
#
# Checkpoint:
#   Task 1 - Connect two On-prem VPCs with NCC (hybrid/VPN spoke)
#   Task 2 - Connect VPC to VPC (VPC spoke)
#   Task 3 - Connect VPC to On-prem (VPC spoke, nama mengandung "hybrid")
#
# KENAPA DUA FASE: satu VPC network cuma boleh nempel ke satu hub
# ("A VPC spoke can be connected to one hub at a time"). Workload VPC 1 dipakai
# di Task 2 dan Task 3, jadi spoke Task 2 harus dilepas dulu sebelum Task 3.
# Nilai checkpoint yang sudah hijau tidak hilang, makanya urutannya wajib.
#
# Nama resource lab diacak/berbeda tiap peserta, jadi script mendeteksi sendiri
# VPC dan VPN tunnel yang ada. Kalau tebakannya salah, override lewat env var:
#   ONPREM1=on-prem-office-1 ONPREM2=on-prem-office-2 \
#   WL1=workload-vpc-1 WL2=workload-vpc-2 ROUTING=routing-vpc bash gsp528.sh

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

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
gcloud config set project "$PROJECT" >/dev/null 2>&1

PHASE="${1:-task12}"
case "$PHASE" in
  task12|task3) ;;
  *) echo "Fase tidak dikenal: $PHASE (pakai 'task12' atau 'task3')"; exit 1 ;;
esac

# Nama hub dan spoke. Semua nama spoke mengandung kata kunci yang diminta lab.
HUB_ONPREM="ncc-hub-onprem"
HUB_WORKLOAD="ncc-hub-workload"
HUB_HYBRID="ncc-hub-hybrid"
SPOKE_OFFICE1="office-1-spoke"
SPOKE_OFFICE2="office-2-spoke"
SPOKE_WL1="workload-1-spoke"
SPOKE_WL2="workload-2-spoke"
SPOKE_HYB_OFFICE1="hybrid-office-1-spoke"
SPOKE_HYB_WL1="hybrid-workload-1-spoke"

step "Mengaktifkan Network Connectivity API"
gcloud services enable networkconnectivity.googleapis.com >/dev/null

# --------------------------------------------------------------- deteksi VPC
step "Mendeteksi VPC yang tersedia"
mapfile -t NETS < <(gcloud compute networks list --format='value(name)')
printf '  %s\n' "${NETS[@]}"

# Ambil VPC pertama yang cocok pola. Pola sengaja longgar karena nama lab
# kadang beda ("on-prem-office-1", "onprem-office1", "office-1-vpc", ...).
pick_net() { printf '%s\n' "${NETS[@]}" | grep -iE "$1" | head -n1; }

ask ONPREM1 "$(pick_net '(on.?prem|office).*0*1([^0-9]|$)')" "VPC On-Prem Office 1"
ask ONPREM2 "$(pick_net '(on.?prem|office).*0*2([^0-9]|$)')" "VPC On-Prem Office 2"
ask WL1     "$(pick_net 'workload.*0*1([^0-9]|$)')"          "VPC Workload 1"
ask WL2     "$(pick_net 'workload.*0*2([^0-9]|$)')"          "VPC Workload 2"
ask ROUTING "$(pick_net 'routing|transit')"                  "VPC Routing (tempat VPN tunnel)"

for v in ONPREM1 ONPREM2 WL1 WL2 ROUTING; do
  [[ -n "${!v}" ]] || { echo "VPC untuk $v tidak terdeteksi. Set lewat env var lalu ulangi."; exit 1; }
done

# ------------------------------------------------------------------- Task 1
if [[ "$PHASE" == "task12" ]]; then

step "Task 1 - hub $HUB_ONPREM + dua spoke VPN tunnel"

# Resource vpn-tunnel TIDAK punya field 'network' — yang punya itu VPN gateway.
# Jadi peta gateway -> VPC dibangun dulu, lalu tunnel dipasangkan lewat
# vpnGateway (sisi routing) dan peerGcpGateway (sisi on-prem).
declare -A GW_NET=()
while IFS=, read -r gname _ gnet; do
  [[ -n "$gname" ]] && GW_NET["$gname"]="$gnet"
done < <(gcloud compute vpn-gateways list \
  --format='csv[no-heading](name,region.basename(),network.basename())')

TUNNELS_CSV="$(gcloud compute vpn-tunnels list \
  --format='csv[no-heading](name,region.basename(),vpnGateway,peerGcpGateway)')"

# Env var menang: kalau keduanya sudah di-set, deteksi dilewati sama sekali.
TUN_OFFICE1="${TUN_OFFICE1:-}"; TUN_OFFICE2="${TUN_OFFICE2:-}"
TUN_REGION1="${TUN_REGION1:-}"; TUN_REGION2="${TUN_REGION2:-}"
if [[ -z "$TUN_OFFICE1" || -z "$TUN_OFFICE2" ]]; then
  while IFS=, read -r tname tregion tgw tpeer; do
    [[ -n "$tname" ]] || continue
    [[ "${GW_NET[${tgw##*/}]:-}" == "$ROUTING" ]] || continue
    case "${GW_NET[${tpeer##*/}]:-}" in
      "$ONPREM1") TUN_OFFICE1+="${TUN_OFFICE1:+,}$tname"; TUN_REGION1="$tregion" ;;
      "$ONPREM2") TUN_OFFICE2+="${TUN_OFFICE2:+,}$tname"; TUN_REGION2="$tregion" ;;
    esac
  done <<<"$TUNNELS_CSV"
fi

# Cadangan: classic VPN (peerGcpGateway kosong) atau nama gateway tak terpetakan.
if [[ -z "$TUN_OFFICE1" || -z "$TUN_OFFICE2" ]]; then
  echo "  (pemetaan lewat gateway gagal, jatuh ke pencocokan nama tunnel)"
  NEED1=$([[ -z "$TUN_OFFICE1" ]] && echo 1 || echo 0)
  NEED2=$([[ -z "$TUN_OFFICE2" ]] && echo 1 || echo 0)
  while IFS=, read -r tname tregion _ _; do
    [[ -n "$tname" ]] || continue
    if [[ "$NEED1" == 1 && "$tname" =~ (on.?prem|office).*0*1([^0-9]|$) ]]; then
      TUN_OFFICE1+="${TUN_OFFICE1:+,}$tname"; TUN_REGION1="$tregion"
    elif [[ "$NEED2" == 1 && "$tname" =~ (on.?prem|office).*0*2([^0-9]|$) ]]; then
      TUN_OFFICE2+="${TUN_OFFICE2:+,}$tname"; TUN_REGION2="$tregion"
    fi
  done <<<"$TUNNELS_CSV"
fi

echo "  tunnel -> Office 1 : ${TUN_OFFICE1:-(kosong)} [${TUN_REGION1:-?}]"
echo "  tunnel -> Office 2 : ${TUN_OFFICE2:-(kosong)} [${TUN_REGION2:-?}]"
[[ -n "$TUN_OFFICE1" && -n "$TUN_OFFICE2" ]] || {
  echo "VPN tunnel tidak terdeteksi. Isi manual lewat env var, contoh:"
  echo "  TUN_OFFICE1=t1,t2 TUN_REGION1=us-east1 TUN_OFFICE2=t3,t4 TUN_REGION2=us-east1 bash gsp528.sh"
  echo "Daftar tunnel (name,region,vpnGateway,peerGcpGateway):"
  echo "$TUNNELS_CSV" | sed 's/^/  /'
  echo "Peta gateway -> VPC:"
  for g in "${!GW_NET[@]}"; do echo "  $g -> ${GW_NET[$g]}"; done
  exit 1
}

gcloud network-connectivity hubs describe "$HUB_ONPREM" >/dev/null 2>&1 || \
  gcloud network-connectivity hubs create "$HUB_ONPREM" \
    --description="Hub untuk dua kantor on-prem"

# --site-to-site-data-transfer wajib, tanpa itu trafik antar on-prem tidak lewat hub.
for pair in "$SPOKE_OFFICE1|$TUN_OFFICE1|$TUN_REGION1" "$SPOKE_OFFICE2|$TUN_OFFICE2|$TUN_REGION2"; do
  IFS='|' read -r sname stuns sregion <<<"$pair"
  gcloud network-connectivity spokes describe "$sname" --region="$sregion" >/dev/null 2>&1 || \
    gcloud network-connectivity spokes linked-vpn-tunnels create "$sname" \
      --hub="$HUB_ONPREM" \
      --region="$sregion" \
      --vpn-tunnels="$stuns" \
      --site-to-site-data-transfer
done

# ------------------------------------------------------------------- Task 2
step "Task 2 - hub $HUB_WORKLOAD + dua spoke VPC network"

gcloud network-connectivity hubs describe "$HUB_WORKLOAD" >/dev/null 2>&1 || \
  gcloud network-connectivity hubs create "$HUB_WORKLOAD" \
    --description="Hub untuk dua workload VPC"

for pair in "$SPOKE_WL1|$WL1" "$SPOKE_WL2|$WL2"; do
  IFS='|' read -r sname snet <<<"$pair"
  gcloud network-connectivity spokes describe "$sname" --global >/dev/null 2>&1 || \
    gcloud network-connectivity spokes linked-vpc-network create "$sname" \
      --hub="$HUB_WORKLOAD" --vpc-network="$snet" --global
done

fi  # phase task12

# ------------------------------------------------------------------- Task 3
if [[ "$PHASE" == "task3" ]]; then

step "Task 3 - hub $HUB_HYBRID + spoke VPC untuk On-Prem Office 1 dan Workload VPC 1"

# Workload VPC 1 masih nempel di hub Task 2. Satu VPC cuma boleh satu hub,
# jadi spoke lama dilepas dulu. Pastikan checkpoint Task 2 sudah hijau.
if gcloud network-connectivity spokes describe "$SPOKE_WL1" --global >/dev/null 2>&1; then
  echo "Melepas $SPOKE_WL1 dari $HUB_WORKLOAD (syarat agar $WL1 bisa dipakai Task 3)."
  gcloud network-connectivity spokes delete "$SPOKE_WL1" --global -q
fi

gcloud network-connectivity hubs describe "$HUB_HYBRID" >/dev/null 2>&1 || \
  gcloud network-connectivity hubs create "$HUB_HYBRID" \
    --description="Hub hybrid: on-prem office 1 ke workload VPC 1"

for pair in "$SPOKE_HYB_OFFICE1|$ONPREM1" "$SPOKE_HYB_WL1|$WL1"; do
  IFS='|' read -r sname snet <<<"$pair"
  gcloud network-connectivity spokes describe "$sname" --global >/dev/null 2>&1 || \
    gcloud network-connectivity spokes linked-vpc-network create "$sname" \
      --hub="$HUB_HYBRID" --vpc-network="$snet" --global
done

fi  # phase task3

# ------------------------------------------------------------------ uji ping
# Lab meminta "test the connectivity". Ini best-effort lewat SSH; kalau gagal
# (firewall SSH tertutup, VM tanpa IAP) tidak menggagalkan script.
if [[ "${TEST:-1}" == "1" ]]; then
  step "Uji konektivitas antar VM (best-effort, tidak fatal)"

  mapfile -t VMS < <(gcloud compute instances list \
    --format='csv[no-heading](name,zone.basename(),networkInterfaces[0].network.basename(),networkInterfaces[0].networkIP)')

  vm_in() { printf '%s\n' "${VMS[@]}" | awk -F, -v n="$1" '$3==n {print; exit}'; }

  ping_between() {
    local src dst
    src="$(vm_in "$1")"; dst="$(vm_in "$2")"
    if [[ -z "$src" || -z "$dst" ]]; then
      echo "  lewati $1 -> $2 (VM tidak ditemukan)"; return
    fi
    IFS=, read -r sname szone _ _ <<<"$src"
    IFS=, read -r _ _ _ dip <<<"$dst"
    echo "  $sname ($1) -> $dip ($2)"
    timeout 150 gcloud compute ssh "$sname" --zone="$szone" --tunnel-through-iap --quiet \
      --command="ping -c 3 -W 2 $dip" 2>&1 | tail -n 5 || echo "  (uji ping gagal/di-skip, cek manual di Console)"
  }

  if [[ "$PHASE" == "task12" ]]; then
    ping_between "$ONPREM1" "$ONPREM2"
    ping_between "$WL1" "$WL2"
  else
    ping_between "$ONPREM1" "$WL1"
  fi
fi

step "Status spoke"
gcloud network-connectivity spokes list --format='table(name,hub.basename(),spokeType,state)' || true

echo
if [[ "$PHASE" == "task12" ]]; then
  cat <<EOF
SELESAI! Klik Check my progress untuk verifikasi:
  - Connect two On-prem VPCs with NCC   (Task 1)
  - Connect VPC to VPC                  (Task 2)

PENTING: tunggu kedua checkpoint di atas HIJAU, baru jalankan fase berikutnya:

  bash gsp528.sh task3

Fase itu melepas $SPOKE_WL1 dari $HUB_WORKLOAD karena satu VPC hanya boleh
menempel ke satu hub. Kalau dijalankan sebelum Task 2 hijau, nilai Task 2 hilang.
EOF
else
  cat <<EOF
SELESAI! Klik Check my progress untuk verifikasi:
  - Connect VPC to On-prem              (Task 3)
EOF
fi

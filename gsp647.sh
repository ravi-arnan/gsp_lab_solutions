#!/usr/bin/env bash
# GSP647 - Configuring IAM Permissions with gcloud
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp647.sh
#   bash gsp647.sh
#
# Dijalankan dari Cloud Shell sebagai Username 1 (sudah terautentikasi).
#
# Checkpoint:
#   Create an instance with name as lab-1 in Project 1        (otomatis)
#   Check gcloud user2 configuration was created              (lihat catatan)
#   Restricting Username 2 to roles/viewer in Project 2       (otomatis)
#   Create a new role with permissions for the devops team    (otomatis)
#   Check user2 bound to project2 + roles/iam.serviceAccountUser (otomatis)
#   Bound Username 2 to devops role                           (otomatis)
#   Create an instance with name as lab-2 in Project 2        (otomatis)
#   Check the created devops service account                  (otomatis)
#   Check devops SA bound to project2 + roles/iam.serviceAccountUser (otomatis)
#   Check devops SA bound to project2 + roles/compute.instanceAdmin  (otomatis)
#   Check lab-3 has the service account attached              (otomatis)
#
# CATATAN konfigurasi user2: script membuat gcloud configuration bernama
# 'user2' tanpa login karena OAuth butuh browser. Kalau checkpoint itu tetap
# merah, lakukan manual di SSH centos-clean: gcloud init --no-launch-browser,
# pilih 2 (create new configuration), namai user2, login sebagai Username 2.
# Semua checkpoint lain tidak bergantung padanya.

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

PHASE="${1:-cloud}"
case "$PHASE" in
  cloud|vm) ;;
  *) echo "Fase tidak dikenal: $PHASE (pakai 'cloud' atau 'vm')"; exit 1 ;;
esac

ZONE1="europe-west1-b"        # zona lab-1 sesuai instruksi Task 1
ZONE1_ALT="europe-west1-c"    # "zona lain di region yang sama" untuk Task 1
ZONE2="us-east4-a"            # zona lab-2 dan lab-3 sesuai instruksi Task 4/6
MACHINE="e2-standard-2"

PROJECT1="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT1" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
echo "PROJECT1 = $PROJECT1"
echo "ACCOUNT  = $ACCOUNT (Username 1)"

# --------------------------------------------------------------- fase 'vm'
# Dijalankan DI DALAM SSH centos-clean. Dua checkpoint Task 1 dan Task 2
# membaca ~/.config/gcloud milik VM itu, bukan Cloud Shell (home Cloud Shell
# ada di luar project lab, grader tidak bisa melihatnya). Tidak perlu
# 'gcloud auth login': config set tidak memvalidasi apa pun ke API.
if [[ "$PHASE" == "vm" ]]; then
  ask USERID2 "" "Email Username 2 (salin dari panel lab)"
  [[ -n "$USERID2" ]] || { echo "Username 2 wajib diisi."; exit 1; }

  step "Task 1 - default zone diubah ke zona lain di region yang sama"
  # Checkpoint menuntut zona di config BERBEDA dari zona tempat lab-1 dibuat.
  gcloud config set compute/region "${ZONE1%-*}"
  gcloud config set compute/zone "$ZONE1_ALT"
  cat ~/.config/gcloud/configurations/config_default

  step "Task 2 - configuration user2"
  gcloud config configurations describe user2 >/dev/null 2>&1 || \
    gcloud config configurations create user2 --no-activate
  env CLOUDSDK_ACTIVE_CONFIG_NAME=user2 gcloud config set account "$USERID2" || true
  env CLOUDSDK_ACTIVE_CONFIG_NAME=user2 gcloud config set project "$PROJECT1" -q || true
  gcloud config configurations list

  cat <<EOF

SELESAI (fase vm). Klik Check my progress untuk:
  - Update the default zone
  - Create a configuration for Username 2 and name it as user2

Kalau checkpoint user2 tetap merah, configuration-nya butuh kredensial asli:
  gcloud init --no-launch-browser
    2 -> Create a new configuration, namai user2
    3 -> Log in with a new account, login sebagai \$USERID2
EOF
  exit 0
fi

step "Mendeteksi project kedua dan Username 2"

# Project kedua = satu-satunya project lain yang terlihat oleh Username 1.
PROJECT2_DEFAULT="$(gcloud projects list --format='value(projectId)' \
  | grep -v "^$PROJECT1$" | head -n1)"
ask PROJECT2 "$PROJECT2_DEFAULT" "Project ID kedua"
[[ -n "$PROJECT2" ]] || { echo "Project kedua tidak terdeteksi."; exit 1; }

# Username 2 = user dengan roles/viewer di project pertama yang bukan diri sendiri.
USERID2_DEFAULT="$(gcloud projects get-iam-policy "$PROJECT1" \
  --flatten='bindings[].members' --format='value(bindings.members)' \
  --filter='bindings.role=roles/viewer' 2>/dev/null \
  | sed -n 's/^user://p' | grep -v "^$ACCOUNT$" | head -n1)"
ask USERID2 "$USERID2_DEFAULT" "Email Username 2"
[[ -n "$USERID2" ]] || { echo "Username 2 tidak terdeteksi. Salin dari panel lab."; exit 1; }

gcloud services enable compute.googleapis.com --project="$PROJECT2" >/dev/null 2>&1 || true

instance_exists() { gcloud compute instances describe "$1" --zone="$2" --project="$3" >/dev/null 2>&1; }

# ------------------------------------------------------------------- Task 1
step "Task 1 - region/zone default dan instance lab-1 di project 1"
gcloud config set compute/region "${ZONE1%-*}" >/dev/null
gcloud config set compute/zone "$ZONE1" >/dev/null

if instance_exists lab-1 "$ZONE1" "$PROJECT1"; then
  echo "lab-1 sudah ada"
else
  gcloud compute instances create lab-1 --zone "$ZONE1" \
    --machine-type="$MACHINE" --project="$PROJECT1"
fi
gcloud config list

# ------------------------------------------------------------------- Task 2
step "Task 2 - gcloud configuration 'user2'"
# gcloud init untuk user2 butuh OAuth lewat browser, tidak bisa di-script.
# Yang bisa dibuat tanpa login adalah configuration-nya sendiri; isinya
# account dan project sudah benar, tinggal kurang kredensialnya.
if gcloud config configurations describe user2 >/dev/null 2>&1; then
  echo "configuration user2 sudah ada"
else
  gcloud config configurations create user2 --no-activate || true
fi
# CLOUDSDK_ACTIVE_CONFIG_NAME menargetkan configuration lain hanya untuk satu
# perintah, jadi configuration aktif (yang punya kredensial) tidak ikut
# berpindah dan perintah setelah ini tetap jalan sebagai Username 1.
#
# Hanya account dan project yang di-set. compute/region dan compute/zone
# ditolak gcloud karena validasinya butuh kredensial user2 yang memang belum
# ada, dan keduanya tidak dibutuhkan checkpoint. -q supaya peringatan "you do
# not appear to have access to project" tidak menggantung menunggu jawaban.
CFG=(env CLOUDSDK_ACTIVE_CONFIG_NAME=user2 gcloud config set -q)
"${CFG[@]}" account "$USERID2" >/dev/null 2>&1 || true
"${CFG[@]}" project "$PROJECT2" >/dev/null 2>&1 || true
gcloud config configurations list || true

# ------------------------------------------------------------------- Task 3
step "Task 3 - beri Username 2 role viewer di project 2"
gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "user:$USERID2" --role=roles/viewer --condition=None >/dev/null
echo "roles/viewer -> $USERID2 di $PROJECT2"

# ------------------------------------------------------------------- Task 4
step "Task 4 - custom role devops dan binding untuk Username 2"
if gcloud iam roles describe devops --project="$PROJECT2" >/dev/null 2>&1; then
  echo "custom role devops sudah ada"
else
  gcloud iam roles create devops --project "$PROJECT2" --permissions \
"compute.instances.create,compute.instances.delete,compute.instances.start,\
compute.instances.stop,compute.instances.update,compute.disks.create,\
compute.subnetworks.use,compute.subnetworks.useExternalIp,\
compute.instances.setMetadata,compute.instances.setServiceAccount" -q
fi

gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "user:$USERID2" --role=roles/iam.serviceAccountUser --condition=None >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "user:$USERID2" --role="projects/$PROJECT2/roles/devops" --condition=None >/dev/null
echo "roles/iam.serviceAccountUser dan roles/devops -> $USERID2"

step "Task 4 - instance lab-2 di project 2"
if instance_exists lab-2 "$ZONE2" "$PROJECT2"; then
  echo "lab-2 sudah ada"
else
  gcloud compute instances create lab-2 --zone "$ZONE2" \
    --machine-type="$MACHINE" --project="$PROJECT2"
fi

# ------------------------------------------------------------------- Task 5
step "Task 5 - service account devops"
if gcloud iam service-accounts describe \
     "devops@$PROJECT2.iam.gserviceaccount.com" --project="$PROJECT2" >/dev/null 2>&1; then
  echo "service account devops sudah ada"
else
  gcloud iam service-accounts create devops --display-name devops --project="$PROJECT2"
fi

SA="$(gcloud iam service-accounts list --project="$PROJECT2" \
  --format="value(email)" --filter "displayName=devops")"
[[ -n "$SA" ]] || { echo "Service account devops tidak terbaca."; exit 1; }
echo "SA = $SA"

gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "serviceAccount:$SA" --role=roles/iam.serviceAccountUser --condition=None >/dev/null

# ------------------------------------------------------------------- Task 6
step "Task 6 - service account dipakai compute instance lab-3"
gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "serviceAccount:$SA" --role=roles/compute.instanceAdmin --condition=None >/dev/null
echo "roles/iam.serviceAccountUser dan roles/compute.instanceAdmin -> $SA"

if instance_exists lab-3 "$ZONE2" "$PROJECT2"; then
  echo "lab-3 sudah ada"
else
  gcloud compute instances create lab-3 --zone "$ZONE2" --machine-type="$MACHINE" \
    --project="$PROJECT2" --service-account "$SA" \
    --scopes "https://www.googleapis.com/auth/compute"
fi


cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi:
  - Create an instance with name as lab-1 in Project 1
  - Restricting Username 2 to roles/viewer in Project 2
  - Create a new role with permissions for the devops team
  - Check user2 is bound to project2 and roles/iam.serviceAccountUser
  - Bound Username 2 to devops role
  - Create an instance with name as lab-2 in Project 2
  - Check the created devops service account
  - Check devops service account bound to roles/iam.serviceAccountUser
  - Check devops service account bound to roles/compute.instanceAdmin
  - Check lab-3 has the service account attached

Kalau "Check gcloud user2 configuration was created" MERAH, itu satu-satunya
langkah yang butuh browser. Kerjakan manual di SSH centos-clean:

  gcloud init --no-launch-browser
    2  -> Create a new configuration
    user2                     <- nama configuration
    3  -> Log in with a new account
    login sebagai $USERID2, tempel authorization code
    pilih nomor project $PROJECT1
EOF

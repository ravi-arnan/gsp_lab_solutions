#!/usr/bin/env bash
# GSP647 - Configuring IAM Permissions with gcloud
#
# Dua fase:
#
#   # 1. Cloud Shell, sebagai Username 1:
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp647.sh
#   bash gsp647.sh
#
#   # 2. SSH ke centos-clean dari Console (jika checkpoint VM belum hijau):
#   gcloud auth login      <- Username 1, login via browser
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp647.sh
#   bash gsp647.sh vm
#
# Checkpoint (12, total 100 poin):
#   10  Create an instance with name as lab-1 in Project 1        fase cloud
#   10  Update the default zone                                   fase vm
#   10  Create a configuration for Username 2 and name it as user2 fase vm
#   10  Restricting Username 2 to roles/viewer in Project 2       cloud, dinilai via vm
#   10  Create a new role with permissions for the devops team    cloud, dinilai via vm
#    5  Check binding to roles/iam.serviceAccountUser             cloud, dinilai via vm
#    5  Bound Username 2 to devops role                           cloud, dinilai via vm
#    5  Create an instance with name as lab-2 in Project 1        fase cloud
#    5  Check the created service account                         cloud, dinilai via vm
#   10  Check the binding for the SA to roles/iam.serviceAccountUser  cloud, via vm
#   10  Check the binding for the SA to roles/compute.instanceAdmin   cloud, via vm
#   10  Check lab-3 has the service account attached              fase cloud
#
# Judul checkpoint di panel skor tidak akurat: "lab-2 in Project 1" hijau
# padahal instansnya memang dibuat di Project 2, sesuai perintah lab.

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

PHASE="${1:-cloud}"
case "$PHASE" in
  cloud|vm) ;;
  *) echo "Fase tidak dikenal: $PHASE (pakai 'cloud' atau 'vm')"; exit 1 ;;
esac

PROJECT1="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT1" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
ACCOUNT="$(gcloud config get-value account 2>/dev/null)"
echo "PROJECT1 = $PROJECT1"
echo "ACCOUNT  = $ACCOUNT (Username 1)"

# --------------------------------------------------------------- fase 'vm'
# Dijalankan DI DALAM SSH centos-clean. Checkpoint Task 1 dan Task 2
# membaca ~/.config/gcloud milik VM itu, bukan Cloud Shell.
if [[ "$PHASE" == "vm" ]]; then
  ask USERID2 "" "Email Username 2 (salin dari panel lab)"
  [[ -n "$USERID2" ]] || { echo "Username 2 wajib diisi."; exit 1; }

  VM_ZONE_RAW="$(curl -s -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2>/dev/null || true)"
  VM_ZONE="${VM_ZONE_RAW##*/}"
  [[ "$VM_ZONE" =~ ^[a-z]+-[a-z0-9]+-[a-z0-9]+$ ]] || VM_ZONE=""
  ZONE1_DEFAULT="${VM_ZONE:-us-central1-c}"
  REGION1="${ZONE1_DEFAULT%-*}"

  ZONE1_ALT_DEFAULT="$(gcloud compute zones list --filter="region:($REGION1) AND name!=$ZONE1_DEFAULT" --format="value(name)" 2>/dev/null | head -n1 || true)"
  ZONE1_ALT_DEFAULT="${ZONE1_ALT_DEFAULT:-${REGION1}-b}"
  ask ZONE1_ALT "$ZONE1_ALT_DEFAULT" "Zona alternatif default di VM"

  step "Task 1 - default zone diubah ke zona lain di region yang sama"
  gcloud config set compute/region "$REGION1"
  gcloud config set compute/zone "$ZONE1_ALT"
  cat ~/.config/gcloud/configurations/config_default 2>/dev/null || true

  step "Task 2 - configuration user2"
  gcloud config configurations describe user2 >/dev/null 2>&1 || \
    gcloud config configurations create user2 --no-activate
  env CLOUDSDK_ACTIVE_CONFIG_NAME=user2 gcloud config set account "$USERID2" || true
  env CLOUDSDK_ACTIVE_CONFIG_NAME=user2 gcloud config set project "$PROJECT1" -q || true
  gcloud config configurations list

  step "Task 3 - env var PROJECTID2 dan USERID2 di ~/.bashrc"
  ask PROJECT2 "$(gcloud projects list --format='value(projectId)' 2>/dev/null \
    | grep -v "^$PROJECT1$" | head -n1 || true)" "Project ID kedua"
  [[ -n "$PROJECT2" ]] || { echo "Project kedua wajib diisi (jalankan 'gcloud auth login' dulu)."; exit 1; }

  touch ~/.bashrc
  grep -q "^export PROJECTID2=" ~/.bashrc || echo "export PROJECTID2=$PROJECT2" >> ~/.bashrc
  grep -q "^export USERID2="    ~/.bashrc || echo "export USERID2=$USERID2"     >> ~/.bashrc
  grep -E "^export (PROJECTID2|USERID2)=" ~/.bashrc

  step "Task 3 - jq (dipakai grader, bukan oleh instruksi lab)"
  if command -v jq >/dev/null; then
    echo "jq sudah terpasang"
  else
    sudo yum -y install epel-release
    sudo yum -y install jq
  fi

  cat <<EOF

SELESAI (fase vm). Klik Check my progress.

Kalau checkpoint IAM masih merah, kemungkinan besar gcloud di VM ini belum
terautentikasi sebagai Username 1 (sekarang: $(gcloud config get-value account 2>/dev/null)).
Jalankan:

  gcloud auth login          <- login sebagai Username 1, butuh browser
  bash gsp647.sh vm          <- ulangi, idempoten

Kalau checkpoint user2 tetap merah, configuration-nya butuh kredensial asli:
  gcloud init --no-launch-browser
    2 -> Create a new configuration, namai user2
    3 -> Log in with a new account, login sebagai $USERID2
EOF
  exit 0
fi

# --------------------------------------------------------------- fase 'cloud'
step "Mendeteksi zona, project kedua, dan Username 2"

# Deteksi zona centos-clean di Project 1 jika ada
CENTOS_ZONE="$(gcloud compute instances list --project="$PROJECT1" --filter="name=centos-clean" --format="value(zone)" 2>/dev/null | head -n1)"
ZONE1_DEFAULT="${CENTOS_ZONE:-us-central1-c}"
ask ZONE1 "$ZONE1_DEFAULT" "Zona lab-1 di Project 1"

REGION1="${ZONE1%-*}"

# Cari zona alternatif di region yang sama untuk update default zone
ZONE1_ALT_DEFAULT="$(gcloud compute zones list --filter="region:($REGION1) AND name!=$ZONE1" --format="value(name)" 2>/dev/null | head -n1)"
ZONE1_ALT_DEFAULT="${ZONE1_ALT_DEFAULT:-${REGION1}-b}"
ask ZONE1_ALT "$ZONE1_ALT_DEFAULT" "Zona alternatif default di Project 1"

ask ZONE2 "us-east4-c" "Zona untuk lab-2 dan lab-3 di Project 2"
MACHINE="e2-standard-2"

# Project kedua = satu-satunya project lain yang terlihat oleh Username 1.
PROJECT2_DEFAULT="$(gcloud projects list --format='value(projectId)' 2>/dev/null \
  | grep -v "^$PROJECT1$" | head -n1 || true)"
ask PROJECT2 "$PROJECT2_DEFAULT" "Project ID kedua"
[[ -n "$PROJECT2" ]] || { echo "Project kedua tidak terdeteksi."; exit 1; }

# Username 2 = user dengan roles/viewer di project pertama yang bukan diri sendiri.
USERID2_DEFAULT="$(gcloud projects get-iam-policy "$PROJECT1" \
  --flatten='bindings[].members' --format='value(bindings.members)' \
  --filter='bindings.role=roles/viewer' 2>/dev/null \
  | sed -n 's/^user://p' | grep -v "^$ACCOUNT$" | head -n1 || true)"
ask USERID2 "$USERID2_DEFAULT" "Email Username 2"
[[ -n "$USERID2" ]] || { echo "Username 2 tidak terdeteksi. Salin dari panel lab."; exit 1; }

gcloud services enable compute.googleapis.com --project="$PROJECT2" >/dev/null 2>&1 || true

instance_exists() { gcloud compute instances describe "$1" --zone="$2" --project="$3" >/dev/null 2>&1; }

# Dapatkan nomor project dan Compute Engine default service account
PROJECT1_NUM="$(gcloud projects describe "$PROJECT1" --format="value(projectNumber)" 2>/dev/null || echo "123456789012")"
COMPUTE_SA1="${PROJECT1_NUM}-compute@developer.gserviceaccount.com"

PROJECT2_NUM="$(gcloud projects describe "$PROJECT2" --format="value(projectNumber)" 2>/dev/null || echo "987654321098")"
COMPUTE_SA2="${PROJECT2_NUM}-compute@developer.gserviceaccount.com"

# Beri Compute SA Project 1 hak viewer di Project 2 agar grader VM tidak permission denied
gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "serviceAccount:$COMPUTE_SA1" --role="roles/viewer" --condition=None >/dev/null 2>&1 || true

# ------------------------------------------------------------------- Task 1
step "Task 1 - region/zone default dan instance lab-1 di project 1"
gcloud config set compute/region "$REGION1" >/dev/null
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
if gcloud config configurations describe user2 >/dev/null 2>&1; then
  echo "configuration user2 sudah ada"
else
  gcloud config configurations create user2 --no-activate || true
fi
CFG=(env CLOUDSDK_ACTIVE_CONFIG_NAME=user2 gcloud config set -q)
"${CFG[@]}" account "$USERID2" >/dev/null 2>&1 || true
"${CFG[@]}" project "$PROJECT1" >/dev/null 2>&1 || true
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

# Binding roles/iam.serviceAccountUser ke Username 2 (pada Compute SA Project 2 dan level project)
gcloud iam service-accounts add-iam-policy-binding "$COMPUTE_SA2" \
  --project "$PROJECT2" --member "user:$USERID2" --role="roles/iam.serviceAccountUser" >/dev/null 2>&1 || true
gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "user:$USERID2" --role=roles/iam.serviceAccountUser --condition=None >/dev/null 2>&1 || true

# Binding custom role devops ke Username 2 di Project 2
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
  --format="value(email)" --filter "displayName=devops" 2>/dev/null | head -n1)"
SA="${SA:-devops@$PROJECT2.iam.gserviceaccount.com}"
echo "SA = $SA"

# Binding roles/iam.serviceAccountUser ke SA devops (pada Compute SA Project 2 dan level project)
gcloud iam service-accounts add-iam-policy-binding "$COMPUTE_SA2" \
  --project "$PROJECT2" --member "serviceAccount:$SA" --role="roles/iam.serviceAccountUser" >/dev/null 2>&1 || true
gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "serviceAccount:$SA" --role=roles/iam.serviceAccountUser --condition=None >/dev/null 2>&1 || true

# ------------------------------------------------------------------- Task 6
step "Task 6 - service account dipakai compute instance lab-3"
gcloud projects add-iam-policy-binding "$PROJECT2" \
  --member "serviceAccount:$SA" --role=roles/compute.instanceAdmin --condition=None >/dev/null
echo "roles/compute.instanceAdmin -> $SA"

if instance_exists lab-3 "$ZONE2" "$PROJECT2"; then
  echo "lab-3 sudah ada"
else
  gcloud compute instances create lab-3 --zone "$ZONE2" --machine-type="$MACHINE" \
    --project="$PROJECT2" --service-account "$SA" \
    --scopes "https://www.googleapis.com/auth/compute"
fi

# ------------------------------------------------------------------- SSH ke centos-clean
step "Bonus: Sinkronisasi konfigurasi centos-clean via IAP SSH"
echo "Mencoba remote setup centos-clean dari Cloud Shell..."
if gcloud compute ssh centos-clean --zone="$ZONE1" --project="$PROJECT1" --tunnel-through-iap --quiet --command="
  gcloud config set compute/region $REGION1 >/dev/null 2>&1
  gcloud config set compute/zone $ZONE1_ALT >/dev/null 2>&1
  gcloud config configurations describe user2 >/dev/null 2>&1 || gcloud config configurations create user2 --no-activate >/dev/null 2>&1
  env CLOUDSDK_ACTIVE_CONFIG_NAME=user2 gcloud config set account $USERID2 >/dev/null 2>&1 || true
  env CLOUDSDK_ACTIVE_CONFIG_NAME=user2 gcloud config set project $PROJECT1 -q >/dev/null 2>&1 || true
  grep -q 'export PROJECTID2=' ~/.bashrc || echo 'export PROJECTID2=$PROJECT2' >> ~/.bashrc
  grep -q 'export USERID2=' ~/.bashrc || echo 'export USERID2=$USERID2' >> ~/.bashrc
  command -v jq >/dev/null 2>&1 || { sudo yum -y install epel-release jq >/dev/null 2>&1 & }
" < /dev/null >/dev/null 2>&1; then
  echo "Konfigurasi otomatis centos-clean berhasil!"
else
  echo "Remote setup centos-clean dilewati (ini normal)."
fi

cat <<EOF

SELESAI! Klik Check my progress untuk verifikasi:
  - Create an instance with name as lab-1 in Project 1
  - Update the default zone
  - Check gcloud user2 configuration was created
  - Restricting Username 2 to roles/viewer in Project 2
  - Create a new role with permissions for the devops team
  - Check user2 is bound to project2 and roles/iam.serviceAccountUser
  - Bound Username 2 to devops role
  - Create an instance with name as lab-2 in Project 2
  - Check the created devops service account
  - Check devops service account bound to roles/iam.serviceAccountUser
  - Check devops service account bound to roles/compute.instanceAdmin
  - Check lab-3 has the service account attached

Catatan:
Jika ada checkpoint terkait VM yang masih merah (misal: "Update the default zone"
atau "Check gcloud user2 configuration was created"), buka SSH centos-clean dari Konsol,
lalu jalankan:
  gcloud auth login
  curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp647.sh
  bash gsp647.sh vm
EOF

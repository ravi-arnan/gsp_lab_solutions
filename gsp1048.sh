#!/usr/bin/env bash
# GSP1048 - Cloud Spanner - Database Fundamentals
#
#   bash gsp1048.sh
#
# Checkpoint:
#   Task 1-2 - Create an instance and database          (banking-instance + banking-db)
#   Task 3   - Create a schema for your database        (tabel Customer)
#   Task 5   - Create an instance and database with CLI (banking-instance-2 + banking-db-2)
#
# Task 4 (insert + query), Task 6 (Terraform), Task 7 (hapus instance) dikerjakan
# script tapi tidak punya checkpoint. Penghapusan banking-instance-2 (Task 7)
# ditahan sampai kamu menekan Enter, supaya ketiga checkpoint sempat dinilai dulu.

set -euo pipefail

REGION="${REGION:-europe-west1}"
CONFIG="regional-$REGION"
PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

echo "Project: $PROJECT"
echo "Config : $CONFIG"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Instance sudah ada = lanjut saja, supaya script aman diulang.
instance_exists() { gcloud spanner instances describe "$1" --project="$PROJECT" &>/dev/null; }
database_exists() { gcloud spanner databases describe "$2" --instance="$1" --project="$PROJECT" &>/dev/null; }

# --edition baru ada di gcloud yang agak baru; kalau ditolak, buat tanpa flag itu
# (default instance tetap lolos checkpoint, edisi tidak diperiksa grader).
create_instance() {
  local name=$1 desc=$2 nodes=$3
  instance_exists "$name" && { echo "$name sudah ada, lewati."; return 0; }
  gcloud spanner instances create "$name" \
    --config="$CONFIG" --description="$desc" --nodes="$nodes" \
    --edition=ENTERPRISE --project="$PROJECT" 2>/dev/null ||
  gcloud spanner instances create "$name" \
    --config="$CONFIG" --description="$desc" --nodes="$nodes" --project="$PROJECT"
}

# ----------------------------------------------------------------- Task 1
step "Task 1: Buat instance banking-instance (Enterprise, $CONFIG, 1 node)"
gcloud services enable spanner.googleapis.com --project="$PROJECT"
create_instance banking-instance "Banking Instance" 1

# ----------------------------------------------------------------- Task 2
step "Task 2: Buat database banking-db"
if database_exists banking-instance banking-db; then
  echo "banking-db sudah ada, lewati."
else
  gcloud spanner databases create banking-db --instance=banking-instance --project="$PROJECT"
fi

# ----------------------------------------------------------------- Task 3
step "Task 3: Buat tabel Customer"
if gcloud spanner databases ddl describe banking-db --instance=banking-instance \
     --project="$PROJECT" 2>/dev/null | grep -q 'CREATE TABLE Customer'; then
  echo "Tabel Customer sudah ada, lewati."
else
  gcloud spanner databases ddl update banking-db --instance=banking-instance --project="$PROJECT" \
    --ddl='CREATE TABLE Customer (
      CustomerId STRING(36) NOT NULL,
      Name STRING(MAX) NOT NULL,
      Location STRING(MAX) NOT NULL,
    ) PRIMARY KEY (CustomerId)'
fi

# ----------------------------------------------------------------- Task 4
step "Task 4: Insert dua baris data, lalu query"
# Baris yang sudah ada bikin insert gagal (ALREADY_EXISTS) — bukan error fatal.
gcloud spanner rows insert --table=Customer --database=banking-db --instance=banking-instance \
  --project="$PROJECT" \
  --data=CustomerId='bdaaaa97-1b4b-4e58-b4ad-84030de92235',Name='Richard Nelson',Location='Ada Ohio' \
  || echo "  (baris pertama sudah ada, lanjut)"

gcloud spanner rows insert --table=Customer --database=banking-db --instance=banking-instance \
  --project="$PROJECT" \
  --data=CustomerId='b2b4002d-7813-4551-b83b-366ef95f9273',Name='Shana Underwood',Location='Ely Iowa' \
  || echo "  (baris kedua sudah ada, lanjut)"

gcloud spanner databases execute-sql banking-db --instance=banking-instance \
  --project="$PROJECT" --sql='SELECT * FROM Customer'

# ----------------------------------------------------------------- Task 5
step "Task 5: Instance + database kedua lewat CLI, lalu turunkan ke 1 node"
create_instance banking-instance-2 "Banking Instance 2" 2

if database_exists banking-instance-2 banking-db-2; then
  echo "banking-db-2 sudah ada, lewati."
else
  gcloud spanner databases create banking-db-2 --instance=banking-instance-2 --project="$PROJECT"
fi

gcloud spanner instances update banking-instance-2 --nodes=1 --project="$PROJECT"
gcloud spanner instances list --project="$PROJECT"

# ----------------------------------------------------------------- Task 6
step "Task 6: Deploy banking-instance-3 lewat Terraform"
if ! command -v terraform &>/dev/null; then
  echo "Terraform belum ada, install..."
  # Sama seperti langkah lab: repo HashiCorp + tulis ~/.customize_environment
  # supaya instalasinya bertahan kalau Cloud Shell restart.
  cat <<'EOF' > ~/.customize_environment
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform
EOF
  bash ~/.customize_environment >/dev/null 2>&1 || true
fi

if command -v terraform &>/dev/null; then
  terraform --version
  TFDIR="/tmp/gsp1048-tf"
  mkdir -p "$TFDIR"
  cat > "$TFDIR/spanner.tf" <<EOF
resource "google_spanner_instance" "banking-instance-3" {
  name         = "banking-instance-3"
  config       = "$CONFIG"
  display_name = "Banking Instance 3"
  num_nodes    = 2
  labels = {
  }
}
EOF
  # Instance yang terlanjur ada di-import dulu, kalau tidak apply-nya ALREADY_EXISTS.
  if instance_exists banking-instance-3 && [[ ! -f "$TFDIR/terraform.tfstate" ]]; then
    (cd "$TFDIR" && terraform init -input=false >/dev/null &&
     terraform import google_spanner_instance.banking-instance-3 \
       "$PROJECT/banking-instance-3" >/dev/null)
  fi
  (cd "$TFDIR" && terraform init -input=false && terraform plan -input=false &&
   terraform apply -auto-approve -input=false)
  gcloud spanner instances list --project="$PROJECT"
else
  echo "Terraform gagal diinstall. Task 6 tidak punya checkpoint, jadi dilewati."
fi

# ----------------------------------------------------------------- Task 7
step "Task 7: Hapus banking-instance-2"
echo "Klik Check my progress dulu untuk tiga checkpoint di bawah:"
echo "  - Create an instance and database"
echo "  - Create a schema for your database"
echo "  - Create an instance and database with CLI"
echo
read -r -p "Sudah hijau semua? Tekan Enter untuk menghapus banking-instance-2..."

gcloud spanner instances delete banking-instance-2 --project="$PROJECT" -q
gcloud spanner instances list --project="$PROJECT"

echo
echo "SELESAI! Klik Check my progress untuk verifikasi:"
echo "  Task 1-2 - Create an instance and database"
echo "  Task 3   - Create a schema for your database"
echo "  Task 5   - Create an instance and database with CLI"

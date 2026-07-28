#!/usr/bin/env bash
# GSP156 - Terraform Fundamentals
#
#   bash gsp156.sh
#
# ZONE diisi dinamis per instance. Script mencoba membacanya dari metadata project;
# kalau gagal, cocokkan dengan panel Lab Details lalu override:
#   ZONE=europe-west1-b bash gsp156.sh
#
# Checkpoint: cuma SATU, di akhir Task 2 — "Create a VM instance in the <region>
# zone with Terraform" (100 poin). Task 1 (jalankan `terraform`) dan Task 3
# (dua soal pilihan ganda, jawabannya True dan True) tidak di-score.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

# Lab menyetel default zone di metadata project, jadi biasanya tidak perlu diisi manual.
ZONE="${ZONE:-$(gcloud compute project-info describe \
  --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null)}"

if [[ -z "$ZONE" ]]; then
  echo "ZONE tidak terbaca dari metadata project."
  echo "Ambil zone dari panel Lab Details, lalu:"
  echo "  ZONE=<zone> bash gsp156.sh"
  exit 1
fi

echo "Project: $PROJECT"
echo "Zone   : $ZONE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Terraform init menolak jalan kalau ada *.tf lain di direktori yang sama, dan
# lab memang menyuruh `ls` untuk memastikan itu. Pakai direktori sendiri.
WORK="$HOME/gsp156"
mkdir -p "$WORK"
cd "$WORK"

# ----------------------------------------------------------------- Task 1
step "Task 1: verifikasi Terraform terpasang"
terraform version

# ----------------------------------------------------------------- Task 2
step "Task 2a: tulis instance.tf"

# Lab sengaja TIDAK memakai blok provider maupun required_providers — `terraform
# init` mengambil provider google versi terbaru sendiri. Jangan di-pin, teks lab
# eksplisit bilang "Your version number may be higher".
cat > instance.tf <<EOF
resource "google_compute_instance" "terraform" {
  project      = "$PROJECT"
  name         = "terraform"
  machine_type = "e2-medium"
  zone         = "$ZONE"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = "default"
    access_config {
    }
  }
}
EOF

cat instance.tf

step "Task 2b: terraform init"
terraform init -input=false

step "Task 2c: terraform plan"
terraform plan -input=false

step "Task 2d: terraform apply"
terraform apply -input=false -auto-approve

step "Task 2e: terraform show"
terraform show

step "Selesai"
cat <<EOF
Klik "Check my progress" untuk checkpoint tunggal lab ini (100 poin):
  "Create a VM instance in the <region> zone with Terraform."

Task 3 dua soal pilihan ganda, jawab manual — keduanya True:
  - "Terraform enables you to safely and predictably create, change, and
     improve infrastructure."                                        -> True
  - "With Terraform, you can create your own custom provider plugins." -> True

State ada di $WORK. Jangan hapus direktori itu sebelum checkpoint hijau.
EOF

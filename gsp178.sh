#!/usr/bin/env bash
# GSP178 - Setting up a Private Kubernetes Cluster
#
#   bash gsp178.sh          # Jalankan Part 1, pause untuk klik checkpoint, lalu lanjut Part 2
#   bash gsp178.sh part1    # Jalankan Task 1-4 saja
#   bash gsp178.sh part2    # Jalankan Task 5-6 (delete private-cluster, buat private-cluster2)
#
# Checkpoint:
#   Part 1:
#     Task 2 - Create a private cluster
#     Task 4 - Create a VM instance (source-instance)
#     Task 4 - Authorize your external address range
#   Part 2:
#     Task 5 - Delete the Kubernetes cluster
#     Task 6 - Create a subnetwork and secondary ranges in us-west1 region
#     Task 6 - Create a private cluster that uses your subnetwork
#     Task 6 - Authorize your external address range for private cluster in custom subnetwork
#
# PENTING: Task 5 menghapus private-cluster. Jangan hapus cluster sebelum
# checkpoint Task 2 dan Task 4 diklik sampai hijau!
#
# LAMA: ~8-12 menit (pembuatan cluster GKE).

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

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

PHASE="${1:-all}"

DEF_ZONE="$(gcloud compute project-info describe --format='value(commonInstanceMetadata.items[google-compute-default-zone])' 2>/dev/null || true)"
ask ZONE "${DEF_ZONE:-us-west1-b}" "Zone GKE (cocokkan dengan teks/panel lab)"
REGION="${ZONE%-*}"

echo "Project: $PROJECT_ID"
echo "Region : $REGION"
echo "Zone   : $ZONE"
echo "Fase   : $PHASE"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

gcloud config set compute/zone "$ZONE" >/dev/null 2>&1
gcloud config set compute/region "$REGION" >/dev/null 2>&1

cluster_exists() {
  gcloud container clusters describe "$1" --zone="$ZONE" >/dev/null 2>&1
}

instance_exists() {
  gcloud compute instances describe "$1" --zone="$ZONE" >/dev/null 2>&1
}

subnet_exists() {
  gcloud compute networks subnets describe "$1" --region="$REGION" >/dev/null 2>&1
}

# ================================================================= PART 1
run_part1() {
  step "Memastikan Container API aktif"
  gcloud services enable container.googleapis.com --project="$PROJECT_ID" -q || true

  step "Task 2: Buat private-cluster (GKE Private Cluster)"
  if cluster_exists private-cluster; then
    echo "Cluster private-cluster sudah ada, lewati pembuatan."
  else
    echo "Membuat cluster private-cluster (~3-4 menit)..."
    gcloud beta container clusters create private-cluster \
      --enable-private-nodes \
      --master-ipv4-cidr 172.16.0.16/28 \
      --enable-ip-alias \
      --create-subnetwork "" \
      --machine-type e2-medium \
      --zone="$ZONE" -q
  fi

  step "Task 4: Buat VM source-instance"
  if instance_exists source-instance; then
    echo "Instance source-instance sudah ada, lewati pembuatan."
  else
    echo "Membuat instance source-instance..."
    gcloud compute instances create source-instance \
      --zone="$ZONE" \
      --machine-type=e2-medium \
      --scopes='https://www.googleapis.com/auth/cloud-platform' -q
  fi

  step "Task 4: Otorisasi external IP source-instance ke private-cluster"
  NAT_IP="$(gcloud compute instances describe source-instance --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
  echo "External IP source-instance: $NAT_IP"
  echo "Mengizinkan range $NAT_IP/32 pada private-cluster..."
  gcloud container clusters update private-cluster \
    --enable-master-authorized-networks \
    --zone="$ZONE" \
    --master-authorized-networks "${NAT_IP}/32" -q
}

# ================================================================= PART 2
run_part2() {
  step "Task 5: Hapus private-cluster"
  if cluster_exists private-cluster; then
    echo "Menghapus cluster private-cluster (~2 menit)..."
    gcloud container clusters delete private-cluster --zone="$ZONE" -q
  else
    echo "Cluster private-cluster sudah terhapus atau tidak ada."
  fi

  step "Task 6: Buat subnetwork kustom 'my-subnet'"
  if subnet_exists my-subnet; then
    echo "Subnet my-subnet sudah ada, lewati pembuatan."
  else
    echo "Membuat subnetwork my-subnet di region $REGION..."
    gcloud compute networks subnets create my-subnet \
      --network default \
      --range 10.0.4.0/22 \
      --enable-private-ip-google-access \
      --region="$REGION" \
      --secondary-range my-svc-range=10.0.32.0/20,my-pod-range=10.4.0.0/14 -q
  fi

  step "Task 6: Buat private-cluster2 di subnetwork kustom"
  if cluster_exists private-cluster2; then
    echo "Cluster private-cluster2 sudah ada, lewati pembuatan."
  else
    echo "Membuat cluster private-cluster2 (~3-4 menit)..."
    gcloud beta container clusters create private-cluster2 \
      --enable-private-nodes \
      --enable-ip-alias \
      --master-ipv4-cidr 172.16.0.32/28 \
      --subnetwork my-subnet \
      --services-secondary-range-name my-svc-range \
      --cluster-secondary-range-name my-pod-range \
      --zone="$ZONE" \
      --machine-type e2-medium -q
  fi

  step "Task 6: Otorisasi external IP source-instance ke private-cluster2"
  NAT_IP="$(gcloud compute instances describe source-instance --zone="$ZONE" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
  echo "External IP source-instance: $NAT_IP"
  echo "Mengizinkan range $NAT_IP/32 pada private-cluster2..."
  gcloud container clusters update private-cluster2 \
    --enable-master-authorized-networks \
    --zone="$ZONE" \
    --master-authorized-networks "${NAT_IP}/32" -q
}

# ================================================================= MAIN ROUTER
case "$PHASE" in
  part1)
    run_part1
    cat <<EOF

--------------------------------------------------------------
PART 1 SELESAI!
Silakan klik 'Check my progress' pada checkpoint berikut:
  1. Create a private cluster (Task 2)
  2. Create a VM instance (Task 4)
  3. Authorize your external address range (Task 4)

Setelah ketiga checkpoint di atas hijau, jalankan Part 2:
  bash $0 part2
--------------------------------------------------------------
EOF
    ;;

  part2)
    run_part2
    cat <<EOF

--------------------------------------------------------------
SELESAI! Silakan klik 'Check my progress' untuk sisa checkpoint:
  4. Delete the Kubernetes cluster (Task 5)
  5. Create a subnetwork and secondary ranges in us-west1 region (Task 6)
  6. Create a private cluster that uses your subnetwork (Task 6)
  7. Authorize your external address range for private cluster in custom subnetwork (Task 6)
--------------------------------------------------------------
EOF
    ;;

  all)
    run_part1
    cat <<EOF

==============================================================
PENTING: JEDA UNTUK VERIFIKASI PART 1
Task 5 berikutnya akan MENGHAPUS 'private-cluster'.
Klik 'Check my progress' pada 3 checkpoint berikut SEKARANG:
  1. Create a private cluster (Task 2)
  2. Create a VM instance (Task 4)
  3. Authorize your external address range (Task 4)

Pastikan ketiganya sudah berwarna HIJAU sebelum lanjut.
==============================================================
EOF
    if [[ -t 0 ]]; then
      read -rp "Tekan ENTER jika 3 checkpoint di atas sudah hijau untuk lanjut ke Part 2... " _
    else
      echo "Non-interactive environment terdeteksi. Script berhenti di sini untuk menjaga skor."
      echo "Setelah verifikasi 3 checkpoint di atas, jalankan Part 2: bash $0 part2"
      exit 0
    fi

    run_part2
    cat <<EOF

--------------------------------------------------------------
SELESAI! Silakan klik 'Check my progress' untuk sisa checkpoint:
  4. Delete the Kubernetes cluster (Task 5)
  5. Create a subnetwork and secondary ranges in us-west1 region (Task 6)
  6. Create a private cluster that uses your subnetwork (Task 6)
  7. Authorize your external address range for private cluster in custom subnetwork (Task 6)
--------------------------------------------------------------
EOF
    ;;

  *)
    echo "Fase '$PHASE' tidak dikenal. Gunakan: part1, part2, atau all"
    exit 1
    ;;
esac

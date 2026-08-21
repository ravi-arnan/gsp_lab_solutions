#!/usr/bin/env bash
# GSP095 - Pub/Sub: Qwik Start - Command Line
#
#   bash gsp095.sh
#
# Checkpoint:
#   Task 1 - Create a Pub/Sub topic         (myTopic)
#   Task 2 - Create Pub/Sub Subscription    (mySubscription)
#   Task 3-4 - publish dan pull pesan, tidak dinilai tapi dikerjakan
#
# Topic dan subscription bernama Test1/Test2 memang dibuat lalu dihapus lagi,
# itu bagian dari materi lab dan tidak mengganggu kedua checkpoint (yang dinilai
# hanya myTopic dan mySubscription).
#
# LAMA: < 1 menit.

set -euo pipefail

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

TOPIC="myTopic"
SUB="mySubscription"

echo "Project: $PROJECT"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

# Cek dulu supaya script aman diulang: create pada resource yang sudah ada
# balas ALREADY_EXISTS dan akan menghentikan script karena set -e.
create_topic() {
  gcloud pubsub topics describe "$1" >/dev/null 2>&1 \
    && echo "topic $1 sudah ada, dilewat." \
    || gcloud pubsub topics create "$1"
}
create_sub() {
  gcloud pubsub subscriptions describe "$1" >/dev/null 2>&1 \
    && echo "subscription $1 sudah ada, dilewat." \
    || gcloud pubsub subscriptions create --topic "$TOPIC" "$1"
}

# ----------------------------------------------------------------- Task 1
step "Task 1: buat topic $TOPIC, Test1, Test2 (checkpoint 1)"
create_topic "$TOPIC"
create_topic Test1
create_topic Test2

echo ">>> Daftar topic:"
gcloud pubsub topics list --format='value(name)'

echo ">>> Hapus Test1 dan Test2 (bagian dari materi lab):"
gcloud pubsub topics delete Test1 -q
gcloud pubsub topics delete Test2 -q
gcloud pubsub topics list --format='value(name)'

# ----------------------------------------------------------------- Task 2
step "Task 2: buat subscription $SUB, Test1, Test2 (checkpoint 2)"
create_sub "$SUB"
create_sub Test1
create_sub Test2

echo ">>> Subscription milik $TOPIC:"
gcloud pubsub topics list-subscriptions "$TOPIC"

echo ">>> Hapus subscription Test1 dan Test2:"
gcloud pubsub subscriptions delete Test1 -q
gcloud pubsub subscriptions delete Test2 -q
gcloud pubsub topics list-subscriptions "$TOPIC"

# ----------------------------------------------------------------- Task 3
step "Task 3: publish 4 pesan lalu pull satu per satu"
gcloud pubsub topics publish "$TOPIC" --message "Hello"
gcloud pubsub topics publish "$TOPIC" --message "Publisher's name is Ravi"
gcloud pubsub topics publish "$TOPIC" --message "Publisher likes to eat sate"
gcloud pubsub topics publish "$TOPIC" --message "Publisher thinks Pub/Sub is awesome"

# Tanpa flag, pull mengembalikan satu pesan saja, dan pesan yang sudah di-ack
# tidak bisa diambil lagi. Empat kali pull memperagakan keduanya: yang keempat
# biasanya masih berisi, yang kelima 'Listed 0 items'.
sleep 5
for i in 1 2 3 4; do
  echo ">>> pull ke-$i"
  gcloud pubsub subscriptions pull "$SUB" --auto-ack
done

# ----------------------------------------------------------------- Task 4
step "Task 4: publish 3 pesan lalu pull sekaligus dengan --limit"
gcloud pubsub topics publish "$TOPIC" --message "Publisher is starting to get the hang of Pub/Sub"
gcloud pubsub topics publish "$TOPIC" --message "Publisher wonders if all messages will be pulled"
gcloud pubsub topics publish "$TOPIC" --message "Publisher will have to test to find out"

sleep 10
gcloud pubsub subscriptions pull "$SUB" --limit=3

cat <<EOF

==============================================================
SELESAI! Klik Check my progress untuk verifikasi:
  1. Create a Pub/Sub topic          (myTopic)
  2. Create Pub/Sub Subscription     (mySubscription)

Kalau blok pull ada yang kosong, itu wajar — pesan butuh beberapa
detik tersedia dan pesan yang sudah di-ack tidak muncul lagi.
Tidak ada checkpoint yang bergantung padanya. Ulangi manual:
  gcloud pubsub subscriptions pull $SUB --limit=3

Kuis: "To receive messages published to a topic, you must create a
subscription to that topic." Jawaban: True
==============================================================
EOF

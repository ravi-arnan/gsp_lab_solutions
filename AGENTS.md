# gsp_lab_solutions

Script otomasi lab Google Cloud Skills Boost (Arcade / Skills Badge). Satu lab = satu script.

## Layout

- `gspNNNN.sh` di root — script solusi, dijalankan di Cloud Shell.
- `docs/gspNNNN.md` — runbook: kenapa lab ini cocok di-script, cara jalan, tabel task mana yang otomatis vs manual, status uji.

## Konvensi script

Header wajib: judul lab, cara menjalankan, daftar checkpoint beserta poinnya.

```bash
#!/usr/bin/env bash
# GSP1281 - Enabling Sensitive Data Protection Discovery for Cloud Storage
#
#   bash gsp1281.sh
#
# Checkpoint:
#   Task 1 (10 pts)  - Create and schedule a discovery scan configuration
#   Task 3 (0 pts)   - Manual (Looker dashboard)

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }
```

Aturan lain:

- **Idempoten.** Script harus aman diulang kalau gagal di tengah. Cek dulu sebelum create, atau hapus/import resource yang sudah ada (lihat riwayat `gsp345`).
- **Nol interaksi selama eksekusi.** `terraform apply -auto-approve`, `gcloud ... -q`. Lab punya batas waktu, jangan ada prompt yang menunggu di tengah jalan.
- **Region/zone dan nilai acak lain ditanyakan di awal** pakai helper `ask`, bukan langsung `REGION="${REGION:-...}"`. Helper-nya disalin utuh ke tiap script (satu file = satu unduhan, jangan bikin lib bersama):

  ```bash
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

  ask REGION "europe-west1" "Region (cocokkan dengan panel lab)"
  ```

  Urutan prioritas: env var → jawaban user → default. Cek `[[ -t 0 ]]` wajib, kalau tidak `curl | bash` dan `nohup` akan menggantung selamanya menunggu jawaban.
- **Banner per task** pakai helper `step()`, supaya jelas posisi kegagalan.
- **Task manual jangan dipaksa.** Kalau harus lewat Console (dashboard, review UI), tulis instruksinya di echo lalu `read -r` untuk jeda.
- **Penutup**: echo `SELESAI! Klik Check my progress untuk verifikasi:` + daftar task.
- Komentar dan pesan echo pakai Bahasa Indonesia, nama resource ikut instruksi lab (Inggris).
- Butuh REST API? Pakai `gcloud auth print-access-token` + `curl`, dan helper `dbg()` yang meringkas response lewat `jq` (lihat `gsp1281.sh`).

## Commit

`gspNNN: <perubahan>` — contoh: `gsp345: pin google provider < 7.0 for VPC module compatibility`.

## Uji

Tidak ada CI. Minimal `bash -n gspNNNN.sh` sebelum commit. Tandai di runbook kalau script belum pernah dijalankan di lab sungguhan.

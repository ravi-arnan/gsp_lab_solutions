# Handoff — sesi 2026-08-04/05

Catatan serah-terima sesi kerja lab Arcade. Baca ini dulu, lalu
[AGENTS.md](AGENTS.md) untuk konvensi script.

## Posisi sekarang

**Game Arcade 2026 (Agustus): 3/6 selesai** — Base Camp, Adventure (Data Vault),
Special (Spans and Plans).

Sisa: **Trail (Cloud Delivery Systems)**, Voyage (Google Sheets),
Simulator (Network Security Engineer).

**Langkah berikutnya: Trail.** Isi labnya belum diketahui. Minta user menempel
halaman lab pertamanya (kode GSP/ARC + daftar task), cocokkan dulu dengan tabel
di [README](README.md) sebelum menulis script baru.

Urutan yang disarankan setelah Trail: Voyage, lalu Simulator terakhir (paling
panjang, paling sedikit yang bisa diotomasi).

## Yang diselesaikan sesi ini

Semua 100/100 di lab instance sungguhan:

| Lab | Catatan singkat |
|-----|-----------------|
| GSP081 | Cloud Run functions console |
| GSP872 | API Gateway |
| ARC109 | API Gateway challenge |
| GSP038 | Natural Language API |
| ARC130 | Sentiment challenge |
| GSP089 | Cloud Monitoring |
| GSP092 | Monitoring Cloud Run functions |
| GSP1108 | Ops Agent + Apache |
| ARC115 | Monitoring challenge |
| GSP736 | Debug apps on GKE |
| GSP510 | Manage Kubernetes challenge — **badge 783 lengkap** |
| GSP1041 | Authorized views |
| GSP1042 | Analytics as a Service — script maks 80/100 |
| GSP1043 | Consuming customer datasets |
| GSP375 | Share Data challenge — script maks 80/100 |

Script baru yang **belum pernah diuji** di lab sungguhan: `gsp1026.sh`,
`gsp053.sh`. Keduanya ditulis lengkap dan lolos syntax + shellcheck, tapi user
lanjut ke lab berikutnya sebelum melaporkan skor.

`gsp510.sh` skornya 100/100, **tapi** dua perbaikan terakhirnya (managed
prometheus tanpa syarat, wildcard `*=` untuk set image) sebagian dikerjakan
manual saat lab berjalan — belum diuji ulang sekali jalan dari nol.

## Perubahan lintas-repo sesi ini

- **Helper `ask()` di 34 script.** Region/zone/nilai acak sekarang ditanyakan
  interaktif. Prioritas: env var → jawaban user → default. Wajib mengecek
  `[[ -t 0 ]]`, kalau tidak `curl | bash` dan `nohup` menggantung selamanya.
  Konvensinya sudah masuk AGENTS.md.
- **README**: 8 script yang belum terdaftar dimasukkan (gsp1048/1049/1050/381/
  752/1124/1164) + semua lab sesi ini.
- **docs/coverage.md**: tanda ✅ disegarkan dari daftar file nyata. Badge yang
  kini lengkap: 636, 624, 681, 1164, 725, 783.

## Pelajaran yang berlaku lintas lab

Ini yang paling berharga dari sesi ini — beberapa **mengoreksi asumsi lama**.

1. **Tidak ada resep seragam untuk lab Cloud Run functions.** GSP081 dan ARC109
   menolak `gcloud functions deploy --gen2` dan menuntut
   `gcloud run deploy --function`; GSP092 justru **sebaliknya**, mencari resource
   Cloud Functions v2. Cek dengan `gcloud functions list` sebelum menduga.
   Rinciannya: [docs/gsp081.md](docs/gsp081.md), [docs/gsp092.md](docs/gsp092.md).

2. **Looker Studio BISA dinilai grader.** Terbukti dua kali (GSP1042, GSP375):
   checkpoint terbagi dua, separuh tabel BigQuery separuh report. Ini
   mengoreksi kesimpulan dari GSP1154 bahwa artefak di luar Google Cloud tidak
   bisa dinilai — kesimpulan itu **tidak berlaku umum**.

3. **Alerting policy lewat REST tanpa notification channel sudah cukup** (3×:
   GSP089, GSP1108, ARC115). Tapi **teks filternya bisa dicocokkan string**:
   GSP736 menolak `metric.type=... AND resource.type=...` dan menerima urutan
   UI `resource.type = "..." AND metric.type = "..."`. Kalau nilainya sudah
   benar tapi checkpoint merah, tukar urutan dulu.

4. **API key untuk checkpoint harus dibuat lewat console.** Key buatan
   `gcloud services api-keys create` boleh dipakai memanggil API, tapi tidak
   menghijaukan checkpoint (ARC132, GSP038, ARC130).

5. **`set -euo pipefail` bisa membunuh script tanpa pesan apa pun.** Dua kasus
   nyata sesi ini:
   - `tr -dc 'a-z' < /dev/urandom | head -c 8` → `head` keluar dulu, `tr` kena
     SIGPIPE (141), pipefail meneruskannya, script mati. Pakai
     `${RANDOM}${RANDOM}`.
   - `kubectl set image ... helloweb=$IMAGE` gagal karena container bernama
     `hello-app` → script mati tepat setelah `docker push`, tanpa error yang
     kelihatan. Pakai wildcard `"*=$IMAGE"`.

6. **"N KiB/s" di instruksi lab berarti threshold `N000`**, bukan `N*1024`.

7. **Dashboard Monitoring pakai REST `v1/dashboards`**, sedangkan uptime check
   dan alert policy di `v3`.

8. **Jangan lewati langkah "enable" hanya karena describe bilang sudah aktif.**
   GSP510: cluster melaporkan managed prometheus `enabled=True` sejak dibuat,
   tapi grader baru mengakui setelah `clusters update --enable-managed-prometheus`
   benar-benar dijalankan.

## Cara kerja yang terbukti efisien sesi ini

- **Isi nilai lewat env var, jangan ketik manual.** User sendiri yang minta ini
  ("takut human error"). Untuk lab multi-project, minta user menempel halaman
  lab lalu balas dengan blok perintah yang sudah terisi penuh.
- **Ambil script lewat commit SHA**, bukan `main` — cache
  `raw.githubusercontent.com` basi ~5 menit dan `?v=$(date +%s)` tidak menolong.
- **Lab yang lama (gateway ~10 menit) jalankan via `nohup ... &` + `tail -f`.**
  Sesi Cloud Shell pernah putus dan mati di tengah (GSP872).
- **Beri jeda sebelum langkah yang merusak state yang dinilai.** GSP510 Task 5
  memperbaiki deployment yang error, jadi checkpoint Task 3 harus diklik dulu.
- Alur normalnya: user tempel halaman lab → tulis/perbaiki script → commit +
  push → beri perintah dengan SHA → user lapor skor → tulis runbook di `docs/`
  + update status README → commit.

## Utang yang masih terbuka

- `gsp1026.sh` dan `gsp053.sh` belum diuji di lab sungguhan.
- `gsp510.sh` belum diuji ulang sekali jalan setelah diperbaiki.
- Beberapa script lama masih "Belum diuji" — lihat kolom Status di README.
- `docs/coverage.md` masih memetakan 20 dari 68 badge; 48 sisanya belum.

# gsp_lab_solutions

Script otomatisasi untuk Google Cloud self-paced labs (Qwiklabs / Cloud Skills Boost), dijalankan dari Cloud Shell.

## Cara pakai

Jalankan langsung dari Cloud Shell:

```bash
curl -sL https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp416.sh | bash
```

Atau download dulu kalau mau baca isinya sebelum jalan (disarankan):

```bash
curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp416.sh
less gsp416.sh
bash gsp416.sh
```

## Daftar lab

| ID | Judul | Coverage | Status | Terakhir diuji |
|----|-------|----------|--------|----------------|
| [GSP416](gsp416.sh) | Working with JSON, Arrays, and Structs in BigQuery | Task 1, 2, 3, 4, 6, 7, 8, 9 | Terverifikasi, skor 100/100 | 2026-07-16 |
| [GSP340](gsp340.sh) | Build a Data Warehouse with BigQuery: Challenge Lab | Task 1, 2, 3, 4 | Terverifikasi, skor 40/40, satu varian task (lihat catatan) | 2026-07-16 |
| [GSP1154](gsp1154.sh) | Getting Started with Agent Studio | Task 2, 3, 4, 5 (best-effort, lihat catatan) | Belum diuji | — |

Keterangan status:

- **Terverifikasi** berarti script pernah dijalankan sampai selesai di lab instance sungguhan dan semua checkpoint hijau, dengan skor yang tercatat di kolom yang sama.
- **Belum diuji** berarti script lolos pemeriksaan syntax dan `shellcheck`, tapi belum pernah dijalankan di lab instance sungguhan.
- **Satu varian task** khusus untuk challenge lab: script terbukti 100% pada varian task yang tercatat di file, tapi karena tasknya diacak per instance, varian lain bisa butuh penyesuaian variabel.

Lab dites ulang saat Google memperbarui materinya. Kolom "Terakhir diuji" menunjukkan kapan verifikasi terakhir dilakukan, jadi kalau tanggalnya sudah lama sementara lab-nya baru saja diupdate, anggap statusnya perlu dikonfirmasi ulang.

### Lab yang tidak cocok diotomasi

**Challenge lab** memilih task secara acak per instance, ditandai teks `Dynamically selected task will show up here...` di halaman labnya. Nama dataset, tabel, dan kolom berbeda tiap peserta, jadi script statis bisa salah parameter.

`gsp340.sh` tetap disertakan, tapi semua nilai yang bisa berubah dikumpulkan di satu blok variabel di awal file. **Cocokkan blok itu dengan teks task di lab-mu sebelum menjalankan.** Kalau nama datasetnya beda, ubah variabelnya, jangan query di bawahnya.

**Lab berbasis Console** seperti GSP1154 (Agent Studio) menilai aksi UI, bukan resource yang bisa dibuat lewat API. `gsp1154.sh` disertakan sebagai *best-effort*: script memanggil Vertex AI API dengan prompt dan konfigurasi yang setara tiap task, dengan asumsi checkpoint melihat jejak pemakaian API di project. **Asumsi ini belum diverifikasi.** Task 1 (Deploy as app ke Cloud Run) sudah pasti tidak bisa diotomasi karena tombol itu membangun container bawaan Agent Studio yang tidak punya padanan gcloud. Anggap script ini pendamping, bukan pengganti lab-nya.

## Yang tidak diotomasi

Script ini mengerjakan bagian yang di-score lewat **Check my progress**, yaitu pembuatan dataset, load tabel, dan eksekusi query. Yang tetap harus dikerjakan manual:

- **Soal pilihan ganda.** Tidak ada API-nya, harus diklik sendiri di halaman lab.
- **Langkah yang murni baca UI.** Contohnya GSP416 Task 5, cuma star `bigquery-public-data` lalu lihat schema. Tidak ada yang di-score di situ.
- **Query yang sengaja dibuat error.** Beberapa lab menyuruh menjalankan query yang pasti gagal supaya kamu lihat pesan errornya. Ini dilewat karena `set -euo pipefail` akan menghentikan script. Jalankan manual di UI kalau ingin melihatnya.

## Catatan

- Script dibuat idempoten (`mk -f`, `load --replace`), jadi aman diulang kalau gagal di tengah.
- Location dikunci ke `US` karena dataset publik seperti `data-to-insights` dan `bigquery-public-data` ada di US, dan BigQuery menolak query lintas-location.
- Project diambil dari `$DEVSHELL_PROJECT_ID` (otomatis terisi di Cloud Shell), fallback ke `gcloud config get-value project`.

## Peringatan

Pola `curl ... | bash` menjalankan kode dari internet tanpa kamu baca dulu. Untuk repo ini kodenya milik sendiri, tapi biasakan tetap baca isinya, apalagi kalau kamu fork atau ada orang lain yang punya akses tulis ke repo ini.

Script ini dibuat untuk belajar. Kalau langsung dijalankan tanpa mengikuti materinya, kamu dapat centang hijau tapi tidak dapat ilmunya.

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

### Script yang butuh fase atau parameter

Sebagian lab tidak bisa dijalankan sebagai one-liner. Download dulu, jangan di-pipe ke `bash`, karena `curl ... | bash -s <arg>` membuat script dan stdin berebut, dan biasanya filenya masih dibutuhkan untuk fase berikutnya.

`gsp1143.sh` contohnya. Task 4 menghapus semua yang dibuat Task 1 sampai 3, jadi harus dipisah dan **checkpoint task 1-3 wajib hijau dulu** sebelum fase delete:

```bash
curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/gsp1143.sh
REGION=europe-west1 bash gsp1143.sh create   # Task 1-3
# klik Check my progress task 1, 2, 3 sampai hijau
REGION=europe-west1 bash gsp1143.sh delete   # Task 4
```

Region di lab ini diisi dinamis per instance, jadi cocokkan dengan halaman lab-mu. Default script `us-central1`.

## Daftar lab

| ID | Judul | Script | Runbook | Status | Terakhir diuji |
|----|-------|--------|---------|--------|----------------|
| GSP416 | Working with JSON, Arrays, and Structs in BigQuery | [gsp416.sh](gsp416.sh) | [docs/gsp416.md](docs/gsp416.md) | Terverifikasi, skor 100/100 | 2026-07-16 |
| GSP340 | Build a Data Warehouse with BigQuery: Challenge Lab | [gsp340.sh](gsp340.sh) | [docs/gsp340.md](docs/gsp340.md) | Terverifikasi, skor 40/40, satu varian task | 2026-07-16 |
| GSP1143 | Knowledge Catalog (Dataplex): Qwik Start - Console | [gsp1143.sh](gsp1143.sh) | [docs/gsp1143.md](docs/gsp1143.md) | Terverifikasi, skor 100/100 | 2026-07-17 |
| GSP1145 | Create and Add Aspects to Knowledge Catalog Assets | [gsp1145.sh](gsp1145.sh) | [docs/gsp1145.md](docs/gsp1145.md) | Terverifikasi, semua checkpoint hijau | 2026-07-17 |
| GSP1157 | Implementing Security in Knowledge Catalog | [gsp1157.sh](gsp1157.sh) | [docs/gsp1157.md](docs/gsp1157.md) | Terverifikasi, skor 100/100, Task 3 dan 5 manual (dua user) | 2026-07-17 |
| GSP514 | Build a Data Mesh with Knowledge Catalog: Challenge Lab | [gsp514.sh](gsp514.sh) | [docs/gsp514.md](docs/gsp514.md) | Belum diuji | - |

Tiap lab punya runbook di `docs/` berisi urutan perintah, nilai yang harus muncul sebagai sanity check, dan troubleshooting. **Baca runbook-nya dulu sebelum jalan**, terutama GSP340 (parameter acak) dan GSP1143 (dua fase).

Keterangan status:

- **Terverifikasi** berarti script pernah dijalankan sampai selesai di lab instance sungguhan dan semua checkpoint hijau, dengan skor yang tercatat di kolom yang sama.
- **Belum diuji** berarti script lolos pemeriksaan syntax dan `shellcheck`, tapi belum pernah dijalankan di lab instance sungguhan.
- **Satu varian task** khusus untuk challenge lab: script terbukti 100% pada varian task yang tercatat di file, tapi karena tasknya diacak per instance, varian lain bisa butuh penyesuaian variabel.

Lab dites ulang saat Google memperbarui materinya. Kolom "Terakhir diuji" menunjukkan kapan verifikasi terakhir dilakukan, jadi kalau tanggalnya sudah lama sementara lab-nya baru saja diupdate, anggap statusnya perlu dikonfirmasi ulang.

### Lab yang tidak cocok diotomasi

**Challenge lab** memilih task secara acak per instance, ditandai teks `Dynamically selected task will show up here...` di halaman labnya. Nama dataset, tabel, dan kolom berbeda tiap peserta, jadi script statis bisa salah parameter.

`gsp340.sh` tetap disertakan, tapi semua nilai yang bisa berubah dikumpulkan di satu blok variabel di awal file. **Cocokkan blok itu dengan teks task di lab-mu sebelum menjalankan.** Kalau nama datasetnya beda, ubah variabelnya, jangan query di bawahnya.

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

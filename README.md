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
| GSP514 | Build a Data Mesh with Knowledge Catalog: Challenge Lab | [gsp514.sh](gsp514.sh) | [docs/gsp514.md](docs/gsp514.md) | Terverifikasi, Task 2b manual (UI) | 2026-07-17 |
| GSP750 | Infrastructure as Code with Terraform | [gsp750.sh](gsp750.sh) | [docs/gsp750.md](docs/gsp750.md) | Belum diuji | - |
| GSP751 | Interact with Terraform Modules | [gsp751.sh](gsp751.sh) | - | Belum diuji | - |
| GSP345 | Build Infrastructure with Terraform: Challenge Lab | [gsp345.sh](gsp345.sh) | - | Terverifikasi, semua checkpoint hijau (google provider dipin `< 7.0` di semua blok) | 2026-07-30 |
| GSP1183 | Gating Deployments with Binary Authorization | [gsp1183.sh](gsp1183.sh) | [docs/gsp1183.md](docs/gsp1183.md) | Terverifikasi di us-east1, 7/7 checkpoint hijau sekali jalan | 2026-07-17 |
| GSP1184 | Secure Builds with Cloud Build | [gsp1184.sh](gsp1184.sh) | - | Belum diuji | - |
| GSP1185 | Securing Container Builds | [gsp1185.sh](gsp1185.sh) | - | Belum diuji | - |
| GSP521 | Secure Software Delivery: Challenge Lab | [gsp521.sh](gsp521.sh) | - | Belum diuji | - |
| ARC125 | Use APIs to Work with Cloud Storage: Challenge Lab | [arc125.sh](arc125.sh) | - | Terverifikasi, semua checkpoint hijau, dua fase | 2026-07-30 |
| GSP294 | Introduction to APIs in Google Cloud | [gsp294.sh](gsp294.sh) | - | Belum diuji | - |
| GSP421 | APIs Explorer: Cloud Storage | [gsp421.sh](gsp421.sh) | - | Belum diuji | - |
| GSP074 | Cloud Storage: Qwik Start - CLI/SDK | [gsp074.sh](gsp074.sh) | - | Belum diuji | - |
| GSP522 | Discover and Protect Sensitive Data: Challenge Lab | [gsp522.sh](gsp522.sh) | - | Belum diuji, Task 3 manual (notebook) | - |
| GSP766 | Managing a GKE Multi-tenant Cluster with Namespaces | [gsp766.sh](gsp766.sh) | - | Terverifikasi, skor 100/100, Looker Studio manual (tidak di-score) | 2026-07-24 |
| GSP343 | Optimize Costs for GKE: Challenge Lab | [gsp343.sh](gsp343.sh) | - | Diuji, jalan tanpa error | 2026-07-24 |
| GSP767 | Exploring Cost-optimization for GKE Virtual Machines | [gsp767.sh](gsp767.sh) | - | Terverifikasi, skor 100/100 | 2026-07-24 |
| GSP414 | Creating Date-Partitioned Tables in BigQuery | [gsp414.sh](gsp414.sh) | - | Belum diuji | - |
| GSP1281 | Enabling Sensitive Data Protection Discovery for Cloud Storage | [gsp1281.sh](gsp1281.sh) | [docs/gsp1281.md](docs/gsp1281.md) | Belum diuji | - |
| GSP412 | Troubleshooting and Solving Data Join Pitfalls | [gsp412.sh](gsp412.sh) | - | Belum diuji | - |
| GSP081 | Cloud Run Functions: Qwik Start - Console | [gsp081.sh](gsp081.sh) | - | Belum diuji | - |
| GSP156 | Terraform Fundamentals | [gsp156.sh](gsp156.sh) | [docs/gsp156.md](docs/gsp156.md) | Belum diuji | - |
| GSP413 | Creating a Data Warehouse Through Joins and Unions | [gsp413.sh](gsp413.sh) | [docs/gsp413.md](docs/gsp413.md) | Belum diuji | - |
| GSP1158 | Assessing Data Quality with Knowledge Catalog | [gsp1158.sh](gsp1158.sh) | [docs/gsp1158.md](docs/gsp1158.md) | Belum diuji, maks 60/100 (Task 2 & 5 wajib manual) | - |
| GSP1282 | Enabling Sensitive Data Protection Discovery for BigQuery | [gsp1282.sh](gsp1282.sh) | [docs/gsp1282.md](docs/gsp1282.md) | Diuji, 80/100 — Task 4 ditolak grader meski konfigurasi benar, butuh `USER2=` | 2026-07-31 |
| GSP297 | Cloud Storage: Bucket Lock | [gsp297.sh](gsp297.sh) | [docs/gsp297.md](docs/gsp297.md) | Terverifikasi, skor 100/100, Task 6 (hapus bucket) sengaja manual | 2026-07-31 |

Tiap lab punya runbook di `docs/` berisi urutan perintah, nilai yang harus muncul sebagai sanity check, dan troubleshooting. **Baca runbook-nya dulu sebelum jalan**, terutama GSP340 (parameter acak) dan GSP1143 (dua fase).

Keterangan status:

- **Terverifikasi** berarti script pernah dijalankan sampai selesai di lab instance sungguhan dan semua checkpoint hijau, dengan skor yang tercatat di kolom yang sama.
- **Belum diuji** berarti script lolos pemeriksaan syntax dan `shellcheck`, tapi belum pernah dijalankan di lab instance sungguhan.
- **Satu varian task** khusus untuk challenge lab: script terbukti 100% pada varian task yang tercatat di file, tapi karena tasknya diacak per instance, varian lain bisa butuh penyesuaian variabel.

Lab dites ulang saat Google memperbarui materinya. Kolom "Terakhir diuji" menunjukkan kapan verifikasi terakhir dilakukan, jadi kalau tanggalnya sudah lama sementara lab-nya baru saja diupdate, anggap statusnya perlu dikonfirmasi ulang.

## Validasi tanpa lab instance

```bash
bash test/run.sh            # semua script
bash test/run.sh gsp416.sh  # satu script
```

Tiga lapis: `bash -n`, `shellcheck -S error`, lalu **dry-run** — script benar-benar dijalankan,
tapi `gcloud`, `bq`, `gsutil`, `kubectl`, `terraform`, `curl`, dan `git` diganti stub di
`test/stubs.sh` yang mencatat tiap panggilan dan menjawab dengan data berbentuk masuk akal.

Yang ditangkap: syntax, variabel kosong yang kena `set -u`, urutan langkah salah, loop tak
berbatas, dan cabang yang tidak pernah tercapai. Yang **tidak** ditangkap: apakah flagnya benar
menurut API sungguhan, dan apakah checkpoint jadi hijau. Dua hal itu cuma bisa dibuktikan di lab
instance sungguhan, jadi status "Terverifikasi" di tabel atas tetap datang dari sana, bukan dari
harness ini.

Status `NEED-NET` berarti script mati karena stub tidak benar-benar mengunduh apa pun, jadi
`cd` ke direktori hasil `git clone`/`gsutil cp` gagal. Itu batas harness, bukan bug script.

Cakupan repo ini terhadap katalog Arcade ada di [docs/coverage.md](docs/coverage.md).

### Lab yang tidak cocok diotomasi

**Challenge lab** memilih task secara acak per instance, ditandai teks `Dynamically selected task will show up here...` di halaman labnya. Nama dataset, tabel, dan kolom berbeda tiap peserta, jadi script statis bisa salah parameter.

`gsp340.sh` tetap disertakan, tapi semua nilai yang bisa berubah dikumpulkan di satu blok variabel di awal file. **Cocokkan blok itu dengan teks task di lab-mu sebelum menjalankan.** Kalau nama datasetnya beda, ubah variabelnya, jangan query di bawahnya.

**Lab berbasis Console** menilai artefak yang dibuat lewat UI, bukan resource yang bisa dibuat lewat API. Contoh terdokumentasi: **GSP1154 (Getting Started with Agent Studio)** — runbook lengkapnya di [docs/gsp1154.md](docs/gsp1154.md).

`gsp1154.sh` ada di repo ini tapi **sudah terbukti menghasilkan 0 poin**, dan sengaja tidak dimasukkan ke tabel di atas. Dites di lab instance sungguhan pada 2026-07-17: skor 0/5.

Yang menarik, kegagalannya bukan karena scriptnya error. Task 1, 2, dan 3 jalan tuntas, API-nya merespons, isinya sesuai lab — **dan tetap 0 poin**. Pesan checkpoint-nya yang menjelaskan kenapa:

```
Please create the 'Insurance Risk Factor Identification' prompt to see the 'Compare' feature
Please run the prompt to generate an image with 'Nano Banana 2'
```

Yang dicari checkpoint adalah **prompt tersimpan dengan nama tertentu** di Agent Studio, app Cloud Run hasil "Deploy as app", dan media hasil generate di Media Studio. Memanggil Vertex AI API dengan isi prompt yang sama persis tidak meninggalkan satu pun artefak itu. Jadi asumsi "checkpoint melihat jejak pemakaian API di project" salah, dan tidak ada tambalan kecil yang bisa memperbaikinya.

Pelajarannya untuk lab lain: **kalau checkpoint menyebut nama artefak UI, otomasi lewat API tidak akan menghasilkan poin** — sebanyak apa pun API call yang sukses. Kerjakan manual, GSP1154 cuma ~15 menit klik.

Script-nya tetap disimpan sebagai pendamping belajar: dia menjalankan semua prompt lab lewat API sekaligus, jadi bisa dipakai membandingkan efek temperature, top-P, few-shot, dan Flash lawan Pro tanpa mengklik satu-satu. **Bukan pengganti lab-nya.**

Catatan lain dari pengujian itu, kalau nanti ada yang meneruskan:

- Model di lab: `gemini-3.5-flash` dan `gemini-2.5-pro` (pasangannya memang terbalik, Flash-nya lebih baru). Keduanya valid di endpoint `global`.
- Gemini 3 pakai `thinkingConfig.thinkingLevel` (enum, mis. `MINIMAL`), bukan `thinkingBudget` (angka) seperti generasi 2.x.
- `gemini-2.5-pro` gampang kena `429 Resource has been exhausted` di project lab.
- Akun student lab tidak punya izin `serviceusage`, jadi jangan panggil `gcloud services enable` — Qwiklabs sudah meng-enable API-nya sejak provisioning.
- Task 5 di materi terbaru pakai **Nano Banana 2**, bukan Imagen 4 seperti yang masih tertulis di teks tugas.

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

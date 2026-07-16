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

Keterangan status:

- **Terverifikasi** berarti script pernah dijalankan sampai selesai di lab instance sungguhan dan semua checkpoint hijau, dengan skor yang tercatat di kolom yang sama.
- **Belum diuji** berarti script lolos pemeriksaan syntax dan `shellcheck`, tapi belum pernah dijalankan di lab instance sungguhan.
- **Satu varian task** khusus untuk challenge lab: script terbukti 100% pada varian task yang tercatat di file, tapi karena tasknya diacak per instance, varian lain bisa butuh penyesuaian variabel.

Lab dites ulang saat Google memperbarui materinya. Kolom "Terakhir diuji" menunjukkan kapan verifikasi terakhir dilakukan, jadi kalau tanggalnya sudah lama sementara lab-nya baru saja diupdate, anggap statusnya perlu dikonfirmasi ulang.

### Lab yang tidak cocok diotomasi

**Challenge lab** memilih task secara acak per instance, ditandai teks `Dynamically selected task will show up here...` di halaman labnya. Nama dataset, tabel, dan kolom berbeda tiap peserta, jadi script statis bisa salah parameter.

`gsp340.sh` tetap disertakan, tapi semua nilai yang bisa berubah dikumpulkan di satu blok variabel di awal file. **Cocokkan blok itu dengan teks task di lab-mu sebelum menjalankan.** Kalau nama datasetnya beda, ubah variabelnya, jangan query di bawahnya.

**Lab berbasis Console** menilai artefak yang dibuat lewat UI, bukan resource yang bisa dibuat lewat API. Contoh terdokumentasi: **GSP1154 (Getting Started with Agent Studio)**.

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

# Handoff (terakhir diperbarui 2026-11-09)

Catatan serah-terima sesi kerja lab Arcade. Baca ini dulu, lalu
[AGENTS.md](AGENTS.md) untuk konvensi script.

## Sesi 2026-11-09: GSP092 - Monitoring and Logging for Cloud Run Functions

- [`gsp092.sh`](gsp092.sh) + [runbook](docs/gsp092.md):
  - Memperbarui default region ke `us-central1` (mengikuti edisi terbaru lab).
  - Menambahkan flag `--quiet` dan `CLOUDSDK_CORE_DISABLE_PROMPTS=1` untuk eksekusi non-interaktif mulus.
  - Mempertahankan flow 2-step deployment: deploy via Cloud Functions v2 (`gcloud functions deploy --gen2`) kemudian update execution environment via Cloud Run (`gcloud run services update --execution-environment=gen2 --cpu=1 --memory=512Mi`).
  - Pembuatan logs-based metric `CloudRunFunctionLatency-Logs` (Distribution) serta load test 200 request paralel.
- **Status Terakhir**: Script siap diuji ulang pada lab instance aktif (us-central1, 2/2 checkpoint).
- **Next Action**: Jalankan di Cloud Shell lab GSP092 dan verifikasi 100/100.

## Sesi 2026-11-09: GSP651 - Setting Up Cost Control with Quota

- [`gsp651.sh`](gsp651.sh) + [runbook](docs/gsp651.md):
  - Membuat script baru untuk otomasi pengendalian biaya BigQuery dengan modifikasi kuota API melalui Service Usage.
  - Menjalankan kueri data publik `bigquery-public-data.wise_all_sky_data_release.mep_wise` yang memproses data ~1.36 TB (Checkpoint 1).
  - Memperbarui kuota harian query per pengguna menjadi 262144 MiB (0.25 TiB) menggunakan `gcloud alpha services quota update`.
  - Menguji eksekusi ulang kueri dengan `--nouse_cache` untuk memverifikasi penolakan kueri `Custom quota exceeded` (Checkpoint 2).
  - Menyediakan dokumentasi jawaban kuis pilihan ganda (1.36 TB dan Caching).
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (global US, 2/2 checkpoint hijau).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP762 - Create PDFs with Go and Cloud Run

- [`gsp762.sh`](gsp762.sh) + [runbook](docs/gsp762.md):
  - Membuat script baru untuk otomasi microservice invoice konversi PDF menggunakan LibreOffice headless dan Go di Cloud Run.
  - Mengompilasi binary secara statis (`CGO_ENABLED=0 GOOS=linux go build -o server`) dan membungkusnya dalam container image Debian dengan instalasi package `libreoffice`.
  - Membangun container image ke Artifact Registry `pdf-converter` via Cloud Build dan men-deploy ke Cloud Run dengan alokasi memori 2Gi.
  - Mengonfigurasi Cloud Storage notification pada bucket `gs://$PROJECT_ID-upload` ke Pub/Sub topic `new-doc`.
  - Membuat Service Account `pubsub-cloud-run-invoker` dengan role `roles/run.invoker` pada Cloud Run service.
  - Membuat push subscription `pdf-conv-sub` ke endpoint Cloud Run dengan otentikasi Service Account.
  - Menghapus pemanggilan `gcloud services enable` karena Google APIs sudah pre-enabled dan akun siswa tidak memiliki role Service Usage Admin.
  - Memperbarui stub test `test/stubs.sh` untuk mendukung `run services describe` URL.
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-central1, 4/4 checkpoint hijau).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP761 - Developing a REST API with Go and Cloud Run

- [`gsp761.sh`](gsp761.sh) + [runbook](docs/gsp761.md):
  - Membuat script baru untuk otomasi penyusunan REST API backend dengan Go (versi 0.1 dan versi 0.2).
  - Mengompilasi binary secara statis (`CGO_ENABLED=0 GOOS=linux go build -o server`) untuk kompatibilitas base distroless.
  - Membangun container image ke Artifact Registry `my-repo` via Cloud Build dan men-deploy ke Cloud Run.
  - Membuat database Firestore mode Native (`europe-west4`) secara idempoten dan mengimpor dataset pelanggan dari Cloud Storage.
  - Menghubungkan endpoint REST API `/v1/customer/{id}` ke Firestore client dan CORS middleware.
  - Menambahkan stub `go` pada test suite `test/stubs.sh` dan `test/run.sh`.
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (europe-west4, 4/4 checkpoint hijau).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP521 - Secure Software Delivery: Challenge Lab

- [`gsp521.sh`](gsp521.sh) + [runbook](docs/gsp521.md):
  - Memperbarui default region ke `us-west1` (sesuai instruksi Task 2 edisi terbaru).
  - Memperbarui Dockerfile Task 5 dari `python:3.8-alpine` ke `python:3.12-slim` dengan versi dependensi terbaru (Flask 3.0.3, Gunicorn 23.0.0, Werkzeug 3.0.4).
  - Menambahkan grant IAM ke Compute SA di samping Cloud Build SA untuk mendukung Cloud Build modern.
  - Mempertahankan flow di mana build Task 4 sengaja gagal di step `severity check` untuk memicu centang Checkpoint 4.
  - Menulis runbook di `docs/gsp521.md` dan memperbarui tabel serta instruksi one-liner di `README.md`.
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-west1, 5/5 checkpoint hijau).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP213 - Control Access to VPC Networks Using Firewall Rules and IAM

- [`gsp213.sh`](gsp213.sh) + [runbook](docs/gsp213.md):
  - Membuat script baru untuk otomasi provisioning VM `blue` (dengan tag `web-server` dan startup script Nginx) serta VM `green` (tanpa tag, kontrol).
  - Membuat tagged firewall rule `allow-http-web-server` untuk ingress port 80 dan icmp dengan target tag `web-server`.
  - Membuat VM `test-vm` di default VPC subnet untuk pengujian konektivitas internal.
  - Memastikan service account `network-admin` terdaftar dan mengikat role `roles/compute.networkAdmin` dan `roles/compute.securityAdmin` (`--condition=None`).
  - Menjaga firewall rule tetap aktif agar seluruh 6 checkpoint evaluasi di grader tetap bernilai hijau.
  - Menyertakan polling kesiapan startup script Nginx.
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-central1-b, 6/6 checkpoint hijau).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP211 - Create and Configure Multiple VPC Networks

- [`gsp211.sh`](gsp211.sh) + [runbook](docs/gsp211.md):
  - Memastikan otomasi pembuatan VPC custom mode (`managementnet` dan `privatenet`), subnets (`managementsubnet-1`, `privatesubnet-1`, `privatesubnet-2`), dan firewall rules (`managementnet-allow-icmp-ssh-rdp`, `privatenet-allow-icmp-ssh-rdp`).
  - Memastikan pembuatan VM instances `managementnet-vm-1` dan `privatenet-vm-1` di zone utama (`us-central1-f`).
  - Memastikan pembuatan VM multi-NIC `vm-appliance` (`e2-standard-4`) dengan 3 network interfaces (`privatesubnet-1`, `managementsubnet-1`, `mynetwork`).
  - Auto-detection zone dan region dari instance default lab (`mynet-vm-1` dan `mynet-vm-2`).
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-central1-f, asia-east1, 7/7 checkpoint hijau).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP750 - Infrastructure as Code with Terraform

- [`gsp750.sh`](gsp750.sh) + [runbook](docs/gsp750.md):
  - Memperbaiki deteksi dummy wrapper Terraform Cloud Shell dan instalasi otomatis jika belum ada (HashiCorp apt repo + zip fallback).
  - Menambahkan pembacaan default zone (`us-east1-c`) dan region (`us-east1`) dari metadata/config lewat helper `ask`.
  - Mempertahankan `google_storage_bucket.example_bucket` dan `another_instance` di konfigurasi Task 4 agar Checkpoint 5 (Create a bucket dependent instance) di grader tidak hilang.
  - Memperbarui header konvensi checkpoint dan echo ringkasan verifikasi 5 task (masing-masing 20 pts).
  - Menulis runbook di `docs/gsp750.md` dan memperbarui tabel serta panduan one-liner di `README.md`.
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-east1-c, debian-12 / cos-stable, 5/5 checkpoint hijau).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP345 - Build Infrastructure with Terraform on Google Cloud: Challenge Lab

- [`gsp345.sh`](gsp345.sh) + [runbook](docs/gsp345.md):
  - Memperbarui Google Provider ke `~> 6.0` dan VPC module ke `10.0.0` sesuai materi lab terbaru.
  - Memperbarui default suffix dinamis: `BUCKET_SUFFIX=852606`, `VPC_SUFFIX=821633`, `INSTANCE3_SUFFIX=298349`.
  - Memperbaiki deteksi dummy wrapper Terraform Cloud Shell dan instalasi otomatis jika belum ada.
  - Menghapus pause interaktif `read -r` pada Task 5 agar eksekusi seluruh 7 task berjalan mulus tanpa jeda.
  - Menambahkan runbook dokumentasi di `docs/gsp345.md`.
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-east1-c, debian-12, 7/7 checkpoint hijau).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP752 - Manage Terraform State

- [`gsp752.sh`](gsp752.sh) + [runbook](docs/gsp752.md):
  - Memperbaiki deteksi dummy wrapper Terraform Cloud Shell dan instalasi otomatis jika belum ada.
  - Menghapus jeda interaktif `read -r` dan penghapusan bucket otomatis pada Task 1 agar checkpoint Task 1 (Work with backends, 100 poin) tetap hijau.
  - Memastikan migrasi local ke gcs backend berjalan mulus (`yes | terraform init -migrate-state`) dan label `key:value` disinkronkan via `terraform refresh`.
  - Mengotomasi Task 2 (Docker container import) tanpa jeda.
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-west1).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP751 - Interact with Terraform Modules

- [`gsp751.sh`](gsp751.sh) + [runbook](docs/gsp751.md):
  - Memperbaiki deteksi dummy wrapper Terraform Cloud Shell dan instalasi otomatis jika belum ada.
  - Memperbarui konfigurasi subnet region dan location bucket ke `us-central1` (default lab) via helper `ask`.
  - Menghapus pause interaktif `read -r` pada Task 2 agar eksekusi 100% otomatis tanpa prompt di tengah jalan.
  - Membiarkan Cloud Storage bucket `gs://$PROJECT_ID` aktif dengan file `index.html` dan `error.html` terunggah agar verifikasi Task 2 (Build a module) lolos 100%.
  - Menambahkan idempotensi `terraform import` untuk storage bucket.
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-central1).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-11-09: GSP156 - Terraform Fundamentals

- [`gsp156.sh`](gsp156.sh) + [runbook](docs/gsp156.md). Diperbarui sesuai materi lab edisi terbaru (update 4 hari lalu):
  - **Temuan krusial**: Di Cloud Shell terdapat dummy wrapper script bawaan untuk `terraform` yang keluar dengan exit code 0 dan hanya mencetak pesan "Follow the instructions...". Pengecekan `command -v terraform` keliru mendeteksinya sebagai terpasang. Diperbaiki dengan memeriksa `terraform --version | grep 'Terraform v'` serta fallback unzip binary jika apt lambat/gagal.
  - Penambahan instalasi otomatis Terraform via HashiCorp repository jika belum terpasang (`cat <<'EOF' > ~/.customize_environment`).
  - Pembaruan nama resource ke `google_compute_instance.default` dan OS image ke `debian-12`.
  - Penambahan helper `ask` dengan deteksi default zone otomatis dari metadata project (`google-compute-default-zone`) / config, fallback ke `us-east1-c`.
  - Idempotensi: pemeriksaan dan `terraform import` jika instance `terraform` sudah ada di GCP.
  - Perintah eksekusi Cloud Shell ditambahkan di akhir [`README.md`](README.md).
- **Status Terakhir**: Terverifikasi sukses 100/100 di live lab Cloud Shell (us-east1-c, debian-12).
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-10-27: Borongan 6 Lab (GSP1024, GSP096, GSP401, GSP192, ARC113, GSP064)

Sesi otomasi dan verifikasi 6 lab (5 lab 100/100, 1 lab 75/100):

### 1. GSP064: Manage Access Control with IAM (100/100)
- [`gsp064.sh`](gsp064.sh) + [runbook](docs/gsp064.md). Dikerjakan 100% otomatis dari terminal Cloud Shell milik Username 1 (Owner).
- **Temuan krusial**: Policy IAM project lab ini memiliki *condition* (pembatasan kurikulum). Perintah `gcloud projects add-iam-policy-binding` dan `remove-iam-policy-binding` secara non-interaktif **wajib menyertakan `--condition=None`**, jika tidak gcloud akan menolak atau gagal diam-diam, menyebabkan log pencopotan akses tidak terbentuk di grader.

### 2. GSP192: Dataflow: Qwik Start - Templates (100/100)
- [`gsp192.sh`](gsp192.sh) + [runbook](docs/gsp192.md). Otomasi BigQuery dataset `taxirides`, table `realtime` partitioned, bucket GCS, dan streaming job Dataflow `iotflow` template `PubSub_to_BigQuery`.
- **Temuan krusial**: Ketika Dataflow API di-disable dan di-enable kembali di Task 1, izin role `roles/dataflow.worker` pada default compute service account (`<project_number>-compute@developer.gserviceaccount.com`) lepas, menyebabkan job gagal (`Workflow failed: There was a problem refreshing your credentials`). Script otomatis mengikat ulang role `roles/dataflow.worker` dan `roles/dataflow.serviceAgent` sebelum job dijalankan.

### 3. GSP401: Cloud Scheduler: Qwik Start (100/100)
- [`gsp401.sh`](gsp401.sh) + [runbook](docs/gsp401.md). Otomasi Pub/Sub topic `cron-topic`, subscription `cron-sub`, dan Cloud Scheduler job `cron-job` dengan target Pub/Sub di region `us-east4`. Selesai dalam < 1 menit.

### 4. GSP096: Pub/Sub: Qwik Start - Console (100/100)
- [`gsp096.sh`](gsp096.sh) + [runbook](docs/gsp096.md). Otomasi pembuatan topic `MyTopic`, subscription `MySub`, publish pesan `Hello World`, dan pull message. Penanganan bypass error kuota 429 pada API enable serviceusage. Selesai dalam < 10 detik.

### 5. ARC113: Implement Event-Driven Messaging and Automation Workflows (100/100)
- [`arc113.sh`](arc113.sh) + [runbook](docs/arc113.md). Uji ulang varian schema + topic + Cloud Run function gen2.
- Penyesuaian: Menambahkan toleransi `2>/dev/null || true` pada langkah `gcloud services enable` dan `add-iam-policy-binding` karena akun student pada challenge lab tidak memiliki wewenang admin serviceusage/IAM.

### 6. GSP1024: Using Prometheus for Monitoring on Google Cloud (75/100)
- [`gsp1024.sh`](gsp1024.sh) + [runbook](docs/gsp1024.md). Update default zone `us-east1-d` dan region `us-east1`, penambahan pengecekan kesiapan `/metrics` sebelum traffic generator, dan pembuatan dashboard dari file JSON.
- Skor meningkat dari 50/100 menjadi 75/100 (Task 1, 3, dan 5 hijau). Task 4 (Verify application deployed) masih merah walau pod 1/1 Running, service memiliki public IP, merespons 200, dan metrik terbukti ter-ingest ke Cloud Monitoring.

- **Status Terakhir**: 4 script baru ditambahkan (`gsp064`, `gsp096`, `gsp401`, `gsp192`) beserta runbook masing-masing. Script `arc113` dan `gsp1024` disempurnakan.
- **Next Action**: Lanjutkan lab arcade berikutnya dari daftar antrean.

## Sesi 2026-10-23: Review PR GitHub dan Status Proyek

- **Review dan Close PR #2**: PR #2 oleh `@rulshrm` (patch `gsp1049.sh`) ditinjau dan ditutup (`closed`). Alasan: breaking change berupa penghapusan fungsi `row_count()` yang esensial untuk gating checkpoint Dataflow Task 3/4, serta ketiadaan aktivitas author selama lebih dari 1.5 bulan sejak review pertama. Saat ini 0 PR terbuka di repository.
- **Daftar File Diubah (git status -s)**:
  - `M README.md`: update status lab GSP095, GSP048, dan GEAR Mini-Project.
  - `M docs/arc102.md`: dokumentasi deploy function gen1 dengan trigger bucket.
  - `M docs/gear-bonus.md`: update status verifikasi GEAR Mini-Project per 2026-09-18.
  - `M arc102.sh`: update penyesuaian trigger Cloud Functions gen1.
  - `M gsp095.sh`: penyesuaian idempotensi Pub/Sub.
  - `?? docs/gsp095.md`: runbook baru untuk GSP095.
- **Status Terakhir**: PR #2 ditutup. Perubahan lokal pada berkas docs dan script siap diuji sebelum commit manual.
- **Next Action**: Lakukan uji coba lokal atau verifikasi `bash -n` untuk script yang diubah sebelum Ravi melakukan git commit manual.

## Sesi 2026-08-22 — GSP328, GSP523, ARC119 (semua 100/100)

### ARC119 — API Data Catalog sudah dimatikan di project lab

[`arc119.sh`](arc119.sh) + [runbook](docs/arc119.md). Secure data lake di
Knowledge Catalog, 4 task.

**Instruksi lab masih memakai kosakata Data Catalog yang API-nya sudah mati.**
Task 4 minta "tag template"; `gcloud data-catalog tag-templates create` ditolak:

```
INVALID_ARGUMENT: Project ... is not allowed to perform read operations
due to Data Catalog deprecation.
WARNING: This command is deprecated. Please use `gcloud dataplex aspect-types` instead.
```

Yang dinilai ternyata **aspect type** dengan display name `Customer Data Tag
Template`; field Text → `type: string`, field Enum → `type: enum` +
`enumValues`. Aturan yang mengeras: kalau soal lab menyebut Data Catalog, tag,
atau entry, terjemahkan dulu ke Knowledge Catalog sebelum menulis perintah.

**Penempelan tag/aspect ke entry tetap tidak diperiksa grader.** Task 4 hijau
25/25 begitu aspect type dibuat, tanpa menempelkannya ke entry bucket sama
sekali — padahal soal menyuruhnya. Ini kali ketiga setelah GSP514 dan ARC117.
Versi pertama script membuang waktu mencari entry bucket di Knowledge Catalog
search (kosong) dan di `data-catalog search` (ditolak). Sekarang langkah itu
dibuang total.

**Pembagian "User 1 / User 2" di soal juga tidak diperiksa.** Semua dikerjakan
dari satu Cloud Shell, keempat checkpoint hijau.

### GSP328 dan GSP523

#### GSP523 — nama dan region dideteksi, bukan ditanya

[`gsp523.sh`](gsp523.sh) + [runbook](docs/gsp523.md). Multimodal vector search
BigQuery, 4 task, 100/100 sekali jalan.

Pola baru yang layak ditiru: **dataset bawaan lab dipakai sebagai sumber
kebenaran**, bukan panel lab. Script mencari `*_bqml_dataset` lewat `bq ls`,
lalu mengambil `location`-nya jadi region connection dan prefiksnya (`gcc`)
jadi dasar nama keempat resource lain. Hasilnya lab ini aman di-pipe ke `bash`
tanpa pertanyaan sama sekali. Region connection memang wajib sama dengan
dataset — beda sedikit langsung `Not found: Connection` saat object table
dibuat, dan pesan itu tidak menyebut region sebagai penyebabnya.

Dua detail lain: service account connection ber-ID acak
(`bqcx-...@gcp-sa-bigquery-condel`) jadi harus dibaca balik dari
`bq show --connection --format=json`, dan role "Agent Platform User" di
instruksi lab adalah nama baru `roles/aiplatform.user`.

#### GSP328 — instruksi lab sendiri yang salah

[`gsp328.sh`](gsp328.sh) + [runbook](docs/gsp328.md). Challenge lab Cloud Run,
7 task, 100/100 sekali jalan. Dua hal yang menentukan:

- **Instruksi lab sendiri salah menunjuk `BILLING_URL`.** Task 5 menyuruh
  mengisi `PROD_BILLING_URL` dari `private-billing-service-339` — itu service
  Task 3. Yang benar billing prod (Task 5), karena SA frontend hanya diberi
  `run.invoker` di service itu. Deploy tetap sukses kalau salah, tapi UI-nya
  kosong. Jangan menyalin perintah lab mentah-mentah untuk nilai yang dipakai
  script.
- **Pola dua fase terpakai lagi.** Task 3 menghapus service yang dinilai Task 1,
  jadi fase staging berhenti dan menunggu checkpoint hijau. Ini lab kesembilan
  yang memakai pola itu.

## Sesi 2026-08-21/22 — borongan 17 lab

Sesi panjang, 16 dari 17 lab dapat 100/100. Script baru: `gsp073`, `gsp095`,
`gsp207`, `gsp351`, `gsp659`, `gsp903`, `arc100`, `arc102`, `arc110`, `arc112`,
`arc131`. Yang sudah ada dan terverifikasi/diperluas: `gsp074`, `gsp080`,
`gsp421`, `arc111` (varian form-1), `arc114`.

Badge **725 Get Started with Cloud Storage** jadi badge pertama yang keempat
labnya terbukti 100/100, bukan sekadar punya script.

### Temuan lintas-lab yang layak diingat

**API key buatan CLI tidak menghijaukan checkpoint "Create an API key".**
Terbukti di ARC131 lalu dipisah variabelnya di ARC114 pada hari yang sama: key
`gcloud` **dengan** `--api-target` tetap merah, key console hijau. Jadi
pembuatan lewat console yang menentukan, bukan restriction-nya. Berlaku juga
untuk arc132, gsp038, arc130. Detail di [docs/arc114.md](docs/arc114.md).

**Generasi Cloud Functions mengikuti tanda tangan kode, bukan selera.** ARC100
dan ARC102 dua-duanya "bikin thumbnail dari upload ke bucket", tapi ARC100
pakai `functions.cloudEvent(...)` → gen2, sedangkan ARC102 pakai
`exports.thumbnail = (event, context)` → **gen1 wajib**. Tambahan: ARC102
memakai `imagemagick-stream` yang butuh binary `convert`, tersedia di runtime
gen1 tapi tidak di buildpack gen2 — kalau salah generasi, fungsi ter-deploy
sehat tapi thumbnail tidak pernah terbentuk. Bandingkan
[docs/arc100.md](docs/arc100.md) dan [docs/arc102.md](docs/arc102.md).

**Service agent Google dibuat malas.** Mengaktifkan API tidak membuat service
account-nya ada, jadi `add-iam-policy-binding` menolak dengan "Service account
... does not exist". Paksa dengan `gcloud beta services identity create
--service=<api>`. Ditemukan di ARC100.

**Yang tersembunyi di balik pilihan console.** GSP351: memilih "Existing
instance" sebagai destination DMS diam-diam men-demote instance itu jadi
replica. Lewat CLI harus eksplisit (`migration-jobs demote-destination`), dan
demote itu membuat instance `<destination>-master` yang tidak pernah `RUNNABLE`
— deteksi otomatis harus mengecualikannya. Juga: hanya `create` yang punya
`--no-async`; `start` dan `promote` menolaknya.

**Jangan telan error dengan `|| true`.** Versi pertama `gsp351.sh` menelan
kegagalan `start`, akibatnya loop memantau `NOT_STARTED` selama 25 menit tanpa
sebab yang terlihat. Pola yang dipakai sekarang: cetak errornya, dan menyerah
cepat kalau state tidak beranjak.

### ARC114 Task 4: ronde keempat, tetap rusak

Ditelusuri ulang atas permintaan, kali ini dengan mencari **bukti apa yang
tersedia untuk dibaca grader**, bukan menebak. Hasilnya: startup script VM
kosong, hanya ada satu home (jadi grader tidak pernah SSH), dan metrik API
menunjukkan `AnalyzeSentiment` tercatat dengan credential service account
maupun API key setelah diuji keduanya. Ketiga saluran bukti dipenuhi serentak,
checkpoint tetap 0/25. Lima belas hipotesis, empat instance, dua di antaranya
setelah lab di-update. Maks tetap **75/100**. Resep query Cloud Monitoring untuk
memeriksa request per credential disimpan di runbook — berguna kalau ada
checkpoint mencurigakan lain.

### Pola yang mengeras jadi kebiasaan

Lab yang punya langkah "undo" (hapus bucket, cabut akses publik, promote,
kembalikan concurrency) selalu dipisah ke fase kedua yang tidak jalan otomatis,
karena langkah itu menghapus persis yang dinilai checkpoint sebelumnya. Sekarang
dipakai di `gsp073`, `gsp074`, `gsp421`, `gsp659`, `gsp903`, `arc110`, `arc112`,
`gsp351`.

## Sesi 2026-08-10 (GSP395, 100/100)

Script baru [`gsp395.sh`](gsp395.sh) + [runbook](docs/gsp395.md). AlloyDB, 5 task,
100/100 di region `us-west1`. Tiga hal yang menentukan:

- **SQL harus lewat SSH ke VM `alloydb-client`.** AlloyDB hanya punya private IP
  di `peering-network`; `psql` dari Cloud Shell tidak akan pernah connect.
- **`psql -v ON_ERROR_STOP=1`.** Tanpa itu psql exit 0 walau DDL gagal dan
  script melapor SELESAI padahal tabelnya tidak ada — kembaran temuan ARC114.
- **Panel lab menampilkan zone (`us-west1-c`), bukan region.** Script memotong
  sufiks zone-nya sendiri. Layak ditiru di script lain yang meminta region.

Read pool dibuat di latar belakang sambil tabel diisi (~5 menit hemat); backup
tidak ikut diparalelkan karena cluster AlloyDB menolak operasi baru selagi ada
operasi lain berjalan.

`test/stubs.sh` dapat satu entri baru: `--format='value(ipAddress)'` mengembalikan
`10.20.0.2`, kalau tidak dry-run berhenti di guard private IP.

## Sesi 2026-08-10 (ARC113, 100/100)

Script baru [`arc113.sh`](arc113.sh) + [runbook](docs/arc113.md). 3 task, 100/100
sekali jalan. **Lab ini punya varian task** — deskripsinya sendiri bilang "you
may get task to use Cloud Scheduler ... Snapshot ... Pub/Sub Lite". Yang ditulis
baru varian schema + topic + Cloud Run function; perintah inti untuk tiga varian
lain ada di runbook, tinggal dirapikan jadi fase kalau muncul.

Dua hal yang menentukan hijau/merah:

- **"Cloud Run Function environment" = `--gen2`.** Bukan Cloud Functions lama.
- **`schemaSettings` hanya bisa diisi saat topic dibuat.** Tidak ada
  `topics update` untuk menempelkan schema, jadi topic yang sudah ada tanpa
  schema harus dihapus dan dibuat ulang.

## Sesi 2026-08-10 (GSP364, 100/100)

Script baru [`gsp364.sh`](gsp364.sh) + [runbook](docs/gsp364.md). Challenge lab
Managed Service for Prometheus: 4 task, semuanya otomatis, 100/100 sekali jalan.
Tiga hal yang tidak ada di instruksi lab tapi dipasang script:

- **PodMonitoring dibuat sendiri.** `examples/example-app.yaml` upstream hanya
  berisi Deployment (dicek di v0.17.0), jadi tanpa itu tidak ada yang men-scrape
  dan filter `{job="prom-example"}` tidak mengenai metrik apa pun.
- **Bucket dibuat `gsutil mb -b off`.** Perintah `acl set public-read` di
  instruksi lab ditolak di bucket uniform bucket-level access; ada fallback ke
  IAM `allUsers/objectViewer`.
- **example-app di dua namespace** (`default` + `gmp-test`) karena instruksi
  tidak menyebut namespace.

Bug yang ditangkap dry-run harness, bukan lab: `VER="$(curl ... | grep ...)"`
tanpa `|| true` membuat `set -e` membunuh script saat GitHub API tidak menjawab,
jadi baris fallback versi tidak pernah tercapai. Pola ini layak dicek di script
lain yang mengambil versi dari API.

## Sesi 2026-08-10 (GSP329, 100/100)

Script baru [`gsp329.sh`](gsp329.sh) + [runbook](docs/gsp329.md). Challenge lab
ML APIs (Vision + Translation): 5 task, semuanya otomatis, nol langkah Console.

**Temuan utama, berlaku untuk semua lab yang memakai key service account dari
Cloud Shell:** dua role yang diminta instruksi (`bigquery.dataEditor` +
`storage.admin`) **tidak cukup**. Panggilan Storage pertama balik
`403 ... does not have serviceusage.services.use access` karena klien Python
mengirim header quota-project. Perbaikannya mengikat
`roles/serviceusage.serviceUsageConsumer` juga dan menjalankan Python dengan
`env -u GOOGLE_CLOUD_QUOTA_PROJECT`. Role tambahan tidak menggagalkan checkpoint
Task 1 — grader mengecek keberadaan dua role lab, bukan ketiadaan yang lain.

Dua keputusan lain yang membedakannya dari solusi umum:

- **`analyze-images-v2.py` ditulis ulang, bukan ditambal.** Grader menilai
  hasilnya (file `.txt` di bucket, baris BigQuery, query yang pernah jalan),
  bukan isi file `.py`. Menambal komentar `# TBD:` bergantung pada teks yang
  bisa berubah antar-revisi lab, dan `sed` yang meleset baru ketahuan di
  tengah lab.
- **Kolom BigQuery dipetakan dari `table.schema`,** bukan tuple posisional
  seperti solusi resmi. Urutan/jumlah kolom yang berbeda antar-instance tidak
  lagi bisa menggagalkan insert. Nama kolom dicetak saat jalan. Kolom di
  instance yang diuji: `original_text, locale, translated_text, file_name` —
  bukan nama yang diasumsikan solusi resmi.

## Sesi 2026-08-10 (GSP319, 100/100)

Script baru [`gsp319.sh`](gsp319.sh) + [runbook](docs/gsp319.md). Challenge lab
monolith-to-microservices: 7 task, semuanya otomatis, **100/100 sekali jalan**
tanpa intervensi. Tiga hal yang membuatnya muat di waktu lab:

- Cluster GKE dibuat di latar belakang (`&` + `wait $PID`) sambil `setup.sh` dan
  build monolith jalan; build orders + products juga paralel. Dua antrean ~5
  menit jadi tumpang tindih.
- `npm run build` di `react-app` cukup sekali: `prebuild` mengurus versi monolith
  dan `postbuild` menyalin hasilnya ke `microservices/src/frontend/public`, jadi
  image frontend otomatis membawa IP orders/products yang baru.
- Frontend dipasang `imagePullPolicy: Always`. Tag-nya tetap `1.0.0` padahal
  isinya berubah antar-run, dan default `IfNotPresent` membuat node memakai image
  lama yang masih menunjuk `localhost` — hanya kelihatan saat rerun.

## Sesi 2026-08-09 (ARC114, ditinggalkan di 75/100)

Script baru [`arc114.sh`](arc114.sh) + [runbook](docs/arc114.md). Task 1-3 hijau
sekali jalan. **Checkpoint Task 4 dianggap rusak**: dua instance lab berbeda,
dua belas hipotesis diuji satu per satu, semuanya gugur, sementara analisis
sentimennya selalu berhasil dan mengeluarkan skor yang benar. Lab ditinggalkan,
tidak diselesaikan.

Runbook memuat tabel lengkap hipotesis yang sudah gugur — **baca dulu** kalau
lab ini disentuh lagi, jangan mengulangi enam ronde diagnosis yang sama. Dua
temuan yang berlaku umum untuk lab keluarga Speech/Language: virtualenv di
`lab-vm` bernama `env` (ARC132 pakai `venv`) dan **isinya kosong**, jadi
`google-cloud-language` harus dipasang sendiri; dan script remote wajib `exit 1`
saat analisis gagal, kalau tidak `set -uo pipefail` tanpa `-e` membuatnya gagal
diam-diam sambil tetap mencetak "SELESAI".

## Posisi sekarang

**Game Arcade 2026 (Agustus): 6/6 SELESAI** (dikonfirmasi user 2026-08-08) — Base Camp,
Adventure (Data Vault), Voyage (Google Sheets), Trail (Cloud Delivery Systems),
Special (Spans and Plans), Simulator (Network Security Engineer).

Bonus di luar game: **GEAR Mini-Project** (bangun AI agent + submit form
verifikasi) — form sudah disubmit 2026-08-08, biaya Rp 0, hasil verifikasi
menunggu ≤48 jam. Runbook + jebakan billing Indonesia ada di
[docs/gear-bonus.md](docs/gear-bonus.md). Jangan hapus project `gear-agent-12083`
atau binding verifiernya sampai program selesai + 2 minggu.

**Langkah berikutnya: tidak ada yang mendesak.** Kalau ada sesi lanjutan, isinya
melunasi utang di bagian bawah dokumen ini (script yang belum pernah diuji) atau
menambah cakupan badge di [docs/coverage.md](docs/coverage.md), bukan mengejar
game.

## Sesi 2026-08-08 (bonus GEAR, tanpa lab)

Sesi ini tidak menyentuh script lab sama sekali. Isinya menuntaskan bonus
GEAR Mini-Project dan merapikan dokumen.

- **[docs/gear-bonus.md](docs/gear-bonus.md)** — runbook baru. Tiga temuan yang
  menghemat waktu kalau program serupa muncul lagi: verifier
  `arcade-agent-verifier@google.com` itu **Google Group** (`--member="group:..."`,
  `user:` ditolak); `gcloud services enable` **berhasil walau `billingEnabled: false`**;
  dan prabayar Rp 500rb untuk kartu debit Indonesia itu syarat kredit trial, **bukan**
  syarat verifikasi. Total biaya akhirnya Rp 0.
- **README** dapat pointer ke dokumen itu.

**Badge berikutnya yang disarankan: 716 Implement DevOps Workflows.** Paling murah —
`gsp053.sh` dan `gsp1077.sh` sudah ada dan terverifikasi, sisa GSP121 + challenge
GSP330, dan materinya sekelanjutan Trail yang baru selesai. Cadangan: 727 Eventarc
(punya `gsp1089.sh`, sisa GSP095, GSP773, ARC118). Hindari dulu 623, 663, 750, 641,
654, 648 — nol script, tiap lab harus ditulis dari nol.

Profil user per 2026-08-08: 28 skill badge, Silver League 693 poin.

## Yang diselesaikan sesi 2026-08-04/05

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
- `docs/coverage.md` bagian "Badge berikutnya yang paling dekat" **basi** — dua badge
  yang disebut di situ (1177, 655) sudah dimiliki user sejak Juli. Belum diperbarui,
  dan file itu memang tidak menandai badge mana yang sudah dimiliki.
- Hasil verifikasi bonus GEAR belum diketahui. Risiko yang tersisa: billing account
  user berstatus `OPEN: False` (prabayar tidak dibayar). Kalau checker mereka menuntut
  billing aktif, poin itu gagal — catat hasilnya di `docs/gear-bonus.md` kalau sudah
  ada kabar dari facilitator.

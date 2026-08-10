# Handoff — terakhir diperbarui 2026-08-10

Catatan serah-terima sesi kerja lab Arcade. Baca ini dulu, lalu
[AGENTS.md](AGENTS.md) untuk konvensi script.

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

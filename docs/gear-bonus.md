# GEAR Mini-Project: Build Your First AI Agent (bonus, di luar lab)

Bukan lab Qwiklabs. Ini tugas bonus program Arcade/GEAR yang dikerjakan di **akun Google Cloud
pribadi** dengan billing sendiri, bukan di project lab. Tidak ada Check my progress; verifikasinya
lewat form.

Status (2026-09-18): **agent jalan dan form terkirim ulang** di project
`gearminiproject-508106`, billing account `01C3E0-29ECF8-0623CA` sudah `OPEN: True`. Prabayar
Rp 500rb sudah dibayar dan diterima sebagai saldo prepayment. Binding verifier
`group:arcade-agent-verifier@google.com` role `serviceusage.serviceUsageViewer` sudah terpasang.
Menunggu hasil verifikasi (maks 48 jam); poin (10) baru masuk di akhir program.

Status sebelumnya (2026-08-08): form disubmit dengan billing `OPEN: False` di project
`gear-agent-12083`.

Sumber: dokumen program "GEAR Mini-Project: Build Your First AI Agent using Vertex AI (Agent
Platform)". Deadline form: 14 Sep 2026.

## Yang sebenarnya dinilai

Dokumennya panjang (install SDK, tulis `agent.py`, jalankan chat loop), tapi yang dibaca sistem
verifikasi cuma dua:

1. **`aiplatform.googleapis.com` aktif** di project yang punya billing.
2. **`arcade-agent-verifier@google.com` punya role `roles/serviceusage.serviceUsageViewer`**
   di project itu — inilah cara mereka membaca status enablement API-mu.

Dua temuan yang menghemat waktu:

- **Verifier itu Google Group, bukan user.** `--member="user:arcade-agent-verifier@google.com"`
  ditolak: `Principal ... is of type "group"`. Pakai `group:`.
- **`gcloud services enable` berhasil walau `billingEnabled: false`.** Enable API tidak menuntut
  billing aktif; yang menuntut cuma pemakaiannya. Jadi syarat nomor 1 bisa dipenuhi tanpa
  mengeluarkan uang sama sekali.

Menulis dan menjalankan agentnya (Step 2–5 di dokumen) **tidak dicek sama sekali**. Kalau kode
contohnya error (nama model / SDK), poinnya tetap aman.

## Prasyarat: billing account aktif

Project lab Qwiklabs tidak bisa dipakai — akunnya sementara dan bukan milikmu. Harus akun sendiri
dengan Free Trial ($300 / 90 hari) atau billing berbayar.

Jebakan yang ditemui waktu menyiapkannya:

- **Payments profile bertipe Organization menuntut NPWP badan** di halaman *Indonesia tax info*,
  dan tipe profil **tidak bisa diubah setelah dibuat**. Solusinya bikin profil baru: kartu
  Contact information → **Change** → **Create new payments profile** → **Account type: Individual**.
  Dengan Individual, tax status jadi `Personal` dan NIK 16 digit diterima sebagai NPWP orang
  pribadi (kolomnya juga boleh dikosongkan).
- **Org bernama `<username>-org` dengan `DIRECTORY_CUSTOMER_ID` kosong itu normal** — Google Cloud
  membuatnya otomatis untuk akun Gmail biasa. Bukan Workspace, tidak ada admin yang mengunci
  apa pun. Cek: `gcloud organizations list`.
- **Error `OR_BACR2_44`** waktu Submit: penolakan generik payments. Yang sempat dicoba dan patut
  dicoba lagi — matikan content blocker (Brave Shields) di halaman itu, buka konteks tanpa org
  (`console.cloud.google.com/billing?organizationId=0`), ganti kartu. Jangan retry lebih dari ~3
  kali; Google mengunci percobaan ~24 jam dan errornya jadi sama terus.

## Blocker: prabayar Rp 500rb untuk kartu debit

Setelah profil Individual beres, Submit memunculkan dialog **"One-time prepayment required"**:
Google Cloud Indonesia mewajibkan deposit **Rp 500.000** kalau metode pembayarannya kartu debit.
Uangnya jadi saldo akun (kepakai untuk pemakaian Cloud) dan refundable saat billing account
ditutup, tapi prosesnya lama.

Kartu kredit umumnya lolos tanpa deposit. Tidak ada metode lain untuk akun self-serve —
GoPay/OVO/transfer bank tidak dipakai di Cloud billing.

**Yang ternyata salah dugaan:** billing account tetap terbentuk walau prabayarnya tidak dibayar,
statusnya cuma `OPEN: False` (`Paid account`, tanpa kredit trial). Dan dengan status itu
`gcloud services enable aiplatform.googleapis.com` **tetap sukses**. Jadi prabayar Rp 500rb itu
syarat mengaktifkan kredit trial $300 dan pemakaian resource, **bukan** syarat memenuhi verifikasi
GEAR.

Kenapa diminta prabayar: di daftar `gcloud billing accounts list` ada dua
`Google Cloud Platform Trial Billing Account` lama — jatah free trial akun ini sudah terpakai, jadi
tidak lagi memenuhi syarat trial gratis.

Keputusan 2026-08-08: **prabayarnya dilewati, form tetap disubmit**. Tidak ada uang keluar; kalau
ternyata verifikasi mereka juga menuntut billing aktif, ya tidak ada yang hilang.

Update 2026-09-18: prabayarnya **dibayar** dan billing account jadi `OPEN: True`. Dana Rp 500rb
ternyata masuk sebagai **deposit awal (prepayment)**, bukan tagihan pemakaian — saldo itu bisa
dipakai untuk biaya Cloud dan refundable saat billing account ditutup. Detail pesannya perlu
dibaca hati-hati: yang diminta saat submit adalah verifikasi metode pembayaran, bukan biaya
bulanan.

## Langkah lengkap

Di Cloud Shell akun pribadi:

```bash
gcloud billing accounts list                  # salin ACCOUNT_ID

PROJECT_ID="gear-agent-$RANDOM"
gcloud projects create "$PROJECT_ID"
gcloud billing projects link "$PROJECT_ID" --billing-account=XXXXXX-XXXXXX-XXXXXX
gcloud config set project "$PROJECT_ID"
gcloud services enable aiplatform.googleapis.com

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="group:arcade-agent-verifier@google.com" \
  --role="roles/serviceusage.serviceUsageViewer"

echo "Project ID: $PROJECT_ID"
```

Cek sebelum submit:

```bash
gcloud services list --enabled | grep aiplatform
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten=bindings --filter="bindings.role:serviceUsageViewer"
```

Lalu isi form verifikasi (`forms.gle/MMfH5RKp83TfRtXj9`, 5 halaman) dengan:

- **Email** — harus **persis** email pendaftaran program. Formnya menegaskan "ONLY login using
  that email address that you used to enrol in the program", dan email yang sama juga harus dipakai
  membuat agentnya. Ini yang menentukan akun mana yang dipakai, bukan preferensi.
- Nama lengkap.
- Project ID + Billing Account ID (format `XXXXXX-XXXXXX-XXXXXX`, dari Billing → Manage Billing
  Account).
- Halaman Terms & Conditions: pilih **"Yes, I accept the terms"**. Menolak = agent tidak
  diverifikasi, poin bonus hangus. Isinya standar (kredit non-transferable, tidak boleh untuk
  mining kripto, larangan negara embargo, Google boleh melacak grade dan pembuatan agent).
- Halaman terakhir: konfirmasi IAM verifier sudah dipasang. Pilih **"Ya"** — lalu pastikan
  halaman konfirmasi menampilkan "Jawaban Anda telah direkam", bukan pesan penolakan. Kalau
  pesan penolakan yang muncul padahal pilihannya benar, cek email konfirmasi Google Forms dan
  pakai link "Edit respons Anda" di sana untuk submit ulang (kasus 2026-09-18: submit ulang
  berhasil dan respons tercatat).

Dokumen program minta IAM binding verifier itu **dipertahankan sampai program selesai + 2 minggu**.
Hapus setelahnya:

```bash
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="group:arcade-agent-verifier@google.com" \
  --role="roles/serviceusage.serviceUsageViewer"
```

`Service Usage Viewer` memang read-only untuk status/kuota API — tidak bisa membaca data atau
mengubah resource. Tetap saja ini akun pribadi, bukan lab sekali pakai, jadi cabut aksesnya kalau
sudah tidak perlu.

## Agentnya (opsional, tidak dinilai)

```bash
pip install --user google-cloud-aiplatform
cloudshell edit agent.py     # paste kode dari dokumen program
python agent.py
```

Kode contohnya pakai `vertexai.generative_models` + `vertexai.init(location="global")` + model
`gemini-3.5-flash`. Kalau SDK atau nama modelnya sudah bergeser, abaikan — tidak ada hubungannya
dengan poin.

Dua jebakan saat menjalankannya (2026-09-18, semuanya teratasi):

- **"Vertex AI (Agent Platform) API" tidak ketemu di API Library.** Nama di Console sudah
  diganti jadi Gemini Enterprise Agent Platform pas rebranding. Aktifkan lewat CLI, API ID-nya
  tetap `aiplatform.googleapis.com`:
  `gcloud services enable aiplatform.googleapis.com`.
- **`vertexai.init(location="global")` tanpa project menyebabkan PERMISSION_DENIED.** SDK
  mencoba resolve project number lewat Cloud Resource Manager API, dan API itu belum enabled
  di project baru. Fix akarnya: pass project ID eksplisit,
  `vertexai.init(project="$PROJECT_ID", location="global")`, tidak perlu enable API tambahan.

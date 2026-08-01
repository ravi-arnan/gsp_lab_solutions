# GENAI129 - Deploy an Agent with Agent Development Kit (ADK): Challenge Lab

Runbook untuk [`genai129.sh`](../genai129.sh). Status: **terverifikasi 100/100** (2026-08-01), semua checkpoint hijau. Script sudah dikoreksi sesuai temuan run pertama; yang tersisa manual cuma percakapan Task 6.

## Kenapa lab ini cocok di-script

Lima dari enam task bisa dikerjakan dari Cloud Shell: data store dan search app lewat REST Discovery Engine, tiga perbaikan kode lewat patcher Python, deploy lewat `adk deploy agent_engine`. Yang tersisa manual cuma percakapan Task 6 di UI chainlit.

Bagian rawan: **isi file lab tidak bisa dilihat dari luar project**. Patcher menulis ulang berdasarkan pola (`sub_agents=[...]`, `tools=[...]`, `def set_session_value`, string instruksi di `coverage_calculator`). Kalau pola tidak ketemu, script berhenti dengan pesan `FATAL:` dan tidak menyentuh file — perbaiki manual di Cloud Shell Editor.

## Jalankan

Enam fase, sengaja dipisah karena indexing PDF butuh beberapa menit:

```bash
curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/genai129.sh
bash genai129.sh setup    # Task 1 + 2  (~6 menit, import PDF di-polling sampai done)
# tunggu dokumen Ready di Agent Platform > Search > Data Stores > Cymbal Paint (+ beberapa menit)
bash genai129.sh patch    # Task 3 + 4  (baca diff-nya)
bash genai129.sh chat     # Task 3      (smoke test harga EcoGreens & Forever Paint)
bash genai129.sh state    # Task 4      (percakapan penuh, cari "74 sq meters")
bash genai129.sh deploy   # Task 5      (5-10 menit)
bash genai129.sh ui       # Task 6      (chainlit, lalu chat manual)
```

Klik Check my progress setelah tiap fase; totalnya 15 + 25 + 25 + 25 + 10.

Semua fase idempoten: data store dan search app dilewati kalau sudah ada, patcher berhenti dengan pesan "tidak berubah" kalau file sudah dipatch.

Region default `us-central1` (lab memakainya di `.env`). Override lewat env var kalau instance-mu beda: `REGION=... bash genai129.sh setup`.

## Apa yang diotomasi

| Task | Status | Catatan |
|------|--------|---------|
| Task 1: data store `Cymbal Paint` | ✅ | Layout parser, `enableTableAnnotation`, `includeAncestorHeadings` |
| Task 1: import PDF datasheet | ✅ | `documents:import` + polling operation |
| Task 1: search app `Paint Search` | ✅ | Enterprise tier, fallback ke standard kalau ditolak |
| Task 2: copy source, pip install, `.env` | ✅ | `SEARCH_ENGINE_ID` diisi `paint-search` (ID kita sendiri, bukan yang di-generate Console) |
| Task 3: `AgentTool(agent=search_agent, skip_summarization=False)` | ✅ | Sekaligus mencabut `search_agent` dari `sub_agents` dan menambah import |
| Task 3: uji percakapan | ✅ | `adk run` disuapi stdin, bukan interaktif |
| Task 4: `set_session_value` | ✅ | `tool_context.state[key] = value` + status `stored '{value}' in '{key}'` |
| Task 4: instruksi `coverage_calculator` | ✅ | Token ALL_CAPS jadi `{TOKEN?}` |
| Task 5: IAM + deploy | ✅ | `roles/aiplatform.user` + `roles/discoveryengine.user` ke `service-<num>@gcp-sa-aiplatform-re` |
| Task 5: tulis resource name ke `chainlit_ui/app.py` | ✅ | Diambil dari log deploy, fallback ke list `reasoningEngines` |
| Task 6: percakapan di UI | ❌ | Harus diketik manual, sembilan giliran (dicetak script) |

## Kenapa error `Multiple tools are supported only when they are all search tools`

Root agent punya tool non-search (`set_session_value`) **dan** sub-agent, dan transfer ke sub-agent memunculkan tool implisit `transfer_to_agent`. Salah satu sub-agent (`search_agent`) memakai `VertexAiSearchTool`, jadi model menerima campuran search tool dan non-search tool. Solusinya bukan membuang tool-nya, tapi membungkus `search_agent` jadi `AgentTool` supaya search tool-nya terisolasi di agent terpisah.

## Yang harus manual (Task 6)

Buka Web Preview port 8000, lalu ketik sembilan giliran ini berurutan:

1. `hello`
2. `yes`
3. `I'd like to use Forever Paint`
4. `Two rooms. The living room and a baby's room.`
5. `"Sunlight through a canvas tent" for the baby's room and "Coffee Cream" for the living room.`
6. `The living room is 5m by 4m. 2.5m high. 1 door, 3 windows.`
7. `Two coats.`
8. `The baby's room is 3m by 3m. 2.5m high. 1 door, 1 window.`
9. `Always two coats.`

Hasil yang benar: 77 sq meters untuk living room, 53 sq meters untuk baby's room.

## Temuan run pertama (sudah dibetulkan di script)

Empat hal yang bikin run pertama tersendat, semuanya sudah masuk script:

1. **`adk deploy` harus menunjuk folder `paint_agent`, bukan `.`.** Instruksi lab ("e.g. `.` if you are currently in the directory") menyesatkan: kalau argumennya `adk_challenge_lab`, container-nya jalan tapi mati saat start dengan `ModuleNotFoundError: No module named '<tmpdir>.agent'`, karena `root_agent` ada di `paint_agent/agent.py`, bukan di root folder. Engine tetap terbuat lalu gagal serve, dan checkpoint merah.
2. **IAM baru bisa diberikan setelah deploy pertama.** Service account `service-<num>@gcp-sa-aiplatform-re.iam.gserviceaccount.com` belum ada sebelum reasoning engine pertama dibuat; `add-iam-policy-binding` menolak dengan `Service account ... does not exist`. Urutan di script: deploy dulu, baru grant (dengan retry 10x30s).
3. **`set_session_value` itu `async def`,** dan token ALL CAPS di `coverage_calculator` adalah `COVERAGE_RATE` dan `PRICE` — `PRICE` tanpa underscore. Patcher awal melewatkan keduanya.
4. **Checkpoint Task 3 dan 4 lulus dari percakapan, bukan dari isi file.** Root agent memasang `log_query_to_model` / `log_model_response` yang mengirim tiap prompt dan response ke Cloud Logging, dan itu yang diperiksa grader. `adk run` yang disuapi stdin sudah cukup, tidak perlu `adk web`.

Catatan kecil: `gcloud beta ai reasoning-engines` tidak ada di gcloud versi Cloud Shell sekarang, jadi engine gagal tidak bisa dihapus lewat CLI itu. Dibiarkan saja tidak masalah — checkpoint hanya mencari engine yang sehat dengan display name `Paint Agent`.

## Troubleshooting

- **Agent menjawab tapi tidak tahu produk cat.** Dokumen belum selesai di-index. Cek tab Documents di data store `Cymbal Paint`, tunggu Ready plus beberapa menit, ulangi `bash genai129.sh chat`.
- **Patcher bilang `FATAL: tidak menemukan tools=[...]`.** Struktur `agent.py` beda dari dugaan. Edit manual: tambah `from google.adk.tools.agent_tool import AgentTool`, keluarkan `search_agent` dari `sub_agents`, masukkan `AgentTool(agent=search_agent, skip_summarization=False)` ke `tools`.
- **Token ALL CAPS yang bukan state key ikut jadi `{TOKEN?}`.** Patcher menyentuh semua ALL CAPS minimal tiga huruf di dalam string instruksi, jadi baca diff-nya; kembalikan manual kalau ada yang salah kena.
- **`ValueError: Tool 'print_image' not found`.** Halusinasi model, bukan bug: instruksi `room_planner_agent` menyuruh menampilkan gambar produk dalam tag `img`, dan lewat CLI model kadang mengarang tool untuk itu. Fase `state` sudah menambahkan "Respond with plain text only" di giliran keempat; kalau masih kambuh, ulangi atau pakai `adk web --allow_origins "regex:https://.*\.cloudshell\.dev"`.
- **`chainlit: command not found`.** `~/.local/bin` belum ada di PATH shell-mu: `export PATH="$PATH:$HOME/.local/bin"`.
- **Konflik pip opentelemetry.** chainlit menarik opentelemetry 1.44 sementara google-adk 1.37 minta ≤1.41.1. Warning ini muncul di run yang lolos 100/100 dan tidak mengganggu; kalau `adk run` sampai error karenanya, turunkan: `pip install "opentelemetry-api<=1.41.1" "opentelemetry-sdk<=1.41.1"`.
- **Deploy gagal minta staging bucket.** Fase `deploy` otomatis mengulang dengan `--staging_bucket gs://<project>-bucket`.
- **Resource name tidak ketemu setelah deploy.** Ada di `~/adk_challenge_lab/deploy.log` dan `agent_resource_name.txt`; isi manual ke `chainlit_ui/app.py`.

## API yang dipakai

| Endpoint | Method | Untuk |
|----------|--------|-------|
| `discoveryengine/v1/.../collections/default_collection/dataStores` | POST | Buat data store + document processing config |
| `.../dataStores/{id}/branches/0/documents:import` | POST | Import PDF dari Cloud Storage |
| `.../collections/default_collection/engines` | POST | Buat search app |
| `{region}-aiplatform/v1/.../reasoningEngines` | GET | Cari resource name agent yang sudah dideploy |

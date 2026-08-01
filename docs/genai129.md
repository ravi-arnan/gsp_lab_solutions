# GENAI129 - Deploy an Agent with Agent Development Kit (ADK): Challenge Lab

Runbook untuk [`genai129.sh`](../genai129.sh). Status: belum diuji di lab instance sungguhan (script lolos `bash -n`, patcher Python diuji terhadap replika sintetis dari file lab).

## Kenapa lab ini cocok di-script

Lima dari enam task bisa dikerjakan dari Cloud Shell: data store dan search app lewat REST Discovery Engine, tiga perbaikan kode lewat patcher Python, deploy lewat `adk deploy agent_engine`. Yang tersisa manual cuma percakapan Task 6 di UI chainlit.

Bagian rawan: **isi file lab tidak bisa dilihat dari luar project**. Patcher menulis ulang berdasarkan pola (`sub_agents=[...]`, `tools=[...]`, `def set_session_value`, string instruksi di `coverage_calculator`). Kalau pola tidak ketemu, script berhenti dengan pesan `FATAL:` dan tidak menyentuh file — perbaiki manual di Cloud Shell Editor.

## Jalankan

Lima fase, sengaja dipisah karena indexing PDF butuh beberapa menit:

```bash
curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/genai129.sh
bash genai129.sh setup    # Task 1 + 2
# tunggu dokumen Ready di Agent Platform > Search > Data Stores > Cymbal Paint (+ beberapa menit)
bash genai129.sh patch    # Task 3 + 4 (baca diff-nya)
bash genai129.sh chat     # Task 3, smoke test adk run
bash genai129.sh deploy   # Task 5, 5-10 menit
bash genai129.sh ui       # Task 6, lalu chat manual
```

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

## Troubleshooting

- **Agent menjawab tapi tidak tahu produk cat.** Dokumen belum selesai di-index. Cek tab Documents di data store `Cymbal Paint`, tunggu Ready plus beberapa menit, ulangi `bash genai129.sh chat`.
- **Patcher bilang `FATAL: tidak menemukan tools=[...]`.** Struktur `agent.py` beda dari dugaan. Edit manual: tambah `from google.adk.tools.agent_tool import AgentTool`, keluarkan `search_agent` dari `sub_agents`, masukkan `AgentTool(agent=search_agent, skip_summarization=False)` ke `tools`.
- **Token ALL CAPS yang bukan state key ikut jadi `{TOKEN?}`.** Patcher hanya menyentuh token yang mengandung underscore, tapi tetap baca diff-nya; kembalikan manual kalau ada yang salah kena.
- **Deploy gagal minta staging bucket.** Fase `deploy` otomatis mengulang dengan `--staging_bucket gs://<project>-bucket`.
- **Resource name tidak ketemu setelah deploy.** Ada di `~/adk_challenge_lab/deploy.log` dan `agent_resource_name.txt`; isi manual ke `chainlit_ui/app.py`.

## API yang dipakai

| Endpoint | Method | Untuk |
|----------|--------|-------|
| `discoveryengine/v1/.../collections/default_collection/dataStores` | POST | Buat data store + document processing config |
| `.../dataStores/{id}/branches/0/documents:import` | POST | Import PDF dari Cloud Storage |
| `.../collections/default_collection/engines` | POST | Buat search app |
| `{region}-aiplatform/v1/.../reasoningEngines` | GET | Cari resource name agent yang sudah dideploy |

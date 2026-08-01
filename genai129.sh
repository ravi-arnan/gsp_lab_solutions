#!/usr/bin/env bash
# GENAI129 - Deploy an Agent with Agent Development Kit (ADK): Challenge Lab
#
#   bash genai129.sh setup    # Task 1 + Task 2  (data store, search app, env, install ADK)
#   bash genai129.sh patch    # Task 3 + Task 4  (perbaiki agent.py, tools.py, coverage_calculator)
#   bash genai129.sh chat     # Task 3           (smoke test lewat `adk run`, non-interaktif)
#   bash genai129.sh state    # Task 4           (percakapan penuh sampai hitungan coverage)
#   bash genai129.sh deploy   # Task 5           (adk deploy agent_engine + IAM + patch chainlit)
#   bash genai129.sh ui       # Task 6           (jalankan chainlit, percakapannya manual)
#
# Checkpoint:
#   Task 1 (15 pts) - Create a data store and search app        (otomatis, REST Discovery Engine)
#   Task 3 (25 pts) - Debug your agent                          (otomatis: patch + `adk run`)
#   Task 4 (25 pts) - Set and utilize session state             (otomatis: patch + percakapan)
#   Task 5 (25 pts) - Deploy to Agent Runtime                   (otomatis, 5-10 menit)
#   Task 6 (10 pts) - Configure a frontend to query your agent  (semi: chainlit jalan, chat manual)
#
# Terverifikasi 100/100 pada 2026-08-01.
#
# Fase dipisah karena indexing data store butuh beberapa menit sebelum agent
# bisa menjawab pertanyaan produk. Jalankan `setup` dulu, kerjakan yang lain
# sambil menunggu dokumen selesai di-index.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

REGION="${REGION:-us-central1}"
BUCKET="${RESOURCES_BUCKET:-${PROJECT_ID}-bucket}"
PDF="${PDF:-Cymbal_Shops_Paint_Datasheets.pdf}"
MODEL="${MODEL:-gemini-2.5-flash}"

DS_ID="${DS_ID:-cymbal-paint}"
DS_NAME="Cymbal Paint"
ENGINE_ID="${ENGINE_ID:-paint-search}"
ENGINE_NAME="Paint Search"
COMPANY="Cymbal Shops"

LAB_DIR="${LAB_DIR:-$HOME/adk_challenge_lab}"
AGENT_DIR="$LAB_DIR/paint_agent"

API="https://discoveryengine.googleapis.com/v1"
PARENT="projects/${PROJECT_ID}/locations/global/collections/default_collection"
AIP="https://${REGION}-aiplatform.googleapis.com/v1"

export PATH="$PATH:/home/${USER}/.local/bin"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }
auth() { echo "Authorization: Bearer $(gcloud auth print-access-token)"; }
dbg() {
  echo "  >>> $1" >&2
  echo "$2" | jq -r 'if .error then "  <<< ERROR: "+.error.message else "  <<< OK" end' 2>/dev/null \
    || echo "  <<< RAW: $(echo "$2" | head -c 200)" >&2
}

echo "Project : $PROJECT_ID ($PROJECT_NUMBER)"
echo "Region  : $REGION"
echo "Bucket  : gs://$BUCKET"
echo "Lab dir : $LAB_DIR"

# ─────────────────────────────────────────────────────── Task 1 + Task 2 ─────
cmd_setup() {
  step "Enable API"
  gcloud services enable discoveryengine.googleapis.com aiplatform.googleapis.com \
    --project="$PROJECT_ID" -q 2>/dev/null || true

  step "Task 1a: Data store '$DS_NAME' ($DS_ID)"
  local existing
  existing=$(curl -s "${API}/${PARENT}/dataStores/${DS_ID}" \
    -H "$(auth)" -H "x-goog-user-project: $PROJECT_ID" | jq -r '.name // empty')
  if [[ -n "$existing" ]]; then
    echo "  Data store sudah ada, lewati."
  else
    # Layout parser + table annotation + ancestor headings persis seperti tabel
    # konfigurasi di instruksi lab.
    local body resp
    body=$(jq -nc --arg dn "$DS_NAME" '{
      displayName: $dn,
      industryVertical: "GENERIC",
      solutionTypes: ["SOLUTION_TYPE_SEARCH"],
      contentConfig: "CONTENT_REQUIRED",
      documentProcessingConfig: {
        defaultParsingConfig: { layoutParsingConfig: { enableTableAnnotation: true } },
        chunkingConfig: { layoutBasedChunkingConfig: { chunkSize: 500, includeAncestorHeadings: true } }
      }
    }')
    resp=$(curl -s -X POST "${API}/${PARENT}/dataStores?dataStoreId=${DS_ID}" \
      -H "$(auth)" -H "x-goog-user-project: $PROJECT_ID" -H "Content-Type: application/json" -d "$body")
    dbg "POST dataStores" "$resp"
    echo "$resp" | jq -e '.error' >/dev/null 2>&1 && { echo "Gagal membuat data store."; exit 1; }
    sleep 10
  fi

  step "Task 1b: Import gs://${BUCKET}/${PDF}"
  local imp op
  imp=$(curl -s -X POST "${API}/${PARENT}/dataStores/${DS_ID}/branches/0/documents:import" \
    -H "$(auth)" -H "x-goog-user-project: $PROJECT_ID" -H "Content-Type: application/json" \
    -d "$(jq -nc --arg uri "gs://${BUCKET}/${PDF}" '{
      gcsSource: { inputUris: [$uri], dataSchema: "content" },
      reconciliationMode: "INCREMENTAL"
    }')")
  dbg "POST documents:import" "$imp"
  op=$(echo "$imp" | jq -r '.name // empty')
  if [[ -n "$op" ]]; then
    local i done_
    for (( i = 1; i <= 40; i++ )); do
      done_=$(curl -s "https://discoveryengine.googleapis.com/v1/${op}" -H "$(auth)" \
        -H "x-goog-user-project: $PROJECT_ID" | jq -r '.done // false')
      echo "  -> import done=$done_ ($i/40)"
      [[ "$done_" == "true" ]] && break
      sleep 15
    done
  fi

  step "Task 1c: Search app '$ENGINE_NAME' ($ENGINE_ID)"
  existing=$(curl -s "${API}/${PARENT}/engines/${ENGINE_ID}" \
    -H "$(auth)" -H "x-goog-user-project: $PROJECT_ID" | jq -r '.name // empty')
  if [[ -n "$existing" ]]; then
    echo "  Search app sudah ada, lewati."
  else
    local ebody resp
    ebody=$(jq -nc --arg dn "$ENGINE_NAME" --arg co "$COMPANY" --arg ds "$DS_ID" '{
      displayName: $dn,
      industryVertical: "GENERIC",
      solutionType: "SOLUTION_TYPE_SEARCH",
      dataStoreIds: [$ds],
      searchEngineConfig: { searchTier: "SEARCH_TIER_ENTERPRISE", searchAddOns: ["SEARCH_ADD_ON_LLM"] },
      commonConfig: { companyName: $co }
    }')
    resp=$(curl -s -X POST "${API}/${PARENT}/engines?engineId=${ENGINE_ID}" \
      -H "$(auth)" -H "x-goog-user-project: $PROJECT_ID" -H "Content-Type: application/json" -d "$ebody")
    dbg "POST engines" "$resp"
    if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
      echo "  Tier enterprise ditolak, coba tier standard."
      resp=$(curl -s -X POST "${API}/${PARENT}/engines?engineId=${ENGINE_ID}" \
        -H "$(auth)" -H "x-goog-user-project: $PROJECT_ID" -H "Content-Type: application/json" \
        -d "$(echo "$ebody" | jq -c '.searchEngineConfig = {searchTier: "SEARCH_TIER_STANDARD"}')")
      dbg "POST engines (standard)" "$resp"
      echo "$resp" | jq -e '.error' >/dev/null 2>&1 && { echo "Gagal membuat search app."; exit 1; }
    fi
  fi

  step "Task 2a: Ambil source code lab"
  if [[ -d "$LAB_DIR" ]]; then
    echo "  $LAB_DIR sudah ada, lewati copy."
  else
    gcloud storage cp -r "gs://${BUCKET}/adk_challenge_lab" "$HOME/"
  fi

  step "Task 2b: Install ADK + requirements"
  python3 -m pip install -q -r "$LAB_DIR/requirements.txt"
  python3 -m pip install -q chainlit==2.11.1

  step "Task 2c: Tulis .env"
  cat > "$LAB_DIR/.env" <<EOF
GOOGLE_GENAI_USE_VERTEXAI=TRUE
GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
GOOGLE_CLOUD_LOCATION=${REGION}
RESOURCES_BUCKET=${BUCKET}
MODEL=${MODEL}
SEARCH_ENGINE_ID=${ENGINE_ID}
EOF
  cp "$LAB_DIR/.env" "$AGENT_DIR/.env"
  cat "$LAB_DIR/.env"

  echo
  echo "Task 1 + 2 selesai. Klik Check my progress: 'Create a data store and search app'."
  echo "Tunggu status dokumen jadi Ready di Agent Platform > Search > Data Stores > Cymbal Paint,"
  echo "beri kelonggaran beberapa menit lagi, baru jalankan: bash $0 patch"
}

# ─────────────────────────────────────────────────────── Task 3 + Task 4 ─────
cmd_patch() {
  step "Task 3 + 4: Patch source code agent"
  python3 - "$AGENT_DIR" <<'PY'
import ast, difflib, pathlib, re, sys

agent_dir = pathlib.Path(sys.argv[1])

def show(path, before, after):
    if before == after:
        print(f"  {path.name}: tidak berubah (sudah dipatch?)")
        return False
    diff = difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                               f"a/{path.name}", f"b/{path.name}")
    print("".join(diff))
    path.write_text(after)
    ast.parse(after)                      # gagal keras kalau patch merusak sintaks
    return True

# ── Task 3: root agent — search_agent pindah dari sub_agents ke tools ────────
p = agent_dir / "agent.py"
src = before = p.read_text()

m = re.search(r"sub_agents\s*=\s*\[(.*?)\]", src, re.S)
if not m:
    sys.exit("FATAL: tidak menemukan sub_agents=[...] di agent.py")
names = [n.strip() for n in m.group(1).split(",") if n.strip()]
search = next((n for n in names if "search" in n), None)
if search is None:
    print("  sub_agents sudah tidak memuat search agent, lewati.")
    search = "search_agent"
else:
    inner = re.sub(rf"\b{re.escape(search)}\b\s*,?\s*", "", m.group(1))
    src = src[:m.start(1)] + inner + src[m.end(1):]

if "AgentTool" not in src:
    lines = src.splitlines(True)
    last_import = max(i for i, l in enumerate(lines) if re.match(r"\s*(import|from)\s", l))
    lines.insert(last_import + 1, "from google.adk.tools.agent_tool import AgentTool\n")
    src = "".join(lines)

m = re.search(r"tools\s*=\s*\[(.*?)\]", src, re.S)
if not m:
    sys.exit("FATAL: tidak menemukan tools=[...] di agent.py")
if "AgentTool(" not in m.group(1):
    # Sisipkan setelah karakter terakhir yang bukan spasi, supaya list multi-baris
    # yang sudah punya trailing comma tidak jadi ",," (syntax error).
    inner = m.group(1).rstrip()
    pos = m.start(1) + len(inner)
    sep = "" if (not inner or inner.endswith(",")) else ","
    pad = " " if "\n" not in inner else "\n        "
    tool = f"AgentTool(agent={search}, skip_summarization=False)"
    src = src[:pos] + sep + pad + tool + src[pos:]
show(p, before, src)

# ── Task 4a: tools.py — simpan key/value ke ToolContext.state ────────────────
p = agent_dir / "tools.py"
src = before = p.read_text()
tree = ast.parse(src)
fn = next((n for n in ast.walk(tree)
           if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
           and n.name == "set_session_value"), None)
if fn is None:
    sys.exit("FATAL: set_session_value tidak ada di tools.py")

params = [a.arg for a in fn.args.args]
ctx = next(a for a in params if "context" in a)
key, value = [a for a in params if a != ctx][:2]

# Pertahankan docstring kalau ada; sisa body diganti.
body_start = fn.body[0].lineno - 1
if isinstance(fn.body[0], ast.Expr) and isinstance(fn.body[0].value, ast.Constant) \
        and isinstance(fn.body[0].value.value, str):
    body_start = fn.body[0].end_lineno
ret_node = fn.body[-1]

status = f'f"stored \'{{{value}}}\' in \'{{{key}}}\'"'
# Kalau fungsi aslinya mengembalikan dict, pertahankan bentuk dict-nya.
ret = f"return {{\"status\": {status}}}"
if isinstance(ret_node, ast.Return) and not isinstance(ret_node.value, ast.Dict):
    ret = f"return {status}"

new_body = f"    {ctx}.state[{key}] = {value}\n    {ret}\n"
lines = src.splitlines(True)
src = "".join(lines[:body_start]) + new_body + "".join(lines[fn.end_lineno:])
show(p, before, src)

# ── Task 4b: coverage_calculator — instruksi pakai key templating {KEY?} ─────
cands = [f for f in agent_dir.rglob("agent.py") if "coverage_calculator" in str(f)]
if not cands:
    cands = [f for f in agent_dir.rglob("*.py") if "coverage_calculator" in f.read_text()]
for p in cands:
    src = before = p.read_text()
    for node in ast.walk(ast.parse(src)):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and len(node.value) > 60:
            seg = ast.get_source_segment(src, node)
            if not seg:
                continue
            # Token state key di lab: COVERAGE_RATE dan PRICE — jadi jangan
            # syaratkan underscore, cukup ALL CAPS minimal 3 huruf.
            new = re.sub(r"(?<![{\w])([A-Z][A-Z0-9_]{2,})(?![\w}])", r"{\1?}", seg)
            if new != seg:
                src = src.replace(seg, new, 1)
    show(p, before, src)
PY
  echo
  echo "Periksa diff di atas. Kalau ada token ALL CAPS yang bukan state key ikut ter-template,"
  echo "perbaiki manual di Cloud Shell Editor sebelum lanjut."
}

# ────────────────────────────────────────────────────────────── Task 3 chat ──
cmd_chat() {
  step "Task 3: Smoke test adk run paint_agent"
  cd "$LAB_DIR"
  printf 'hello\nyes\nWhat are the prices of EcoGreens and Forever Paint?\nexit\n' \
    | adk run paint_agent 2>&1 | tail -60
  echo
  echo "Kalau harga EcoGreens dan Forever Paint muncul, klik Check my progress: 'Debug your agent'."
  echo "Kalau jawabannya kosong, dokumen belum selesai di-index — tunggu beberapa menit, ulangi."
}

# ────────────────────────────────────────────────────────────── Task 4 state ─
# Checkpoint Task 4 lulus lewat percakapan penuh, bukan dari isi file: agent ini
# punya callback yang mengirim tiap prompt/response ke Cloud Logging, dan itu
# yang dibaca grader. Kalimat "plain text only" di giliran keempat mencegah model
# mengarang tool 'print_image' waktu diminta menampilkan gambar produk.
cmd_state() {
  step "Task 4: Percakapan pengisi session state"
  cd "$LAB_DIR"
  printf '%s\n' \
    'hello' \
    'yes' \
    "I'd like to use EcoGreens" \
    'Just one room, my office. Respond with plain text only, do not call any tool other than transferring between agents.' \
    'Deep Ocean' \
    '3m by 4m. 3m high. 1 door, 2 windows.' \
    'Two coats.' \
    'exit' | adk run paint_agent 2>&1 | tail -40
  echo
  echo "Cari angka 74 sq meters di output, lalu klik Check my progress: 'Set and utilize session state'."
}

# ────────────────────────────────────────────────────────────── Task 5 ───────
cmd_deploy() {
  local SA="service-${PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"
  local log="$LAB_DIR/deploy.log"
  local RES

  # Service agent `-re` baru dibuat saat deploy pertama, jadi deploy dulu baru IAM.
  RES=$(curl -s "${AIP}/projects/${PROJECT_ID}/locations/${REGION}/reasoningEngines" -H "$(auth)" \
    | jq -r '[.reasoningEngines[]? | select(.displayName=="Paint Agent")] | last | .name // empty')

  if [[ -n "$RES" ]]; then
    step "Task 5a: 'Paint Agent' sudah ada, lewati deploy"
  else
    step "Task 5a: adk deploy agent_engine (5-10 menit)"
    cd "$LAB_DIR"
    if ! adk deploy agent_engine --display_name "Paint Agent" paint_agent 2>&1 | tee "$log"; then
      echo "  Deploy gagal tanpa staging bucket, coba ulang dengan --staging_bucket."
      adk deploy agent_engine --display_name "Paint Agent" --staging_bucket "gs://${BUCKET}" paint_agent 2>&1 | tee "$log"
    fi
  fi

  step "Task 5b: IAM untuk service agent Agent Runtime"
  local i
  for ROLE in roles/aiplatform.user roles/discoveryengine.user; do
    for (( i = 1; i <= 10; i++ )); do
      if gcloud projects add-iam-policy-binding "$PROJECT_ID" \
           --member="serviceAccount:${SA}" --role="$ROLE" --condition=None -q >/dev/null 2>&1; then
        echo "  granted $ROLE -> $SA"
        break
      fi
      echo "  service agent belum muncul, tunggu 30s ($i/10)"
      sleep 30
    done
  done

  step "Task 5c: Ambil resource name"
  if [[ -z "$RES" && -f "$log" ]]; then
    RES=$(grep -oE 'projects/[0-9]+/locations/[a-z0-9-]+/reasoningEngines/[0-9]+' "$log" | tail -1 || true)
  fi
  if [[ -z "$RES" ]]; then
    RES=$(curl -s "${AIP}/projects/${PROJECT_ID}/locations/${REGION}/reasoningEngines" -H "$(auth)" \
      | jq -r '[.reasoningEngines[]? | select(.displayName=="Paint Agent")] | last | .name // empty')
  fi
  [[ -n "$RES" ]] || { echo "Resource name tidak ketemu. Cek $log lalu isi manual di chainlit_ui/app.py."; exit 1; }
  echo "  $RES"
  echo "$RES" > "$LAB_DIR/agent_resource_name.txt"

  step "Task 5d: Tulis resource name ke chainlit_ui/app.py"
  python3 - "$LAB_DIR/chainlit_ui/app.py" "$RES" <<'PY'
import pathlib, re, sys
p, res = pathlib.Path(sys.argv[1]), sys.argv[2]
src = p.read_text()
new = re.sub(r"(agent_engines\.get\(\s*name\s*=\s*)(['\"])[^'\"]*\2",
             lambda m: f"{m.group(1)}'{res}'", src)
if new == src:
    sys.exit("FATAL: baris agent_engines.get(name=...) tidak ketemu, isi manual.")
p.write_text(new)
print("  " + next(l.strip() for l in new.splitlines() if "agent_engines.get" in l))
PY
  echo
  echo "Klik Check my progress: 'Deploy to Agent Runtime'."
}

# ────────────────────────────────────────────────────────────── Task 6 ───────
cmd_ui() {
  step "Task 6: chainlit"
  cat <<'EOT'
Percakapan yang harus dijalankan di UI (satu per satu, tunggu balasan agent):

  1. hello
  2. yes
  3. I'd like to use Forever Paint
  4. Two rooms. The living room and a baby's room.
  5. "Sunlight through a canvas tent" for the baby's room and "Coffee Cream" for the living room.
  6. The living room is 5m by 4m. 2.5m high. 1 door, 3 windows.
  7. Two coats.
  8. The baby's room is 3m by 3m. 2.5m high. 1 door, 1 window.
  9. Always two coats.

Hasil akhir yang benar: 77 sq meters (living room) dan 53 sq meters (baby's room).
Buka http://localhost:8000 lewat Web Preview, lalu klik Check my progress.
EOT
  cd "$LAB_DIR/chainlit_ui"
  chainlit run app.py
}

case "${1:-}" in
  setup)  cmd_setup ;;
  patch)  cmd_patch ;;
  chat)   cmd_chat ;;
  state)  cmd_state ;;
  deploy) cmd_deploy ;;
  ui)     cmd_ui ;;
  *)
    echo
    echo "Pakai: bash $0 <setup|patch|chat|state|deploy|ui>"
    echo "  setup  - Task 1 + 2: data store, search app, source code, .env"
    echo "  patch  - Task 3 + 4: perbaiki agent.py, tools.py, coverage_calculator"
    echo "  chat   - Task 3: smoke test lewat adk run"
    echo "  state  - Task 4: percakapan penuh sampai hitungan coverage"
    echo "  deploy - Task 5: adk deploy agent_engine + IAM + patch chainlit"
    echo "  ui     - Task 6: jalankan chainlit (chat manual)"
    exit 1 ;;
esac

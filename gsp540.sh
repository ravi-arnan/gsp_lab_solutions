#!/usr/bin/env bash
# GSP540 - Engineer AI Agents with Agent Development Kit (ADK): Challenge Lab
#
#   bash gsp540.sh setup   # Task 1, 2, 4, 5: download source, .env, patch ketiga agent
#   bash gsp540.sh geo     # Task 4: python3 geo_validator/agent.py  -> {"capital": "Paris"}
#   bash gsp540.sh cli     # Task 3: adk run my_google_search_agent (kurs mata uang Jepang)
#   bash gsp540.sh web     # Task 2 + 5: adk web, dua percakapan manual di UI
#
# Checkpoint:
#   Task 2 (25 pts) - Run the agent using the ADK's Web UI    (patch otomatis, chat manual)
#   Task 3 (25 pts) - Chat with an agent via the CLI          (otomatis)
#   Task 4 (25 pts) - Run an agent programmatically           (otomatis)
#   Task 5 (25 pts) - Preview a multi-agent example           (patch otomatis, chat manual)
#
# `gcloud auth application-default login` interaktif, jalankan sendiri sebelum setup.

set -euo pipefail

PROJECT_ID="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set."; exit 1; }
BUCKET="${BUCKET:-${PROJECT_ID}-bucket}"
MODEL="${MODEL:-gemini-3.5-flash}"
LOCATION="${LOCATION:-global}"
PROJ_DIR="${PROJ_DIR:-$HOME/adk_project}"

export PATH="$PATH:/home/${USER}/.local/bin"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

echo "Project : $PROJECT_ID"
echo "Bucket  : gs://$BUCKET"
echo "Dir     : $PROJ_DIR"

cmd_setup() {
  step "Task 1: Install ADK + source code"
  python3 -m pip install -q google-adk
  if [[ ! -d "$PROJ_DIR" ]]; then
    cd "$HOME"
    gcloud storage cp "gs://${BUCKET}/adk_project.zip" .
    unzip -oq adk_project.zip
  else
    echo "  $PROJ_DIR sudah ada, lewati download."
  fi
  cd "$PROJ_DIR"
  pip install -q -r requirements.txt

  step "Task 1: .env (Agent Platform, location global)"
  # geo_validator dijalankan lewat `python3 geo_validator/agent.py` dari root,
  # dan load_dotenv() mencari dari cwd — jadi root project ikut ditulis.
  python3 - "$PROJ_DIR" "$PROJECT_ID" "$LOCATION" "$MODEL" <<'PY'
import pathlib, sys
root, project, location, model = pathlib.Path(sys.argv[1]), *sys.argv[2:]
env = (f"GOOGLE_GENAI_USE_ENTERPRISE=true\n"
       f"GOOGLE_CLOUD_PROJECT={project}\n"
       f"GOOGLE_CLOUD_LOCATION={location}\n"
       f"MODEL={model}\n")
for d in [root, root/"my_google_search_agent", root/"geo_validator", root/"llm_auditor"]:
    (d/".env").write_text(env)
    print(f"  {d/'.env'}")
PY

  step "Task 2 + 4 + 5: Patch agent"
  python3 - "$PROJ_DIR" <<'PY'
import ast, difflib, pathlib, sys

root = pathlib.Path(sys.argv[1])

# Tiap patch: (pola lama, pengganti, penanda "sudah dipatch"). Penandanya
# terpisah karena pola lama kadang jadi bagian dari hasil patch (dan sebaliknya:
# baris import reviser yang dikomentari memuat teks hasil patch-nya).
def edit(rel, patches):
    p = root / rel
    before = src = p.read_text()
    for old, new, marker in patches:
        if marker in src:
            continue
        if old not in src:
            sys.exit(f"FATAL: pola tidak ketemu di {rel}:\n{old}")
        src = src.replace(old, new, 1)
    if src == before:
        print(f"  {rel}: tidak berubah (sudah dipatch)")
        return
    ast.parse(src)
    p.write_text(src)
    print("".join(difflib.unified_diff(before.splitlines(True), src.splitlines(True),
                                       f"a/{rel}", f"b/{rel}")))

# ── Task 2: aktifkan google_search ──────────────────────────────────────────
edit("my_google_search_agent/agent.py", [
    ("    # Add the google_search tool below.\n\n)",
     "    # Add the google_search tool below.\n    tools=[google_search],\n)",
     "tools=[google_search]"),
])

# ── Task 4: output_schema Pydantic + matikan transfer ───────────────────────
edit("geo_validator/agent.py", [
    ("from google.genai import types\n",
     "from google.genai import types\nfrom pydantic import BaseModel\n",
     "from pydantic import BaseModel"),
    ("# Create an async main function",
     "class CountryCapital(BaseModel):\n    capital: str\n\n\n# Create an async main function",
     "class CountryCapital"),
    ("        after_model_callback=log_model_response,\n\n    )",
     "        after_model_callback=log_model_response,\n"
     "        output_schema=CountryCapital,\n"
     "        disallow_transfer_to_parent=True,\n"
     "        disallow_transfer_to_peers=True,\n    )",
     "output_schema=CountryCapital"),
])

# ── Task 5: hidupkan reviser_agent di pipeline sequential ───────────────────
edit("llm_auditor/agent.py", [
    ("# from .sub_agents.reviser import reviser_agent  # <--- TODO: ENABLE THIS",
     "from .sub_agents.reviser import reviser_agent",
     "\nfrom .sub_agents.reviser import reviser_agent"),
    ("sub_agents=[critic_agent], # <--- TODO: ADD reviser_agent CHECK HERE",
     "sub_agents=[critic_agent, reviser_agent],",
     "critic_agent, reviser_agent"),
])
PY
  echo
  echo "Lanjut: bash $0 geo   (Task 4, paling cepat)"
}

cmd_geo() {
  step "Task 4: python3 geo_validator/agent.py"
  cd "$PROJ_DIR"
  python3 geo_validator/agent.py
  echo
  echo 'Output harus berupa JSON {"capital": "Paris"}, lalu klik Check my progress: Run an agent programmatically.'
}

cmd_cli() {
  step "Task 3: adk run my_google_search_agent"
  cd "$PROJ_DIR"
  printf '%s\n' \
    'What is the currency exchange rate for Japan?' \
    'exit' | adk run my_google_search_agent 2>&1 | tail -30
  echo
  echo "Klik Check my progress: Chat with an agent via the command-line interface."
}

cmd_web() {
  step "Task 2 + 5: adk web"
  cat <<'EOT'
Buka lewat link http://127.0.0.1:8000 (Web Preview port 8000), lalu:

  Task 2 — pilih agent 'my_google_search_agent', kirim:
      What are some major events in Tokyo in 2025?
    Jawaban harus grounded (ada hasil pencarian), baru klik Check my progress.

  Task 5 — pilih agent 'llm_auditor', + New Session, kirim:
      Double check this: You can take a direct train from Hawaii to Japan.
    Critic membantah klaimnya, lalu reviser memperbaiki kalimatnya.

CTRL+C untuk mematikan server kalau sudah selesai.
EOT
  cd "$PROJ_DIR"
  adk web --allow_origins "regex:https://.*\.cloudshell\.dev"
}

case "${1:-}" in
  setup) cmd_setup ;;
  geo)   cmd_geo ;;
  cli)   cmd_cli ;;
  web)   cmd_web ;;
  *)
    echo
    echo "Pakai: bash $0 <setup|geo|cli|web>"
    echo "  setup - Task 1, 2, 4, 5: source code, .env, patch ketiga agent"
    echo "  geo   - Task 4: jalankan geo_validator secara programatik"
    echo "  cli   - Task 3: adk run my_google_search_agent"
    echo "  web   - Task 2 + 5: adk web, dua percakapan manual"
    exit 1 ;;
esac

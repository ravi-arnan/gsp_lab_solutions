#!/usr/bin/env bash
# Arcade Buildathon (course_templates/1968) - Evaluator Path (Steps 1-5 & Step 7 check)
#
#   curl -sLO https://raw.githubusercontent.com/ravi-arnan/gsp_lab_solutions/main/arcade-buildathon-7b4m.sh
#   bash arcade-buildathon-7b4m.sh
#
# Langkah yang dijalankan:
#   Step 1 - Buat ~/arcade-buildathon-7b4m/requirements.txt
#   Step 2 - Buat ~/arcade-buildathon-7b4m/Dockerfile
#   Step 3 - Enable APIs, tunggu service account, grant IAM & verifikasi billing
#   Step 4 - Buat ~/arcade-buildathon-7b4m/main.py (Evaluator Path - Portfolio Builder)
#   Step 5 - Deploy Cloud Run service arcade-agent di us-central1
#   Step 7 - Jalankan pengecekan submission form (Project ID, Path, Service URL)

set -euo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1

PROJECT_ID="${PROJECT_ID:-${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}}"

ask() {
  local _cur="${!1:-}"
  if [[ -n "$_cur" ]]; then echo "$1 = $_cur (dari env)"; return; fi
  if [[ -t 0 ]]; then
    local _v
    read -rp "$3 [$2]: " _v
    printf -v "$1" '%s' "${_v:-$2}"
  else
    printf -v "$1" '%s' "$2"
  fi
  echo "$1 = ${!1}"
}

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

if [[ -z "$PROJECT_ID" ]]; then
  ask PROJECT_ID "" "Masukkan Project ID (yang terhubung ke GDP Event Credit)"
fi
[[ -n "$PROJECT_ID" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <PROJECT_ID>"; exit 1; }

gcloud config set project "$PROJECT_ID" >/dev/null 2>&1
echo "Project ID : $PROJECT_ID"

WORKDIR="$HOME/arcade-buildathon-7b4m"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# ----------------------------------------------------------------- Step 1
step "Step 1: Membuat requirements.txt di $WORKDIR"
cat <<'EOF' > "$WORKDIR/requirements.txt"
Flask==3.0.3
gunicorn==22.0.0
google-genai==2.28.0
requests==2.34.2
google-cloud-bigquery==3.46.1
pydantic==2.13.5
EOF
echo "requirements.txt selesai ditulis."

# ----------------------------------------------------------------- Step 2
step "Step 2: Membuat Dockerfile di $WORKDIR"
cat <<'EOF' > "$WORKDIR/Dockerfile"
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD exec gunicorn --bind 0.0.0.0:8080 --workers 1 --threads 8 --timeout 0 main:app
EOF
echo "Dockerfile selesai ditulis."

# ----------------------------------------------------------------- Step 3
step "Step 3: Enable APIs, IAM permissions, dan cek billing"
# Fungsi bawaan lab memakai unset vars dan arithmetic ((n++)) saat 0,
# sehingga harus berjalan dengan set +euo pipefail.
set +euo pipefail

sp() {
  m=$1; shift; touch /tmp/sp.on
  ( f=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); i=0 b=$SECONDS; while [ -f /tmp/sp.on ]; do e=$((SECONDS-b)); printf "\r%s %s %d:%02d " "${f[i++%10]}" "$m" $((e/60)) $((e%60)); sleep 0.2; done & )
  trap 'rm -f /tmp/sp.on' INT
  "$@" >/tmp/arcade_step.log 2>&1; s=$?
  rm -f /tmp/sp.on; trap - INT; sleep 0.3; printf "\r\033[K"; return $s
}

ensure_apis() {
  local enabled missing=() api
  enabled=$(gcloud services list --enabled --format='value(config.name)' 2>/dev/null)
  for api in "$@"; do
    grep -qxF "$api" <<<"$enabled" || missing+=("$api")
  done
  [ ${#missing[@]} -eq 0 ] && return 0
  for try in 1 2; do
    gcloud services enable "${missing[@]}" && return 0
    [ "$try" -eq 1 ] && sleep 20
  done
  return 1
}

s3() {
  ER=
  P=$(gcloud config get-value project 2>/dev/null)
  A=$(gcloud config get-value account 2>/dev/null)
  [ -z "$P" ] && { echo "[ERROR] No project selected. Select your project in Cloud Shell, then run this block again."; return 1; }
  if ! sp "Checking/enabling APIs for $P" ensure_apis compute.googleapis.com aiplatform.googleapis.com cloudbilling.googleapis.com; then
    echo "[ERROR] Could not enable the APIs:"; tail -n 10 /tmp/arcade_step.log
    echo "If it mentions billing, link your credit: https://console.cloud.google.com/billing/linkedaccount?project=$P"; return 1
  fi
  SA=$(gcloud projects describe "$P" --format='value(projectNumber)')-compute@developer.gserviceaccount.com
  wsa() { for i in {1..12}; do gcloud iam service-accounts describe "$SA" && return; sleep 5; done; }
  sp "Waiting for your agent's service account" wsa

  chk() {
    l=$1 m=$2; shift 2; n=0 x=
    for r; do
      if grep -qixF "$m $r" <<<"$T"; then ((n++)); else x+=" $r"
      [ $G ] && { O=$(gcloud projects add-iam-policy-binding "$P" --member="$m" --role="roles/$r" --condition=None 2>&1 >/dev/null) || ER=$O; }
      fi
    done
    [ -n "$x" ] && F=1; [ $G ] && return
    c=; (($#>1)) && c=" ($n/$#)"
    [ -z "$x" ] && echo "[OK] $l$c" || echo "[MISSING] $l${c:+, missing:$x}"
  }

  rd() {
    G=$1 F=
    T=$(gcloud projects get-iam-policy "$P" --flatten='bindings[].members' --format='value(bindings.members,bindings.role)' 2>/dev/null | sed 's#\troles/# #')
    if [ -z "$G" ]; then
      B=$(gcloud billing projects describe "$P" --format='value(billingAccountName)' 2>/dev/null | sed 's#.*/##')
      N=$([ -n "$B" ] && gcloud billing accounts describe "$B" --format='value(displayName)' 2>/dev/null)
      [ -n "$B" ] && echo "[OK] Billing linked: ${N:-$B}" || { echo "[MISSING] No billing account linked to $P"; F=1; }
      T+=$'\n'$(gcloud services list --enabled --format='value(config.name)' 2>/dev/null | sed 's/^/api /;s/\.googleapis\.com$//')
      chk "Your account is Owner" "user:$A" owner
      chk "APIs enabled" api compute aiplatform
    fi
    chk "Agent permissions" "serviceAccount:$SA" run.builder aiplatform.user
    chk "Review team access" "group:arcade-agent-verifier@google.com" serviceusage.serviceUsageViewer run.viewer browser
  }

  gr() { for t in {1..6}; do rd g; [ -z "$F" ] && return; ((t<6)) && sleep 10; done; }
  sp "Granting permissions" gr
  echo "Summary for project $P:"; rd
  [ -n "$F" ] && [ -n "$ER" ] && { echo "Last error:"; echo "$ER" | tail -n 3; }
  [ -z "$F" ] && echo "Step 3 OK!" || { echo "Ada item Step 3 yang belum lengkap."; return 1; }
}

s3 || exit 1

# ----------------------------------------------------------------- Step 4
step "Step 4: Membuat main.py (Evaluator Path - Portfolio Builder)"
cat <<'EOF' > "$WORKDIR/main.py"
import os
import json
import time
import hmac
from collections import deque
from flask import Flask, request, jsonify
from google import genai
from google.genai import types
from pydantic import BaseModel, Field

client = genai.Client(vertexai=True, project=os.environ.get("DEVSHELL_PROJECT_ID"), location="global")

# ---- OPTIONAL EDIT: Swap in another persona from Step B, or write your own ----
SYSTEM_INSTRUCTION = (
    "You are an experienced tech recruiter and frontend designer. The user will give you a "
    "rough summary of their coding skills and background. Score how ready it is to get noticed "
    "by hiring managers, list what's currently holding it back, and generate a complete, polished "
    "single-file HTML/CSS (Tailwind) portfolio website that reframes their skills into a clear, "
    "professional 'About Me' section."
)
PAGE_TITLE = "Portfolio Builder"
PAGE_SUBTITLE = "Paste your bio. Get a score, feedback, and a polished portfolio site."
INPUT_PLACEHOLDER = "Paste a rough summary of your skills and background..."
BUTTON_LABEL = "Build My Portfolio"
SCORE_LABEL = "Portfolio Readiness"
FINDINGS_LABEL = "What's Holding You Back"
OUTPUT_LABEL = "Your New Portfolio Site"

# ---- DO NOT EDIT BELOW THIS LINE: Core agent and verification logic ----
app = Flask(__name__)

# Cost and abuse protection.
RATE_LIMIT_WINDOW_SECONDS = 60
RATE_LIMIT_MAX_REQUESTS = 20
# ---- margin for verification checks ----
MAX_LIFETIME_COST_ESTIMATE = 4.5
PRICE_PER_INPUT_TOKEN = 1.50 / 1_000_000
PRICE_PER_OUTPUT_TOKEN = 9.00 / 1_000_000  # gemini-3.5-flash
VERIFY_TOKEN = os.environ.get("VERIFY_TOKEN", "")
MAX_INPUT_CHARS = 3500
_request_log = {}
_lifetime_cost_estimate = 0.0

def is_rate_limited(client_ip):
    now = time.time()
    window_start = now - RATE_LIMIT_WINDOW_SECONDS
    timestamps = _request_log.setdefault(client_ip, deque())
    while timestamps and timestamps[0] < window_start:
        timestamps.popleft()
    if len(timestamps) >= RATE_LIMIT_MAX_REQUESTS:
        return True
    timestamps.append(now)
    return False

def is_verifier_request():
    token = request.headers.get("X-Verify-Token", "")
    return bool(VERIFY_TOKEN) and hmac.compare_digest(token.encode(), VERIFY_TOKEN.encode())

def is_over_budget():
    return not is_verifier_request() and _lifetime_cost_estimate > MAX_LIFETIME_COST_ESTIMATE

def track_cost(response):
    if is_verifier_request():
        return
    global _lifetime_cost_estimate
    prompt_tokens = response.usage_metadata.prompt_token_count
    billable_output_tokens = response.usage_metadata.total_token_count - prompt_tokens
    _lifetime_cost_estimate += prompt_tokens * PRICE_PER_INPUT_TOKEN + billable_output_tokens * PRICE_PER_OUTPUT_TOKEN

def get_client_ip():
    forwarded = request.headers.get("X-Forwarded-For", "")
    return forwarded.split(",")[-1].strip() if forwarded else request.remote_addr

class VerdictResponse(BaseModel):
    score: int = Field(description="0-100 score reflecting overall quality")
    summary: str = Field(description="1-2 sentence summary of the verdict")
    findings: list[str] = Field(description="Specific issues, risks, or notes found")
    output: str = Field(description="The improved, rewritten, or refactored result")

def generate_verdict(user_text):
    response = client.models.generate_content(
        model="gemini-3.5-flash",
        contents=user_text,
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_INSTRUCTION,
            response_mime_type="application/json",
            response_schema=VerdictResponse,
            temperature=0.4,
            thinking_config=types.ThinkingConfig(thinking_level="low")
        )
    )
    track_cost(response)
    data = json.loads(response.text)
    data["reply"] = data.get("summary", "")
    return data

@app.route("/", methods=["GET"])
def home():
    return HTML_PAGE

@app.route("/chat", methods=["POST"])
def chat_endpoint():
    client_ip = get_client_ip()
    if is_rate_limited(client_ip):
        return jsonify({"error": "Too many requests. Please wait a moment and try again."}), 429

    data = request.get_json(force=True)
    user_message = data.get("message", "")
    if not user_message.strip():
        return jsonify({"error": "No 'message' field provided."}), 400
    if len(user_message) > MAX_INPUT_CHARS:
        return jsonify({"error": f"Input is too large. Please keep it under {MAX_INPUT_CHARS} characters."}), 400
    if is_over_budget():
        return jsonify({"error": "This agent has reached its usage limit for this deployment."}), 429

    try:
        return jsonify(generate_verdict(user_message))
    except Exception as e:
        error_text = str(e)
        if "RESOURCE_EXHAUSTED" in error_text or "429" in error_text:
            return jsonify({"error": "The AI is briefly overloaded right now, please wait a few seconds and try again."}), 429
        return jsonify({"error": "Something went wrong generating a response. Please try again."}), 500

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>__PAGE_TITLE__ | The Arcade</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>&#128269;</text></svg>">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700;900&display=swap" rel="stylesheet">
  <style>
    /* ---- OPTIONAL EDIT: Change hex color codes below to customize your theme (see Side Quest guide) ---- */
    :root {
      --page-background: #1a1012; --chat-window-background: #241619;
      --title-and-button-color: #c9564d; --your-message-color: #e0a75e;
      --decorative-accent-blue: #e0a75e; --message-text-color: #f0e6e2; --subtitle-color: #a8938e;
    }
    * { box-sizing: border-box; }
    body {
      background-color: var(--page-background);
      background-image: radial-gradient(circle at 50% 0%, rgba(201,86,77,0.14), transparent 55%);
      color: var(--message-text-color); font-family: 'Roboto', Arial, sans-serif;
      margin: 0; padding: 40px 16px; min-height: 100vh;
      display: flex; flex-direction: column; align-items: center;
    }
    .wrap { width: 100%; max-width: 760px; position: relative; }
    .corner { position: absolute; width: 22px; height: 22px; border-color: var(--your-message-color); opacity: 0.55; }
    .corner-tl { top: -14px; left: -14px; border-top: 2px solid; border-left: 2px solid; }
    .corner-tr { top: -14px; right: -14px; border-top: 2px solid; border-right: 2px solid; }
    .corner-bl { bottom: -14px; left: -14px; border-bottom: 2px solid; border-left: 2px solid; }
    .corner-br { bottom: -14px; right: -14px; border-bottom: 2px solid; border-right: 2px solid; }
    @media (max-width: 640px) { .corner { display: none; } }
    .header { text-align: center; margin-bottom: 24px; }
    .eyebrow { display: inline-block; font-size: 11px; font-weight: 700; letter-spacing: .1em; text-transform: uppercase;
      padding: 6px 14px; border-radius: 4px; background: var(--title-and-button-color); color: #2a0705; margin-bottom: 18px; }
    .badge { width: 64px; height: 64px; padding: 3px; margin: 0 auto 14px;
      background: linear-gradient(135deg, var(--title-and-button-color), var(--your-message-color));
      clip-path: polygon(30% 0%, 70% 0%, 100% 30%, 100% 70%, 70% 100%, 30% 100%, 0% 70%, 0% 30%);
      display: flex; align-items: center; justify-content: center; }
    .badge-inner { width: 100%; height: 100%; background: var(--chat-window-background);
      clip-path: polygon(30% 0%, 70% 0%, 100% 30%, 100% 70%, 70% 100%, 30% 100%, 0% 70%, 0% 30%);
      display: flex; align-items: center; justify-content: center; }
    .badge-inner { font-size: 28px; }
    .header h1 { font-size: 26px; margin: 0 0 6px; font-weight: 900; color: var(--title-and-button-color); }
    .header p { font-size: 14px; color: var(--subtitle-color); margin: 0; }
    .card { background: var(--chat-window-background); border-radius: 6px; padding: 24px;
      border: 1px solid rgba(255,255,255,.06); margin-bottom: 20px; }
    textarea { width: 100%; height: 220px; background: var(--page-background); color: var(--your-message-color);
      border: 1px solid rgba(255,255,255,.12); border-radius: 4px; padding: 14px; font-family: monospace;
      font-size: 16px; outline: none; resize: vertical; }
    textarea:focus { border-color: var(--title-and-button-color); }
    button { width: 100%; min-height: 48px; padding: 14px; border-radius: 4px; border: none; background: var(--title-and-button-color);
      color: #2a0705; font-weight: 700; font-size: 15px; cursor: pointer; margin-top: 12px; transition: background .15s;
      display: flex; align-items: center; justify-content: center; }
    button:hover { background: var(--your-message-color); color: #2a1c00; }
    button:disabled { opacity: .8; cursor: not-allowed; }
    .spinner { display: inline-block; width: 16px; height: 16px; margin-right: 8px;
      border: 2px solid rgba(42,7,5,.35); border-top-color: #2a0705; border-radius: 50%;
      animation: spin .7s linear infinite; }
    button:hover .spinner { border-color: rgba(42,28,0,.35); border-top-color: #2a1c00; }
    @keyframes spin { to { transform: rotate(360deg); } }
    #resultCard { display: none; }
    .score-badge { font-size: 42px; font-weight: 900; margin: 10px 0; }
    #findingsList { padding-left: 20px; color: var(--message-text-color); }
    #findingsList li { margin-bottom: 6px; }
    pre { background: var(--page-background); padding: 16px; border-radius: 4px; overflow-x: auto;
      color: var(--your-message-color); border: 1px solid rgba(255,255,255,.08); white-space: pre-wrap; }
    h3 { color: var(--subtitle-color); font-size: 13px; text-transform: uppercase; letter-spacing: .08em; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="corner corner-tl"></div>
    <div class="corner corner-tr"></div>
    <div class="corner corner-bl"></div>
    <div class="corner corner-br"></div>
    <div class="header">
      <div class="eyebrow">The Arcade | Google Cloud</div>
      <div class="badge"><div class="badge-inner">
        &#128269;
      </div></div>
      <h1>__PAGE_TITLE__</h1>
      <p>__PAGE_SUBTITLE__</p>
    </div>

    <div class="card">
      <textarea id="userInput" placeholder="__INPUT_PLACEHOLDER__"></textarea>
      <button id="submitBtn" onclick="runVerdict()"><span id="btnSpinner" class="spinner" style="display:none;"></span><span id="btnLabel">__BUTTON_LABEL__</span></button>
    </div>

    <div id="resultCard" class="card">
      <h3>__SCORE_LABEL__</h3>
      <div class="score-badge"><span id="scoreText">--</span>/100</div>
      <p id="summaryText" style="color: var(--subtitle-color);"></p>

      <h3>__FINDINGS_LABEL__</h3>
      <ul id="findingsList"></ul>

      <h3>__OUTPUT_LABEL__</h3>
      <pre><code id="outputText"></code></pre>
    </div>
  </div>

  <script>
    async function runVerdict() {
      const text = document.getElementById("userInput").value;
      const resultCard = document.getElementById("resultCard");
      if (!text.trim()) { alert("Please paste something first!"); return; }

      resultCard.style.display = "none";

      const btn = document.getElementById("submitBtn");
      const spinner = document.getElementById("btnSpinner");
      const label = document.getElementById("btnLabel");
      btn.disabled = true;
      spinner.style.display = "inline-block";
      label.textContent = "Working on it...";

      try {
        const response = await fetch("/chat", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: text })
        });

        const data = await response.json();
        if (data.error) { alert(data.error); return; }

        document.getElementById("scoreText").innerText = data.score;
        const scoreColor = data.score >= 80 ? "#34A853" : data.score >= 50 ? "#e0a75e" : "#c9564d";
        document.querySelector(".score-badge").style.color = scoreColor;
        document.getElementById("summaryText").innerText = data.summary;

        const findingsList = document.getElementById("findingsList");
        findingsList.innerHTML = "";
        data.findings.forEach(f => {
          const li = document.createElement("li");
          li.textContent = f;
          findingsList.appendChild(li);
        });

        document.getElementById("outputText").textContent = data.output;
        resultCard.style.display = "block";
      } catch (err) {
        alert("Something went wrong. Please wait a moment and try again.");
      } finally {
        btn.disabled = false;
        spinner.style.display = "none";
        label.textContent = "__BUTTON_LABEL__";
      }
    }
  </script>
</body>
</html>
"""

HTML_PAGE = (
    HTML_TEMPLATE
    .replace("__PAGE_TITLE__", PAGE_TITLE)
    .replace("__PAGE_SUBTITLE__", PAGE_SUBTITLE)
    .replace("__INPUT_PLACEHOLDER__", INPUT_PLACEHOLDER)
    .replace("__BUTTON_LABEL__", BUTTON_LABEL)
    .replace("__SCORE_LABEL__", SCORE_LABEL)
    .replace("__FINDINGS_LABEL__", FINDINGS_LABEL)
    .replace("__OUTPUT_LABEL__", OUTPUT_LABEL)
)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
EOF
echo "main.py selesai ditulis."

# ----------------------------------------------------------------- Step 5
step "Step 5: Deploy ke Cloud Run (arcade-agent di us-central1)"
[ -f ~/.arcade-agent-verify-token ] || openssl rand -hex 16 > ~/.arcade-agent-verify-token
VERIFY_TOKEN=$(cat ~/.arcade-agent-verify-token)
L=/tmp/arcade_step.log

s5() {
  [ -f main.py ] || { echo "[ERROR] main.py not found. Create it first."; return 1; }
  h() { for x; do grep -qixF "$x" <<<"$T" || printf " %s" "${x##* }"; done; }
  ck() {
    P=$(gcloud config get-value project)
    a="serviceAccount:$(gcloud projects describe "$P" --format='value(projectNumber)')-compute@developer.gserviceaccount.com "
    T=$(gcloud projects get-iam-policy "$P" --flatten='bindings[].members' --format='value(bindings.members,bindings.role)' | sed 's#\troles/# #')
    M=$(h "$a"{run.builder,aiplatform.user} "group:arcade-agent-verifier@google.com "{serviceusage.serviceUsageViewer,run.viewer,browser}) K=
    if grep -q bigquery main.py; then
      C=$(bq show --connection --format=json us-central1.vertex_ai_conn | jq -r '.cloudResource.serviceAccountId // empty')
      [ -z "$C" ] && K+=" vertex_ai_conn"
      K+=$(h "$a"{bigquery.jobUser,bigquery.dataViewer,bigquery.connectionUser} "serviceAccount:$C aiplatform.user")
      bq show arcade_knowledge.badge_embeddings || K+=" badge_embeddings"
    fi
  }
  sp "Checking your project setup" ck
  [ -n "$M" ] && echo "[MISSING] Setup not complete, missing:$M. Run Step 3 again."
  [ -n "$K" ] && echo "[MISSING] Knowledge base not ready, missing:$K."
  [ -n "$M$K" ] && return 1
  echo "[OK] Project setup confirmed"

  sp "Turning on Cloud Run..." ensure_apis run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com || { echo "[ERROR] Could not turn on Cloud Run:"; tail -n 10 "$L"; return 1; }
  echo "[OK] Services ready"
  echo "Deploy memakan waktu hingga 10 menit. Tunggu sampai selesai..."
  for t in 1 2 3; do
    sp "Deploying your agent, up to 10 min" gcloud run deploy arcade-agent --source . --region us-central1 --no-invoker-iam-check --max-instances=1 --set-env-vars "VERIFY_TOKEN=$VERIFY_TOKEN" --quiet && {
      echo "[OK] Done! Your agent is live."
      echo "Service URL: $(grep -o 'https://[^ ]*run\.app' "$L" | tail -n 1)"
      return 0
    }
    grep -q "missing required IAM permissions" "$L" && ((t<3)) || break
    cp "$L" /tmp/d.log; sp "Activating your permissions" sleep 30; cp /tmp/d.log "$L"
  done
  if grep -q "refreshing your current auth tokens" "$L"; then
    echo "[ERROR] Cloud Shell lost its sign-in. Reopen it and run this script again."
  else
    echo "[ERROR] Something went wrong:"; tail -n 15 "$L"
  fi
  return 1
}

s5 || exit 1

# ----------------------------------------------------------------- Step 7
step "Step 7: Verifikasi kesiapan submission form"
s7() {
  cd "$WORKDIR" 2>/dev/null
  ensure_apis cloudbilling.googleapis.com &>/dev/null
  P=$(gcloud config get-value project 2>/dev/null)
  A=$(gcloud config get-value account 2>/dev/null)
  V=group:arcade-agent-verifier@google.com
  F=
  echo "Checking your project the same way our review does..."
  pol() { T=$(gcloud projects get-iam-policy "$P" --flatten='bindings[].members' --format='value(bindings.members,bindings.role)' 2>/dev/null | sed 's#\troles/# #'); }
  pol
  for R in serviceusage.serviceUsageViewer run.viewer browser; do
    grep -qixF "$V $R" <<<"$T" || gcloud projects add-iam-policy-binding "$P" --member="$V" --role="roles/$R" --condition=None &>/dev/null
  done
  pol
  B=$(gcloud billing projects describe "$P" --format='value(billingAccountName)' 2>/dev/null | sed 's#billingAccounts/##')
  U=$(gcloud run services describe arcade-agent --region us-central1 --format='value(status.url)' 2>/dev/null)
  AP=$(gcloud services list --enabled --filter=config.name=aiplatform.googleapis.com --format='value(config.name)' 2>/dev/null)
  H=; [ -n "$U" ] && H=$(curl -sL -o /dev/null -w '%{http_code}' -m 30 "$U")
  if grep -q VerdictResponse main.py 2>/dev/null; then N=Evaluator
  elif grep -q fetch_doc_text main.py 2>/dev/null; then N=Navigator
  elif grep -q bigquery main.py 2>/dev/null; then N=Researcher
  else N=; fi

  ok() { l=$1 h=$2; shift 2; if "$@"; then echo "[OK] $l"; else echo "[FAIL] $l: $h"; F=1; fi; }
  ok "Your account is Owner" "sign in to Cloud Shell with the account that owns this project" grep -qixF "user:$A owner" <<<"$T"
  ok "Review team access" "run Step 3 again" test "$(grep -ciE "^$V (serviceusage.serviceUsageViewer|run.viewer|browser)$" <<<"$T")" = 3
  ok "Agent Platform API enabled" "run Step 3 again" test -n "$AP"
  ok "Billing account linked" "link your credit in Billing" test -n "$B"
  ok "Agent deployed" "run Step 5 again" test -n "$U"
  ok "Agent page opens" "open your Service URL and check that it loads" test "${H:0:1}" = 2
  ok "Path detected" "check that main.py is in the arcade-buildathon-7b4m folder" test -n "$N"

  echo
  if [ -n "$F" ]; then
    echo "Perbaiki item [FAIL] di atas sebelum submit."
    return 1
  fi
  echo "Ready to submit. Salin data berikut ke submission form:"
  echo "   Project ID:          $P"
  echo "   Path:                $N"
  echo "   Service URL:         $U"
}

s7

echo
echo "SELESAI! Langkah manual selanjutnya (Step 6 & Step 7):"
echo "  1. Buka Service URL di browser, uji 1 pesan, dan rekam demo 30-60 detik."
echo "  2. Upload video ke YouTube (Unlisted) atau Google Drive (Anyone with the link)."
echo "  3. (Opsional +1 poin) Posting ke sosmed dengan #GoogleCloud #GEAR #ArcadeBuildathon."
echo "  4. Isi Arcade Build-a-thon Verification Form di Step 7 memakai data di atas."

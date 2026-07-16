#!/usr/bin/env bash
# GSP1154 - Getting Started with Agent Studio (Vertex AI Studio)
#
# BACA DULU. Lab ini hampir seluruhnya kerja klik di Console, dan checkpoint-nya
# tidak transparan. Script ini TIDAK menggantikan lab-nya. Yang dilakukan script
# ini adalah memanggil API yang setara dengan prompt tiap task, dengan asumsi
# checkpoint melihat jejak pemakaian Vertex AI di project. Asumsi ini belum
# diverifikasi di lab instance sungguhan.
#
# Yang PASTI tetap manual:
#   Task 1  - "Deploy as app" ke Cloud Run. Tombol itu membangun container
#             bawaan Agent Studio yang tidak ada padanan gcloud/API-nya.
#             Checkpoint task 1 hanya bisa hijau lewat UI.
#   Task 5  - bagian Chirp (opsional di lab) tidak disentuh script ini.
#
# Pemakaian:
#   bash gsp1154.sh
#
# Override kalau beda:
#   FLASH=gemini-3.5-flash PRO=gemini-2.5-pro IMAGE_URI=gs://.../timetable.png \
#     IMAGEN_REGION=us-central1 bash gsp1154.sh

set -euo pipefail

# ----------------------------------------------------------------- parameter
# Sesuai teks lab. Perhatikan pasangannya memang "terbalik": Flash-nya generasi
# 3.5, Pro-nya generasi 2.5. Task 3 membandingkan keduanya.
FLASH="${FLASH:-gemini-3.5-flash}"
PRO="${PRO:-gemini-2.5-pro}"

# Task 3 minta "Thinking level: Minimal" untuk Flash. Model Gemini 3 pakai
# thinkingLevel (enum), bukan thinkingBudget (angka) seperti generasi 2.x.
# Kalau enum-nya ditolak, script otomatis mundur ke panggilan tanpa config ini.
THINKING_CFG="${THINKING_CFG:-{\"thinkingLevel\":\"MINIMAL\"}}"

# Task 4 pakai timetable.png dari bucket bawaan lab. Nama bucket-nya beda tiap
# instance, jadi default-nya dialihkan ke copy publik yang isinya sama.
# Kalau mau persis punya lab: IMAGE_URI=gs://<bucket-lab>/timetable.png
IMAGE_URI="${IMAGE_URI:-gs://cloud-samples-data/generative-ai/image/timetable.png}"

# Gemini pakai endpoint global (sesuai instruksi "Region: Global").
# Imagen belum ada di global, jadi tetap regional.
IMAGEN_MODEL="${IMAGEN_MODEL:-imagen-4.0-generate-001}"
IMAGEN_REGION="${IMAGEN_REGION:-us-central1}"

PROJECT="${DEVSHELL_PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT" ]] || { echo "Project belum di-set. Jalankan: gcloud config set project <ID>"; exit 1; }

command -v jq >/dev/null || { echo "jq tidak ada. Di Cloud Shell harusnya sudah terinstall."; exit 1; }

echo "Project    : $PROJECT"
echo "Flash model: $FLASH"
echo "Pro model  : $PRO"
echo "Image      : $IMAGE_URI"

step() { echo; echo "=============================================================="; echo ">> $1"; echo "=============================================================="; }

TOKEN=""
refresh_token() { TOKEN="$(gcloud auth print-access-token)"; }
refresh_token

GEMINI_HOST="https://aiplatform.googleapis.com"
GEMINI_BASE="$GEMINI_HOST/v1/projects/$PROJECT/locations/global/publishers/google/models"

# gen <model> <payload-json> -- kirim ke generateContent, cetak teks jawabannya.
# Retry sekali kalau kena 429 (lab-nya sendiri memperingatkan soal quota).
gen() {
  local model="$1" payload="$2" resp text
  for attempt in 1 2 3; do
    resp="$(curl -sS -X POST \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      "$GEMINI_BASE/$model:generateContent" \
      -d "$payload")"

    if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
      local code msg
      code="$(echo "$resp" | jq -r '.error.code')"
      msg="$(echo "$resp" | jq -r '.error.message')"
      if [[ "$code" == "429" && "$attempt" -lt 3 ]]; then
        echo "   (429 quota exhausted, tunggu 20 detik lalu coba lagi)" >&2
        sleep 20
        continue
      fi
      echo "GAGAL [$code]: $msg" >&2
      return 1
    fi

    text="$(echo "$resp" | jq -r '[.candidates[]?.content.parts[]?.text] | join("")')"
    [[ -n "$text" ]] || text="$(echo "$resp" | jq -c '.')"
    echo "$text"
    return 0
  done
}

# ----------------------------------------------------------------- teks prompt
# Disalin apa adanya dari halaman lab. Single quote memang disengaja: $7,500 dan
# $5k-$10k itu nominal uang di teks lab, bukan variabel shell. Itu sebabnya ada
# beberapa "shellcheck disable=SC2016" di bawah.

SYS_UNDERWRITER='You are an expert AI assistant for an insurance underwriting department.
Your primary goal is to help underwriters by accurately and concisely summarizing client information and highlighting potential risk factors.
Maintain a professional and objective tone.
Focus only on the information provided in the prompt. Do not invent details.'

SYS_EXTRACTOR='You are an AI assistant specializing in parsing and extracting specific data points from unstructured insurance claim notifications.
Your goal is to identify and list key information accurately.
If a piece of information is not found, clearly state "Not found".
Output the extracted information in a key: value format, with each key on a new line.'

SYS_ANALYST='You are an insurance risk analyst assistant. Your task is to identify potential risk factors from a given scenario. Be concise.'

FIELDS='- Policy Number
- Claimant Name
- Date of Loss
- Time of Loss
- Type of Loss
- Brief Description of Damage
- Estimated Loss Amount
- Injuries Reported'

# shellcheck disable=SC2016
VANCE_NOTE='Claim Notification Received:
"Hi team, just got a call from Mrs. Eleanor Vance, policy #POL458892. She reported a kitchen fire that occurred on May 12th, 2025, around 3 PM. The main damage seems to be to the oven and surrounding cabinets. She mentioned smoke damage in the kitchen and dining area too. She thinks the total damage might be around $7,500. Her contact is 555-0123. No injuries reported, thankfully."'

# shellcheck disable=SC2016
STERLING_NOTE='Claim Notification Received:
"Email from John Sterling (policy POL77521) re: water damage at his shop. Happened sometime last night, May 10th, 2025. A pipe burst in the ceiling. Stockroom is flooded, some damage to inventory. He'"'"'s not sure on the cost yet, maybe $5k-$10k? No one was there, so no injuries."'

# shellcheck disable=SC2016
STERLING_OUTPUT='Policy Number: POL77521
Claimant Name: John Sterling
Date of Loss: May 10th, 2025
Time of Loss: Night
Type of Loss: Water damage
Brief Description of Damage: Pipe burst in ceiling, stockroom flooded, some damage to inventory.
Estimated Loss Amount: $5,000 - $10,000
Injuries Reported: No'

GRILL_SCENARIO='Scenario:
"The applicant, '"'"'The Fiery Grill,'"'"' is a new upscale restaurant specializing in wood-fired oven pizzas and open-flame grilling. They have installed a brand new, custom-built fire suppression system for their cooking area, but it has not yet been certified by a third party. The restaurant plans to feature live acoustic music on weekend evenings and has a small, raised stage area. They also want to offer valet parking."

Based on this scenario, list three primary risk factors an underwriter should consider.'

# ================================================================== Task 0
step "Cek Vertex AI API"
# Akun student lab tidak punya izin serviceusage, dan memang tidak perlu:
# Qwiklabs sudah meng-enable API-nya waktu provisioning project. Jadi jangan
# paksa enable, cukup lapor lalu lanjut. Kalau API-nya benar-benar mati,
# panggilan pertama akan gagal dengan pesan yang jelas.
if gcloud services list --enabled --project="$PROJECT" \
     --filter="config.name=aiplatform.googleapis.com" --format="value(config.name)" 2>/dev/null \
     | grep -q aiplatform; then
  echo "aiplatform.googleapis.com sudah aktif."
else
  echo "Tidak bisa memastikan status API (biasanya karena akun lab dibatasi)."
  echo "Lanjut saja; di lab ini API-nya sudah di-enable dari awal."
fi

# ================================================================== Task 1
step "Task 1: ringkasan risiko SafeHarbor Warehousing ($FLASH)"
echo "CATATAN: checkpoint task 1 menilai app Cloud Run hasil 'Deploy as app'."
echo "Panggilan di bawah ini cuma menjalankan prompt-nya, BUKAN pengganti deploy."
echo

TASK1_PROMPT="Customer Notes for 'SafeHarbor Warehousing':
\"The applicant is seeking coverage for their 50,000 sq ft warehouse. The business is 5 years old. The building is a concrete tilt-up structure, originally built in 2010. They store a variety of non-hazardous dry goods.
Fire safety measures include a full sprinkler system, a centrally monitored fire alarm, and documented annual inspections by a certified third party.
Security measures include a 24/7 centrally monitored burglar alarm, comprehensive security camera coverage of the interior and exterior, a fully fenced perimeter, and nightly patrols by a contracted security guard service.
The company reports no major property or liability losses in their 5-year history. They have specifically asked to ensure their new automated shelving and retrieval system, installed last month, is adequately covered under the policy.\"

Your Task:
1. Briefly summarize the key details of the 'SafeHarbor Warehousing' business and its existing safety measures.
2. Based *only* on the notes provided, identify any immediate questions an underwriter should ask or potential risk factors they should consider further.
Present the summary first, then the questions/risk factors as bullet points."

gen "$FLASH" "$(jq -n \
  --arg sys "$SYS_UNDERWRITER" --arg p "$TASK1_PROMPT" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$p}]}]}')"

# ================================================================== Task 2
step "Task 2a: zero-shot extraction, temperature 0.1 ($FLASH)"
gen "$FLASH" "$(jq -n \
  --arg sys "$SYS_EXTRACTOR" \
  --arg p "$VANCE_NOTE

Extract the following:
$FIELDS" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:0.1,maxOutputTokens:1024}}')"

step "Task 2b: few-shot extraction (1 contoh Sterling), temperature 0.1"
# Contoh few-shot di UI = giliran user/model palsu sebelum input asli.
gen "$FLASH" "$(jq -n \
  --arg sys "$SYS_EXTRACTOR" \
  --arg ex_in "$STERLING_NOTE

Extract the following:
$FIELDS" \
  --arg ex_out "$STERLING_OUTPUT" \
  --arg p "$VANCE_NOTE

Extract the following data points from the provided claim notification:
$FIELDS" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$ex_in}]},
              {role:"model",parts:[{text:$ex_out}]},
              {role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:0.1,maxOutputTokens:1024}}')"

STORY_PROMPT='Write the *first paragraph* of a short story about a homeowner who just used a futuristic AI insurance app to file a claim. The claim was for a bizarre and unexpected incident.'

step "Task 2c: efek temperature (1.5 vs 0.1) di prompt kreatif"
for t in 1.5 0.1; do
  echo "--- temperature $t ---"
  gen "$FLASH" "$(jq -n --arg p "$STORY_PROMPT" --argjson t "$t" \
    '{contents:[{role:"user",parts:[{text:$p}]}],
      generationConfig:{temperature:$t}}')"
  echo
done

step "Task 2d: efek output token limit (500, jawaban akan terpotong)"
gen "$FLASH" "$(jq -n --arg p "$STORY_PROMPT" \
  '{contents:[{role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:1.0,maxOutputTokens:500}}')" || true

step "Task 2e: efek Top-P (0.8 vs 1.0)"
for tp in 0.8 1.0; do
  echo "--- topP $tp ---"
  gen "$FLASH" "$(jq -n --arg p "$STORY_PROMPT" --argjson tp "$tp" \
    '{contents:[{role:"user",parts:[{text:$p}]}],
      generationConfig:{temperature:0.5,topP:$tp}}')"
  echo
done

# ================================================================== Task 3
step "Task 3a: baseline Fiery Grill, temperature 0.2 ($FLASH)"
gen "$FLASH" "$(jq -n --arg sys "$SYS_ANALYST" --arg p "$GRILL_SCENARIO" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:0.2}}')"

step "Task 3b: compare - system instruction diubah (minta mitigasi)"
SYS_ANALYST_V2='You are an expert insurance risk analyst assistant. Your task is to identify potential risk factors from a given scenario. For each risk factor, also briefly suggest a potential mitigation strategy or question for the underwriter. Be clear and structured.'
gen "$FLASH" "$(jq -n --arg sys "$SYS_ANALYST_V2" --arg p "$GRILL_SCENARIO" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:0.2}}')"

step "Task 3c: compare - temperature 2.0 (sengaja ekstrem, output ngawur)"
gen "$FLASH" "$(jq -n --arg sys "$SYS_ANALYST" --arg p "$GRILL_SCENARIO" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:2.0}}')"

GUIDELINES_PROMPT='Scenario:
"The applicant, '"'"'The Fiery Grill,'"'"' is an upscale restaurant specializing in wood-fired ovens and open-flame grilling. They have a brand new, custom-built fire suppression system, but it has not been certified by a third party. The restaurant will feature live acoustic music on a small, raised stage. They also want to offer valet parking, managed by their own staff. The applicant has no prior business history."

Underwriting Guidelines:
Priority Hierarchy: Liability risks are classed as:
- Class A (Critical): Fire, structural failure, failure of safety systems.
- Class B (Standard): General premises liability (e.g., slip-and-fall).
- Class C (Niche): Auto/Vehicle liability.

Compounding Factors: A "compounding risk" (a condition that makes another risk worse) must be elevated to the highest priority.
Inexperience: Lack of prior business history is a general negative factor but does not create a primary risk on its own.
Auto Liability: Class C risks (Valet) are only considered a primary risk if the applicant is using an unvetted, third-party contractor.

Task:
Based on the scenario and the underwriting guidelines, identify the single, #1 highest-priority risk. Then, write a 2-sentence justification that explains why it is the #1 risk, citing the specific guideline(s) that apply.'

step "Task 3d: compare model - $FLASH (thinking level minimal)"
PAYLOAD_MIN="$(jq -n --arg sys "$SYS_ANALYST" --arg p "$GUIDELINES_PROMPT" --argjson tc "$THINKING_CFG" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:0.2,thinkingConfig:$tc}}')"
PAYLOAD_PLAIN="$(jq -n --arg sys "$SYS_ANALYST" --arg p "$GUIDELINES_PROMPT" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:0.2}}')"
gen "$FLASH" "$PAYLOAD_MIN" || {
  echo "   (thinkingConfig ditolak model ini, ulangi tanpa setelan thinking)"
  echo "   Kalau mau cocok dengan lab, cari nama field-nya di error di atas,"
  echo "   lalu jalankan ulang dengan THINKING_CFG='{\"...\":\"...\"}'"
  gen "$FLASH" "$PAYLOAD_PLAIN"
}

step "Task 3e: compare model - $PRO"
gen "$PRO" "$(jq -n --arg sys "$SYS_ANALYST" --arg p "$GUIDELINES_PROMPT" \
  '{systemInstruction:{parts:[{text:$sys}]},
    contents:[{role:"user",parts:[{text:$p}]}],
    generationConfig:{temperature:0.2}}')"

# ================================================================== Task 4
step "Task 4a: analisis gambar timetable.png ($FLASH)"
echo "Sumber gambar: $IMAGE_URI"
gen "$FLASH" "$(jq -n --arg uri "$IMAGE_URI" \
  --arg p '1. Provide a concise title for this image (under 5 words).
2. Describe the image in one or two sentences.
3. Extract all visible text from the image. Present the flight schedule as a clearly formatted list with columns for "Time" and "City".' \
  '{contents:[{role:"user",parts:[
      {fileData:{mimeType:"image/png",fileUri:$uri}},
      {text:$p}]}]}')"

step "Task 4b: penalaran atas gambar, temperature 0.2 lalu 0.8"
REASON_PROMPT='Based on the flight schedule shown in the image, what percentage of the listed flights depart before 11:30 AM? Show your calculation if possible.'
for t in 0.2 0.8; do
  echo "--- temperature $t ---"
  gen "$FLASH" "$(jq -n --arg uri "$IMAGE_URI" --arg p "$REASON_PROMPT" --argjson t "$t" \
    '{contents:[{role:"user",parts:[
        {fileData:{mimeType:"image/png",fileUri:$uri}},
        {text:$p}]}],
      generationConfig:{temperature:$t}}')"
  echo
done

# ================================================================== Task 5
step "Task 5: generate 4 gambar lebah dengan $IMAGEN_MODEL ($IMAGEN_REGION)"
refresh_token
IMAGEN_URL="https://$IMAGEN_REGION-aiplatform.googleapis.com/v1/projects/$PROJECT/locations/$IMAGEN_REGION/publishers/google/models/$IMAGEN_MODEL:predict"
OUT_DIR="./gsp1154-images"

IMAGEN_RESP="$(curl -sS -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$IMAGEN_URL" \
  -d "$(jq -n --arg p 'A close-up, photorealistic image of a single honeybee collecting pollen from a vibrant purple lavender flower, with a softly blurred garden background.' \
    '{instances:[{prompt:$p}],
      parameters:{sampleCount:4,aspectRatio:"1:1"}}')")"

if echo "$IMAGEN_RESP" | jq -e '.error' >/dev/null 2>&1; then
  echo "GAGAL: $(echo "$IMAGEN_RESP" | jq -r '.error.message')" >&2
  echo "Kalau modelnya tidak ketemu, coba: IMAGEN_MODEL=imagen-3.0-generate-002 bash gsp1154.sh" >&2
else
  mkdir -p "$OUT_DIR"
  n=0
  while read -r b64; do
    n=$((n + 1))
    echo "$b64" | base64 -d > "$OUT_DIR/bee-$n.png"
  done < <(echo "$IMAGEN_RESP" | jq -r '.predictions[]?.bytesBase64Encoded')
  echo "Tersimpan $n gambar di $OUT_DIR/"
fi

# ==================================================================
cat <<EOF

--------------------------------------------------------------
Script selesai.

Yang tetap HARUS dikerjakan di Console:

  Task 1  Buka Agent Platform > Studio, buat prompt
          "Insurance Risk Summary - Prototype", Save, lalu
          Deploy > Cloud Run > Deploy as app. Tanpa ini,
          checkpoint task 1 tidak akan hijau.
          Kalau deploy pertama "Failed", tunggu semenit lalu
          klik Update app > Confirm.

  Task 5  Bagian Chirp (text-to-speech) opsional, tidak
          dijalankan script ini.

Klik Check my progress tiap task dan lihat mana yang hijau.
Kalau ada yang tetap merah, tandanya checkpoint itu memang
menilai aksi UI, bukan pemakaian API. Kerjakan manual.
--------------------------------------------------------------
EOF

#!/usr/bin/env bash
# Validasi semua script lab tanpa project Google Cloud.
#
#   bash test/run.sh            # semua script
#   bash test/run.sh gsp416.sh  # satu script
#
# Tiga lapis:
#   1. bash -n     -> syntax
#   2. shellcheck  -> quoting, variabel tak dipakai, pola berbahaya
#   3. dry-run     -> jalankan sungguhan, tapi gcloud/bq/kubectl/terraform diganti
#                     stub yang mencatat perintah. Menangkap variabel kosong
#                     (`set -u`), urutan salah, dan langkah yang tidak pernah tercapai.
#
# Yang TIDAK ditangkap: apakah flag-nya benar menurut API asli, dan apakah
# checkpoint lab jadi hijau. Itu hanya bisa dibuktikan di lab instance sungguhan.

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
STUBS="$WORK/bin"
trap 'rm -rf "$WORK"' EXIT

# Script yang butuh argumen fase, kalau tidak akan berhenti di awal.
declare -A ARGS=( [gsp1143.sh]="create" [gsp1157.sh]="reader" )

# Script yang wajib diberi env, guard-nya sengaja exit kalau kosong.
declare -A ENVS=(
  [gsp1157.sh]="USER2=user2@example.com"
  [gsp514.sh]="USER2=user2@example.com"
)

# Script yang sudah tercatat tidak layak diotomasi (lihat README).
declare -A SKIP=( [gsp1154.sh]="terbukti 0/5, lab berbasis UI" )

mkdir -p "$STUBS"
for c in gcloud bq gsutil kubectl terraform curl git docker sleep; do
  install -m755 "$ROOT/test/stubs.sh" "$STUBS/$c"
done
export PATH="$STUBS:$PATH"
export DEVSHELL_PROJECT_ID="dryrun-project"
export GOOGLE_CLOUD_PROJECT="dryrun-project"

mapfile -t SCRIPTS < <(
  if (( $# )); then printf '%s\n' "$@"
  else cd "$ROOT" && ls -1 gsp*.sh
  fi
)

pass=0; fail=0; skip=0
FAILED=()

printf '%-14s %-8s %-11s %-9s %s\n' SCRIPT SYNTAX SHELLCHECK DRY-RUN CATATAN
printf '%s\n' "-------------------------------------------------------------------"

for s in "${SCRIPTS[@]}"; do
  s=$(basename "$s")
  src="$ROOT/$s"

  if [[ -n "${SKIP[$s]:-}" ]]; then
    printf '%-14s %-8s %-11s %-9s %s\n' "$s" - - SKIP "${SKIP[$s]}"
    (( skip++ )); continue
  fi

  bash -n "$src" 2>"$WORK/$s.syntax" && syn=ok || syn=FAIL

  if shellcheck -S error "$src" >"$WORK/$s.sc" 2>&1; then sc=ok
  else sc="FAIL"; fi

  # dry-run di direktori kosong: script yang bikin file terraform tidak
  # mengotori repo, dan file sisa run sebelumnya tidak menutupi bug.
  run="$WORK/run_$s"; mkdir -p "$run"
  TRACE="$WORK/$s.trace"; : >"$TRACE"
  export TRACE

  if [[ "$syn" == ok ]]; then
    # stdin diisi baris kosong tanpa habis: `read -r` yang dipakai sebagai jeda
    # "tekan ENTER" akan balik sukses, bukan EOF (EOF = exit 1 di `set -e`).
    ( cd "$run" && eval "export ${ENVS[$s]:-DRYRUN=1}" \
      && timeout 120 bash "$src" ${ARGS[$s]:-} < <(yes '') ) >"$WORK/$s.out" 2>&1
    rc=$?
  else
    rc=1
  fi

  calls=$(wc -l <"$TRACE")
  if (( rc == 0 )); then
    dry=ok
  elif grep -qE "(cd|ls|cat): (cannot access )?.*No such file or directory" "$WORK/$s.out"; then
    # Stub tidak benar-benar mengunduh apa pun, jadi `cd` ke direktori hasil
    # git clone / gsutil cp pasti gagal. Bukan bug script.
    dry=NEED-NET
  else
    dry="FAIL($rc)"
  fi

  note="${calls} panggilan"
  [[ "$dry" != ok ]] && note="$note | $(tail -3 "$WORK/$s.out" | tr '\n' ' ' | cut -c1-70)"

  printf '%-14s %-8s %-11s %-9s %s\n' "$s" "$syn" "$sc" "$dry" "$note"

  if [[ "$syn" == ok && "$sc" == ok && "$dry" == ok ]]; then (( pass++ ))
  elif [[ "$dry" == NEED-NET ]]; then (( skip++ ))
  else (( fail++ )); FAILED+=("$s"); fi
done

echo
echo "lolos: $pass   gagal: $fail   dilewat: $skip"

if (( fail )); then
  echo
  echo "Detail yang gagal:"
  for s in "${FAILED[@]}"; do
    echo
    echo "### $s"
    [[ -s "$WORK/$s.syntax" ]] && { echo "-- syntax --"; cat "$WORK/$s.syntax"; }
    [[ -s "$WORK/$s.sc" ]]     && { echo "-- shellcheck --"; head -20 "$WORK/$s.sc"; }
    [[ -s "$WORK/$s.out" ]]    && { echo "-- dry-run (10 baris terakhir) --"; tail -10 "$WORK/$s.out"; }
  done
fi

exit $(( fail > 0 ))

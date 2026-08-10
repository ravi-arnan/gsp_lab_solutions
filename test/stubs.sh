#!/usr/bin/env bash
# Fake gcloud/bq/kubectl/terraform/... untuk dry-run.
# Tiap panggilan dicatat ke $TRACE, lalu dijawab dengan nilai yang bentuknya
# masuk akal supaya script yang mem-parse output tetap jalan.
#
# Bukan simulator. Tujuannya cuma bikin script berjalan sampai akhir supaya
# error syntax, variabel kosong, dan urutan yang salah ketahuan tanpa project asli.

set -uo pipefail

cmd=$(basename "$0")
printf '%s %s\n' "$cmd" "$*" >>"$TRACE"

args="$*"

# has <pola>  -> true kalau argumen mengandung pola (glob)
has() { [[ "$args" == *"$1"* ]]; }

case "$cmd" in

gcloud)
  if   has 'config get-value project'      ; then echo "${DEVSHELL_PROJECT_ID:-dryrun-project}"
  elif has 'auth print-access-token'       ; then echo "ya29.DRYRUN.fake-token"
  elif has 'projectNumber'                 ; then echo "123456789012"
  elif has 'ipAddress'                     ; then echo "10.20.0.2"   # private IP AlloyDB/Spanner dsb
  elif has 'instances list' && has 'zone'  ; then echo "us-central1-a"
  elif has 'sourceImage'                   ; then echo "https://www.googleapis.com/compute/v1/projects/debian-cloud/global/images/debian-12-bookworm-v20240110"
  elif has 'image_summary.digest'          ; then echo "sha256:0000000000000000000000000000000000000000000000000000000000000000"
  elif has 'writerIdentity'                ; then echo "serviceAccount:p123456789012-000000@gcp-sa-logging.iam.gserviceaccount.com"
  elif has 'buckets list'                  ; then
    # Lab mem-provision bucket ini sebelum script jalan; gsp514 memang menolak
    # lanjut kalau belum ada. Sebut semuanya supaya guard-nya teruji, bukan dilewati.
    p="${DEVSHELL_PROJECT_ID:-dryrun-project}"
    printf '%s\n' "$p-bucket" "$p-customer-online-sessions" "$p-dq-config"
  elif has 'value(status)'                 ; then echo "RUNNING"   # loop tunggu cluster/operasi
  elif has 'google-compute-default-zone'   ; then echo "us-central1-a"
  elif has 'google-compute-default-region' ; then echo "us-central1"
  elif has 'binauthz policy export'        ; then
    printf 'defaultAdmissionRule:\n  evaluationMode: ALWAYS_ALLOW\n  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG\n'
  elif has 'dataplex entries lookup'       ; then
    echo '{"entry":{"aspects":{"dryrun":{"data":{"protected-data-flag":"Yes"}}}}}'
  elif has 'config get-value'              ; then echo "us-central1"
  elif has '--format=json'                 ; then echo '[]'   # jangan bikin `| python3 -c json.load` meledak
  fi
  ;;

bq)
  # `bq ls` balik array, `bq show` balik objek. Bentuknya harus beda, kalau
  # tidak jq/python yang mengiterasi field-nya meledak dan itu bukan bug script.
  sub=""; target=""
  for a in "$@"; do
    [[ "$a" == -* ]] && continue
    [[ -z "$sub" ]] && { sub="$a"; continue; }   # subcommand: token non-flag pertama
    target="$a"                                  # target: token non-flag terakhir
  done
  if   [[ "$sub" == ls ]] ; then echo '[]'
  elif has 'prettyjson' || has '--format=json'; then
    # `bq show dataset` dan `bq show dataset.table` balik objek yang beda isinya.
    # Script mem-grep timePartitioning dari yang tabel, jadi bentuknya harus dibedakan.
    if [[ "$target" == *.* ]]; then
      echo '{"id":"dryrun:dataset.table","timePartitioning":{"type":"DAY","field":"date","expirationMs":"5184000000"}}'
    else
      echo '{"location":"US","id":"dryrun:dataset","access":[]}'
    fi
  fi
  ;;

kubectl)
  # `-o name` dipakai untuk loop drain/cordon node
  if   has '-o=name' || has '-o name'      ; then printf 'node/gke-dryrun-node-1\nnode/gke-dryrun-node-2\n'
  elif has 'jsonpath'                      ; then echo "10.0.0.1"
  elif has 'get pod'                       ; then printf 'NAME                    READY   STATUS    RESTARTS   AGE\nloadgenerator-000-abc   1/1     Running   0          1m\n'
  fi
  ;;

terraform)
  has '--version' && echo "Terraform v1.9.0"
  # `terraform init/plan/apply` cukup diam dan sukses
  ;;

curl)
  # Dua peran: unduh file, dan panggil REST API yang outputnya di-jq.
  # Kalau ada -o/-O, bikin filenya supaya langkah berikutnya tidak kehilangan file.
  out=""; prev=""
  for a in "$@"; do
    [[ "$prev" == "-o" ]] && out="$a"
    prev="$a"
  done
  if [[ -n "$out" ]]; then : >"$out"; return 0 2>/dev/null || exit 0; fi
  # JSON generik: cukup untuk `jq -r '.x // empty'` tanpa bikin jq error
  echo '{"infoTypes":[],"discoveryConfigs":[],"name":"dryrun","done":true}'
  ;;

git)
  # `git clone <url> [dir]` harus benar-benar bikin direktori, kalau tidak `cd` gagal
  if has 'clone'; then
    dir=""
    for a in "$@"; do [[ "$a" == http* || "$a" == git@* ]] && dir=$(basename "$a" .git); done
    for a in "$@"; do [[ "$a" != -* && "$a" != clone && "$a" != http* && "$a" != git@* ]] && dir="$a"; done
    [[ -n "$dir" ]] && mkdir -p "$dir"
  fi
  ;;

gh)
  # GitHub CLI: cukup jawab login dan username, sisanya diam dan sukses.
  if   has 'api user'          ; then echo "dryrun-user"
  elif has 'deploy-key list'   ; then :   # belum ada deploy key
  fi
  ;;

sleep)
  # dry-run tidak perlu benar-benar menunggu
  ;;

esac

exit 0

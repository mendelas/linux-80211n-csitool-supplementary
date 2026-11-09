#!/bin/bash
# Verification for "prepare once, record many": does skipping the driver reload keep each RX's
# inter-antenna pi pattern? Same installation, STATIC scene (nobody moves), back to back:
#   round k:  run_experiment.sh --resetup <label>_k<k>_reload    driver reload on every node + record
#             run_experiment.sh <label>_k<k>_keep<j>, j=1..KEEPS record only (same NIC init)
# If the hypothesis holds (compare in csi-track): all files of one round share one pi pattern per
# RX, and the NIC timestamp does not restart between them; rounds may differ from each other.
# usage: ./reload_ab.sh <label> <seconds> [rounds=2] [keeps=1]      (1 1 = the minimal pair)
#   KEEP_OPTS=--resetup-tx ./reload_ab.sh ...   if the TX cannot inject without its own setup
#   (LORCON), the keep runs then reload only the TX; the RX still keep their init.
# Writes the condition -> file list to ~/csi_data/<date>/<stamp>_<label>_reload_ab.txt
set -u
LABEL=${1:?usage: reload_ab.sh <label> <seconds> [rounds=2] [keeps=1]}
SECS=${2:?usage: reload_ab.sh <label> <seconds> [rounds=2] [keeps=1]}
ROUNDS=${3:-2}; KEEPS=${4:-1}; KEEP_OPTS=${KEEP_OPTS:-}
HERE=$(cd "$(dirname "$0")" && pwd)
LIST=$HOME/csi_data/$(date +%Y%m%d)/$(date +%Y%m%d_%H%M%S)_${LABEL}_reload_ab.txt
mkdir -p "$(dirname "$LIST")"
printf "condition\tlabel\tmerged\n" > "$LIST"

one() {   # one <condition> <label> [run_experiment options...]
  local cond=$1 lab=$2 rc mg; shift 2
  echo; echo "################ reload_ab: $lab ($cond) ################"
  "$HERE/run_experiment.sh" "$@" "$lab" "$SECS"; rc=$?
  [ "$rc" -eq 0 ] || { echo "!! reload_ab: $lab ended with rc=$rc; stopping. List so far: $LIST"; exit "$rc"; }
  mg=$(ls -t "$HOME"/csi_data/*/*_"$lab"_merged.bin 2>/dev/null | head -1)
  printf "%s\t%s\t%s\n" "$cond" "$lab" "${mg:-MISSING}" >> "$LIST"
}

for k in $(seq 1 "$ROUNDS"); do
  one reload "${LABEL}_k${k}_reload" --resetup
  # shellcheck disable=SC2086  # KEEP_OPTS is empty or one flag
  for j in $(seq 1 "$KEEPS"); do one keep "${LABEL}_k${k}_keep$j" $KEEP_OPTS; done
done
echo; echo "=== reload_ab done: $LIST ==="; column -t -s $'\t' "$LIST" 2>/dev/null || cat "$LIST"

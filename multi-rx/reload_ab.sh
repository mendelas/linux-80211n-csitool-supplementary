#!/bin/bash
# Verification for "prepare once, record many": does skipping the driver reload keep each RX's
# inter-antenna pi pattern? Same installation, STATIC scene (nobody moves), back to back:
#   round k:  run_experiment.sh --resetup <base>_k<k>_reload.json   driver reload on every node + record
#             run_experiment.sh <base>_k<k>_keep<j>.json, j=1..KEEPS record only (same NIC init)
# If the hypothesis holds (compare in csi-track): all files of one round share one pi pattern per
# RX, and the NIC timestamp does not restart between them; rounds may differ from each other.
#
# usage: ./reload_ab.sh experiments/<YYYYMMDD>/<base>.json [rounds=2] [keeps=1]   ("1 1" = minimal pair)
#   <base>.json is a normal, today's experiment config with trajectory.type "static". It is not
#   recorded itself: every recording gets its own config (rule 2026-11-07), written next to it as
#   <base>_k<k>_reload.json / <base>_k<k>_keep<j>.json (label replaced, purpose_note extended,
#   "reload_ab": {round, condition}). Existing files are never overwritten.
#   KEEP_OPTS=--resetup-tx ./reload_ab.sh ...   if the TX cannot inject without its own setup
#   (LORCON): the keep runs then reload only the TX; the RX still keep their init.
# Writes the condition -> recording list to ~/csi_data/<date>/<stamp>_<base>_reload_ab.txt
set -u
BASE=${1:?usage: reload_ab.sh experiments/<YYYYMMDD>/<base>.json [rounds=2] [keeps=1]}
ROUNDS=${2:-2}; KEEPS=${3:-1}; KEEP_OPTS=${KEEP_OPTS:-}
HERE=$(cd "$(dirname "$0")" && pwd)
"$HERE/exp_meta.py" check "$BASE" >/dev/null || exit 1
BLABEL=$(basename "$BASE" .json); CDIR=$(dirname "$BASE")

# The per-recording configs, all written (and checked) before anything is recorded.
PLAN=()   # "condition round label" in recording order
for k in $(seq 1 "$ROUNDS"); do
  PLAN+=("reload $k ${BLABEL}_k${k}_reload")
  for j in $(seq 1 "$KEEPS"); do PLAN+=("keep $k ${BLABEL}_k${k}_keep$j"); done
done
python3 - "$BASE" "$CDIR" "$ROUNDS" "$KEEPS" "${PLAN[@]}" <<'EOF' || exit 1
import json, os, sys
base, cdir, rounds, keeps, plan = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5:]
exp = json.load(open(base))
if exp.get('trajectory', {}).get('type') != 'static':
    sys.exit(f'{base}: trajectory.type must be "static" for reload_ab')
out = []
for i, pc in enumerate(plan):
    cond, rnd, lab = pc.split()
    rnd = int(rnd)
    p = os.path.join(cdir, lab + '.json')
    if os.path.exists(p):
        sys.exit(f'{p} already exists; use another base label (nothing was written)')
    e = dict(exp, label=lab, session_order=i + 1)
    e['purpose_note'] = (exp['purpose_note'] + f' [reload_ab {os.path.basename(base)}: round {rnd}, '
                         + ('driver reload on every node (--resetup)' if cond == 'reload'
                            else 'no reload, same NIC init as this round\'s reload') + ']')
    e['reload_ab'] = {'base': os.path.basename(base), 'round': rnd, 'condition': cond,
                      'rounds': int(rounds), 'keeps_per_round': int(keeps)}
    out.append((p, e))
for p, e in out:
    with open(p, 'w') as f:
        json.dump(e, f, ensure_ascii=False, indent=2)
        f.write('\n')
    print('  config:', p)
EOF

LIST=$HOME/csi_data/$(date +%Y%m%d)/$(date +%Y%m%d_%H%M%S)_${BLABEL}_reload_ab.txt
mkdir -p "$(dirname "$LIST")"
printf "condition\tlabel\tmerged\n" > "$LIST"
for pc in "${PLAN[@]}"; do
  read -r cond _ lab <<<"$pc"
  if [ "$cond" = reload ]; then opts=--resetup; else opts=$KEEP_OPTS; fi
  echo; echo "################ reload_ab: $lab ($cond) ################"
  # shellcheck disable=SC2086  # opts is empty or one flag
  "$HERE/run_experiment.sh" $opts "$CDIR/$lab.json"; rc=$?
  [ "$rc" -eq 0 ] || { echo "!! reload_ab: $lab ended with rc=$rc; stopping. List so far: $LIST"; exit "$rc"; }
  mg=$(ls -t "$HOME"/csi_data/*/*_"$lab"/*_"$lab"_merged.bin 2>/dev/null | head -1)
  printf "%s\t%s\t%s\n" "$cond" "$lab" "${mg:-MISSING}" >> "$LIST"
done
echo; echo "=== reload_ab done: $LIST ==="; column -t -s $'\t' "$LIST" 2>/dev/null || cat "$LIST"
echo "The generated configs in $CDIR belong to these recordings: commit them with the day's configs."

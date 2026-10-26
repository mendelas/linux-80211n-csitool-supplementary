#!/bin/bash
# Run the test plan in plan.sh in order: for each device, for each frequency case, one
# run_test.sh. Pauses before every run so the device / laptop can be prepared; the operator
# presses Enter (s = skip this run, q = quit). Runs are independent: each writes its own
# tx/rx logs, .csi and report under ~/csi_data/YYYYMMDD/.
# usage: ./run_plan.sh [dev ...]
#   ./run_plan.sh          # every device in plan.sh DEVICES, in order
#   ./run_plan.sh 2        # only Dev2 (all cases)
#   ./run_plan.sh 2 3      # Dev2 then Dev3
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
S0=${SECS:-}                              # SECS=10 ./run_plan.sh  -> short runs (dry run), overrides plan.sh
source "$HERE/plan.sh"                    # -> NAME_PREFIX DEVICES CASES SECS
SECS=${S0:-$SECS}
sel=("$@"); list=()
for d in "${DEVICES[@]}"; do
  num=${d%%:*}; nodeN=${d#*:}; [ "$nodeN" = "$d" ] && nodeN=
  if [ ${#sel[@]} -gt 0 ]; then keep=0; for s in "${sel[@]}"; do [ "$s" = "$num" ] && keep=1; done; [ "$keep" = 1 ] || continue; fi
  list+=("$num:$nodeN")
done
[ ${#list[@]} -gt 0 ] || { echo "!! no matching device; plan.sh DEVICES=(${DEVICES[*]})"; exit 1; }
total=$(( ${#list[@]} * ${#CASES[@]} )); i=0
echo "plan: ${#list[@]} device(s) x ${#CASES[@]} case(s) = $total run(s), ${SECS}s recording each"
for d in "${list[@]}"; do
  num=${d%%:*}; nodeN=${d#*:}
  name="${NAME_PREFIX}-Dev${num}"
  for c in "${CASES[@]}"; do
    i=$((i + 1)); set -- $c          # "<MHz> <BW>"
    echo; echo "########## run $i/$total : $name   ${1} MHz / ${2} MHz   TX laptop: ${nodeN:-hosts.sh TX_NODE} ##########"
    read -r -p "Prepare Dev${num} as TX, then press Enter to start  (s = skip, q = quit): " ans
    case "$ans" in q|Q) echo "quit"; exit 0;; s|S) echo "skipped"; continue;; esac
    if [ -n "$nodeN" ]; then TX_NODE=$nodeN "$HERE/run_test.sh" "$1" "$2" "$name" "$SECS"
    else "$HERE/run_test.sh" "$1" "$2" "$name" "$SECS"; fi
    rc=$?
    if [ "$rc" -ne 0 ]; then
      read -r -p "run_test.sh exited with $rc. Enter = next run, q = quit: " ans
      case "$ans" in q|Q) exit "$rc";; esac
    fi
  done
done
echo; echo "plan finished. Reports: ~/csi_data/$(date +%Y%m%d)/*_report.txt"

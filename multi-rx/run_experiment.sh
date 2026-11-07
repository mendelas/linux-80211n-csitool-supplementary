#!/bin/bash
# Run one multi-RX CSI experiment from the control PC (pull model).
# usage: ./run_experiment.sh experiments/<YYYYMMDD>/<label>.json
#   EVERY recording needs its own experiment config (rule 2026-11-07, experiments/README.md):
#   label, seconds (how long to RECORD after CSI flows; Enter stops early), TX rate/streams/antennas,
#   setup id (experiments/setups/<id>.json: positions, angles, antenna states), trajectory, purpose.
#   Without it the script refuses to run. The config + setup + radio + hosts + beep times + how the
#   run ended + the operator's note go to <stamp>_<label>_meta.json next to the .bin files.
# Which machine is TX and which are RX (any number) comes from hosts.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
EXP=${1:-}
if [ $# -ne 1 ] || [ ! -f "$EXP" ] || [ "${EXP##*.}" != "json" ]; then
  echo "usage: ./run_experiment.sh experiments/<YYYYMMDD>/<label>.json"
  echo "  収録ごとに実験 config が必須 (書き方: experiments/README.md)。<label> <秒数> の形は廃止 (2026-11-07)。"
  exit 1
fi
CHK=$("$HERE/exp_meta.py" check "$EXP") || exit 1
read -r LABEL SECS CFG_RATE <<< "$CHK"
source "$HERE/hosts.sh"      # -> TX, RXS[] (rx_id = index)

# ===== radio settings (edit for your setup) =====
CH=157; BW=HT40+; PAYLOAD=100; DELAY=1000   # DEFAULT: ch157 HT40+ = 157+161, center 5795MHz 40MHz (UNII-3; needs 5.8GHz experimental license + anechoic chamber)
# TX rate comes from the experiment config (tx.rate): 0x4901 = ant A only, HT40, MCS1 (1 stream);
# 0x1c911 = ant A+B+C, HT40, MCS17 (3 streams -> Ntx=3 CSI, TX-side AoD; licence confirmed 2026-11-05).
if [ -n "${RATE:-}" ] && [ "$RATE" != "$CFG_RATE" ]; then
  echo "RATE=$RATE (環境変数) が config の tx.rate $CFG_RATE と違う。rate は config で指定する。"; exit 1
fi
RATE=$CFG_RATE
IF=wlan1
TXPWR=15   # dBm, i.e. the card's max (EEPROM ceiling is ~15-16 dBm).
           # This is the SETTING, not the radiated power: the 5300 tops out below it, and
           # the antenna-port output at 15 was MEASURED under the 25 mW 指定事項 of the
           # 5.8GHz experimental licence. So max setting is still inside the licence.
REMOTE=~/linux-80211n-csitool-supplementary
DAYDIR=$HOME/csi_data/$(date +%Y%m%d)
STARTUP_MARGIN=180        # extra injection seconds to cover 5GHz CSI startup
# ================================================
NRX=${#RXS[@]}
[ "$NRX" -ge 1 ] || { echo "hosts.sh: RX_NODES is empty"; exit 1; }
for r in "${RXS[@]}"; do [ "$r" = "$TX" ] && { echo "hosts.sh: $r is both TX and RX"; exit 1; }; done
STAMP=$(date +%Y%m%d_%H%M%S)
# One directory per recording (2026-11-07): ~/csi_data/<YYYYMMDD>/<stamp>_<label>/ holds the rxN.bin,
# the merged.bin and the meta.json. An aborted retake is removed by deleting its whole directory.
OUTDIR=$DAYDIR/${STAMP}_${LABEL}
ls -d "$DAYDIR"/*_"${LABEL}" >/dev/null 2>&1 && \
  echo "!!! 今日すでに $LABEL の収録がある: $(ls -d "$DAYDIR"/*_"${LABEL}" | tr '\n' ' ')。撮り直しなら、中断した回のディレクトリごと消すこと。"
mkdir -p "$OUTDIR"
R=(); for i in $(seq 0 $((NRX-1))); do R+=("$OUTDIR/${STAMP}_${LABEL}_rx$i.bin"); done
MG=$OUTDIR/${STAMP}_${LABEL}_merged.bin
META=$OUTDIR/${STAMP}_${LABEL}_meta.json
NPKTS=$(( (SECS + STARTUP_MARGIN) * 1000000 / DELAY ))
echo "TX=$TX   RX=${RXS[*]}   ($NRX RX)   config=$EXP   rate=$RATE   out=$OUTDIR"
CH=$CH BW=$BW RATE=$RATE TXPWR=$TXPWR PAYLOAD=$PAYLOAD DELAY=$DELAY NPKTS=$NPKTS IF=$IF TX=$TX \
  RXS="${RXS[*]}" RFILES="${R[*]}" MG=$MG "$HERE/exp_meta.py" start "$EXP" "$META" "$STAMP" || exit 1
# Timed events on the control-PC clock (CLOCK_REALTIME = the clock of the merged records' t).
# The start beep is audible, so a video of the walk can be synced to the CSI with it.
ev() { "$HERE/exp_meta.py" event "$META" "$1" "$(date +%s.%N)"; }
ev script_start

# Stop everything this script starts: injection on TX, csi_stream on every RX, csi_recv here.
# Used by step 5 AND by the Ctrl-C trap. Without the trap, Ctrl-C only kills this script:
# bash starts background jobs with SIGINT ignored, so the ssh|csi_recv pipelines survive,
# the remote csi_stream keeps streaming into the rxN.bin files and random_packets keeps
# transmitting until NPKTS runs out (observed 2026-10-23: three aborted runs kept growing
# for 18 minutes and injected on top of each other).
P=(); PT=
stop_all() {
  ssh -o ConnectTimeout=5 "$TX" "sudo pkill -f random_packets" 2>/dev/null
  for r in "${RXS[@]}"; do ssh -o ConnectTimeout=5 "$r" "sudo pkill -f csi_stream" 2>/dev/null; done
  kill "${P[@]}" $PT 2>/dev/null
  # `wait <pid of a pipeline job>` waits for the WHOLE pipeline, i.e. also the ssh client.
  # An ssh whose remote side was already killed can hang in the channel close (seen
  # 2026-10-29: walk_sq1 sat in wait for 5 min). Kill our ssh children, hard if needed.
  pkill -P $$ -x ssh 2>/dev/null; sleep 1; pkill -9 -P $$ -x ssh 2>/dev/null
  wait "${P[@]}" $PT 2>/dev/null
}
merge_all() {
  echo "=== [6/6] merge ==="
  "$HERE/csi_merge" "$MG" "${R[@]}"
  "$HERE/read_merged" "$MG" | tail -2
  echo ""
  echo "=== DONE ==="
  echo "  merged : $MG"
  echo "  per-RX : ${R[*]}"
  echo "  meta   : $META"
  echo "  check  : ./csi_check.py $MG"
}
# The operator's note on what actually happened (someone entered, the walker stopped, ...).
ask_note() {
  if [ -t 0 ]; then
    read -r -p "Note (what happened / anything unusual; Enter = none): " NOTE
    "$HERE/exp_meta.py" set "$META" operator_note "$NOTE"
  fi
}
# Ctrl-C: stop everything, and still merge whatever was recorded (a walking capture ended
# with Ctrl-C instead of Enter is valid data).
on_interrupt() {
  # Run the cleanup ONCE: further Ctrl-C presses are ignored until it is done (2026-11-07: without
  # this, each extra Ctrl-C restarted the handler, and Ctrl-C at the note prompt looped for 90 s).
  trap '' INT TERM
  echo; echo "!!! interrupted: stopping injection + streams on every node"; ev interrupted; stop_all
  ev streams_stopped
  "$HERE/exp_meta.py" set "$META" ended_by interrupted
  if [ -s "${R[0]}" ]; then merge_all; fi
  trap - INT TERM          # Ctrl-C at the note prompt now just exits (the note stays empty)
  ask_note
  exit 130
}
trap on_interrupt INT TERM

echo "=== [0/6] kill leftovers from a previous aborted run ==="
stop_all

echo "=== [1/6] RX radio setup (ch$CH $BW) ==="
for r in "${RXS[@]}"; do ssh "$r" "~/rx_setup.sh $CH $BW"; done

echo "=== [2/6] start RX streams -> control PC ==="
P=()
for i in $(seq 0 $((NRX-1))); do
  ssh "${RXS[$i]}" "sudo $REMOTE/multi-rx/csi_stream /dev/stdout" 2>/dev/null | "$HERE/csi_recv" "$i" "${R[$i]}" &
  P+=($!)
done
sleep 2

# ★ TX setup + injection MUST be one ssh session (LORCON fails across sessions)
echo "=== [3/6] TX setup + inject in ONE ssh ($NPKTS pkts, ${TXPWR}dBm) ==="
ssh "$TX" "~/tx_setup.sh $CH $BW $RATE $IF $TXPWR; cd $REMOTE/injection && sudo ./random_packets $NPKTS $PAYLOAD 1 $DELAY >/dev/null 2>&1" &
PT=$!

echo "=== [4/6] waiting for CSI to flow on ALL $NRX RX (up to 120s) ==="
prev=(); for i in $(seq 0 $((NRX-1))); do prev+=(0); done
ready=0
for t in $(seq 1 120); do
  sleep 1
  ok=1; line=""
  for i in $(seq 0 $((NRX-1))); do
    s=$(stat -c%s "${R[$i]}" 2>/dev/null || echo 0)
    { [ "$s" -gt "${prev[$i]}" ] && [ "$s" -gt 2000 ]; } || ok=0
    prev[$i]=$s
    line+=$(printf "rx%d=%8s  " "$i" "$s")
  done
  printf "\r    %sbytes  (%ss)   " "$line" "$t"
  [ "$ok" -eq 1 ] && { ready=1; break; }
done
echo
if [ "$ready" -ne 1 ]; then
  echo "!!!!! WARNING: CSI did NOT start on every RX."
  echo "!!!!! Check: same channel on all / clear channel / CSI firmware active / TX injecting."
fi

echo ""
echo "##################################################################"
echo "#                                                                #"
echo "#      >>>>>   START THE EXPERIMENT NOW   <<<<<                   #"
printf  "#              recording for %-4s seconds                        #\n" "$SECS"
echo "#                                                                #"
echo "##################################################################"
ev start_beep
printf '\a'; sleep 0.3; printf '\a'

# Enter stops early: walking captures must stop the moment the walk ends (a static tail
# skews the evaluation, 08-05 note). read returns 0 on Enter, >128 after its 1 s timeout
# (already waited), 1 on EOF when there is no tty -> sleep instead.
T0=$(date +%s)
ENDED_BY=timer
for r in $(seq "$SECS" -1 1); do
  printf "\r    recording... %4ss left   (Enter = stop now)   " "$r"
  read -r -t 1 _ && { ENDED_BY=enter; break; }
  [ $? -gt 128 ] || sleep 1
done
ev record_end
REC_S=$(( $(date +%s) - T0 ))
echo; echo "    recorded $REC_S s"

echo "=== [5/6] stop streams & injection ==="
stop_all
ev streams_stopped
"$HERE/exp_meta.py" set "$META" ended_by "$ENDED_BY" recorded_s "$REC_S" csi_started_on_all_rx "$ready"
# End beep (3x), AFTER the streams are stopped: a walker keeps walking until the timer ends and
# stops on the beep, so neither a static tail (skews the evaluation) nor the walk back to press
# Enter is recorded.
printf '\a'; sleep 0.3; printf '\a'; sleep 0.3; printf '\a'
trap - INT TERM
merge_all
ask_note

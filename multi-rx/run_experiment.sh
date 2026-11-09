#!/bin/bash
# Run one multi-RX CSI experiment from the control PC (pull model).
# usage: ./run_experiment.sh --prepare                                  once per installation
#        ./run_experiment.sh [--resetup | --resetup-tx] experiments/<YYYYMMDD>/<label>.json
#   EVERY recording needs its own experiment config (rule 2026-11-07, experiments/README.md):
#   label, seconds (how long to RECORD after CSI flows; Enter stops early), TX rate/streams/antennas,
#   setup id (experiments/setups/<id>.json: positions, angles, antenna states), trajectory, purpose.
#   Without it the script refuses to run. The config + setup + radio + hosts + beep times + how the
#   run ended go to ~/csi_data/<YYYYMMDD>/<stamp>_<label>/<stamp>_<label>_meta.json with the .bin files.
#   A recording does NOT reload iwlwifi: it checks every radio (radio_check.sh) and only starts
#   csi_stream / random_packets. A reload re-initializes the 5300 and moves one RX chain's phase
#   by a multiple of pi, so prepare once and record many times on the same NIC init.
#   --prepare     reload + monitor + channel on every node (rx_setup.sh / tx_setup.sh), check, exit.
#                 No config: the TX is set to 0x4901 and each recording re-applies its tx.rate.
#   --resetup     the old behaviour: prepare every node again, then record
#   --resetup-tx  prepare only the TX again, inside the injection ssh (fallback if LORCON will
#                 not open a mon0 prepared in an earlier ssh session); the RX keep their init
#   The meta records which of these ran (result.radio_prep) and each node's check line, whose
#   ifindex changes on every driver reload.
# Which machine is TX and which are RX (any number) comes from hosts.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
MODE=record; RESETUP_RX=0; RESETUP_TX=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prepare)    MODE=prepare ;;
    --resetup)    RESETUP_RX=1; RESETUP_TX=1 ;;
    --resetup-tx) RESETUP_TX=1 ;;
    -*)           echo "unknown option: $1"; exit 2 ;;
    *)            break ;;
  esac
  shift
done
EXP=${1:-}
if [ "$MODE" = prepare ]; then
  [ $# -eq 0 ] || { echo "usage: ./run_experiment.sh --prepare   (no experiment config)"; exit 1; }
  LABEL=prepare; SECS=0; CFG_RATE=0x4901
else
  if [ $# -ne 1 ] || [ ! -f "$EXP" ] || [ "${EXP##*.}" != "json" ]; then
    echo "usage: ./run_experiment.sh [--resetup | --resetup-tx] experiments/<YYYYMMDD>/<label>.json"
    echo "       ./run_experiment.sh --prepare     (設置ごとに1回: ドライバ再読込・monitor・チャネル)"
    echo "  収録ごとに実験 config が必須 (書き方: experiments/README.md)。<label> <秒数> の形は廃止 (2026-11-07)。"
    exit 1
  fi
  CHK=$("$HERE/exp_meta.py" check "$EXP") || exit 1
  read -r LABEL SECS CFG_RATE <<< "$CHK"
fi
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

# Prepare = driver reload + monitor + channel (once per installation, or --resetup).
prepare_rx() { for r in "${RXS[@]}"; do ssh "$r" "~/rx_setup.sh $CH $BW"; done; }
# Read-only check of every radio. radio_check.sh is piped from here, so nodes need no copy.
# usage: check_radios rx|all     (rx: the TX is about to be prepared inside the injection ssh)
# Leaves "radio_<node> <its check line>" pairs in RC_LINES for the meta.
RC_LINES=()
check_radios() {
  local bad=0 i out
  for i in $(seq 0 $((NRX-1))); do
    echo "  rx$i ${RXS[$i]}"
    out=$(ssh -o ConnectTimeout=5 "${RXS[$i]}" "bash -s -- rx $CH $BW $IF" < "$HERE/radio_check.sh") || bad=1
    echo "$out"; RC_LINES+=("radio_rx$i" "$(sed -n '1s/^ *//p' <<<"$out")")
  done
  if [ "$1" = all ]; then
    echo "  tx  $TX"
    out=$(ssh -o ConnectTimeout=5 "$TX" "bash -s -- tx $CH $BW" < "$HERE/radio_check.sh") || bad=1
    echo "$out"; RC_LINES+=("radio_tx" "$(sed -n '1s/^ *//p' <<<"$out")")
  fi
  return $bad
}

if [ "$MODE" = prepare ]; then
  echo "=== PREPARE (once per installation): driver reload + monitor + ch$CH $BW on every node ==="
  # leftovers of an aborted run first, as stop_all does
  ssh -o ConnectTimeout=5 "$TX" "sudo pkill -f random_packets" 2>/dev/null
  for r in "${RXS[@]}"; do ssh -o ConnectTimeout=5 "$r" "sudo pkill -f csi_stream" 2>/dev/null; done
  prepare_rx
  ssh "$TX" "~/tx_setup.sh $CH $BW $RATE $IF $TXPWR"
  echo "=== check ==="
  check_radios all; ok=$?
  # one line per prepare, so a recording's ifindex (in its meta) can be traced to its prepare
  mkdir -p "$DAYDIR"
  echo "$(date +%FT%T) prepare ch$CH $BW ok=$([ $ok -eq 0 ] && echo yes || echo NO) ${RC_LINES[*]}" >> "$DAYDIR/radio_prepare.log"
  [ $ok -eq 0 ] || { echo "!!!!! not ready after prepare (see above)"; exit 1; }
  echo "prepared (logged in $DAYDIR/radio_prepare.log)."
  echo "Record as often as needed on this NIC init:  ./run_experiment.sh experiments/<YYYYMMDD>/<label>.json"
  exit 0
fi

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
# No note prompt at the end (removed 2026-11-07, user: it gets in the way; notes are written when
# the data is reviewed on the other PC, into the meta's result.operator_note).
# Ctrl-C: stop everything, and still merge whatever was recorded (a walking capture ended
# with Ctrl-C instead of Enter is valid data).
on_interrupt() {
  # Run the cleanup ONCE: further Ctrl-C presses are ignored until it is done (2026-11-07: without
  # this, each extra Ctrl-C restarted the handler).
  trap '' INT TERM
  echo; echo "!!! interrupted: stopping injection + streams on every node"; ev interrupted; stop_all
  ev streams_stopped
  "$HERE/exp_meta.py" set "$META" ended_by interrupted
  if [ -s "${R[0]}" ]; then merge_all; fi
  exit 130
}
trap on_interrupt INT TERM

echo "=== [0/6] kill leftovers from a previous aborted run ==="
stop_all

if [ "$RESETUP_RX" = 1 ]; then
  echo "=== [1/6] RX radio setup (ch$CH $BW): driver reload (--resetup), then check ==="
  prepare_rx
else
  echo "=== [1/6] check radios are prepared (ch$CH $BW); no driver reload ==="
fi
if [ "$RESETUP_TX" = 1 ]; then SCOPE=rx; else SCOPE=all; fi
if ! check_radios $SCOPE; then
  echo "!!!!! radios not prepared (see above). Recordings no longer reload the driver."
  echo "!!!!! prepare once for this installation:  ./run_experiment.sh --prepare"
  echo "!!!!! or prepare + record in one go:       ./run_experiment.sh --resetup $EXP"
  # Nothing was recorded: drop this run's directory, which holds only the meta written above.
  rm -f "$META"; rmdir "$OUTDIR" 2>/dev/null
  exit 1
fi
if [ "$RESETUP_RX" = 1 ]; then PREP=resetup; elif [ "$RESETUP_TX" = 1 ]; then PREP=resetup_tx; else PREP=check; fi
"$HERE/exp_meta.py" set "$META" radio_prep "$PREP" "${RC_LINES[@]}"

echo "=== [2/6] start RX streams -> control PC ==="
P=()
for i in $(seq 0 $((NRX-1))); do
  ssh "${RXS[$i]}" "sudo $REMOTE/multi-rx/csi_stream /dev/stdout" 2>/dev/null | "$HERE/csi_recv" "$i" "${R[$i]}" &
  P+=($!)
done
sleep 2

# ★ TX setup + injection MUST be one ssh session (LORCON fails across sessions, cadcc26).
#   Normal: radio_check.sh tx (check; txpower + monitor_tx_rate = the config's tx.rate; no reload)
#   && random_packets. --resetup / --resetup-tx: the full tx_setup.sh (driver reload) in that session.
#   random_packets' stderr is kept so "Error opening LORCON interface" is visible.
INJECT="cd $REMOTE/injection && sudo ./random_packets $NPKTS $PAYLOAD 1 $DELAY >/dev/null"
if [ "$RESETUP_TX" = 1 ]; then
  echo "=== [3/6] TX setup (driver reload) + inject in ONE ssh ($NPKTS pkts, ${TXPWR}dBm) ==="
  ssh "$TX" "~/tx_setup.sh $CH $BW $RATE $IF $TXPWR; $INJECT" &
else
  echo "=== [3/6] TX check + txpower/rate (no reload) + inject in ONE ssh ($NPKTS pkts, ${TXPWR}dBm) ==="
  ssh "$TX" "bash -s -- tx $CH $BW $RATE $TXPWR && $INJECT" < "$HERE/radio_check.sh" &
fi
PT=$!

echo "=== [4/6] waiting for CSI to flow on ALL $NRX RX (up to 120s) ==="
prev=(); for i in $(seq 0 $((NRX-1))); do prev+=(0); done
ready=0
for t in $(seq 1 120); do
  sleep 1
  if ! kill -0 "$PT" 2>/dev/null; then
    echo; echo "!!!!! the TX ssh ended before CSI flowed: TX not ready or injection failed (output above)."
    echo "!!!!! 'Error opening LORCON interface' -> LORCON wants mon0 set up in the same ssh: add --resetup-tx"
    echo "!!!!! nothing usable was recorded: delete $OUTDIR"
    stop_all; "$HERE/exp_meta.py" set "$META" ended_by tx_session_ended; exit 1
  fi
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

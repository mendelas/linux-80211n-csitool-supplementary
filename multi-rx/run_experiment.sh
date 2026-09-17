#!/bin/bash
# Run one multi-RX CSI experiment from the control PC (pull model).
# usage: ./run_experiment.sh <label> <experiment_seconds>
#   <experiment_seconds> = how long to RECORD after CSI is confirmed flowing.
# Which machine is TX and which are RX (any number) comes from hosts.sh.
set -u
LABEL=${1:-exp}; SECS=${2:-60}
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/hosts.sh"      # -> TX, RXS[] (rx_id = index)

# ===== radio settings (edit for your setup) =====
CH=157; BW=HT40+; RATE=0x4901; PAYLOAD=100; DELAY=1000   # DEFAULT: ch157 HT40+ = 157+161, center 5795MHz 40MHz (UNII-3; needs 5.8GHz experimental license + anechoic chamber)
IF=wlan1
TXPWR=15   # dBm, i.e. the card's max (EEPROM ceiling is ~15-16 dBm).
           # This is the SETTING, not the radiated power: the 5300 tops out below it, and
           # the antenna-port output at 15 was MEASURED under the 25 mW 指定事項 of the
           # 5.8GHz experimental licence. So max setting is still inside the licence.
REMOTE=~/linux-80211n-csitool-supplementary
OUTDIR=$HOME/csi_data/$(date +%Y%m%d)
STARTUP_MARGIN=180        # extra injection seconds to cover 5GHz CSI startup
# ================================================
NRX=${#RXS[@]}
[ "$NRX" -ge 1 ] || { echo "hosts.sh: RX_NODES is empty"; exit 1; }
for r in "${RXS[@]}"; do [ "$r" = "$TX" ] && { echo "hosts.sh: $r is both TX and RX"; exit 1; }; done
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d_%H%M%S)
R=(); for i in $(seq 0 $((NRX-1))); do R+=("$OUTDIR/${STAMP}_${LABEL}_rx$i.bin"); done
MG=$OUTDIR/${STAMP}_${LABEL}_merged.bin
NPKTS=$(( (SECS + STARTUP_MARGIN) * 1000000 / DELAY ))
echo "TX=$TX   RX=${RXS[*]}   ($NRX RX)"

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
printf '\a'; sleep 0.3; printf '\a'

for r in $(seq "$SECS" -1 1); do printf "\r    recording... %4ss left    " "$r"; sleep 1; done
echo

echo "=== [5/6] stop streams & injection ==="
ssh "$TX" "sudo pkill -f random_packets" 2>/dev/null
for r in "${RXS[@]}"; do ssh "$r" "sudo pkill -f csi_stream" 2>/dev/null; done
kill "${P[@]}" $PT 2>/dev/null; wait "${P[@]}" 2>/dev/null

echo "=== [6/6] merge ==="
"$HERE/csi_merge" "$MG" "${R[@]}"
"$HERE/read_merged" "$MG" | tail -2
echo ""
echo "=== DONE ==="
echo "  merged : $MG"
echo "  per-RX : ${R[*]}"

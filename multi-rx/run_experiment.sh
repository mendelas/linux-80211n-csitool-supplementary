#!/bin/bash
# Run one multi-RX CSI experiment from the control PC (pull model).
# usage: ./run_experiment.sh <label> <experiment_seconds>
#   <experiment_seconds> = how long to RECORD after CSI is confirmed flowing.
set -u
LABEL=${1:-exp}; SECS=${2:-60}

# ===== settings (edit for your setup) =====
RX0=kota@192.168.100.11
RX1=kota@192.168.100.12
TX=kota@192.168.100.13
CH=48; BW=HT20; RATE=0x4101; PAYLOAD=100; DELAY=1000   # MAIN: ch48 5.24GHz 20MHz (worst-case, license-free W52, WiTraj-comparable)
REMOTE=~/linux-80211n-csitool-supplementary
HERE=$(cd "$(dirname "$0")" && pwd)
OUTDIR=$HOME/csi_data/$(date +%Y%m%d)
STARTUP_MARGIN=180        # extra injection seconds to cover 5GHz CSI startup
# ==========================================
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d_%H%M%S)
R0=$OUTDIR/${STAMP}_${LABEL}_rx0.bin
R1=$OUTDIR/${STAMP}_${LABEL}_rx1.bin
MG=$OUTDIR/${STAMP}_${LABEL}_merged.bin
NPKTS=$(( (SECS + STARTUP_MARGIN) * 1000000 / DELAY ))

echo "=== [1/6] RX radio setup (ch$CH $BW) ==="
ssh "$RX0" "~/rx_setup.sh $CH $BW"
ssh "$RX1" "~/rx_setup.sh $CH $BW"

echo "=== [2/6] start RX streams -> control PC ==="
ssh "$RX0" "sudo $REMOTE/multi-rx/csi_stream /dev/stdout" 2>/dev/null | "$HERE/csi_recv" 0 "$R0" &
P0=$!
ssh "$RX1" "sudo $REMOTE/multi-rx/csi_stream /dev/stdout" 2>/dev/null | "$HERE/csi_recv" 1 "$R1" &
P1=$!
sleep 2

# ★ TX setup + injection MUST be one ssh session (LORCON fails across sessions)
echo "=== [3/6] TX setup + inject in ONE ssh ($NPKTS pkts) ==="
ssh "$TX" "~/tx_setup.sh $CH $BW $RATE; cd $REMOTE/injection && sudo ./random_packets $NPKTS $PAYLOAD 1 $DELAY >/dev/null 2>&1" &
PT=$!

echo "=== [4/6] waiting for CSI to flow on BOTH RX (up to 120s) ==="
prev0=0; prev1=0; ready=0
for i in $(seq 1 120); do
  sleep 1
  s0=$(stat -c%s "$R0" 2>/dev/null || echo 0)
  s1=$(stat -c%s "$R1" 2>/dev/null || echo 0)
  printf "\r    rx0=%8s bytes   rx1=%8s bytes   (%ss)   " "$s0" "$s1" "$i"
  if [ "$s0" -gt "$prev0" ] && [ "$s1" -gt "$prev1" ] && [ "$s0" -gt 2000 ] && [ "$s1" -gt 2000 ]; then
    ready=1; break
  fi
  prev0=$s0; prev1=$s1
done
echo
if [ "$ready" -ne 1 ]; then
  echo "!!!!! WARNING: CSI did NOT start on both RX."
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
ssh "$TX"  "sudo pkill -f random_packets" 2>/dev/null
ssh "$RX0" "sudo pkill -f csi_stream"     2>/dev/null
ssh "$RX1" "sudo pkill -f csi_stream"     2>/dev/null
kill $P0 $P1 $PT 2>/dev/null; wait $P0 $P1 2>/dev/null

echo "=== [6/6] merge ==="
"$HERE/csi_merge" "$MG" "$R0" "$R1"
"$HERE/read_merged" "$MG" | tail -2
echo ""
echo "=== DONE ==="
echo "  merged : $MG"
echo "  per-RX : $R0 , $R1"

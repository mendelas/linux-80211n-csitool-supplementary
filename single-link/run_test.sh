#!/bin/bash
# Control-PC driver for ONE 1 TX -> 1 RX comprehensive-test run (実験試験局 application).
# Pull model like multi-rx/run_experiment.sh: this PC ssh-es into the TX and the RX laptop
# (multi-rx/hosts.sh: TX_NODE and RX_NODES[0]; override with TX_NODE= / RX_NODE= env), sets up
# both radios with the nodes' ~/tx_setup.sh / ~/rx_setup.sh and runs
#   RX : csi_stream (node) --ssh--> csi_report -i -p (here) : raw CSI saved HERE + 1 line / s
#   TX : tx_setup.sh ; tx_inject -p   (node, ONE ssh)      : 1 line / s
# Every line is time-stamped HERE (one clock for both sides) and goes to the terminal and to
#   ~/csi_data/YYYYMMDD/<stamp>_<name>_<MHz>MHz_<BW>MHz_{tx,rx}.log  (+ _rx.csi, + _report.txt)
# The report (TX block, then RX block) is printed at the end: that is what goes into the
# application. Recording = <seconds> AFTER CSI is confirmed flowing (5 GHz CSI can take up to
# a minute to start); TX is stopped right after.
#
# usage: ./run_test.sh <MHz|ch> <20|40|HT20|HT40+|HT40-> [display name] [seconds]
#   ./run_test.sh 5795 40 NICT-ISAC-Dev1 60
#   TX_NODE=14 RX_NODE=11 ./run_test.sh 5765 20 NICT-ISAC-Dev2     # other laptops than hosts.sh says
# defaults: name = <NAME_PREFIX>-Dev1 and seconds = SECS from plan.sh
# env: TXPWR=15 MCS=1 PAYLOAD=100 DELAY=1000 IF=wlan1 (as multi-rx/run_experiment.sh), RATE= override
# To run the whole plan (all devices x all cases) use ./run_plan.sh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/common.sh"
TXN=${TX_NODE:-}; RXN=${RX_NODE:-}           # env overrides, captured before hosts.sh sets TX_NODE
source "$HERE/../multi-rx/hosts.sh"          # -> NODE_USER NODE_NET TX_NODE RX_NODES node()
source "$HERE/plan.sh"                       # -> NAME_PREFIX SECS
[ $# -ge 2 ] || usage_radio
resolve_radio "$1" "$2" || usage_radio
NAME=${3:-${NAME_PREFIX}-Dev1}
SECS=${4:-$SECS}
TX_NODE=${TXN:-$TX_NODE}; RX_NODE=${RXN:-${RX_NODES[0]}}
TX=$(node "$TX_NODE"); RX=$(node "$RX_NODE")
[ "$TX_NODE" != "$RX_NODE" ] || { echo "!! TX and RX are the same laptop ($TX_NODE)" >&2; exit 1; }
TXPWR=${TXPWR:-15}; MCS=${MCS:-1}; PAYLOAD=${PAYLOAD:-100}; DELAY=${DELAY:-1000}; IF=${IF:-wlan1}
[ "$MCS" -ge 0 ] && [ "$MCS" -le 7 ] || { echo "!! MCS=$MCS must be 0-7 (8+ = 2 streams, changes the CSI shape)" >&2; exit 1; }
RATE=${RATE:-$(derive_rate "$MCS")}
REMOTE='~/linux-80211n-csitool-supplementary'  # on the nodes (quoted: the node's shell expands ~)
STARTUP_WAIT=120                             # max seconds to wait for the first CSI (5 GHz start-up)
[ -x "$HERE/csi_report" ] || { echo "!! $HERE/csi_report missing: make -C $HERE csi_report" >&2; exit 1; }

BASE=$(out_base "$NAME")
TXLOG=${BASE}_tx.log; RXLOG=${BASE}_rx.log; CSI=${BASE}_rx.csi; REPORT=${BASE}_report.txt

# stamp TAG LOG: stdin lines -> "HH:MM:SS  line" into LOG, "HH:MM:SS  TAG  line" on the terminal
stamp() {
  local tag=$1 log=$2 t line
  while IFS= read -r line || [ -n "$line" ]; do
    printf -v t '%(%H:%M:%S)T' -1
    printf '%s  %s\n' "$t" "$line" >> "$log"
    printf '%s  %s  %s\n' "$t" "$tag" "$line"
  done
}

PR=; PT=; SP=
stop_all() {   # TX first (its end summary needs the ssh still open), then the RX stream
  [ -n "$SP" ] && kill "$SP" 2>/dev/null
  ssh -o ConnectTimeout=5 "$TX" "sudo pkill -TERM -x tx_inject" 2>/dev/null
  [ -n "$PT" ] && wait "$PT" 2>/dev/null
  sleep 1                                                                    # last CSI records in flight
  ssh -o ConnectTimeout=5 "$RX" "sudo pkill -INT -x csi_stream" 2>/dev/null  # INT: csi_stream flushes stdout
  [ -n "$PR" ] && wait "$PR" 2>/dev/null
  PT=; PR=
}
write_report() {
  { cat "$TXLOG"; echo; cat "$RXLOG"; } > "$REPORT"
  echo; echo "################## REPORT (saved: $REPORT) ##################"
  cat "$REPORT"
  echo "files : $TXLOG"
  echo "        $RXLOG"
  echo "        $CSI  ($(stat -c%s "$CSI" 2>/dev/null || echo 0) bytes, CSI-tool .csi format)"
}
trap 'echo; echo "!!! interrupted: stopping TX and RX"; stop_all; trap - INT TERM; write_report; exit 130' INT TERM

echo "TX=$TX  RX=$RX  ch$CH $BW (centre $CENTER_MHZ MHz / $WIDTH_MHZ MHz)  rate $RATE  ${TXPWR} dBm  '$NAME'  ${SECS}s"
echo "=== [0/5] kill leftovers from a previous aborted run ==="
ssh -o ConnectTimeout=5 "$TX" "sudo pkill -x tx_inject; sudo pkill -x random_packets; true" 2>/dev/null
ssh -o ConnectTimeout=5 "$RX" "sudo pkill -INT -x csi_stream; true" 2>/dev/null

echo "=== [1/5] RX radio setup on $RX (ch$CH $BW) ==="
RXSET=$(ssh "$RX" "~/rx_setup.sh $CH $BW $IF 2>&1; iw dev $IF info | grep -E 'channel|txpower'") || { echo "!! RX setup failed (ssh / rx_setup.sh)"; exit 1; }
{
  print_header "RX side" "$NAME (counterpart)"
  echo "Equipment   : Intel WiFi Link 5300 (IEEE 802.11n), monitor mode, CSI firmware (connector_log=0x1), laptop $RX ($IF)"
  echo "Reception   : CSI (30 subcarriers x Ntx x Nrx, complex) from every received frame; receive only, no transmission"
  echo "$RXSET" | sed 's/^/              /'
  echo "Recording   : $CSI   (time stamps = control PC $(hostname) clock)"
  echo "------------------------------------------------------------------"
} | tee "$RXLOG"

echo "=== [2/5] RX stream $RX -> csi_report (here) ==="
ssh "$RX" "sudo $REMOTE/multi-rx/csi_stream /dev/stdout" 2>/dev/null | "$HERE/csi_report" -i -p "$CSI" | stamp RX "$RXLOG" &
PR=$!
sleep 2

echo "=== [3/5] TX setup + inject on $TX in ONE ssh (${TXPWR} dBm, rate $RATE, ${PAYLOAD} B, ${DELAY} us) ==="
{
  print_header "TX side" "$NAME"
  echo "Equipment   : Intel WiFi Link 5300 (IEEE 802.11n), monitor-mode injection (LORCON, mon0), laptop $TX ($IF)"
  echo "Emission    : $(mcs_text "$MCS"), monitor_tx_rate $RATE"
  echo "TX power    : setting ${TXPWR} dBm ($(awk "BEGIN{printf \"%.1f\", 10^($TXPWR/10)}") mW nominal); the application states the MEASURED antenna-port power"
  echo "Log         : $TXLOG   (time stamps = control PC $(hostname) clock)"
  echo "------------------------------------------------------------------"
} | tee "$TXLOG"
ssh "$TX" "~/tx_setup.sh $CH $BW $RATE $IF $TXPWR 2>&1; iw dev mon0 info | grep -E 'channel|txpower'; cd $REMOTE/single-link && sudo ./tx_inject -p -l $PAYLOAD -d $DELAY -m 1" 2>&1 | stamp TX "$TXLOG" &
PT=$!

echo "=== [4/5] waiting for CSI (up to ${STARTUP_WAIT}s), then recording ${SECS}s ==="
prev=0; ready=0
for t in $(seq 1 "$STARTUP_WAIT"); do
  sleep 1
  s=$(stat -c%s "$CSI" 2>/dev/null || echo 0)
  if [ "$s" -gt "$prev" ] && [ "$s" -gt 2000 ]; then ready=1; break; fi
  prev=$s
  kill -0 "$PT" 2>/dev/null || { echo "!! TX ended before any CSI arrived (see the TX lines above)"; break; }
done
if [ "$ready" -eq 1 ]; then
  printf -v endt '%(%H:%M:%S)T' $(( $(printf '%(%s)T' -1) + SECS ))
  echo "=== CSI flowing: recording ${SECS}s (until $endt) ==="
  sleep "$SECS" & SP=$!; wait "$SP"; SP=        # sleep in the background: a trap fires at once, not after the sleep
else
  echo "!!!!! WARNING: no CSI within ${STARTUP_WAIT}s (same channel/bandwidth on both? clear channel? CSI firmware? TX injecting?)"
fi

echo "=== [5/5] stop TX, then the RX stream ==="
stop_all
trap - INT TERM
write_report

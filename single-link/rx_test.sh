#!/bin/bash
# FALLBACK without control PC / LAN: RX side of the 1 TX -> 1 RX comprehensive test, run ON
# the RX laptop. (With the LAN use run_test.sh on the control PC instead.)
# Radio setup as multi-rx/rx_setup.sh, then csi_report (netlink): the report header, one
# line per second (CSI records / loss / RSS / Ntx x Nrx / rate), start + end summary.
# Everything shown on the terminal also goes to a .log; the raw CSI goes to a .csi
# (standard CSI-tool framing, read_bf_file.m readable). Time stamps = THIS laptop's clock.
#
# usage: ./rx_test.sh <MHz|ch> <20|40|HT20|HT40+|HT40-> [display name] [seconds]
#   ./rx_test.sh 5795 40 NICT-ISAC-Dev1          # until Ctrl-C
#   ./rx_test.sh 5765 20 NICT-ISAC-Dev1 60       # stops 60 s after the first CSI record
# env: IF=wlan1 (default: first `iw dev` interface)  REG=US
# ** <MHz> <BW> must match the TX exactly (a mismatch receives nothing and gives no error) **
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/common.sh"
source "$HERE/plan.sh"
[ $# -ge 2 ] || usage_radio
resolve_radio "$1" "$2" || usage_radio
NAME=${3:-${NAME_PREFIX}-Dev1}
SECS=${4:-0}
REG=${REG:-US}
[ -x "$HERE/csi_report" ] || { echo "!! $HERE/csi_report missing: make -C $HERE csi_report" >&2; exit 1; }

echo "=== RX radio setup: ch$CH $BW (centre ${CENTER_MHZ} MHz / ${WIDTH_MHZ} MHz) ==="
sudo service network-manager stop 2>/dev/null
sudo modprobe -r iwlwifi mac80211 cfg80211 2>/dev/null
sudo modprobe iwlwifi connector_log=0x1
sleep 3
IF=${IF:-$(iw dev | awk '/Interface/{print $2; exit}')}
[ -n "$IF" ] || { echo "!! no wireless interface found (set IF=)" >&2; exit 1; }
sudo iw reg set "$REG"
sleep 3
sudo ifconfig "$IF" down
sudo iwconfig "$IF" mode monitor
sudo ifconfig "$IF" up
sleep 3
sudo iw dev "$IF" set channel "$CH" "$BW" || { echo "!! set channel $CH $BW failed (regdb without UNII-3? too soon after iw reg set?)" >&2; exit 1; }

BASE=$(out_base "$NAME")
LOG="${BASE}_rx.log"; CSI="${BASE}_rx.csi"
{
  print_header "RX side" "$NAME (counterpart)"
  echo "Equipment   : Intel WiFi Link 5300 (IEEE 802.11n), monitor mode, CSI firmware (connector_log=0x1), IF=$IF, reg=$REG"
  echo "Reception   : CSI (30 subcarriers x Ntx x Nrx, complex) from every received frame; receive only, no transmission"
  iw dev "$IF" info 2>/dev/null | grep -E 'channel|txpower' | sed 's/^[[:space:]]*/              /'
  echo "Recording   : $CSI"
  echo "Log         : $LOG"
  [ "$SECS" -gt 0 ] && echo "Duration    : ${SECS} s after the first CSI record" || echo "Duration    : until Ctrl-C"
  echo "------------------------------------------------------------------"
} | tee "$LOG"

# tee -i ignores Ctrl-C so csi_report's end summary still reaches the log.
# (${OPT[@]+"${OPT[@]}"}: an empty array under set -u is an error on bash 4.3 / Ubuntu 14.04)
OPT=(); [ "$SECS" -gt 0 ] && OPT=(-t "$SECS")
sudo "$HERE/csi_report" ${OPT[@]+"${OPT[@]}"} "$CSI" | tee -a -i "$LOG"
sudo chown "$(id -un)" "$CSI" 2>/dev/null

{
  echo "------------------------------------------------------------------"
  echo "End $(now_str)   recording $(stat -c%s "$CSI" 2>/dev/null || echo 0) bytes -> $CSI"
  echo "=================================================================="
} | tee -a "$LOG"
echo "log: $LOG"

#!/bin/bash
# FALLBACK without control PC / LAN: TX side of the 1 TX -> 1 RX comprehensive test, run ON
# the TX laptop. (With the LAN use run_test.sh on the control PC instead.)
# Radio setup as multi-rx/tx_setup.sh (mon0, channel, txpower AFTER the channel,
# monitor_tx_rate), then tx_inject in the SAME shell (LORCON needs that): the report header,
# the frame description, one line per second (frames sent / total), start + end summary.
# Everything shown on the terminal also goes to a .log. Time stamps = THIS laptop's clock.
#
# usage: ./tx_test.sh <MHz|ch> <20|40|HT20|HT40+|HT40-> [display name] [seconds]
#   ./tx_test.sh 5795 40 NICT-ISAC-Dev1          # until Ctrl-C
#   ./tx_test.sh 5765 20 NICT-ISAC-Dev1 60       # 60 s, then stops
# env: TXPWR=15 (dBm; card max, measured < 25 mW at the antenna port -> inside the licence)
#      MCS=1 (0-7, 1 stream)  PAYLOAD=100 (bytes)  DELAY=1000 (us -> 1000 frames/s)
#      RATE=0x4901 (override the BW/MCS-derived monitor_tx_rate)  IF=wlan1  REG=US
# ** <MHz> <BW> must match the RX exactly **
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/common.sh"
source "$HERE/plan.sh"
[ $# -ge 2 ] || usage_radio
resolve_radio "$1" "$2" || usage_radio
NAME=${3:-${NAME_PREFIX}-Dev1}
SECS=${4:-0}
TXPWR=${TXPWR:-15}; MCS=${MCS:-1}; PAYLOAD=${PAYLOAD:-100}; DELAY=${DELAY:-1000}; REG=${REG:-US}
[ "$MCS" -ge 0 ] && [ "$MCS" -le 7 ] || { echo "!! MCS=$MCS must be 0-7 (8+ = 2 streams, changes the CSI shape)" >&2; exit 1; }
RATE=${RATE:-$(derive_rate "$MCS")}
[ -x "$HERE/tx_inject" ] || { echo "!! $HERE/tx_inject missing: install LORCON, then make -C $HERE tx_inject" >&2; exit 1; }

echo "=== TX radio setup: ch$CH $BW (centre ${CENTER_MHZ} MHz / ${WIDTH_MHZ} MHz), ${TXPWR} dBm, rate $RATE ==="
sudo service network-manager stop 2>/dev/null
sudo iw dev mon0 del 2>/dev/null
sudo modprobe -r iwlwifi mac80211 cfg80211 2>/dev/null
sudo modprobe iwlwifi
sleep 3
IF=${IF:-$(iw dev | awk '/Interface/{print $2; exit}')}
[ -n "$IF" ] || { echo "!! no wireless interface found (set IF=)" >&2; exit 1; }
sudo iw reg set "$REG"
sleep 3
sudo ifconfig "$IF" down
sudo iw dev "$IF" interface add mon0 type monitor
sudo iw dev "$IF" del
sudo ifconfig mon0 up
sleep 3
sudo iw dev mon0 set channel "$CH" "$BW" || { echo "!! set channel $CH $BW failed (regdb without UNII-3? too soon after iw reg set?)" >&2; exit 1; }
# txpower MUST come after the channel (the driver defers it otherwise). iw's exit status
# lies (iwlagn_mac_config discards iwl_set_tx_power's return): dmesg is the honest report.
sudo dmesg -C >/dev/null 2>&1
sudo iw dev mon0 set txpower fixed "${TXPWR}00" >/dev/null 2>&1
if dmesg | grep -qi TXPOWER; then PWR_NOTE="!! REFUSED by driver: $(dmesg | grep -i TXPOWER | tail -1)"; else PWR_NOTE="(applied)"; fi
RF=$(sudo find /sys/kernel/debug -name monitor_tx_rate | head -1)
[ -n "$RF" ] || { echo "!! monitor_tx_rate not found (kernel without CONFIG_IWLWIFI_DEBUGFS)" >&2; exit 1; }
echo "$RATE" | sudo tee "$RF" >/dev/null
RATE_SET=$(sudo cat "$RF")

BASE=$(out_base "$NAME")
LOG="${BASE}_tx.log"
{
  print_header "TX side" "$NAME"
  echo "Equipment   : Intel WiFi Link 5300 (IEEE 802.11n), monitor-mode injection (LORCON, mon0), IF=$IF, reg=$REG"
  echo "Emission    : $(mcs_text "$MCS"), monitor_tx_rate $RATE_SET"
  echo "TX power    : setting ${TXPWR} dBm ($(awk "BEGIN{printf \"%.1f\", 10^($TXPWR/10)}") mW nominal) ${PWR_NOTE}; the application states the MEASURED antenna-port power"
  iw dev mon0 info 2>/dev/null | grep -E 'channel|txpower' | sed 's/^[[:space:]]*/              /'
  echo "Log         : $LOG"
  echo "------------------------------------------------------------------"
} | tee "$LOG"

# tee -i ignores Ctrl-C so tx_inject's end summary still reaches the log.
# (${OPT[@]+"${OPT[@]}"}: an empty array under set -u is an error on bash 4.3 / Ubuntu 14.04)
OPT=(); [ "$SECS" -gt 0 ] && OPT=(-t "$SECS")
sudo "$HERE/tx_inject" ${OPT[@]+"${OPT[@]}"} -l "$PAYLOAD" -d "$DELAY" -m 1 | tee -a -i "$LOG"

{
  echo "------------------------------------------------------------------"
  echo "End $(now_str)"
  echo "=================================================================="
} | tee -a "$LOG"
echo "log: $LOG"

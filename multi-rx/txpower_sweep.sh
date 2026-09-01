#!/bin/bash
# Sweep TX power and report what the RX actually receives at each level.
# Answers "is the 25 mW experimental-licence cap enough in this room?" empirically.
#
# SETTLED: the antenna-port output was measured and stays under the 25 mW 指定事項
# even at the max setting (15 dBm), because the 5300 tops out at its EEPROM ceiling
# (max_power_avg, ~15-16 dBm) well below the nominal 31.6 mW. So the licence does not
# constrain the setting -- run at 15. This script is now only for checking link margin
# and for spotting AGC saturation (see the note at the end).
#
# usage: ./txpower_sweep.sh [CH] [BW] [RATE]
set -u
RX0=kota@192.168.100.11
TX=kota@192.168.100.13
REMOTE=~/linux-80211n-csitool-supplementary
CH=${1:-157}; BW=${2:-HT40+}; RATE=${3:-0x4901}   # default: ch157 HT40+, center 5795MHz = the standard capture setting
LEVELS="0 3 6 9 11 13 14 15 16"                  # dBm; 14 = 25 mW

echo "=== TX power sweep, ch$CH $BW (TX->RX0) ==="
# txpower must be set AFTER the channel: a channel change re-commits the RXON and
# the driver defers the power set (iwl-agn-rxon.c iwl_set_tx_power).
ssh "$TX"  "~/tx_setup.sh $CH $BW $RATE" || exit 1
ssh "$RX0" "~/rx_setup.sh $CH $BW"       || exit 1
echo

printf "%-5s %-7s %-7s %s\n" "dBm" "mW" "pkts" "mean signal"
for p in $LEVELS; do
  # iw's exit status lies here: iwlagn_mac_config() discards iwl_set_tx_power()'s
  # return value, so iw and `iw dev info` both report success even when the
  # firmware refused the level. dmesg is the only honest source.
  rej=$(ssh "$TX" "sudo dmesg -C >/dev/null 2>&1; \
                   sudo iw dev mon0 set txpower fixed ${p}00 >/dev/null 2>&1; \
                   dmesg | grep -i TXPOWER | tail -1")
  if [ -n "$rej" ]; then
    printf "%-5s %-7s %s\n" "$p" "-" "refused by driver: $rej"
    continue
  fi

  ssh "$TX" "cd $REMOTE/injection && sudo timeout 8 ./random_packets 30000 100 1 500 >/dev/null 2>&1" &
  txp=$!
  sleep 2
  out=$(ssh "$RX0" "sudo timeout 5 tcpdump -e -i wlan1 2>/dev/null | grep 16:ea" 2>/dev/null)
  wait $txp 2>/dev/null
  ssh "$TX" "sudo pkill -f random_packets" 2>/dev/null

  n=$(printf '%s' "$out" | grep -c .)
  sig=$(printf '%s' "$out" | grep -o -- '-[0-9]*dBm signal' | grep -o -- '-[0-9]*' \
        | awk '{s+=$1; c++} END {if (c) printf "%.1f dBm", s/c; else print "n/a"}')
  mw=$(awk "BEGIN{printf \"%.1f\", 10^($p/10)}")
  printf "%-5s %-7s %-7s %s\n" "$p" "$mw" "$n" "$sig"
  sleep 1
done

echo
echo "=== done ==="
echo "Read the 14 dBm row. If pkts matches the 15/16 dBm rows and the mean signal"
echo "sits well above ~-80 dBm, the 25 mW cap costs nothing for this geometry."
echo "A signal stronger than about -35 dBm is the opposite problem: the AGC"
echo "saturates and the CSI distorts (get_total_rss subtracts agc), so back off."

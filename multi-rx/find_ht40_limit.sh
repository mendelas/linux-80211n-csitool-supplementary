#!/bin/bash
# Sweep candidate HT40 channels and report which ones the RX can actually receive.
# Finds the upper frequency limit where 40MHz injection is still received.
# usage: ./find_ht40_limit.sh
set -u
RX0=kota@192.168.100.11
TX=kota@192.168.100.13
REMOTE=~/linux-80211n-csitool-supplementary
# "primary:BW:centerMHz"  (non-DFS, HT40-capable pairs; DFS W53/W56 skipped = injection blocked)
CHANS=(
  "36:HT40+:5190"    # 36+40  W52
  "44:HT40+:5230"    # 44+48  W52
  "149:HT40+:5755"   # 149+153 UNII-3
  "157:HT40-:5775"   # 153+157 UNII-3
  "161:HT40-:5795"   # 157+161 UNII-3
)
echo "=== HT40 reception sweep (TX->RX0) ==="
for spec in "${CHANS[@]}"; do
  ch=${spec%%:*}; rest=${spec#*:}; bw=${rest%%:*}; ctr=${rest##*:}
  printf "ch%-4s %-6s center~%sMHz : " "$ch" "$bw" "$ctr"
  # TX: setup + inject in ONE ssh (LORCON needs same session), time-boxed
  ssh "$TX" "~/tx_setup.sh $ch $bw 0x4901 >/dev/null 2>&1; cd $REMOTE/injection && sudo timeout 9 ./random_packets 30000 100 1 500 >/dev/null 2>&1" &
  TXP=$!
  sleep 2
  # RX: setup + count OUR HT40 packets (MCS from injection MAC) over a few seconds
  n=$(ssh "$RX0" "~/rx_setup.sh $ch $bw >/dev/null 2>&1; sudo timeout 5 tcpdump -i wlan1 2>/dev/null | grep -i mcs | grep -c 16:ea" 2>/dev/null)
  wait $TXP 2>/dev/null
  ssh "$TX" "sudo pkill -f random_packets" 2>/dev/null
  n=${n:-0}
  if [ "$n" -gt 0 ]; then echo "OK  ($n HT40 pkts received)"; else echo "--  (nothing received)"; fi
  sleep 1
done
echo "=== done. Highest 'OK' channel = the 40MHz reception limit ==="

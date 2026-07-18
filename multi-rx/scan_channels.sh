#!/bin/bash
# 5GHz channel occupancy scan — find a CLEAR channel before injecting.
# Run this on an RX laptop (needs the Intel 5300 + monitor mode).
# usage: ~/scan_channels.sh [IF]        (default wlan1)
#   Part A: managed-mode AP scan  -> APs per channel + strongest signal
#   Part B: monitor-mode measure  -> frames/3s on the injection candidates
# No AP + few frames = clear. Set CH= on TX and every RX to that channel.
IF=${1:-wlan1}
CANDIDATES="36 44 48 149 153 157 161 165"   # non-DFS (W52 + UNII-3); the only injectable channels

# --- clean driver reload (managed mode) ---
sudo service network-manager stop 2>/dev/null
sudo modprobe -r iwlwifi mac80211 cfg80211 2>/dev/null
sudo modprobe iwlwifi
sleep 3
sudo iw reg set US            # make UNII-3 (ch149-165) visible
sleep 1
sudo ip link set "$IF" up
sleep 1

echo "==================================================================="
echo " Part A: 5GHz AP scan (managed mode)  IF=$IF"
echo "==================================================================="
SCAN=$(sudo iw dev "$IF" scan 2>/dev/null)
[ -z "$SCAN" ] && { sleep 2; SCAN=$(sudo iw dev "$IF" scan 2>/dev/null); }

echo "$SCAN" | awk '
  /freq:/    { freq=$2 }
  /signal:/  { sig=$2+0; if (freq>=5000) { cnt[freq]++; if (best[freq]=="" || sig>best[freq]) best[freq]=sig } }
  /SSID:/    { s=$0; sub(/^[ \t]*SSID: /,"",s); if (freq>=5000 && s!="") ssid[freq]=ssid[freq] s " " }
  END {
    printf "%-6s %-8s %-6s %-8s  %s\n","ch","freq","#AP","strongest","SSIDs"
    printf "%-6s %-8s %-6s %-8s  %s\n","----","----","---","--------","-----"
    n=0
    for (f in cnt) { fr[n]=f; n++ }
    for (i=0;i<n;i++) for (j=i+1;j<n;j++) if (cnt[fr[j]]>cnt[fr[i]]) { t=fr[i];fr[i]=fr[j];fr[j]=t }
    for (i=0;i<n;i++){ f=fr[i]; ch=(f-5000)/5; printf "ch%-4d %-8d %-6d %-8s  %s\n", ch, f, cnt[f], best[f]" dBm", ssid[f] }
    if (n==0) print "(no 5GHz AP found — all channels clear, or scan unsupported)"
  }'

echo
echo "==================================================================="
echo " Part B: injection candidates measured (monitor mode, 3s each)"
echo "  -> fewer frames = clearer. 0..~30 is clear enough."
echo "==================================================================="
sudo ip link set "$IF" down
sudo iw dev "$IF" set type monitor 2>/dev/null
sudo ip link set "$IF" up
printf "%-6s %-8s %s\n" "ch" "MHz" "frames/3s"
printf "%-6s %-8s %s\n" "----" "----" "---------"
for CH in $CANDIDATES; do
  MHZ=$((5000 + CH*5))
  if sudo iw dev "$IF" set channel "$CH" 2>/dev/null; then
    N=$(sudo timeout 3 tcpdump -i "$IF" -c 1000 2>/dev/null | grep -c .)
    FLAG=""; [ "$N" -le 30 ] && FLAG="  <= clear candidate"
    printf "ch%-4d %-8d %d%s\n" "$CH" "$MHZ" "$N" "$FLAG"
  else
    printf "ch%-4d %-8d (cannot set: DFS/reg limit)\n" "$CH" "$MHZ"
  fi
done

echo
echo "Pick the emptiest ch, then set CH= in run_experiment.sh (or rx/tx_setup.sh)."
echo "TX and every RX must match. W52 (ch36/44/48) = license-free;"
echo "UNII-3 (ch149-165) needs the 5.8GHz experimental license."

#!/bin/bash
# TX radio + rate setup only (invoked over ssh by the control PC). No injection here.
# usage: tx_setup.sh [CH] [BW] [RATE] [IF]
CH=${1:-157}; BW=${2:-HT40-}; RATE=${3:-0x4901}; IF=${4:-wlan1}
sudo service network-manager stop 2>/dev/null
sudo iw dev mon0 del 2>/dev/null
sudo modprobe -r iwlwifi mac80211 cfg80211 2>/dev/null
sudo modprobe iwlwifi
sleep 3
sudo iw reg set US
sleep 3
sudo ifconfig "$IF" down
sudo iw dev "$IF" interface add mon0 type monitor
sudo iw dev "$IF" del
sudo ifconfig mon0 up
sleep 3
sudo iw dev mon0 set channel "$CH" "$BW"
echo -n "TX freq: "; iwconfig mon0 | grep -o '[0-9.]* GHz' || echo "(no channel - set failed?)"
RF=$(sudo find /sys/kernel/debug -name monitor_tx_rate | head -1)
echo "$RATE" | sudo tee "$RF" >/dev/null
echo -n "TX rate: "; sudo cat "$RF"

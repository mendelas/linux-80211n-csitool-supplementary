#!/bin/bash
# RX radio setup only (invoked over ssh by the control PC). No capture here.
# usage: rx_setup.sh [CH] [BW] [IF]
CH=${1:-48}; BW=${2:-HT20}; IF=${3:-wlan1}   # default MAIN: ch48 5.24GHz 20MHz (license-free W52)
sudo service network-manager stop 2>/dev/null
sudo modprobe -r iwlwifi mac80211 cfg80211 2>/dev/null
sudo modprobe iwlwifi connector_log=0x1
sleep 3
sudo iw reg set US
sleep 3
sudo ifconfig "$IF" down
sudo iwconfig "$IF" mode monitor
sudo ifconfig "$IF" up
sleep 3
sudo iw dev "$IF" set channel "$CH" "$BW"
echo -n "RX freq: "; iwconfig "$IF" | grep -o '[0-9.]* GHz' || echo "(no channel - set failed?)"

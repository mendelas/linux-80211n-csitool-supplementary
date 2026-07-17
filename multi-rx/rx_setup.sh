#!/bin/bash
# RX 電波設定のみ（キャプチャはしない）。制御PCから ssh で叩かれる。
# usage: rx_setup.sh [CH] [BW]
CH=${1:-165}; BW=${2:-HT20}; IF=${3:-wlan1}
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
echo -n "RX freq: "; iwconfig "$IF" | grep -o '[0-9.]* GHz'

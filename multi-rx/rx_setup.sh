#!/bin/bash
# RX radio PREPARE only (invoked over ssh by the control PC). No capture here.
# Run it ONCE per installation (./run_experiment.sh --prepare, or --resetup), not per
# recording: the driver reload re-initializes the 5300 and moves one RX chain's phase by
# a multiple of pi. Recordings only check the result (radio_check.sh rx).
# usage: rx_setup.sh [CH] [BW] [IF]
CH=${1:-157}; BW=${2:-HT40+}; IF=${3:-wlan1}   # default: ch157 HT40+ = 157+161, center 5795MHz (UNII-3, licensed)
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

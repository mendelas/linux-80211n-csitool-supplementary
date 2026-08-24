#!/bin/bash
# TX radio + rate setup only (invoked over ssh by the control PC). No injection here.
# usage: tx_setup.sh [CH] [BW] [RATE] [IF] [TXPWR_dBm]
CH=${1:-48}; BW=${2:-HT20}; RATE=${3:-0x4101}; IF=${4:-wlan1}   # default MAIN: ch48 5.24GHz 20MHz MCS1 HT (license-free W52)
TXPWR=${5:-14}   # dBm. 14 = 25 mW = the 5.8GHz experimental-licence 指定事項.
                 # The card's own ceiling is only ~15-16 dBm, so this costs ~2 dB and
                 # keeps the station inside its licensed power on every channel.
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
# txpower MUST come after the channel: a channel change re-commits the RXON and the
# driver defers the power set. iw's exit status lies here (iwlagn_mac_config discards
# iwl_set_tx_power's return), so confirm via dmesg, not via iw or `iw dev info`.
sudo dmesg -C >/dev/null 2>&1
sudo iw dev mon0 set txpower fixed "${TXPWR}00" >/dev/null 2>&1
echo -n "TX power: ${TXPWR} dBm "
if dmesg | grep -qi TXPOWER; then echo "!! REFUSED by driver: $(dmesg | grep -i TXPOWER | tail -1)"; else echo "(applied)"; fi
RF=$(sudo find /sys/kernel/debug -name monitor_tx_rate | head -1)
echo "$RATE" | sudo tee "$RF" >/dev/null
echo -n "TX rate: "; sudo cat "$RF"

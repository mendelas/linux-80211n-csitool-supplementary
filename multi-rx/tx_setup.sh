#!/bin/bash
# TX radio + rate setup only (invoked over ssh by the control PC). No injection here.
# usage: tx_setup.sh [CH] [BW] [RATE] [IF] [TXPWR_dBm]
CH=${1:-157}; BW=${2:-HT40+}; RATE=${3:-0x4901}; IF=${4:-wlan1}   # default: ch157 HT40+ = 157+161, center 5795MHz, MCS1 HT (UNII-3, licensed)
TXPWR=${5:-15}   # dBm, i.e. the card's max (EEPROM ceiling is ~15-16 dBm). This is the
                 # SETTING, not the radiated power: the antenna-port output at 15 was
                 # MEASURED under the 25 mW 指定事項 of the 5.8GHz experimental licence.
                 # The driver may refuse 16+; the dmesg check below is the only honest
                 # report (iw's exit status lies -- see the comment at the txpower call).
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

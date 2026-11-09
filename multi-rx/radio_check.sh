#!/bin/bash
# Per-recording readiness check of ONE node's radio (runs on the node).
# It never reloads iwlwifi, never takes the interface down and never re-tunes it: every
# reload re-initializes the 5300 and moves one RX chain's phase by a multiple of pi
# (csi-track, 2026-11-04). So the radio is PREPARED once per installation (rx_setup.sh /
# tx_setup.sh, or ./run_experiment.sh --prepare) and every recording only CHECKS it here.
#
# usage: radio_check.sh rx CH BW [IF]           IF default wlan1
#        radio_check.sh tx CH BW [RATE TXPWR]   checks mon0 (what tx_setup.sh creates)
#   tx with RATE+TXPWR: once the check passes, re-apply txpower (dmesg-checked, as in
#   tx_setup.sh) and monitor_tx_rate. Neither reloads nor re-tunes the NIC; it makes every
#   recording transmit at the TXPWR it asked for, even after txpower_sweep.sh left another level.
# The control PC pipes this file, so nodes need no copy of it:
#   ssh node "bash -s -- rx 157 HT40+ wlan1" < radio_check.sh
# exit: 0 ready, 1 not ready (reasons printed), 2 usage
ROLE=${1:-}; CH=${2:-}; BW=${3:-}
case "$ROLE" in
  rx) IF=${4:-wlan1}; RATE=; TXPWR= ;;
  tx) IF=mon0; RATE=${4:-}; TXPWR=${5:-} ;;
  *)  ROLE= ;;
esac
[ -n "$ROLE" ] && [ -n "$CH" ] && [ -n "$BW" ] || { echo "usage: radio_check.sh rx|tx CH BW [IF | RATE TXPWR]"; exit 2; }

BAD=(); NOTE=
fail() { BAD+=("$*"); }

# "channel 157 (5785 MHz), type: HT40+"                      (iw on a 3.5 kernel: channel type)
# "channel 157 (5785 MHz), width: 40 MHz, center1: 5795 MHz" (newer kernels: width + center)
# -> prints "CH BW", BW in rx_setup.sh / tx_setup.sh notation (HT20, HT40+, HT40-)
parse_iw_channel() {
  local l=$1 ch f type width c1
  ch=$(sed -nE 's/.*channel ([0-9]+) .*/\1/p' <<<"$l")
  f=$(sed -nE 's/.*channel [0-9]+ \(([0-9]+) MHz\).*/\1/p' <<<"$l")
  type=$(sed -nE 's/.*type: ([^,]+).*/\1/p' <<<"$l")
  width=$(sed -nE 's/.*width: ([0-9]+) MHz.*/\1/p' <<<"$l")
  c1=$(sed -nE 's/.*center1: ([0-9]+) MHz.*/\1/p' <<<"$l")
  if [ -n "$type" ]; then echo "$ch ${type// /}"
  elif [ "$width" = 20 ]; then grep -q 'no HT' <<<"$l" && echo "$ch NOHT" || echo "$ch HT20"
  elif [ "$width" = 40 ] && [ -n "$f" ] && [ "$c1" = $((f + 10)) ]; then echo "$ch HT40+"
  elif [ "$width" = 40 ] && [ -n "$f" ] && [ "$c1" = $((f - 10)) ]; then echo "$ch HT40-"
  else echo "$ch width${width:-?}/center1:${c1:-?}"
  fi
}

# 1) driver (and, on RX, the CSI log switch)
CL=
if [ ! -d /sys/module/iwlwifi ]; then
  fail "iwlwifi is not loaded"
elif [ "$ROLE" = rx ]; then
  CL=$(cat /sys/module/iwlwifi/parameters/connector_log 2>/dev/null)
  if [ -z "$CL" ]; then fail "iwlwifi has no connector_log parameter (not the CSI driver?)"
  elif [ "$CL" = 0 ]; then fail "iwlwifi was loaded with connector_log=0 (no CSI); the prepare step loads it with 0x1"
  fi
fi

# 2) interface: exists, monitor, up, channel + bandwidth
if [ ! -e "/sys/class/net/$IF" ]; then
  fail "$IF does not exist"
else
  INFO=$(iw dev "$IF" info 2>/dev/null)
  # 803 = ARPHRD_IEEE80211_RADIOTAP, the link type mac80211 gives a monitor interface
  grep -q 'type monitor' <<<"$INFO" || [ "$(cat "/sys/class/net/$IF/type")" = 803 ] || fail "$IF is not in monitor mode"
  (( $(cat "/sys/class/net/$IF/flags") & 1 )) || fail "$IF is down"
  CHL=$(grep -m1 -E '^[[:space:]]*channel [0-9]+' <<<"$INFO")
  if [ -n "$CHL" ]; then
    read -r GOT_CH GOT_BW <<<"$(parse_iw_channel "$CHL")"
    { [ "$GOT_CH" = "$CH" ] && [ "$GOT_BW" = "$BW" ]; } || fail "$IF is on ch$GOT_CH $GOT_BW, expected ch$CH $BW"
  else
    # iw too old to print the channel: check the frequency through wext; bandwidth unknown
    WANT_F=$(( CH <= 14 ? 2407 + 5 * CH : 5000 + 5 * CH ))
    GHZ=$(iwconfig "$IF" 2>/dev/null | grep -o 'Frequency[:=][0-9.]*' | grep -o '[0-9.]*$')
    GOT_F=$(awk -v g="$GHZ" 'BEGIN { if (g != "") printf "%d", g * 1000 + 0.5 }')
    if [ -z "$GOT_F" ]; then fail "cannot read $IF's channel (neither iw dev info nor iwconfig shows it)"
    elif [ "$GOT_F" != "$WANT_F" ]; then fail "$IF is on $GOT_F MHz, expected ch$CH = $WANT_F MHz"
    else NOTE="  (bandwidth $BW NOT verified: iw dev info prints no channel line)"
    fi
  fi
fi

# 3) TX: the rate knob must exist (debugfs)
RF=
if [ "$ROLE" = tx ]; then
  RF=$(sudo find /sys/kernel/debug -name monitor_tx_rate 2>/dev/null | head -1)
  [ -n "$RF" ] || fail "monitor_tx_rate not found in debugfs"
fi

if [ ${#BAD[@]} -gt 0 ]; then
  echo "    NOT READY ($ROLE ch$CH $BW on $(hostname)):"
  for b in "${BAD[@]}"; do echo "      - $b"; done
  exit 1
fi
# ifindex is new after every driver reload: equal numbers across recordings = same NIC init
echo "    ready: $ROLE $IF ch$CH $BW monitor up${CL:+ connector_log=$CL}  ifindex $(cat "/sys/class/net/$IF/ifindex")$NOTE"

# 4) TX: re-apply power + rate (no reload, no re-tune). Same commands as tx_setup.sh.
if [ "$ROLE" = tx ] && [ -n "$RATE" ] && [ -n "$TXPWR" ]; then
  sudo dmesg -C >/dev/null 2>&1
  sudo iw dev mon0 set txpower fixed "${TXPWR}00" >/dev/null 2>&1
  echo -n "    TX power: ${TXPWR} dBm "
  if dmesg | grep -qi TXPOWER; then echo "!! REFUSED by driver: $(dmesg | grep -i TXPOWER | tail -1)"; else echo "(applied)"; fi
  echo "$RATE" | sudo tee "$RF" >/dev/null
  echo "    TX rate: $(sudo cat "$RF")"
fi
exit 0

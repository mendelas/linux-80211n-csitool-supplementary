#!/bin/bash
# Shared by run_test.sh / run_plan.sh / rx_test.sh / tx_test.sh (sourced).
# Radio-parameter resolution, test-report header, file naming. All output text is English.
#
# The radio is given as  <MHz|ch> <20|40|HT20|HT40+|HT40->  so the comprehensive-test cases
# can be typed as they appear in the application (5795 40 / 5765 20 / 5785 20 / 5805 20)
# or in iw notation (157 HT40+ / 153 HT20 / 157 HT20 / 161 HT20). Both forms resolve to
# CH / BW for `iw` and CENTER_MHZ / WIDTH_MHZ / PRIMARY_MHZ / CH2 for the log.
#
# 40 MHz on the Intel 5300: only the EEPROM pairs exist (iwl_eeprom_band_7 = 36,44,52,60,
# 100,108,116,124,132,149,157 as the LOWER channel; multi-rx/find_ht40_limit.sh), so a
# 40 MHz centre is always "lower ch HT40+" here, e.g. 5795 -> 157 HT40+ (= 161 HT40-).
HT40_LOWER="36 44 52 60 100 108 116 124 132 149 157"

usage_radio() {
  cat >&2 <<EOF
usage: $0 <MHz|ch> <20|40|HT20|HT40+|HT40-> [display name] [seconds]
  e.g.  $0 5795 40 NICT-ISAC-Dev1        # centre 5795 MHz, 40 MHz (= ch157 HT40+)
        $0 5765 20 NICT-ISAC-Dev1 60     # centre 5765 MHz, 20 MHz (= ch153 HT20), 60 s
        $0 157 HT40+ NICT-ISAC-Dev2      # iw notation works too
EOF
  exit 1
}

ch_to_mhz() {   # channel number -> primary (control) channel centre in MHz
  local c=$1
  if   [ "$c" -ge 1 ] && [ "$c" -le 13 ]; then echo $((2407 + 5 * c))
  elif [ "$c" -eq 14 ]; then echo 2484
  elif [ "$c" -ge 32 ] && [ "$c" -le 177 ]; then echo $((5000 + 5 * c))
  else echo "!! ch$c is out of range" >&2; return 1; fi
}

mhz_to_ch() {   # 20 MHz channel centre in MHz -> channel number
  local f=$1
  if   [ "$f" -ge 2412 ] && [ "$f" -le 2472 ] && [ $(( (f - 2407) % 5 )) -eq 0 ]; then echo $(( (f - 2407) / 5 ))
  elif [ "$f" -eq 2484 ]; then echo 14
  elif [ "$f" -ge 5160 ] && [ "$f" -le 5885 ] && [ $(( f % 5 )) -eq 0 ]; then echo $(( (f - 5000) / 5 ))
  else echo "!! ${f} MHz is not a channel centre" >&2; return 1; fi
}

# resolve_radio <MHz|ch> <20|40|HT20|HT40+|HT40->  -> sets CH BW CENTER_MHZ WIDTH_MHZ PRIMARY_MHZ CH2 BW_LABEL
resolve_radio() {
  local a=${1:-} b=${2:-}
  case "$a" in ''|*[!0-9]*) echo "!! first argument must be a frequency [MHz] or a channel number: '$a'" >&2; return 1;; esac
  [ -n "$b" ] || { echo "!! second argument must be 20 / 40 / HT20 / HT40+ / HT40-" >&2; return 1; }
  if [ "$a" -ge 1000 ]; then                         # ---- "<centre MHz> <20|40>" ----
    case "$b" in
      20|HT20)  CH=$(mhz_to_ch "$a") || return 1; BW=HT20 ;;
      40|HT40*) local lo; lo=$(mhz_to_ch $((a - 10))) || return 1
                case " $HT40_LOWER " in *" $lo "*) ;; *)
                  echo "!! no 40 MHz channel centred at ${a} MHz on the 5300 (lower ch$lo is not an HT40 pair). Injectable 40 MHz centres: 5190 5230 (W52) / 5755 5795 (UNII-3) MHz" >&2; return 1;; esac
                CH=$lo; BW=HT40+ ;;
      *) echo "!! bandwidth must be 20 or 40: '$b'" >&2; return 1;;
    esac
  else                                              # ---- "<ch> <HT20|HT40+|HT40->" ----
    CH=$a
    case "$b" in HT20|HT40+|HT40-) BW=$b;; 20) BW=HT20;; 40) BW=HT40+;;
      *) echo "!! bandwidth must be HT20 / HT40+ / HT40- (plain \"HT40\" is rejected by iw): '$b'" >&2; return 1;; esac
  fi
  PRIMARY_MHZ=$(ch_to_mhz "$CH") || return 1
  case "$BW" in
    HT20)  WIDTH_MHZ=20; CENTER_MHZ=$PRIMARY_MHZ; CH2=;;
    HT40+) WIDTH_MHZ=40; CENTER_MHZ=$((PRIMARY_MHZ + 10)); CH2=$((CH + 4));;
    HT40-) WIDTH_MHZ=40; CENTER_MHZ=$((PRIMARY_MHZ - 10)); CH2=$((CH - 4));;
  esac
  BW_LABEL="${CENTER_MHZ}MHz(${WIDTH_MHZ}MHz)"
  export CH BW CENTER_MHZ WIDTH_MHZ PRIMARY_MHZ CH2 BW_LABEL
}

# RATE for monitor_tx_rate from BW and MCS (same rule as csi-scripts/tx_capture.sh):
# ant A (0x4000) + HT (0x100) + 40 MHz bit (0x800 when HT40) + MCS 0-7 (1 spatial stream)
derive_rate() {
  local mcs=${1:-1} ht40bit=0
  case "$BW" in HT40*) ht40bit=0x800;; esac
  printf '0x%x' $((0x4100 | ht40bit | mcs))
}

mcs_text() {   # MCS index (1 stream) -> modulation / coding rate / nominal rate at this BW (long GI)
  local m=${1:-1} mod cr r20 r40
  case "$m" in
    0) mod=BPSK;   cr=1/2; r20=6.5;  r40=13.5;;
    1) mod=QPSK;   cr=1/2; r20=13;   r40=27;;
    2) mod=QPSK;   cr=3/4; r20=19.5; r40=40.5;;
    3) mod=16-QAM; cr=1/2; r20=26;   r40=54;;
    4) mod=16-QAM; cr=3/4; r20=39;   r40=81;;
    5) mod=64-QAM; cr=2/3; r20=52;   r40=108;;
    6) mod=64-QAM; cr=3/4; r20=58.5; r40=121.5;;
    7) mod=64-QAM; cr=5/6; r20=65;   r40=135;;
    *) echo "MCS$m"; return;;
  esac
  local r=$r20; [ "$WIDTH_MHZ" = 40 ] && r=$r40
  echo "OFDM (IEEE 802.11n HT), ${mod} coding rate ${cr}, 1 spatial stream, MCS${m}, nominal ${r} Mbps"
}

now_str() { date '+%Y-%m-%d %H:%M:%S'; }

# print_header <"TX side"|"RX side"> <display name>   (the block the comprehensive-test report asks for)
print_header() {
  local side=$1 name=$2
  echo "=================================================================="
  echo "Comprehensive test result"
  echo "$name"
  echo "${side}: ${BW_LABEL}"
  now_str
  echo "------------------------------------------------------------------"
  if [ -n "$CH2" ]; then
    echo "Frequency   : centre ${CENTER_MHZ} MHz / occupied bandwidth ${WIDTH_MHZ} MHz  (ch${CH} ${BW} = ch${CH}+ch${CH2}, primary ${PRIMARY_MHZ} MHz)"
  else
    echo "Frequency   : centre ${CENTER_MHZ} MHz / occupied bandwidth ${WIDTH_MHZ} MHz  (ch${CH} ${BW})"
  fi
}

# ~/csi_data/YYYYMMDD/YYYYMMDD_HHMMSS_<name>_<centre>MHz_<width>MHz   (name: spaces and / -> _)
out_base() {
  local name=$1 dir="$HOME/csi_data/$(date +%Y%m%d)"
  mkdir -p "$dir"
  echo "$dir/$(date +%Y%m%d_%H%M%S)_$(echo "$name" | tr ' /' '__')_${CENTER_MHZ}MHz_${WIDTH_MHZ}MHz"
}

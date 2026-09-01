#!/bin/bash
# Intel 5300 CSI RX -> 制御PCへSSHストリーム（multi-RX用）
# 使い方: ~/rx_stream.sh <rx_id:0|1> <user@control> [ラベル] [CH] [BW]
#   例:   ~/rx_stream.sh 0 kota@192.168.1.10 walking
#   例:   ~/rx_stream.sh 0 kota@192.168.1.10 w52test 48 HT40-
RXID=${1:?rx_id(0 or 1) が必要}
CONTROL=${2:?制御PC user@host が必要}
LABEL=${3:-csi}
# 既定は run_experiment.sh と同じ ch157 HT40+ (157+161, 中心5795MHz, 40MHz)。
# TX の ch/BW と表記まで完全に一致させること。ズレると1パケットも受からない。
CH=${4:-157}
BW=${5:-HT40+}
IF=wlan1
CTRL_OUT="csi_data/rx${RXID}.bin"   # 制御PC側の保存名(ホーム相対)

# --- 電波設定（rx_capture.sh と同じ）---
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
echo "--- freq ---"; iwconfig "$IF" | grep -i freq

# --- ローカルバックアップ先 ---
DIR="$HOME/csi_data/$(date +%Y%m%d)"; mkdir -p "$DIR"
LOCAL="$DIR/$(date +%Y%m%d_%H%M%S)_rx${RXID}_${LABEL}.csi"

echo "=== stream rx$RXID -> $CONTROL:~/$CTRL_OUT  (local backup: $LOCAL)  Ctrl+C で停止 ==="
# csi_stream(要root) -> tee(ローカル保存) -> ssh(制御PCの csi_recv でスタンプ保存)
sudo ~/linux-80211n-csitool-supplementary/multi-rx/csi_stream /dev/stdout \
  | tee "$LOCAL" \
  | ssh "$CONTROL" "mkdir -p ~/csi_data && ~/linux-80211n-csitool-supplementary/multi-rx/csi_recv $RXID ~/$CTRL_OUT"

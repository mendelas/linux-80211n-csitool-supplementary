#!/bin/bash
# Intel 5300 CSI RX -> 制御PCへSSHストリーム（multi-RX用）
# 使い方: ~/rx_stream.sh [--resetup] <rx_id:0|1> <user@control> [ラベル] [CH] [BW]
#   例:   ~/rx_stream.sh 0 kota@192.168.1.10 walking
#   例:   ~/rx_stream.sh 0 kota@192.168.1.10 w52test 48 HT40-
# ドライバの再読込はしない (再読込のたびに NIC が再初期化され、素子1本の位相が π 単位で変わる)。
# 無線の準備 (rx_setup.sh) は設置ごとに1回。ここでは radio_check.sh で確認だけして、
# できていなければ止まる。--resetup を付けたときだけ rx_setup.sh で準備し直す。
# radio_check.sh はこのノードの clone (下の SUPP) から使う。古い clone なら git pull / コピーしておく。
RESETUP=0; [ "${1:-}" = --resetup ] && { RESETUP=1; shift; }
RXID=${1:?rx_id(0 or 1) が必要}
CONTROL=${2:?制御PC user@host が必要}
LABEL=${3:-csi}
# 既定は run_experiment.sh と同じ ch157 HT40+ (157+161, 中心5795MHz, 40MHz)。
# TX の ch/BW と表記まで完全に一致させること。ズレると1パケットも受からない。
CH=${4:-157}
BW=${5:-HT40+}
IF=wlan1
CTRL_OUT="csi_data/rx${RXID}.bin"   # 制御PC側の保存名(ホーム相対)

SUPP=~/linux-80211n-csitool-supplementary/multi-rx

# --- 電波: 準備は --resetup のときだけ。毎回は確認だけ (再読込・down/up・チャネル再設定なし) ---
[ "$RESETUP" = 1 ] && "$SUPP/rx_setup.sh" "$CH" "$BW" "$IF"
if ! bash "$SUPP/radio_check.sh" rx "$CH" "$BW" "$IF"; then
  echo "!! 無線の準備ができていない。設置ごとに1回:  $SUPP/rx_setup.sh $CH $BW $IF"
  echo "!! (準備し直して収録するなら:  ~/rx_stream.sh --resetup $RXID $CONTROL $LABEL $CH $BW)"
  exit 1
fi

# --- ローカルバックアップ先 ---
DIR="$HOME/csi_data/$(date +%Y%m%d)"; mkdir -p "$DIR"
LOCAL="$DIR/$(date +%Y%m%d_%H%M%S)_rx${RXID}_${LABEL}.csi"

echo "=== stream rx$RXID -> $CONTROL:~/$CTRL_OUT  (local backup: $LOCAL)  Ctrl+C で停止 ==="
# csi_stream(要root) -> tee(ローカル保存) -> ssh(制御PCの csi_recv でスタンプ保存)
sudo ~/linux-80211n-csitool-supplementary/multi-rx/csi_stream /dev/stdout \
  | tee "$LOCAL" \
  | ssh "$CONTROL" "mkdir -p ~/csi_data && ~/linux-80211n-csitool-supplementary/multi-rx/csi_recv $RXID ~/$CTRL_OUT"

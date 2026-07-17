#!/bin/bash
# 制御PCから全機を操作して1実験を実行 → merged.bin まで作る
# usage: ./run_experiment.sh <ラベル> [実験秒数]
set -u
LABEL=${1:-exp}; SECS=${2:-60}

# ===== 設定（環境に合わせる）=====
RX0=kota@192.168.100.11
RX1=kota@192.168.100.12
TX=kota@192.168.100.13
CH=165; BW=HT20; RATE=0x4101; PAYLOAD=100; DELAY=1000
REMOTE=~/linux-80211n-csitool-supplementary          # 各機のrepo位置
HERE=$(cd "$(dirname "$0")" && pwd)                  # 制御PC側のmulti-rx
OUTDIR=$HOME/csi_data/$(date +%Y%m%d)
# ================================
NPKTS=$(( SECS * 1000000 / DELAY ))                  # 秒数→パケット数
mkdir -p "$OUTDIR"
STAMP=$(date +%Y%m%d_%H%M%S)
R0=$OUTDIR/${STAMP}_${LABEL}_rx0.bin
R1=$OUTDIR/${STAMP}_${LABEL}_rx1.bin
MG=$OUTDIR/${STAMP}_${LABEL}_merged.bin

echo "=== 1) RX 電波設定 ==="
ssh "$RX0" "~/rx_setup.sh $CH $BW"
ssh "$RX1" "~/rx_setup.sh $CH $BW"
echo "=== 2) TX 電波設定+レート ==="
ssh "$TX"  "~/tx_setup.sh $CH $BW $RATE"

echo "=== 3) RX ストリーム開始 ==="
ssh "$RX0" "sudo $REMOTE/multi-rx/csi_stream /dev/stdout" 2>/dev/null | "$HERE/csi_recv" 0 "$R0" &
P0=$!
ssh "$RX1" "sudo $REMOTE/multi-rx/csi_stream /dev/stdout" 2>/dev/null | "$HERE/csi_recv" 1 "$R1" &
P1=$!
sleep 2

echo "=== 4) TX 注入開始（${SECS}秒 / $NPKTS pkts）==="
ssh "$TX" "cd $REMOTE/injection && sudo ./random_packets $NPKTS $PAYLOAD 1 $DELAY" >/dev/null 2>&1 &
PT=$!

echo "=== CSIが流れ出すまで待機（〜1分）→ 実験を開始してください ==="
wait $PT
echo "=== 5) TX終了。ストリーム停止 ==="
ssh "$RX0" "sudo pkill -f csi_stream" 2>/dev/null
ssh "$RX1" "sudo pkill -f csi_stream" 2>/dev/null
kill $P0 $P1 2>/dev/null; wait $P0 $P1 2>/dev/null

echo "=== 6) マージ ==="
"$HERE/csi_merge" "$MG" "$R0" "$R1"
"$HERE/read_merged" "$MG" | tail -3
echo "=== 完了: $MG ==="

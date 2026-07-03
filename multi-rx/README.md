# multi-rx: 2台のRXのCSIを1ファイルに（クロック同期不要）

1台のTX → 2台のRXが同じ電波を観測。各RXのCSIを **SSHで制御PCへリアルタイム送信**し、
制御PCが**到着時に自分の時計(CLOCK_MONOTONIC)でスタンプ** → 実験後に1ファイルへマージ。
制御PCの1つの時計が共通基準になるので、**RX間のクロック同期は不要**（相対整列のみ、誤差=LANジッタ数ms）。

## ツール
- `csi_stream`（RX機で make）: log_to_file と同じ。ただし状態表示を stderr に出し、stdout はCSIバイナリ専用（pipe用）。
- `csi_recv`（制御PC）: stdinのCSIストリームをフレーム分解し、制御PC時計でスタンプして保存。
- `csi_merge`（制御PC）: 複数の csi_recv 出力を時刻順にマージして1ファイルに。
- `read_merged`（制御PC）: マージ済みファイルを読む最小サンプル（C++後段の入口）。

## レコード形式（マージ後）
```
double   t         // 制御PCの相対時刻[秒]（2RX共通軸）
uint8_t  rx_id     // 0 or 1
uint16_t len       // ペイロード長
uint8_t  payload[len]  // 元のCSIレコード（先頭0xbb=CSI, 中にNIC timestamp_low）
```

## 使い方
### 準備
- 制御PC: `make`（csi_recv/csi_merge/read_merged ができる）
- 各RX機: `make csi_stream`（CSIツール導入済みの5300ノート上で）

### 実験（各RX機で。ローカルバックアップ付き）
CSIモードで起動後（rx_capture.sh のドライバ設定を先に済ませておく）:
```bash
# RX0
sudo ~/multi-rx/csi_stream /dev/stdout \
  | tee ~/csi_data/$(date +%Y%m%d)/rx0_$(date +%H%M%S).csi \
  | ssh user@control "~/multi-rx/csi_recv 0 ~/csi_data/rx0.bin"
# RX1 も同様に csi_recv 1 ~/csi_data/rx1.bin
```
→ 実験。数秒〜1分でCSIが流れ始める。終わったら各 csi_stream を Ctrl+C。

### 実験後（制御PC）
```bash
~/multi-rx/csi_merge ~/csi_data/merged.bin ~/csi_data/rx0.bin ~/csi_data/rx1.bin
~/multi-rx/read_merged ~/csi_data/merged.bin   # 確認
```

## 注意
- **RX機は csi_stream の前に、モニターモード/ch/connector_log の設定を済ませる**こと
  （rx_capture.sh の前半＝log_to_file を呼ぶ直前まで）。csi_stream は log_to_file の置き換え。
- payload の中身（CSI行列）を C++ で取り出すには CSIツールの bfee 形式(read_bfee.c)を移植する。

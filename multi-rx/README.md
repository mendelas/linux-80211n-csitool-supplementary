# multi-rx: 1TX → 2RX の CSI を1ファイルに（クロック同期不要）

1台のTXが撒く電波を2台のRX(Intel 5300)が観測し、各RXのCSIを**SSHで制御PCへリアルタイム送信**。
制御PCが**到着時に自分の時計(CLOCK_MONOTONIC)でスタンプ**し、実験後に時刻順で1ファイルへマージ。
→ 制御PCの1つの時計が共通基準なので**RX間クロック同期は不要**（相対整列のみ・誤差=LANジッタ数ms、sub-100ms余裕）。

## 役割と必要なもの
| 機 | 役割 | 必要なもの |
|---|---|---|
| TX ノート | 5300でパケット注入 | カーネルrepo(3.5.7) + supplementary + CSIファーム |
| RX0/RX1 ノート | 5300でCSI観測→送信 | カーネルrepo(3.5.7) + supplementary + CSIファーム |
| **制御PC** | 受信・スタンプ・マージ・解析 | **supplementary のみ**（+ g++, sshd, MATLAB/Octave）。5300もカーネルも不要 |

## ツール
| ツール | どこで | 役割 |
|---|---|---|
| `csi_stream` | RX機 | log_to_file と同じ。状態表示をstderrへ、stdoutはCSI専用(pipe用) |
| `csi_recv` | 制御PC | stdinのCSIをフレーム分解し、制御PC時計でスタンプ保存 |
| `csi_merge` | 制御PC | 複数RXの出力を時刻順にマージ→1ファイル |
| `read_merged` | 制御PC | マージ済みを読むC++サンプル(後段の入口) |
| `rx_stream.sh` | RX機 | 電波設定 + csi_stream|tee|ssh を一発起動 |

## レコード形式（マージ後 / C++後段が読む）
```
double   t         // 制御PCの相対時刻[秒]（2RX共通軸）
uint8_t  rx_id     // 0 or 1
uint16_t len       // ペイロード長
uint8_t  payload[len]  // 元のCSIレコード(先頭0xbb=CSI, 中にNIC timestamp_low)
```

---

## セットアップ（1回だけ）
### 制御PC
```bash
git clone https://github.com/mendelas/linux-80211n-csitool-supplementary.git
make -C linux-80211n-csitool-supplementary/multi-rx     # csi_recv/csi_merge/read_merged
# sshd を有効化（RXからssh流入するため）: sudo apt-get install openssh-server
# 各RXから制御PCへ鍵認証でsshできるようにしておく(ssh-copy-id)
```
### 各RX機（5300ノート, CSIツール導入済み）
```bash
make -C ~/linux-80211n-csitool-supplementary/multi-rx csi_stream
# rx_stream.sh を取得
wget https://raw.githubusercontent.com/mendelas/linux-80211n-csitool-supplementary/master/multi-rx/rx_stream.sh -O ~/rx_stream.sh && chmod +x ~/rx_stream.sh
# 先頭の CH= を空きch(scan_channels.shで確認)に合わせる
```

## 実行（本番）
```bash
# 1) TX機: 注入開始
~/tx_capture.sh                      # ch/rate は tx_capture.sh の設定

# 2) RX0機: 設定+ストリーム（ローカルバックアップ tee 込み）
~/rx_stream.sh 0 kota@<制御PCのIP> walking
# 3) RX1機:
~/rx_stream.sh 1 kota@<制御PCのIP> walking
#   → 各RXで freq を確認。数秒〜1分でCSIが流れ始める

# 4) 実験本番 → 終わったら 各 rx_stream.sh を Ctrl+C、TXも停止
```
制御PCには `~/csi_data/rx0.bin` `~/csi_data/rx1.bin` が溜まる。

## マージ・確認（制御PC, 実験後）
```bash
cd ~/linux-80211n-csitool-supplementary/multi-rx
./csi_merge ~/csi_data/merged.bin ~/csi_data/rx0.bin ~/csi_data/rx1.bin
./read_merged ~/csi_data/merged.bin        # t順にrx0/rx1が並ぶ
```

## 解析（制御PC, MATLAB/Octave）
- CSI行列の取り出しは supplementary/matlab の `read_bf_file.m`/`get_scaled_csi.m`。
- merged.bin の payload は元のCSIレコードなので、C++後段で `read_bfee.c` のロジックを移植すれば行列を取り出せる。

## 注意
- **csi_stream の前に電波設定が必要**（rx_stream.sh が自動でやる）。csi_stream 単体は log_to_file の置換。
- リアルタイム送信のため LAN 断でその分欠落するが、**tee のローカル `.csi` が保険**（後から通常解析も可）。
- 各RXの `CH=` と TX の `CH=` は一致必須。空きchを scan_channels.sh で選ぶ。
- 制御PCは普通のLinuxでOK（5300・カーネル不要）。

# single-link: 1TX → 1RX 総合試験用スクリプト（実験試験局申請）

**単一送信機・単一受信機**の総合試験を**制御PCから1コマンドで実行**し、申請書の「総合試験結果」に貼れる
英語ログ（送信側ブロック・受信側ブロック）を**制御PCの端末に出し、制御PCに保存**するためのセット。
`multi-rx/`（スイッチングハブ + 制御PC + ssh）と同じ配線・同じ `hosts.sh` を使う。
**既存ファイルは一切変更していない**（`multi-rx/` の `hosts.sh` / `rx_setup.sh` / `tx_setup.sh` / `csi_stream` をそのまま呼ぶ）。
スクリプトの出力はすべて英語、README だけ日本語。

```
        [TX laptop]  tx_setup.sh ; tx_inject -p        [RX laptop]  rx_setup.sh ; csi_stream
          192.168.100.<TX_NODE>                            192.168.100.<RX_NODES[0]>
               │ 802.11n HT frames (1000/s) ──無線──▶          │
   ────────────┴──── スイッチングハブ（有線LAN）────────────────┴────────
                                   │ ssh (pull)
                             [制御PC]  ./run_test.sh 5795 40 NICT-ISAC-Dev1 60
                              ・TX 側の 1 行/秒を受け取り時刻付与   → …_tx.log
                              ・RX 側の生 CSI を受け取り csi_report で 1 行/秒 → …_rx.log + …_rx.csi
                              ・最後に 送信側ブロック + 受信側ブロック → …_report.txt（端末にも表示）
```
時刻はすべて**制御PCの時計**で付く（TX/RX ラップトップの時計合わせ不要）。

---

## 1. 結果はどこに・どう格納されるか

### 既存 multi-rx（参考）
| 側 | 残るもの | 形式 |
|---|---|---|
| TX | **何も残らない**（`random_packets` の出力は `/dev/null`） | — |
| RX → 制御PC | `~/csi_data/YYYYMMDD/<日時>_<ラベル>_rxN.bin` → `csi_merge` → `_merged.bin` | 1レコード = `[double t 制御PC時刻][uint8 rx_id][uint16 len][payload]` |
| payload | `0xbb` + `iwl_bfee_notif`（timestamp_low, bfee_count, Nrx, Ntx, rssiA/B/C, noise, agc, antenna_sel, len, rate, CSI 行列） | CSI Tool の bfee 形式そのまま（`netlink/bfee.h`） |

### single-link（制御PCの `~/csi_data/YYYYMMDD/`、1 回の実行で 4 ファイル）
| ファイル | 内容 |
|---|---|
| `<日時>_<表示名>_<中心MHz>MHz_<幅>MHz_tx.log` | 送信側ブロック: ヘッダ（表示名 / TX side: 5795MHz(40MHz) / 日時 / 周波数 / 設備 / 電波の型式 / 空中線電力）+ `tx_setup.sh` の設定結果 + フレーム内容 + **1 秒ごとの送信数** + 開始/終了 |
| `<日時>_<表示名>_<中心MHz>MHz_<幅>MHz_rx.log` | 受信側ブロック: ヘッダ（表示名 (counterpart) / RX side: … / 日時 / 周波数 / 設備）+ `rx_setup.sh` の設定結果 + **1 秒ごとの受信数・欠落・RSS・Ntx×Nrx・レート** + 開始/終了 |
| `<日時>_<表示名>_<中心MHz>MHz_<幅>MHz_report.txt` | 上 2 つを「送信側 → 受信側」の順に結合したもの = **申請書に貼る総合試験結果** |
| `<日時>_<表示名>_<中心MHz>MHz_<幅>MHz_rx.csi` | 生 CSI 全件。**CSI Tool 標準の `.csi` 形式** `[uint16 BE len][payload]`（`log_to_file` と同一）→ `matlab/read_bf_file.m` でそのまま読める |

1000 Hz の PRF で全件を端末に出すと読めないので、**表示は開始・1 秒ごと・終了**に集約し、全件は `.csi` にだけ残す。

---

## 2. セットアップ（各機 1 回）

前提: multi-rx の環境（固定 IP、ssh 鍵、NOPASSWD sudo、各機の `~/rx_setup.sh` `~/tx_setup.sh`、`csi_stream`、TX 機の LORCON）が整っていること（`multi-rx/check_nodes.sh` で全 ok）。

```bash
# 制御PC（csi_report を使う。kernel ヘッダ = linux-headers-$(uname -r) が必要、普通は入っている）
cd ~/linux-80211n-csitool-supplementary && git pull && make -C single-link csi_report

# TX 機（tx_inject = random_packets と同じく LORCON 必須）
cd ~/linux-80211n-csitool-supplementary && git pull && make -C single-link tx_inject

# RX 機: 追加は不要（既存の csi_stream / rx_setup.sh を使う）。git pull だけしておく
```
TX / RX にする機は `multi-rx/hosts.sh` の `TX_NODE` / `RX_NODES`（先頭が RX）。実行時に `TX_NODE=14 RX_NODE=11 ./run_test.sh …` でも変えられる。

---

## 3. 使い方

### 3-1. 1 回だけ（周波数・帯域幅・表示名・秒数はすべてコマンド引数）
```bash
cd ~/linux-80211n-csitool-supplementary/single-link
./run_test.sh <中心MHz> <20|40> [表示名] [秒数]
./run_test.sh 5795 40 NICT-ISAC-Dev1 60        # 中心 5795 MHz / 40 MHz (= ch157 HT40+)
./run_test.sh 5765 20 NICT-ISAC-Dev2 60        # 中心 5765 MHz / 20 MHz (= ch153 HT20)
./run_test.sh 157 HT40+ NICT-ISAC-Dev3         # iw 表記でも可。秒数省略 = plan.sh の SECS
```
流れ: RX 電波設定 → RX ストリーム開始 → TX 電波設定 + 送信開始（1 ssh）→ **CSI が流れ始めるのを待つ（最大 120 s）** → **秒数ぶん記録** → TX 停止 → RX 停止 → レポート表示。
途中 Ctrl-C でも両機を止めてレポートを出す。

| 申請書の欄 | コマンド | 内部設定 |
|---|---|---|
| 5795MHz(40MHz) | `./run_test.sh 5795 40 NICT-ISAC-Dev1` | ch157 HT40+ (157+161), monitor_tx_rate 0x4901 |
| 5765MHz(20MHz) | `./run_test.sh 5765 20 NICT-ISAC-Dev1` | ch153 HT20, 0x4101 |
| 5785MHz(20MHz) | `./run_test.sh 5785 20 NICT-ISAC-Dev1` | ch157 HT20, 0x4101 |
| 5805MHz(20MHz) | `./run_test.sh 5805 20 NICT-ISAC-Dev1` | ch161 HT20, 0x4101 |

### 3-2. 順番に全部回す（Dev1 → Dev2 → Dev3 × 4 周波数）
試験計画は **`plan.sh`** に書く（表示名の接頭辞・装置の順番・周波数ケースの順番・秒数）:
```bash
NAME_PREFIX=NICT-ISAC          # 表示名 = NICT-ISAC-Dev<N>（RX 側は " (counterpart)" が付く）
DEVICES=(1 2 3)                # 試験する装置の順番。"1:13" と書けば Dev1 は 13 番機を TX にする
CASES=("5795 40" "5765 20" "5785 20" "5805 20")   # 1 装置あたりの周波数ケース（この順）
SECS=60                        # 1 ケースの記録秒数（CSI が流れ始めてから）
```
```bash
./run_plan.sh            # plan.sh の全装置 × 全ケース（12 回）。毎回「装置を用意して Enter」(s=スキップ, q=終了)
./run_plan.sh 2          # Dev2 だけ
./run_plan.sh 2 3        # Dev2 → Dev3
SECS=5 ./run_plan.sh 1   # 短く通し確認
```
装置を差し替えるだけで TX ラップトップが同じなら `DEVICES=(1 2 3)` のまま。装置ごとにラップトップが違うなら `DEVICES=(1:13 2:14 3:15)`。

### 3-3. LAN が無いときの代替（各機で単独実行、時刻は各機の時計）
```bash
# RX 機で                                  # TX 機で
./rx_test.sh 5795 40 NICT-ISAC-Dev1        ./tx_test.sh 5795 40 NICT-ISAC-Dev1 60
```
出力・保存形式は同じ（各機の `~/csi_data/` に `_rx.log`+`_rx.csi` / `_tx.log`）。両機の `date` を合わせておく（`clock_sync.sh <user@相手>` で ssh 経由で合わせられる）。

---

## 4. 出力例（制御PCの端末 / `_report.txt`）

```
==================================================================
Comprehensive test result
NICT-ISAC-Dev1
TX side: 5795MHz(40MHz)
2026-11-05 14:03:10
------------------------------------------------------------------
Frequency   : centre 5795 MHz / occupied bandwidth 40 MHz  (ch157 HT40+ = ch157+ch161, primary 5785 MHz)
Equipment   : Intel WiFi Link 5300 (IEEE 802.11n), monitor-mode injection (LORCON, mon0), laptop kota@192.168.100.13 (wlan1)
Emission    : OFDM (IEEE 802.11n HT), QPSK coding rate 1/2, 1 spatial stream, MCS1, nominal 27 Mbps, monitor_tx_rate 0x4901
TX power    : setting 15 dBm (31.6 mW nominal); the application states the MEASURED antenna-port power
Log         : /home/kota/csi_data/20261105/20261105_140310_NICT-ISAC-Dev1_5795MHz_40MHz_tx.log   (time stamps = control PC ctrl clock)
------------------------------------------------------------------
14:03:22  TX freq: 5.785 GHz
14:03:22  TX power: 15 dBm (applied)
14:03:22  TX rate: 0x4901
14:03:22  	channel 157 (5785 MHz), width: 40 MHz, center1: 5795 MHz
14:03:22  	txpower 15.00 dBm
14:03:23  Frame    : IEEE 802.11 data frame (24-byte header + 100-byte pseudo-random (LFSR) payload + 4-byte FCS = 128 bytes)
14:03:23  DA / SA / BSSID : 00:16:ea:12:34:56 / 00:16:ea:12:34:56 / ff:ff:ff:ff:ff:ff   (one-way injection, no acknowledgement)
14:03:23  Interval : 1000 us (= 1000 frames/s)   duration : until stopped
14:03:23  --- TX start ---
14:03:24  sent   812 frames/s  total     812  (elapsed 1 s)
14:03:25  sent  1000 frames/s  total    1812  (elapsed 2 s)
   ...（1 秒に 1 行）...
14:04:29  sent  1000 frames/s  total   66812  (elapsed 66 s)
14:04:30  sent   412 frames/s  total   67224  (elapsed 67 s)
14:04:30  --- TX end (Ctrl-C / SIGTERM) ---
14:04:30  sent 67224 frames / 67.2 s = 1000 frames/s   failed 0

==================================================================
Comprehensive test result
NICT-ISAC-Dev1 (counterpart)
RX side: 5795MHz(40MHz)
2026-11-05 14:02:58
------------------------------------------------------------------
Frequency   : centre 5795 MHz / occupied bandwidth 40 MHz  (ch157 HT40+ = ch157+ch161, primary 5785 MHz)
Equipment   : Intel WiFi Link 5300 (IEEE 802.11n), monitor mode, CSI firmware (connector_log=0x1), laptop kota@192.168.100.11 (wlan1)
Reception   : CSI (30 subcarriers x Ntx x Nrx, complex) from every received frame; receive only, no transmission
              RX freq: 5.785 GHz
              channel 157 (5785 MHz), width: 40 MHz, center1: 5795 MHz
Recording   : /home/kota/csi_data/20261105/20261105_140258_NICT-ISAC-Dev1_5795MHz_40MHz_rx.csi   (time stamps = control PC ctrl clock)
------------------------------------------------------------------
14:03:10  waiting (no CSI yet: TX not started / channel or bandwidth mismatch?)
14:03:20  waiting (no CSI yet: TX not started / channel or bandwidth mismatch?)
14:03:29  --- RX start (first CSI record) ---
14:03:30  recv   640 rec/s  total     640  lost 0  RSS  -52.3 dBm (rssi 36/38/41 agc 44)  Ntx x Nrx 1x3  HT40 MCS1
14:03:31  recv  1000 rec/s  total    1640  lost 0  RSS  -52.1 dBm (rssi 36/38/41 agc 44)  Ntx x Nrx 1x3  HT40 MCS1
   ...（1 秒に 1 行）...
14:04:30  recv  1000 rec/s  total   60640  lost 0  RSS  -52.4 dBm (rssi 36/38/41 agc 44)  Ntx x Nrx 1x3  HT40 MCS1
14:04:31  recv   412 rec/s  total   61052  lost 0  RSS  -52.2 dBm (rssi 36/38/41 agc 44)  Ntx x Nrx 1x3  HT40 MCS1
14:04:32  --- RX end (stream ended) ---
14:04:32  received 61052 CSI records / ~62 s = ~985 rec/s   lost (est., bfee_count gaps) 0   first 14:03:29  last 14:04:31
14:04:32  saved: /home/kota/csi_data/20261105/20261105_140258_NICT-ISAC-Dev1_5795MHz_40MHz_rx.csi (CSI-tool .csi format, readable by read_bf_file.m)
```
（数値は例。各行は**その 1 秒が終わった時刻**に出る。`RSS` は `matlab/get_total_rss.m` と同じ式
`10log10(Σ10^(rssi/10)) − 44 − agc` の 1 秒平均、`lost` は bfee_count の連番飛びからの推定。
実行中の端末には TX/RX 両方の行が `HH:MM:SS  TX  …` / `HH:MM:SS  RX  …` と交互に流れ、終了時に上のレポートがまとめて出る。）

---

## 5. パラメータ

| どこで | 何を | 既定 |
|---|---|---|
| コマンド引数 | 中心周波数 / 帯域幅 / 表示名 / 秒数 | — / — / `<NAME_PREFIX>-Dev1` / `SECS` |
| `plan.sh` | `NAME_PREFIX` `DEVICES` `CASES` `SECS` | NICT-ISAC / 1 2 3 / 4 ケース / 60 |
| `multi-rx/hosts.sh` | どの機が TX / RX（`TX_NODE` / `RX_NODES[0]`） | 13 / 11 |
| 環境変数 | `TX_NODE` `RX_NODE`（その回だけ機を変える） | hosts.sh |
| 環境変数 | `TXPWR`(dBm) `MCS`(0–7) `PAYLOAD`(byte) `DELAY`(µs) `IF` `RATE` | 15 / 1 / 100 / 1000 / wlan1 / BW と MCS から自動 |

例: `TXPWR=10 MCS=3 ./run_test.sh 5785 20 NICT-ISAC-Dev2 30`

---

## 6. 注意

- **40 MHz の中心は 5300 の EEPROM ペアだけ**: 5755 (149+153) / 5795 (157+161)（UNII-3）、5190 / 5230（W52）。他（例 5775）はエラーにする。
- **中心 5795/5765/5785/5805 MHz は免許が要る**（UNII-3。日本では Wi-Fi 割当が無く ETC/DSRC 帯と重なる）。免許前の動作確認は電波暗室/シールドボックスか、免許不要の `./run_test.sh 5230 40`（ch44 HT40+, W52）で。
- **RX 機は送信しない**（monitor mode のみ）。申請は TX 機のみ。
- 空中線電力は**設定値ではなく空中線端の実測値**を記載する。ログの「setting 15 dBm (31.6 mW nominal)」は設定値（実測は 25 mW 未満 = 指定事項内、`multi-rx/txpower_sweep.sh` 冒頭参照）。
- 5 GHz は注入開始から CSI が流れ出すまで数秒〜1 分かかる。`run_test.sh` はそれを待ってから秒数を数える（TX ログの方が長くなるのは正常）。
- 送受の ch/帯域は `run_test.sh` が同じ値を両機に渡すのでズレない。ヘッダの `width` / `center1` が両ブロックで一致していることだけ確認。

---

## 7. トラブル

| 症状 | 原因 / 対処 |
|---|---|
| `csi_report missing` | 制御PCで `make -C single-link csi_report`（`/lib/modules/$(uname -r)/build` が無ければ `sudo apt install linux-headers-$(uname -r)`） |
| TX 行に `tx_inject: No such file` | TX 機で `git pull && make -C single-link tx_inject`（LORCON 必須） |
| `RX setup failed` | ssh 鍵 / NOPASSWD / `~/rx_setup.sh` が無い → `multi-rx/check_nodes.sh` |
| RX が `waiting` のまま 120 s | ①TX 行にエラーが出ていないか（LORCON / monitor_tx_rate）②空き ch か ③CSI ファーム（csifw=csi）④立ち上がり待ち |
| `Ntx x Nrx` に `(mixed)` | 1 秒内に行列サイズが変わった = 別の送信機も拾っている（空き ch でない） |
| 受信が 1000 rec/s より大きく少ない | 低電力注入が埋もれている（混雑 ch）/ 距離。`RSS` を見る |
| Ctrl-C 後も TX 機が送信し続ける | `ssh kota@192.168.100.13 "sudo pkill -x tx_inject"` |

関連: `multi-rx/README.md`（配線・ノード設定・複数 RX）、kernel repo `SETUP_CSITOOL_JA.md` 4-C（標準設定と申請諸元）、`csi-scripts/`（単体キャプチャ版）。

# multi-rx: マルチRX CSI 実験セットアップ（1TX → N台RX → 制御PCで1ファイル）

制御PCから全機を SSH で操作し、各RXのCSIをリアルタイムに集約・時刻付与・1バイナリへ統合する。
**RX間のクロック同期は不要**（制御PCの1つの時計が共通基準。誤差=LANジッタ数ms）。
ふたを閉じたラップトップを「箱」として運用でき、操作は制御PCの1コマンドで完結する。

---

## 1. 構成

```
         [TX]  Intel5300 / 3.5.7+ / CSIファーム        192.168.100.<TX_NODE>
           │ 802.11n HTパケットを注入(random_packets)
           ├──────────────▶ [rx0] Intel5300 monitor    192.168.100.<RX_NODES[0]>
           ├──────────────▶ [rx1] Intel5300 monitor    192.168.100.<RX_NODES[1]>
           └──────────────▶ [rxN] ...                  (台数は hosts.sh で自由)
                                │  │  (無線=CSI観測)
   ─── スイッチングハブ(有線LAN) ───┴──┴───────────────
                                │
                          [制御PC]  192.168.100.10 (可変でも可)
        ssh で全機を操作 / csi_recv で時刻スタンプ / csi_merge で統合
```

**★ IP はマシンに固定、役割(TX/RX)は実験ごとに `hosts.sh` で割り当てる。**
- 各ラップトップには**マシン番号 N**(= IP 末尾 `192.168.100.N`)を振り、本体に書いておく。N は一生変えない。
- 全機に `rx_setup.sh` と `tx_setup.sh` の両方を置くので、どの機でも TX にも RX にもなれる
  (TX になるには LORCON/`random_packets` のビルドも必要。`check_nodes.sh` の `inject` 列で分かる)。
- 「どの機が TX で、どの機が rx0, rx1, ...」は `hosts.sh` の `TX_NODE` / `RX_NODES` の2行だけ。

| 機 | 役割 | 必要なもの |
|---|---|---|
| ノード(全ラップトップ共通) | TX(注入) または RX(CSI観測→制御PCへ送出) | 5300 + kernel3.5.7 + CSIファーム + csi_stream + rx/tx_setup.sh。TX にするなら + LORCON/random_packets |
| **制御PC** | 指揮・時刻付与・統合・解析 | **supplementary のみ**（+ g++ / ssh / MATLAB）。5300もカーネルも不要 |

**SSHの向きは Pull**（制御PC → 各機）。RX/TX側は制御PCのIPを知らなくてよい
→ **固定IPが要るのはノードだけ**。制御PCのIPは自由（ただし同一サブネットに手動設定は必要＝ハブにDHCPが無いため）。

---

## 2. ネットワーク（固定IP = マシン番号）

| 機 | IP | 備考 |
|---|---|---|
| 制御PC | 192.168.100.10（同一サブネットなら何でも可） | ノードではない |
| ノード N | 192.168.100.N（N = 11, 12, 13, ...） | **本体に N を書く**。台帳は `hosts.sh` の冒頭コメント |

netmask `255.255.255.0` / **ゲートウェイ・DNSは不要**（閉じたLAN）。

### ノード（Ubuntu 14.04）＝ `/etc/network/interfaces`
**新しい機は `node_setup.sh` で一発**（固定IP・sshd・NOPASSWD・両スクリプト配置・ビルドまで。3-2 参照）:
```bash
cd ~/linux-80211n-csitool-supplementary/multi-rx && ./node_setup.sh 13     # ← この機を .13 にする
```
手動でやる場合の中身（**キャプチャ中に `service network-manager stop` するため、有線はNM管理外にする**のが重要）:
```bash
ip link                      # 有線IF名を確認（eth0 等）
sudo tee -a /etc/network/interfaces << 'EOF'

auto eth0
iface eth0 inet static
    address 192.168.100.13   # = マシン番号
    netmask 255.255.255.0
EOF
sudo ifdown eth0 2>/dev/null; sudo ifup eth0
ip addr show eth0
```

### 制御PC（Ubuntu 22.04/24.04 等）＝ NetworkManager
GUI: 設定→ネットワーク→有線→IPv4→**手動** → `192.168.100.10 / 255.255.255.0`（GW空欄）
または:
```bash
nmcli con show
sudo nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses 192.168.100.10/24 ipv4.gateway "" ipv4.dns ""
sudo nmcli con up "Wired connection 1"
```
※ 制御PCの**WiFi(インターネット)はそのまま**使える（有線と併用）。

---

## 3. セットアップ（各機1回だけ）

### 3-1. 制御PC
```bash
sudo apt-get update && sudo apt-get install -y build-essential git openssh-client   # ★g++必須
git clone https://github.com/mendelas/linux-80211n-csitool-supplementary.git
make -C linux-80211n-csitool-supplementary/multi-rx      # csi_recv / csi_merge / read_merged
# 有線に手動IP（上記）
# ssh鍵を配る（N = hosts.sh の ALL_NODES）
ls ~/.ssh/id_*.pub 2>/dev/null || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
for n in 11 12 13 14 15 16; do ssh-copy-id kota@192.168.100.$n; done
# 全機の状態を一覧（ping/ssh/sudo/カーネル/CSIファーム/rx.sh/tx.sh/inject）
./check_nodes.sh
```
※ 制御PCに **sshd は不要**（Pull方式）。

### 3-2. ノード（新しいラップトップを追加するとき。5300ノート・CSIツール導入済みが前提）
**★要ネットの作業を先に**（標準ファーム/通常カーネルでWiFiが使えるうちに）:
```bash
cd ~/linux-80211n-csitool-supplementary
git remote set-url origin https://github.com/mendelas/linux-80211n-csitool-supplementary.git
git pull
# TX にもなれるようにするなら LORCON（要ネット。RX 専用でよければ省略可）
sudo apt-get install -y libpcap-dev
cd ~ && git clone https://github.com/dhalperi/lorcon-old.git
cd lorcon-old && ./configure && make && sudo make install && sudo ldconfig
# ★一発セットアップ: 固定IP .N / sshd / NOPASSWD / rx_setup.sh+tx_setup.sh / csi_stream / random_packets
cd ~/linux-80211n-csitool-supplementary/multi-rx && ./node_setup.sh <N>
```
> NOPASSWD は必須（ssh越しはttyが無く sudo パスワードを入力できないため）。
> `node_setup.sh` は最後に wlan IF 名を表示する。**`wlan1` でなければ** `run_experiment.sh` / `rx_setup.sh` / `tx_setup.sh` の `IF=` を合わせる。

**オフラインでOK:**
```bash
# GRUB既定を 3.5.7 に（★memtestを選ばないよう“名前”で指定）
grep -E "menuentry '|submenu '" /boot/grub/grub.cfg | sed -E "s/.*(menuentry|submenu) '([^']*)'.*/\2/"
sudo nano /etc/default/grub
#   GRUB_DEFAULT="Advanced options for Ubuntu>Ubuntu, with Linux 3.5.7+"
sudo update-grub
# CSIファーム有効化 → 再起動
for f in /lib/firmware/iwlwifi-5000-*.ucode; do sudo mv "$f" "$f.standard"; done
sudo ln -sf iwlwifi-5000-2.ucode.sigcomm2010 /lib/firmware/iwlwifi-5000-2.ucode
sudo reboot          # → 3.5.7+ で自動起動すること
```
最後に制御PCの `hosts.sh` の `ALL_NODES` に N を足し、台帳コメントに機種/MACを書いて `./check_nodes.sh`。

### 3-3. 役割の割り当て（実験ごと）
`hosts.sh` の2行だけ:
```bash
TX_NODE=13              # TX にする機（check_nodes.sh で inject=ok の機）
RX_NODES=(11 12 14)     # rx0, rx1, rx2, ... の順。台数自由
```
`run_experiment.sh` / `txpower_sweep.sh` / `find_ht40_limit.sh` は全部これを読む。

---

## 4. 実験の実行

### 事前チェック（制御PCから一括）
```bash
./check_nodes.sh          # 全機。TX 行は tx.sh+inject=ok、RX 行は rx.sh=ok、全機 kernel 3.5.7+ / csifw=csi ならOK
```

### 空きチャネル調査（実験前）
どの ch が空いているかは **制御PC自身のWiFiで普通に調べればよい**（占有APや混雑chだと低電力注入が埋もれて受からない）。
```bash
# 制御PCで一発。5GHz(FREQ>=5000)の行を見て、AP が居ない/弱い ch を選ぶ
nmcli -f CHAN,FREQ,SIGNAL,SSID dev wifi list --rescan yes | sort -n
```
MAIN は ch48 固定にしたいので、ch48 に強い AP が無ければそのまま。混んでいれば W52内(ch36/44) の空きへ。
決めた ch を `run_experiment.sh` の `CH=` に設定（全機共通）。
（RX位置での注入帯フレーム実測まで見たい時だけ、RX機で `~/scan_channels.sh` を回す。通常は上の nmcli で十分。）

### 当日
1. 全ノード: 電源ON（3.5.7で自動起動）＋ LANケーブル接続 → **ふたを閉じて放置**
2. 制御PC:
   ```bash
   cd ~/linux-80211n-csitool-supplementary/multi-rx
   ./run_experiment.sh <ラベル> <秒数>     # 例: ./run_experiment.sh walking 60
   ```
   自動で: RX設定 → TX設定 → ストリーム開始 → 注入 → 停止 → **merged.bin**
3. 出力: `~/csi_data/YYYYMMDD/<日時>_<ラベル>_merged.bin`（+ rx0.bin / rx1.bin / ...）

> **CSIは開始から数秒〜1分で流れ出す**（5GHzの立ち上がり）。実験本番はそれを待ってから。

---

## 5. データ形式

### 統合ファイル（merged.bin）
```
1レコード:
  double   t         // 制御PCの相対時刻[秒]（全RX共通軸・CLOCK_MONOTONIC）
  uint8_t  rx_id     // RX_NODES の添字 0,1,2,...
  uint16_t len       // ペイロード長
  uint8_t  payload[len]  // 元のCSIレコード（先頭0xbb=CSI, 中にNIC timestamp_low）
```
→ `t` 昇順にソート済み。全 rx が到着時刻順に混在。

### 単体キャプチャ(.csi) との差
| | .csi（単体） | merged.bin |
|---|---|---|
| CSI本体(payload) | あり | **同一（そのまま保持）** |
| 制御PC時刻 `t` | ✗ | **✓** |
| `rx_id` | ✗ | **✓** |
→ **足したのは t と rx_id だけ**。CSIの中身は不変。

### 読み方
```bash
./read_merged ~/csi_data/日付/xxx_merged.bin        # t/rx_id/len/code を確認
```
CSI行列を取り出すには payload を CSIツールの bfee 形式で解釈（MATLAB: `read_bf_file.m`/`get_scaled_csi.m`、C++: `read_bfee.c` を移植）。

---

## 6. パラメータ（実験ごとに変える）

`hosts.sh`（役割）と `run_experiment.sh` 先頭（電波）:
| 変数 | 意味 | 備考 |
|---|---|---|
| `TX_NODE` / `RX_NODES` | どの機が TX / rx0,rx1,... か | **hosts.sh**。マシン番号で指定 |
| `CH` | チャンネル | **★全機共通**。空きchを使う |
| `BW` | 帯域 | HT20 / HT40-（**全機共通**） |
| `RATE` | 送信レート | HT20→`0x4101` / HT40→`0x4901` |
| `PAYLOAD` | ペイロード長 | **100推奨**（小さすぎると注入不安定） |
| `DELAY` | 送信間隔[µs] | 1000=1000pkt/s |
| 引数 | ラベル / 秒数 | `NPKTS` は秒数から自動計算 |

**動作実績のあるch**: `ch48`(5.240GHz, W52, 日本合法) / `ch165`(5.825GHz, 5.8GHz帯)
**★空きchを使うこと**（他機が使っているchだと注入が埋もれて受からない。`scan_channels.sh` で確認）

---

## 7. 別の実験セットアップを作るには

- **チャンネル/帯域を変える** → `run_experiment.sh` の `CH`/`BW`/`RATE` を変えるだけ（全機に自動反映。rx_setup.sh/tx_setup.sh は引数で受け取る）
- **レート/時間を変える** → `DELAY`（pkt/s）と実行時の秒数引数
- **RXを増やす/減らす・TXを別機に** → `hosts.sh` の `RX_NODES=( ... )` / `TX_NODE=` を書き換えるだけ。
  setup / csi_recv / 到達待ち判定 / csi_merge / 停止処理はすべて台数に追従する（`csi_merge` は可変長入力、rx_id=添字）
- **新しいラップトップを足す** → 3-2（`node_setup.sh <N>`）→ `ALL_NODES` に追加 → `check_nodes.sh`
- **単体で取りたい** → `rx_capture.sh`（ローカル保存版, 制御PC不要）

---

## 8. トラブルシューティング

| 症状 | 原因 / 対処 |
|---|---|
| `ping` が通らない | 制御PCの有線に手動IPが無い / RX側の固定IP未設定 / ケーブル・ハブ |
| ssh でパスワードを聞かれる | `ssh-copy-id` 未実施（`check_nodes.sh` の ssh 列が NO） |
| ssh越しの sudo で止まる | NOPASSWD sudo 未設定（`/etc/sudoers.d/csi`、`node_setup.sh` がやる） |
| TX 機で注入が始まらない | その機に `random_packets` が無い（`check_nodes.sh` の inject 列）→ LORCON をビルドするか `TX_NODE` を inject=ok の機に |
| `make` が Error 127 | 制御PCに `g++` が無い → `apt-get install build-essential` |
| 起動したら Memtest86+ | `GRUB_DEFAULT` が番号指定でmemtestを選択 → **サブメニュー名で指定** |
| WiFiが繋がらない(RX/TX) | CSIファーム有効中は正常（標準ファームに戻せば復帰） |
| CSIが0のまま | ①全機のchが一致しているか ②空きchか ③`monitor_tx_rate`(0x41xx)か ④立ち上がり1分待ったか |
| 受信はできるがCSI 0 | connector ID不一致（`netlink/iwl_connector.h` を `10 + 0xf`）/ 標準ファームを読んでいる |
| ふたを閉じると止まる | ふた閉じサスペンドを無効化（電源設定 / `HandleLidSwitch=ignore`） |

---

## 9. ラップトップを再起動した時の流れ

**結論：設定が済んでいれば、電源を入れるだけ。手動操作は不要。**

### 再起動しても自動で戻るもの（永続）
| 項目 | 復帰 | 理由 |
|---|---|---|
| カーネル 3.5.7+ で起動 | ✓ | `GRUB_DEFAULT`（サブメニュー名で指定済み） |
| 固定IP | ✓ | `/etc/network/interfaces`（NM非依存） |
| sshd | ✓ | サービス自動起動 |
| CSIファーム有効 | ✓ | `/lib/firmware` のシンボリックリンク（ファイルなので永続） |
| NOPASSWD sudo / 各スクリプト | ✓ | ファイル |
| ふた閉じ無効化 | ✓ | 設定ファイル |

### 再起動で消えるもの（＝毎回 `run_experiment.sh` が自動でやり直す）
- モニターモード / チャンネル / `connector_log` / `mon0` / `monitor_tx_rate`
→ **揮発するのが正常**。実験のたびに `rx_setup.sh` / `tx_setup.sh` が設定するので**手動不要**。

### 手順
```bash
# 1) 電源ON（or 制御PCからリモート再起動）
ssh kota@192.168.100.11 "sudo reboot"
# 2) 1〜2分待つ
# 3) 制御PCから復帰確認
./check_nodes.sh 11
#    → kernel 3.5.7+ と csifw csi が出ればOK
# 4) そのまま実験
./run_experiment.sh walking 60
```

### 想定外のとき
| 症状 | 確認 |
|---|---|
| `uname -r` が 3.5.7+ でない | `GRUB_DEFAULT` を確認（memtest/別カーネルを指していないか）→ `sudo update-grub` |
| ping が通らない | `/etc/network/interfaces` の固定IP / ケーブル・ハブのリンク |
| ssh できない | sshd が動いているか（現地で `sudo service ssh start`） |
| sigcomm2010 が出ない | CSIファームが標準に戻っている → 有効化し直して再起動 |
| 起動途中で止まる/画面が出ない | ふたを開けて GRUB を確認（既定が壊れている可能性） |

> 💡 ふたを閉じたまま運用するなら、**GRUB既定=3.5.7** と **ふた閉じサスペンド無効** が前提。
> これが効いていれば、電源ON→自動でCSIモード＋LAN復帰→制御PCから即実験、が成立する。

---

## 10. 関連ドキュメント
- 基本セットアップ（kernel 3.5.7 ビルド・ファーム・全ハマり所）: kernel repo `SETUP_CSITOOL_JA.md`
- 単体キャプチャ用スクリプト: kernel repo `csi-scripts/`
- 解析（MATLAB）: supplementary `matlab/`（`read_bf_file.m` / `get_scaled_csi.m`）

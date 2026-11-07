# 実験 config (収録 1 本ごとに必須、2026-11-07 から)

**規則: 収録は 1 本ごとに、その収録だけの実験 config を作ってから撮る。** あとで誰が見ても「どういう状況で、どういう実験だったか」が分かるようにするため。`run_experiment.sh` は config が無いと動かない。

```bash
cd ~/linux-80211n-csitool-supplementary/multi-rx
./run_experiment.sh experiments/<YYYYMMDD>/<label>.json
```

## 置き場所

| パス | 中身 |
|---|---|
| `experiments/setups/<setup_id>.json` | 設置: 座標系と角度の規約、TX・各 RX の位置と向き (ブロードサイド、+x から反時計回り)、素子の並び、歩行の四角、部屋、目視か実測か |
| `experiments/<YYYYMMDD>/<label>.json` | 実験 1 本: ラベル、秒数、TX のモード (rate・ストリーム数・アンテナの状態)、setup の id、軌跡、目的、人の配置、直前の設置変更 |
| `~/csi_data/<YYYYMMDD>/<stamp>_<label>_meta.json` | 収録時に `run_experiment.sh` が書く記録。上の 2 つの写し + 電波設定 + ホスト + git の版 + 事象の時刻 (開始ベルなど) + 終わり方 + 操作者のメモ |

設置が変わったら (RX を動かした、TX を回した) 新しい setup を作る。B・C の寝かせ / 立てのように収録ごとに変わるものは実験 config の `tx.antennas` に書く。

## 実験 config の項目 (`exp_meta.py check` が検査する)

| 項目 | 内容 |
|---|---|
| `label` | `[A-Za-z0-9_]+`、ファイル名と同じ |
| `date` | 収録日 `YYYY-MM-DD`。**今日でないと撮れない** (前の日の config の使い回しを防ぐ) |
| `seconds` | 記録の上限秒数 (Enter で早く止められる) |
| `setup` | `experiments/setups/<id>.json` の id |
| `tx.rate` / `tx.streams` / `tx.antennas` | `0x4901` = 1 ストリーム (A のみ)、`0x1c911` = 3 ストリーム (A・B・C)。ストリーム数が rate と合わないと撮れない |
| `trajectory.type` / `trajectory.description` | `static` / `square` / `line` / `radial` / `perimeter` / `free` / `other` と、歩き方の具体 (開始の角、向き、止まるか、ベルとの関係) |
| `purpose` / `purpose_note` | `exploration` / `confirmation` / `pilot` / `calibration` / `other` と、何のための収録か (csi-track のノートの節など)。`confirmation` は撮った後に csi-track の `docs/registry/confirmation_data.txt` へ封印登録する |
| `people` | 部屋にいる人と、その位置・動き |
| 任意 | `session_order`、`block`、`setup_change_before`、`notes` |

`run_experiment.sh` は環境変数 `RATE` が config の `tx.rate` と違うと止まる (rate は config で指定する)。`csi_check.py` は `_meta.json` を表示し、CSI の Ntx が `tx.streams` と違うと CHECK にする。

## 2026-11-07 より前の収録

- 2026-11-07 の 16:37〜16:55 の 7 本 (`st_pre` 〜 `aod_st_pre`) は旧形式で撮った。`_meta.json` は収録後に作り、`backfilled` 欄に作り方と未確認の点を書いた。
- それより前 (2026-07-24 〜 2026-11-05) の記録は csi-track のノートにある。csi-track 側で収録ごとの記録に起こす (csi-track のセッションで行う)。

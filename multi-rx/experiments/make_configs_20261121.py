#!/usr/bin/env python3
# Kept in the repo (2026-11-21, user: the same kind of data set will be recorded again on later days).
# For another day: change the date / OUT folder, the survey path (new ts_survey.py run) and the notes, then run it.
"""Write the 2026-11-21 block-1 REDO configs (1 stream, A on port 1). Overwrites the configs of the
first block (their recordings keep their own copy in each _meta.json)."""
import json, os

OUT = os.path.expanduser("~/linux-80211n-csitool-supplementary/multi-rx/experiments/20261121")
SURVEY = "/home/kota/csi_data/20261121/20261121_144103_survey/20261121_144103_survey_ts.json"
TX1 = {"rate": "0x4901", "streams": 1,
       "antennas": "A のみ給電。B・C は寝かせる (1 ストリームの標準、11/07 と同じ)。port 1 = A を立て、"
                   "port 2・3 = B・C にもアンテナを付けて寝かせる"}
REDO = ("撮り直し。2026-11-21 の 1 本目のブロック (14:52〜15:49 の 9 本) は TX のアンテナが port 2 に 1 本だけで、"
        "rate 0x4901 が送る port 1 (A) にアンテナが無かった (ユーザー 15:5x。受信電力が 11/07 より約 20 dB 低い)。"
        "その 9 本は残して meta に注記し、同じラベルでこの条件で撮り直す")
PRISM_HEAD = ("歩行者の頭に付ける。プリズムの点 = 頭の位置で、体の中心から数 cm〜十数 cm ずれ得る。"
              "頭の高さはアンテナより約 0.8 m 上 (11/21 の 1 本目のブロックの TS)。始める前に TS16 本体で LOCK をかける")
PRISM_STATIC = ("歩行域の外に置き、誰も持たない (置いた位置は bag の /ts16/prism_setup)。"
                "始める前に TS16 本体で LOCK をかける")
WALKER = "歩行者 1 名 (操作者が兼ね、頭にプリズム)。歩行域にほかの人はいない"
STILL = "部屋の中は操作者 1 名だけで、歩行域の外で動かない。歩行域に人はいない"
SQ = "setup の walking_square (1.6 x 1.2 m)"
C1 = "c1 (1.008, 0.954)、TX に最も近い角"
C2 = "c2 (2.608, 0.954)、RX1 に最も近い角"
CENTRE = "四角の中央 (1.808, 1.554)"
SEAL = ("収録後、csi-track の docs/registry/confirmation_data.txt に封印登録する (ユーザー)。"
        "健全性検査 (csi_check と TS の件数・途切れ) 以外で読まない")
EXP_NOTE = ("探索用 (TS16 の真値つき)。同じ型の _conf と対 (計画 2026-11-04-experiment-plan-after-team §4 D の"
            "「1 本は探索、1 本は封印」と同じ形)。Doppler 格子・参照選択・range の棄却などの探索に使ってよい")
CONF_NOTE = "確認用 (TS16 の真値つき)。同じ型の _exp と対。" + SEAL
AREA = "四角とその周り 0.5 m まで (おおよそ x 0.5〜3.1 m、y 0.45〜2.65 m)。TX・RX のアンテナに 0.5 m より近づかない"


def square(direction):
    turn = "反時計回り (左回り、c1 → c2 → c3 → c4)" if direction == "ccw" else "時計回り (右回り、c1 → c4 → c3 → c2)"
    return {"type": "square", "direction": direction, "path": SQ, "start_corner": C1,
            "description": f"開始ベル (2 回) で c1 から歩き始め、四角を{turn}に止まらず何周もする。"
                           "角でも止まらない。自然な速さ。終了ベル (3 回) で止まる"}


def circle(direction):
    turn = "反時計回り (左回り)" if direction == "ccw" else "時計回り (右回り)"
    first = "右 (c2・RX1 の側) へ" if direction == "ccw" else "左 (c1・TX の側) へ"
    return {"type": "other", "shape": "circle", "direction": direction,
            "path": "四角の中央 (1.808, 1.554) を中心にした半径約 0.9 m の円 (四角より一回り大きく、四角の上下の辺の 0.3 m 外を通る)。1 本目の circ_ccw_exp (16:52) が自然に半径 0.93 m だったので、それに合わせた (当初の計画は 0.6 m)",
            "start_corner": "円の一番下 (1.808, 0.65)、c1 と c2 の中点から TX 側へ 0.3 m",
            "description": f"開始ベル (2 回) で円の一番下 (c1 と c2 の中点から TX 側へ 0.3 m) から{first}歩き出し、中央を中心に半径約 0.9 m の円を"
                           f"{turn}に止まらず何周もする。中央の床の印を見ながら同じ半径を保つ。自然な速さ。終了ベル (3 回) で止まる"}


RAD = {"type": "radial", "path": "四角の対角線 c1 (1.008, 0.954) ↔ c3 (2.608, 2.154)", "start_corner": C1,
       "description": "開始ベル (2 回) で c1 から歩き始め、c1 と c3 を結ぶ対角線を止まらずに往復する。端では止まらずに折り返す。"
                      "自然な速さ。終了ベル (3 回) で止まる。TX から見てほぼ視線方向 (c1 は 43°・1.39 m、c3 は 40°・3.38 m) で、"
                      "TX に近づく・遠ざかるの繰り返し"}
LINE = {"type": "line", "path": "四角の対角線 c2 (2.608, 0.954) ↔ c4 (1.008, 2.154)", "start_corner": C2,
        "description": "開始ベル (2 回) で c2 から歩き始め、c2 と c4 を結ぶ対角線を止まらずに往復する。端では止まらずに折り返す。"
                       "自然な速さ。終了ベル (3 回) で止まる。TX から見て横切る向き (TX からの距離は c2 2.78 m、c4 2.38 m)。"
                       "RX0 には c4 で近づき (1.20 m)、RX1 には c2 で近づく (1.50 m)"}
FIG8 = {"type": "other", "shape": "figure8",
        "path": "四角の中の 8 の字。左の輪は c1・c4 の側 (x 1.0〜1.8 m)、右の輪は c2・c3 の側 (x 1.8〜2.6 m)、四角の中央で斜めに交わる",
        "start_corner": CENTRE,
        "description": "開始ベル (2 回) で四角の中央から左上 (c4 の方) へ歩き出し、左の輪を反時計回りに回って中央を右上へ抜け、"
                       "右の輪を時計回りに回って中央に戻る。これを止まらずに繰り返して 8 の字を描き続ける。角は作らず、なめらかな曲線で。"
                       "自然な速さ。終了ベル (3 回) で止まる"}
FIG8R = {"type": "other", "shape": "figure8_reversed",
         "path": FIG8["path"] + "。fig8 と同じ形で逆回り",
         "start_corner": CENTRE,
         "description": "開始ベル (2 回) で四角の中央から左下 (c1 の方) へ歩き出し、左の輪を時計回りに回って中央を右下へ抜け、"
                        "右の輪を反時計回りに回って中央に戻る。これを止まらずに繰り返して 8 の字を描き続ける (fig8 の逆回り)。"
                        "角は作らず、なめらかな曲線で。自然な速さ。終了ベル (3 回) で止まる"}
FREE = lambda extra: {"type": "free", "area": AREA,
                      "description": "開始ベル (2 回) で四角の中から歩き始め、上の範囲を自由に歩く。曲がる・向きを変える・引き返す・"
                                     "真ん中を横切る・範囲の端まで行く・ときどき数秒止まる、を混ぜる。四角の周回に偏らない。"
                                     "向きは弧を描いてゆっくり変える (その場で急に回ると TS の LOCK が外れやすい)。" + extra +
                                     "終了ベル (3 回) まで歩き続ける (最後に止まらない)"}
STOPGO = {"type": "other", "shape": "stop_and_go",
          "path": "c1 → c2 → c3 → c4 → 四角の中央 (1.808, 1.554) → c1 → … の 5 点",
          "start_corner": C1,
          "description": "開始ベル (2 回) のときは c1 に立って止まっている。各点で約 10 s (心の中で数える) 止まり、次の点まで普通の速さで"
                         "まっすぐ歩く。順番は c1 → c2 → c3 → c4 → 中央 → c1 → …。止まっている間は体を動かさない (向きは自由)。"
                         "終了ベル (3 回) が鳴ったら、歩いている途中でもその場で止まる"}

cfgs = [
    ("st_pre", 60, {"type": "static", "description": "静止。1 ストリームの歩行の前。開始ベルから終了ベルまで誰も動かない"},
     "calibration", "歩行の前の静止。収録中に設置が動いていないことの基準と、RX 側の B (AoA の切片) の基準。"
                    "アンテナを付け直したので、受信電力が 11/07 の st_pre (AGC rx0 37・rx1 40) に戻ったかの確認も兼ねる",
     STILL, PRISM_STATIC,
     "TX のアンテナを付け直した: port 2 に 1 本だけだったのを、11/07 と同じ状態 (port 1 = A を立て、port 2・3 = B・C を付けて寝かせる) にした。"
     "TX の本体とアレイは動かさずに付け直した (動いた場合はサーベイし直す)。ドライバの再読込はしていない (同じ NIC の初期化のまま)。"
     "プリズムは頭から歩行域の外の置き場所に移した"),
    ("sq_ccw_exp", 90, square("ccw"), "exploration", EXP_NOTE, WALKER, PRISM_HEAD,
     "プリズムを歩行域の外の置き場所から歩行者の頭に移した (TS16 で LOCK をかけ直す)"),
    ("sq_cw_exp", 90, square("cw"), "exploration", EXP_NOTE, WALKER, PRISM_HEAD, "なし"),
    ("sq_ccw_conf", 90, square("ccw"), "confirmation", CONF_NOTE, WALKER, PRISM_HEAD, "なし"),
    ("sq_cw_conf", 90, square("cw"), "confirmation", CONF_NOTE, WALKER, PRISM_HEAD, "なし"),
    ("fig8_exp", 90, FIG8, "exploration",
     "探索用 (TS16 の真値つき)。推定しやすい形 (ユーザー 2026-11-21「八の字とか、推定しやすい形」「何本かとっても良い」)。"
     "なめらかで、曲がる向き (左回り・右回り) が 1 周ごとに入れ替わる。fig8_conf と対。逆回りは fig8r_exp",
     WALKER, PRISM_HEAD, "なし"),
    ("fig8_conf", 90, FIG8, "confirmation", "確認用 (TS16 の真値つき)。fig8_exp と対。" + SEAL, WALKER, PRISM_HEAD, "なし"),
    ("fig8r_exp", 90, FIG8R, "exploration",
     "探索用 (TS16 の真値つき)。fig8_exp の逆回り (ユーザー 2026-11-21「八の字も入れるべき、何本かとっても良い」)。fig8r_conf と対",
     WALKER, PRISM_HEAD, "なし"),
    ("fig8r_conf", 90, FIG8R, "confirmation", "確認用 (TS16 の真値つき)。fig8r_exp と対。" + SEAL, WALKER, PRISM_HEAD, "なし"),
    ("circ_ccw_exp", 90, circle("ccw"), "exploration",
     "探索用 (TS16 の真値つき)。円 (ユーザー 2026-11-21「円とかは不要か」)。速さと曲がり方が一定で角も折り返しも無い、"
     "一番推定しやすい形。circ_ccw_conf と対", WALKER, PRISM_HEAD, "なし"),
    ("circ_ccw_conf", 90, circle("ccw"), "confirmation", "確認用 (TS16 の真値つき)。circ_ccw_exp と対。" + SEAL,
     WALKER, PRISM_HEAD, "なし"),
    ("circ_cw_exp", 90, circle("cw"), "exploration",
     "探索用 (TS16 の真値つき)。円の時計回り (circ_ccw_exp の逆回り)。circ_cw_conf と対", WALKER, PRISM_HEAD, "なし"),
    ("circ_cw_conf", 90, circle("cw"), "confirmation", "確認用 (TS16 の真値つき)。circ_cw_exp と対。" + SEAL,
     WALKER, PRISM_HEAD, "なし"),
    ("rad_c1c3", 90, RAD, "exploration",
     "探索用 (TS16 の真値つき)。四角以外の軌跡 (ユーザー 2026-11-21「四角以外の trajectory も取れる」)。"
     "TX に対して視線方向の動きで、Doppler・range・AoA がどう振る舞うかを見る。line_c2c4 (横切り) と対比。rad_c1c3_conf と対",
     WALKER, PRISM_HEAD, "なし"),
    ("rad_c1c3_conf", 90, RAD, "confirmation", "確認用 (TS16 の真値つき)。rad_c1c3 と対 (TX に対して視線方向の往復)。" + SEAL,
     WALKER, PRISM_HEAD, "なし"),
    ("line_c2c4", 90, LINE, "exploration",
     "探索用 (TS16 の真値つき)。四角以外の軌跡 (ユーザー 2026-11-21)。"
     "TX に対して横切る動きで、TX からの距離があまり変わらないときの追跡を見る。rad_c1c3 (視線方向) と対比。line_c2c4_conf と対",
     WALKER, PRISM_HEAD, "なし"),
    ("line_c2c4_conf", 90, LINE, "confirmation", "確認用 (TS16 の真値つき)。line_c2c4 と対 (TX の前を横切る往復)。" + SEAL,
     WALKER, PRISM_HEAD, "なし"),
    ("free_exp", 120, FREE(""), "exploration",
     "探索用 (TS16 の真値つき)。決まった形でない歩行 (ユーザー 2026-11-21「四角以外の trajectory も取れる」)。"
     "真値が TS なので形に頼らずに評価できる。同じ型の free_conf と対",
     WALKER, PRISM_HEAD, "なし"),
    ("free_conf", 120, FREE("free_exp と同じ道順はなぞらない。"), "confirmation",
     "確認用 (TS16 の真値つき)。決まった形でない歩行で、四角以外での追跡の確認。free_exp と対。" + SEAL,
     WALKER, PRISM_HEAD, "なし"),
    ("stopgo", 120, STOPGO, "exploration",
     "探索用 (TS16 の真値つき)。止まっている人は Doppler に映らないので推定が一番難しい形 (ユーザー 2026-11-21 に追加の OK)。"
     "止まる区間での推定 (位置の保持、AoA・range だけでの位置) を TS の真値で調べる。各点で止まった位置と時刻は TS の bag で分かる。"
     "stopgo_conf と対",
     WALKER, PRISM_HEAD, "なし"),
    ("stopgo_conf", 120, STOPGO, "confirmation",
     "確認用 (TS16 の真値つき)。stopgo と対 (各実験 2 本、ユーザー 2026-11-21「各実験あたり2本は同じものをとっても良い」)。" + SEAL,
     WALKER, PRISM_HEAD, "なし"),
    ("st_post", 60, {"type": "static", "description": "静止。1 ストリームの歩行の後。開始ベルから終了ベルまで誰も動かない"},
     "calibration", "歩行の後の静止。st_pre と比べて設置が動いていないことを確かめる", STILL, PRISM_STATIC,
     "プリズムを歩行者の頭から歩行域の外の置き場所に戻した (TS16 で LOCK をかけ直す)"),
]

# Order (user 2026-11-21 16:1x「封印用じゃなくて、普通に使う用として、封印はその後のほうが良い」「各実験あたり2本」):
# st_pre, then per trajectory 2 exploration runs (<exp>, <exp>_2), then all the sealed _conf runs, then st_post.
byl = {c[0]: c for c in cfgs}
GROUPS = [("sq_ccw_exp", "sq_ccw_conf"), ("sq_cw_exp", "sq_cw_conf"), ("fig8_exp", "fig8_conf"), ("fig8r_exp", "fig8r_conf"),
          ("circ_ccw_exp", "circ_ccw_conf"), ("circ_cw_exp", "circ_cw_conf"),
          ("rad_c1c3", "rad_c1c3_conf"), ("line_c2c4", "line_c2c4_conf"), ("free_exp", "free_conf"), ("stopgo", "stopgo_conf")]
ordered = [byl["st_pre"]]
for e, c in GROUPS:
    label, secs, traj, purpose, pnote, people, prism, change = byl[e]
    if e == "free_exp":
        traj = FREE("free_exp と同じ道順はなぞらない。")
    note2 = (f"探索用の 2 本目 (TS16 の真値つき、ユーザー 2026-11-21「各実験あたり2本は同じものをとっても良い」"
             f"「封印用じゃなくて普通に使う用、封印はその後」)。歩き方は {e} と同じ。封印用の {c} は探索用を撮り終えた後にまとめて撮る")
    ordered += [byl[e], (e + "_2", secs, traj, "exploration", note2, people, prism, "なし")]
ordered += [byl[c] for _, c in GROUPS]
ordered.append(byl["st_post"])
assert len(ordered) == len(cfgs) + len(GROUPS)
cfgs = ordered

os.makedirs(OUT, exist_ok=True)
for i, (label, secs, traj, purpose, pnote, people, prism, change) in enumerate(cfgs, 1):
    cfg = {"label": label, "date": "2026-11-21", "seconds": secs, "setup": "20261121_std",
           "session_order": i, "block": "block1_1stream_redo", "tx": TX1, "trajectory": traj,
           "purpose": purpose, "purpose_note": pnote, "people": people,
           "ts": {"survey": SURVEY, "prism": prism},
           "setup_change_before": change, "notes": REDO}
    with open(os.path.join(OUT, f"{label}.json"), "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{i:2d} {label}")

# ---- block 2: the same trajectories with 3 TX streams (user 2026-11-21「そのあとで、同じものを送信アンテナ3本で行う」) ----
import re
TX3 = {"rate": "0x1c911", "streams": 3,
       "antennas": "A・B・C とも立てて給電 (3 ストリーム、MCS 17)。3 本給電は免許の範囲内と確認済み (2026-11-05)"}
labels = [c[0] for c in cfgs]
pat = re.compile(r"(?<![A-Za-z0-9_])(" + "|".join(sorted(labels, key=len, reverse=True)) + r")(?![A-Za-z0-9_])")
aod = lambda s: pat.sub(lambda m: "aod_" + m.group(1), s)
n0 = len(cfgs)
for j, (label, secs, traj, purpose, pnote, people, prism, change) in enumerate(cfgs, 1):
    if label == "st_pre":
        pnote = ("TX 3 本給電の静止。TX 側の B_t と混合 (csi-track aod-pilot-health §7.4) の基準。ドライバを再読込しないので、"
                 "TX の状態 (素子ごとの 0/π) はこのブロックの間は変わらないはず (2026-11-09 からの手順)。1 ストリームの st_post との比較にも使う")
        change = "TX の B・C を寝かせた状態から立てた (port 1・2・3 = A・B・C、TX の本体とアレイは動かしていない)。プリズムは歩行域の外の置き場所のまま"
    elif label == "st_post":
        pnote = "3 ストリームの歩行の後の静止。aod_st_pre と比べて設置と TX の状態が変わっていないことを確かめる"
    else:
        pnote = aod(pnote) + f"。TX 3 ストリーム (TX 側の AoD も使える)。同じ軌跡の 1 ストリーム版は {label}"
        traj = json.loads(aod(json.dumps(traj, ensure_ascii=False)))
        traj["description"] = traj["description"].replace("1 ストリーム", "3 ストリーム")
    if traj["type"] == "static":
        traj = dict(traj, description=traj["description"].replace("1 ストリーム", "3 ストリーム"))
    cfg = {"label": "aod_" + label, "date": "2026-11-21", "seconds": secs, "setup": "20261121_std",
           "session_order": n0 + j, "block": "block2_3stream", "tx": TX3, "trajectory": traj,
           "purpose": purpose, "purpose_note": pnote, "people": people,
           "ts": {"survey": SURVEY, "prism": prism},
           "setup_change_before": change, "notes": ""}
    with open(os.path.join(OUT, f"aod_{label}.json"), "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{n0 + j:2d} aod_{label}")

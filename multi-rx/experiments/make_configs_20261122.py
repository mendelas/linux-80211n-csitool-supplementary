#!/usr/bin/env python3
"""Write the 2026-11-22 configs: visit 1 of csi-track's recording plan (version 5, approved 2026-11-13),
docs/reports/plan/2026-11-13-recording-plan-after-tof-diagnosis.md.

The 8 recordings + pilot_long come from the plan's drafts in
csi-track experiments/recording-plan-20261113/configs/ (trajectory, segments, purpose, seconds kept as drafted);
this script fills in the day: date, setup, TS16 survey, prism, people, notes. Plus pilot_ctrlc (tool check).
"""
import copy, glob, json, os, sys

DAY = "2026-11-22"
SETUP = "20261122_std"
D8 = DAY.replace("-", "")
OUT = os.environ.get("OUT") or os.path.expanduser(f"~/linux-80211n-csitool-supplementary/multi-rx/experiments/{D8}")
DRAFTS = os.path.expanduser("~/csi-track/experiments/recording-plan-20261113/configs")
PLAN = "csi-track docs/reports/plan/2026-11-13-recording-plan-after-tof-diagnosis.md (第 5 版、2026-11-13 承認)"
_surveys = sorted(glob.glob(os.path.expanduser(f"~/csi_data/{D8}/*_survey/*_survey_ts.json")))
if not _surveys:
    sys.exit(f"no survey of {DAY}: run ~/total_station_ros2/ts_survey.py --setup-id {SETUP} first")
SURVEY = _surveys[-1]

TX1 = {"rate": "0x4901", "streams": 1,
       "antennas": "A のみ給電。B・C は寝かせる (1 ストリームの標準、11/07・11/21 と同じ)。port 1 = A を立て、"
                   "port 2・3 = B・C にもアンテナを付けて寝かせる"}
PRISM_HEAD = ("歩行者の頭に付ける (11/21 と同じ)。プリズムの点 = 頭の位置で、体の中心から数 cm〜十数 cm ずれ得る。"
              "頭の高さはアンテナより約 0.8 m 上。始める前に TS16 本体で LOCK をかける")
PRISM_STATIC = ("歩行域の外に置き、誰も持たない (置いた位置は bag の /ts16/prism_setup)。"
                "始める前に TS16 本体で LOCK をかける")
STILL = "歩行域に人はいない。部屋の中は操作者 1 名だけで、歩行域の外 (操作の場所) で動かない (11/21 の静止と同じ)"
WALKER = "歩行者 1 名 (操作者が兼ね、頭にプリズム)。歩行域にほかの人はいない"
TRUTH = ("TS16 (rosbag2、制御 PC の時計)。run_experiment.sh が開始ベルから記録終了まで <stamp>_<label>_ts/ に記録する。"
         "TS16 は (−1.802, 0.383)、TX の後ろ。プリズムの付け方は ts.prism")
NOTES = (f"{PLAN} の訪問 1。計画との違い: (1) 床の印 s1・s3・m0 は貼らず TS でも測らない (ユーザー 2026-11-22"
         "「床の印は不要でしょう。ts あるし」)。足踏みは目分量の位置で、立った位置は TS の bag で決める。c1〜c4 は 20261105_std の床の印。"
         "(2) 設置は 11/07 の 20261105_std ではなく、当日の TS16 サーベイの 20261122_std (機器が少しずれただけ、ユーザー)。"
         "(3) 開始ベルは鳴る (計画を書いた時点では鳴らなかった)。(4) TS の bag は収録のフォルダの中 (計画 §7 の truth/ ではない)。"
         "封印の登録はファイル単位 (計画 §8 の 1) なので bag は読める。(5) pilot_long は前の日ではなく当日の最初。"
         "(6) 動画の控え、送受信の線を横切る事象 (計画 §4 の c) は無し")
MORNING = ("朝にノード 3 台を起動し直し、--prepare で 1 回だけ初期化した (11/21 とは別の NIC の初期化)。"
           f"TS16 で当日のサーベイを取った (setup {SETUP})。プリズムは歩行域の外の置き場所")


def recorded(label):
    return bool(glob.glob(os.path.expanduser(f"~/csi_data/{D8}/*_{label}/*_meta.json")))


def base(label, draft=None):
    d = json.load(open(os.path.join(DRAFTS, f"{draft or label}.json"))) if (draft or label) else {}
    d = copy.deepcopy(d)
    d["label"] = label
    d["date"] = DAY
    d["setup"] = SETUP
    d["tx"] = TX1
    d["truth"] = TRUTH
    d["notes"] = NOTES
    d["setup_change_before"] = "なし"
    return d


cfgs = []
# tool check (csi-track day note 2026-11-21 §6: the Ctrl-C fix 8f1ec40 and ts_record.py 4264f19 untried on hardware)
c = base("pilot_ctrlc", "pilot_long")
c.update(seconds=60, block="tool_check",
         trajectory={"type": "static", "description": "静止。CSI が流れ始めてから約 20 s で Ctrl-C を押して止める。誰も動かない"},
         purpose="pilot",
         purpose_note=("道具の実機確認 (データとしては使わない)。run_experiment.sh の録画中の Ctrl-C の修正 (supplementary 8f1ec40) で、"
                       "カウントダウンが止まり、後始末 (ノードの csi_stream・random_packets の停止、merge、meta) が最後まで走ること。"
                       "ts_record.py の修正 (total_station_ros2 4264f19) で ts_exit が 0 になること"),
         people=STILL, ts={"survey": SURVEY, "prism": PRISM_STATIC}, setup_change_before=MORNING)
c.pop("session_order", None)
cfgs.append(c)

c = base("pilot_long")
c.update(people=STILL, ts={"survey": SURVEY, "prism": PRISM_STATIC})
c["purpose_note"] += "。計画では前の日までに撮るものを、当日の最初に撮る。通らなければ台本を短い収録に切り直す"
cfgs.append(c)

for label in ["st_pre", "sq_base_a", "sq_speed_a", "sq_base_b", "sq_speed_b", "sq_base_c", "sq_speed_c", "st_post"]:
    c = base(label)
    static = c["trajectory"]["type"] == "static"
    c.update(people=STILL if static else WALKER, ts={"survey": SURVEY, "prism": PRISM_STATIC if static else PRISM_HEAD})
    if label == "sq_base_a":
        c["setup_change_before"] = "プリズムを歩行域の外の置き場所から歩行者の頭に移した (TS16 で LOCK をかけ直す)"
    if label == "st_post":
        c["setup_change_before"] = "プリズムを歩行者の頭から歩行域の外の置き場所に戻した (TS16 で LOCK をかけ直す)"
    if label == "st_pre":
        c["purpose_note"] += "。受信電力を 11/21 の st_pre (AGC rx0 40.0・rx1 43.3) と比べ、A が port 1 に付いていることを確かめる"
    cfgs.append(c)

os.makedirs(OUT, exist_ok=True)
for c in cfgs:
    if recorded(c["label"]):
        print(f"   {c['label']:12s} kept (already recorded today)")
        continue
    with open(os.path.join(OUT, f"{c['label']}.json"), "w") as f:
        json.dump(c, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{c.get('session_order', '-')!s:>2} {c['label']:12s} {c['seconds']:4d} s  {c['purpose']}")
print("survey:", SURVEY)

# ---- 2026-11-22 15:0x: visit 1 split into short recordings ----
# User: 「このような長いやつは一人で行うのはかなり難しい」「次からのやつは長くないもので」「ドライバの初期化はなおしたので、
# 一気に取らなくても大丈夫ですよね」. The plan's reason for long recordings (§1: the NIC was re-initialized per recording)
# no longer holds since supplementary 68338f8 (2026-11-09); the static inter-element phases of pilot_ctrlc, pilot_long and
# st_pre (same NIC init) agree within 1 deg (rx0) / 4 deg (rx1), no pi flips. Each segment type of sq_base / sq_speed
# becomes its own ~100 s recording; 3 takes (a, b, c) per type as in the plan, assigned exploration / confirmation /
# spare by dice and coin after all takes (plan §7). Rounds a, b, c in turn so that time of day is not tied to a type.
SPEED = {"normal": ("ふつう", "約 9.5 秒 (11/07 と同じ)", "約 10 周"),
         "slow": ("ゆっくり", "約 14 秒", "約 7 周"),
         "fast": ("速め", "約 6.5 秒", "約 14 周")}
ROT = {"ccw": ("反時計回り", "{s}"), "cw": ("時計回り", "{s}")}
ORDER_CCW = {"c1": "c1 → c2 → c3 → c4", "c3": "c3 → c4 → c1 → c2"}
ORDER_CW = {"c1": "c1 → c4 → c3 → c2", "c3": "c3 → c2 → c1 → c4"}
CORNER = {"c1": "c1 (1.008, 0.954)、TX に最も近い角", "c3": "c3 (2.608, 2.154)、TX から最も遠い角"}
SHORT_NOTE = ("四角の型は開始ベルですぐ歩き出す (ユーザー 2026-11-22「ベルなってからすぐに、歩き始めて」。sq_ccw_a だけは 5 数えてから)。"
              "計画の訪問 1 の台本 (sq_base・sq_speed) の区間を 1 本ずつの短い収録に分けたもの (ユーザー 2026-11-22)。"
              "長い収録にする理由 (計画 §1: 収録ごとの初期化) は 11/09 の 68338f8 で無くなっている。同じ型を a・b・c の 3 本撮り、"
              "全部撮り終えた後に、型ごとに、さいころと硬貨で探索用・確認用 (封印)・予備の確認用 (封印) を決める (計画 §7)。"
              "決まるまで、どれも開けない (点検は欠落・間隔・VERDICT の行と TS の件数・途切れだけ)")


def sq_short(rot, speed, start):
    sp, lap, laps = SPEED[speed]
    order = (ORDER_CCW if rot == "ccw" else ORDER_CW)[start]
    return {"type": "square", "direction": rot, "speed": speed, "path": "setup の walking_square (1.6 x 1.2 m)",
            "start_corner": CORNER[start],
            "description": f"開始ベル (2 回) が鳴ったらすぐ {start} から (ベルの前から歩いていてもよい)、四角を{ROT[rot][0]} ({order}) に、"
                           f"{sp}の速さ (1 周 {lap}) で止まらず回り続ける。角でも止まらない。周回は数えなくてよい (100 s で{laps})。"
                           "終了ベル (3 回) が鳴ったら、その場で止まる"}


STEP = {"type": "other", "shape": "stepping", "path": "印 c1 → s1 → c3 → s3 → m0 (s1・s3・m0 は目分量。setup の marks_note)",
        "start_corner": CORNER["c1"],
        "description": "開始ベル (2 回) のとき c1 に立っている。c1 → s1 (下の辺の中点) → c3 → s3 (上の辺の中点) → m0 (中心) の順に、"
                       "各点で、まず動かずに立って 5 数え、続けてその場で足踏みしながら 10 数える。体はずっと +y (RX0 の側、c1 から c4 を見る向き) を向く。"
                       "腕は自然に振る。点の間はふつうに歩く。m0 で足踏みを終えたら、そのまま m0 で動かずに立ち、終了ベル (3 回) まで待つ"}

TYPES = [("sq_ccw", 100, sq_short("ccw", "normal", "c1"), "計画 §6.1 区間 2 (反時計回り・ふつう)"),
         ("sq_cw", 100, sq_short("cw", "normal", "c1"), "計画 §6.1 区間 3 (時計回り・ふつう)"),
         ("step", 110, STEP, "計画 §6.1 区間 4・5 (足踏み 1 巡。2 巡目は別の take)"),
         ("sq_ccw_slow", 100, sq_short("ccw", "slow", "c3"), "計画 §6.2 区間 3 (反時計回り・ゆっくり、c3 から)"),
         ("sq_cw_fast", 100, sq_short("cw", "fast", "c3"), "計画 §6.2 区間 4 (時計回り・速め、c3 から)"),
         ("sq_cw_slow", 100, sq_short("cw", "slow", "c3"), "計画 §6.2 区間 5 (時計回り・ゆっくり、c3 から)"),
         ("sq_ccw_fast", 100, sq_short("ccw", "fast", "c3"), "計画 §6.2 区間 6 (反時計回り・速め、c3 から)")]
k = 0
for take in "abc":
    for name, secs, traj, src in TYPES:
        k += 1
        c = base(f"{name}_{take}", "sq_base_a")
        c.pop("trajectory")
        c.update(seconds=secs, session_order=100 + k, block="visit1_short_1stream", trajectory=traj, purpose="other",
                 purpose_note=f"{SHORT_NOTE}。この型: {src}。take {take}", people=WALKER,
                 ts={"survey": SURVEY, "prism": PRISM_HEAD}, setup_change_before="なし")
        if recorded(c["label"]):
            print(f"    {c['label']:14s} kept (already recorded today)")
            continue
        with open(os.path.join(OUT, f"{c['label']}.json"), "w") as f:
            json.dump(c, f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"{c['session_order']:3d} {c['label']:14s} {secs:4d} s")

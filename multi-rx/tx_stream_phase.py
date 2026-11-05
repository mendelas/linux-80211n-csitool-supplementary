#!/usr/bin/env python3
"""Inter-TX-stream phase conj(H_tx1)*H_txk per (RX, RX antenna, subcarrier), per static capture.
Per-packet RX-side phase (CFO, STO slope, RX chain) is common to all TX streams at one RX chain
and cancels in the product; what remains is geometry + CSD + TX chain phase offset.
Compares captures: if the TX chain offsets do not jump on re-init, the difference is ~0.
usage: tx_stream_phase.py STEP file1 file2 ...
"""
import sys, struct
import numpy as np
sys.dont_write_bytecode = True   # csi_check is imported from this directory; leave no __pycache__ in the repo
from csi_check import parse_bfee

step = int(sys.argv[1]); files = sys.argv[2:]


def load(path):
    data = open(path, 'rb').read()
    off, out, seen = 0, {}, {}
    while off + 11 <= len(data):
        t, rx, ln = struct.unpack_from('<dBH', data, off); off += 11
        pl = data[off:off + ln]; off += ln
        if len(pl) < ln: break
        if not ln or pl[0] != 0xbb: continue
        seen[rx] = seen.get(rx, 0) + 1
        if seen[rx] % step: continue
        b = parse_bfee(pl[1:])
        if b['csi'] is None or b['ntx'] != 3 or b['nrx'] != 3: continue
        H = np.zeros((3, 3, 30), complex)               # [tx, physical rx antenna, subcarrier]
        for j in range(9):
            H[j % 3, b['perm'][j // 3] - 1] = b['csi'][:, j]
        out.setdefault(rx, []).append(H)
    return {rx: np.array(v) for rx, v in out.items()}


res = {}
for f in files:
    name = f.split('_', 2)[-1].replace('_merged.bin', '')
    d = load(f)
    res[name] = {}
    for rx, H in d.items():
        P = np.conj(H[:, 0:1]) * H[:, 1:3]               # (N, 2 [tx2,tx3], 3 ant, 30 sc)
        Pn = P / np.maximum(np.abs(P), 1e-9)
        mean = Pn.mean(0)                                # coherent mean of unit phasors
        R = np.abs(mean)                                 # 1 = perfectly stable within the capture
        half = len(Pn) // 2
        drift = np.angle(Pn[half:].mean(0) * np.conj(Pn[:half].mean(0)))
        res[name][rx] = mean
        print(f"{name} rx{rx}: N={len(Pn)}  within-capture |mean phasor| tx2 {R[0].mean():.3f} tx3 {R[1].mean():.3f}"
              f"  2nd-half minus 1st-half [deg] tx2 {np.degrees(np.median(np.abs(drift[0]))):.1f} tx3 {np.degrees(np.median(np.abs(drift[1]))):.1f}")
        # slope across the 30 grouped subcarriers (1.25 MHz steps): CSD check
        for k, lab in ((0, 'tx2'), (1, 'tx3')):
            dph = np.angle(mean[k, :, 1:] * np.conj(mean[k, :, :-1]))   # per-step phase increment
            print(f"      {lab}/tx1 per-subcarrier-step phase [deg], ant1..3 median: "
                  + "  ".join(f"{np.degrees(np.median(dph[a])):7.1f}" for a in range(3)))

names = list(res)
print("\nchange between captures of conj(tx1)*txk phase [deg] (median over 30 subcarriers), per RX antenna:")
for i in range(len(names)):
    for j in range(i + 1, len(names)):
        a, b = names[i], names[j]
        for rx in sorted(res[a]):
            dd = np.angle(res[b][rx] * np.conj(res[a][rx]))           # (2, 3, 30)
            med = np.degrees(np.angle(np.exp(1j * dd).mean(-1)))      # circular mean over subcarriers
            spread = np.degrees(np.abs(np.angle(np.exp(1j * (dd - np.radians(med)[..., None])))).max(-1))
            print(f"  {a} -> {b} rx{rx}: tx2 " + " ".join(f"{m:7.1f}" for m in med[0])
                  + "   tx3 " + " ".join(f"{m:7.1f}" for m in med[1])
                  + f"   (max dev over sc: {spread.max():.0f})")

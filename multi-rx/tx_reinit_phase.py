#!/usr/bin/env python3
"""Split one capture at TX re-init gaps (>2 s without records) and compare the inter-TX-stream
phase conj(H_tx1)*H_txk per (RX, physical RX antenna, subcarrier) between segments.
RX-side per-packet phase and RX chain offsets cancel in the product (same RX chain).
usage: tx_reinit_phase.py STEP merged.bin
"""
import sys, struct
import numpy as np
sys.dont_write_bytecode = True   # csi_check is imported from this directory; leave no __pycache__ in the repo
from csi_check import parse_bfee

step = int(sys.argv[1]); path = sys.argv[2]
data = open(path, 'rb').read()
off, T, HH, seen = 0, {}, {}, {}
while off + 11 <= len(data):
    t, rx, ln = struct.unpack_from('<dBH', data, off); off += 11
    pl = data[off:off + ln]; off += ln
    if len(pl) < ln: break
    if not ln or pl[0] != 0xbb: continue
    seen[rx] = seen.get(rx, 0) + 1
    if seen[rx] % step: continue
    b = parse_bfee(pl[1:])
    if b['csi'] is None or b['ntx'] != 3 or b['nrx'] != 3: continue
    H = np.zeros((3, 3, 30), complex)
    for j in range(9):
        H[j % 3, b['perm'][j // 3] - 1] = b['csi'][:, j]
    T.setdefault(rx, []).append(t); HH.setdefault(rx, []).append(H)

def cmean(x, axis):
    return np.exp(1j * x).mean(axis)

seg_means = {}
for rx in sorted(T):
    t = np.array(T[rx]); H = np.array(HH[rx])
    cut = np.where(np.diff(t) > 2.0)[0] + 1
    segs = np.split(np.arange(len(t)), cut)
    print(f"rx{rx}: segments " + ", ".join(f"{t[s[-1]] - t[s[0]]:.1f}s(N={len(s)})" for s in segs)
          + "   gaps " + ", ".join(f"{t[c] - t[c - 1]:.1f}s" for c in cut))
    P = np.conj(H[:, 0:1]) * H[:, 1:3]
    Pn = P / np.maximum(np.abs(P), 1e-9)
    seg_means[rx] = []
    for i, s in enumerate(segs):
        m = Pn[s].mean(0); h = len(s) // 2
        drift = np.angle(Pn[s[h:]].mean(0) * np.conj(Pn[s[:h]].mean(0)))
        dmed = np.degrees(np.angle(cmean(drift, -1)))            # (2, 3) circular mean over sc
        print(f"   seg{i}: |mean phasor| tx2 {np.abs(m[0]).mean():.3f} tx3 {np.abs(m[1]).mean():.3f}"
              f"   2nd-1st half [deg] tx2 " + " ".join(f"{v:6.1f}" for v in dmed[0])
              + "  tx3 " + " ".join(f"{v:6.1f}" for v in dmed[1]))
        seg_means[rx].append(m)

print("\nchange of conj(tx1)*txk across TX re-init [deg]: circular mean over 30 subcarriers per RX antenna"
      " (R = |mean e^{jD}| over subcarriers, 1 = same change on every subcarrier)")
for rx in sorted(seg_means):
    ms = seg_means[rx]
    for i in range(len(ms) - 1):
        D = np.angle(ms[i + 1] * np.conj(ms[i]))                  # (2, 3, 30)
        c = cmean(D, -1)
        print(f"   rx{rx} seg{i}->seg{i + 1}: tx2 " + " ".join(f"{np.degrees(np.angle(v)):7.1f}(R{abs(v):.2f})" for v in c[0])
              + "   tx3 " + " ".join(f"{np.degrees(np.angle(v)):7.1f}(R{abs(v):.2f})" for v in c[1]))

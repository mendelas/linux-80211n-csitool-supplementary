#!/usr/bin/env python3
"""Count distinct TX states across TX inits (segments = files, and gaps > 2 s inside a file).
Per segment and RX: G[k,l,ant,sc] = unit-phasor mean of conj(H_k) H_l over records (k<l TX streams,
physical RX antenna after perm). RX-side per-packet phase and RX chain offsets cancel (same chain).
Distance(a,b) = median over (rx, k<l, ant, sc) of |angle(G_b conj G_a)| [deg]; same TX state in a
static scene -> ~noise floor (each segment split in halves gives the floor). Also the amplitude
fingerprint error (mean |H| normalised per (rx, ant, sc) by the sum over tx).
usage: tx_state_count.py STEP TRIM_S file [file ...]   (TRIM_S = seconds dropped after each gap)
"""
import os, sys, struct
import numpy as np
sys.dont_write_bytecode = True   # csi_check is imported from this directory; leave no __pycache__ in the repo
from csi_check import parse_bfee

step = int(sys.argv[1]); trim = float(sys.argv[2]); files = sys.argv[3:]
PAIRS = ((0, 1), (0, 2), (1, 2))


def feats(Hs):
    A = np.abs(Hs).mean(0); A = A / A.sum(0, keepdims=True)
    G = np.stack([np.conj(Hs[:, k]) * Hs[:, l] for k, l in PAIRS], 1)    # (N, 3 pairs, ant, sc)
    G = (G / np.maximum(np.abs(G), 1e-9)).mean(0)
    return A, G


segs = []   # (label, {rx: (A, G, A_half1, G_half1, A_half2, G_half2)})
for path in files:
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
    name = path.split('/')[-1].split('_', 2)[-1].replace('_merged.bin', '').replace('aod_', '')
    rx0 = sorted(T)[0]
    t0 = np.array(T[rx0])
    cut = np.where(np.diff(t0) > 2.0)[0] + 1
    bounds = [-np.inf] + [t0[c] - 1.0 for c in cut] + [np.inf]
    starts = [t0[0]] + [t0[c] for c in cut]
    nseg = len(bounds) - 1
    for i in range(nseg):
        d = {}
        for rx in sorted(T):
            t = np.array(T[rx]); H = np.array(HH[rx])
            m = (t > bounds[i]) & (t < bounds[i + 1]) & (t > starts[i] + trim)
            Hs = H[m]; h = len(Hs) // 2
            d[rx] = feats(Hs) + feats(Hs[:h]) + feats(Hs[h:]) + (len(Hs),)
        segs.append((name if nseg == 1 else f"{name}/s{i}", d))


def dist(da, db, ia=0, ib=0):
    ph = []; am = []
    for rx in da:
        Ga, Gb = da[rx][ia * 2 + 1], db[rx][ib * 2 + 1]
        Aa, Ab = da[rx][ia * 2], db[rx][ib * 2]
        ph.append(np.abs(np.angle(Gb * np.conj(Ga))).ravel())
        am.append(np.abs(Ab - Aa).mean() / Aa.mean())
    return np.degrees(np.median(np.concatenate(ph))), np.mean(am)


labels = [s[0] for s in segs]
print("segments (records used per RX at step %d):" % step)
for lab, d in segs:
    floor = dist(d, d, 1, 2)
    print(f"  {lab:>16s}  N={[d[rx][6] for rx in d]}  coherence |G| {np.mean([np.abs(d[rx][1]).mean() for rx in d]):.3f}"
          f"  half-vs-half: phase {floor[0]:5.1f} deg  amp {floor[1]:.3f}")

n = len(segs)
P = np.zeros((n, n)); Am = np.zeros((n, n))
for i in range(n):
    for j in range(n):
        P[i, j], Am[i, j] = dist(segs[i][1], segs[j][1])
w = max(len(l) for l in labels)
print("\nphase distance [deg] (median |angle change| of conj(H_k)H_l over rx, pair, ant, sc):")
print(" " * (w + 2) + " ".join(f"{i:>5d}" for i in range(n)))
for i in range(n):
    print(f"{labels[i]:>{w}s}  " + " ".join(f"{P[i, j]:5.1f}" for j in range(n)) + f"   [{i}]")
print("\namplitude-fingerprint distance:")
for i in range(n):
    print(f"{labels[i]:>{w}s}  " + " ".join(f"{Am[i, j]:5.3f}" for j in range(n)) + f"   [{i}]")

# greedy clustering by phase distance threshold (THR env var, deg). Across captures the scene also
# changes: on 2026-11-05 the same TX state differed by 13-17 deg between captures, different states
# by 81-97 deg, so cross-capture clusters need THR ~ 30 (8 only separates within one capture).
thr = float(os.environ.get('THR', '8'))
cl = [-1] * n; k = 0
for i in range(n):
    if cl[i] >= 0: continue
    cl[i] = k
    for j in range(i + 1, n):
        if cl[j] < 0 and P[i, j] < thr: cl[j] = k
    k += 1
print(f"\nclusters (phase distance < {thr} deg to the first member):")
for c in range(k):
    mem = [labels[i] for i in range(n) if cl[i] == c]
    print(f"  state {chr(65 + c)}: " + ", ".join(mem))

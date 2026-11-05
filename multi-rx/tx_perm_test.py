#!/usr/bin/env python3
"""Is a TX re-init a permutation of which antenna sends which stream?
Per segment: amplitude fingerprint A[rx][tx, ant, sc] = mean |H| (RX-phase invariant), normalised
per (rx, ant, sc) by the sum over tx (removes RX gain / AGC). For every permutation p of the 3 TX
streams, error(p) = mean |A_b[k] - A_a[p(k)]| / mean A. Static scene + TX perm -> one p ~ 0.
Then, for the best p, the phase test: G[k,l] = mean conj(H_k) H_l (RX-phase invariant) must obey
G_b[k,l] = e^{j(c_l - c_k)} G_a[p(k), p(l)] with the same phase on every RX antenna -> R_ant ~ 1.
usage: tx_perm_test.py STEP file [file ...]   (segments = files, and gaps > 2 s inside a file)
"""
import sys, struct, itertools
import numpy as np
sys.dont_write_bytecode = True   # csi_check is imported from this directory; leave no __pycache__ in the repo
from csi_check import parse_bfee

step = int(sys.argv[1]); files = sys.argv[2:]
segs = []    # (label, {rx: (A [3,3,30], G [3,3,3,30])})
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
    name = path.split('/')[-1].split('_', 2)[-1].replace('_merged.bin', '')
    rx0 = sorted(T)[0]
    cut = np.where(np.diff(np.array(T[rx0])) > 2.0)[0] + 1
    tcut = [T[rx0][c] - 1.0 for c in cut]
    nseg = len(cut) + 1
    for i in range(nseg):
        d = {}
        for rx in sorted(T):
            t = np.array(T[rx]); H = np.array(HH[rx])
            lo = -np.inf if i == 0 else tcut[i - 1]; hi = np.inf if i == nseg - 1 else tcut[i]
            Hs = H[(t > lo) & (t < hi)]
            A = np.abs(Hs).mean(0)
            A = A / A.sum(0, keepdims=True)
            G = (np.conj(Hs[:, :, None]) * Hs[:, None, :])
            G = (G / np.maximum(np.abs(G), 1e-9)).mean(0)          # unit-phasor mean, [k, l, ant, sc]
            d[rx] = (A, G)
        segs.append((name if nseg == 1 else f"{name}/seg{i}", d))

perms = list(itertools.permutations(range(3)))
lab = lambda p: "(" + ",".join(f"tx{q + 1}" for q in p) + ")"
print("amplitude-fingerprint error for each TX-stream permutation p (b[k] vs a[p(k)]), both RX pooled:")
for i in range(len(segs) - 1):
    for j in range(i + 1, len(segs)):
        (na, da), (nb, db) = segs[i], segs[j]
        errs = []
        for p in perms:
            e = np.mean([np.abs(db[rx][0] - da[rx][0][list(p)]).mean() / da[rx][0].mean() for rx in da])
            errs.append(e)
        k = int(np.argmin(errs))
        # phase test for the best p
        Rs = []
        for rx in da:
            Ga, Gb = da[rx][1], db[rx][1]
            for (u, v) in ((0, 1), (0, 2), (1, 2)):
                ratio = Gb[u, v] * np.conj(Ga[perms[k][u], perms[k][v]])   # [ant, sc]
                ratio = ratio / np.maximum(np.abs(ratio), 1e-9)
                Rs.append(np.abs(ratio.mean(0)).mean())                     # consistency across RX antennas, per sc
        print(f"  {na:>28s} -> {nb:<28s} " + "  ".join(f"{lab(p)}:{e:.3f}" for p, e in zip(perms, errs))
              + f"   best {lab(perms[k])}  phase-consistency over RX antennas R={np.mean(Rs):.2f}")

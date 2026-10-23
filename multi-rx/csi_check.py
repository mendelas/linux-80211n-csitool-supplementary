#!/usr/bin/env python3
"""csi_check.py: is this merged.bin (or rxN.bin) a healthy capture?

usage: ./csi_check.py [file ...]        default: newest ~/csi_data/*/*_merged.bin

Record: [double t][uint8 rx_id][uint16 len][len bytes payload]
payload[0] == 0xbb -> payload[1:] is a CSI-tool bfee record (matlab/read_bfee.c).
Prints per-RX counts, rate, loss, timing, RSSI, antenna perm and amplitude stability,
then a verdict line. Needs python3 + numpy on the control PC.
"""
import sys, os, glob, struct, collections
import numpy as np

EXPECTED_RATE = 1000     # rec/s expected from DELAY=1000 in run_experiment.sh


def parse_bfee(b):
    ts_low, bfee_count = struct.unpack_from('<IH', b, 0)
    nrx, ntx, ra, rb, rc, noise, agc, asel, clen, rate = struct.unpack_from('<BBBBBbBBHH', b, 8)
    calc = (30 * (nrx * ntx * 8 * 2 + 3) + 7) // 8
    csi = None
    if clen == calc and len(b) >= 20 + clen:
        p = b[20:20 + clen]
        csi = np.zeros((30, nrx * ntx), dtype=np.complex64)
        idx = 0
        for i in range(30):
            idx += 3
            r = idx % 8
            for j in range(nrx * ntx):
                k = idx // 8
                re = ((p[k] >> r) | (p[k + 1] << (8 - r))) & 0xff
                im = ((p[k + 1] >> r) | (p[k + 2] << (8 - r))) & 0xff
                csi[i, j] = complex(re - 256 if re > 127 else re, im - 256 if im > 127 else im)
                idx += 16
    perm = ((asel & 3) + 1, ((asel >> 2) & 3) + 1, ((asel >> 4) & 3) + 1)
    return dict(ts=ts_low, cnt=bfee_count, nrx=nrx, ntx=ntx, rssi=(ra, rb, rc), noise=noise,
                agc=agc, perm=perm, clen=clen, calc=calc, rate=rate, csi=csi)


def load(path):
    data = open(path, 'rb').read()
    off, per, codes = 0, collections.defaultdict(list), collections.Counter()
    while off + 11 <= len(data):
        t, rx, ln = struct.unpack_from('<dBH', data, off); off += 11
        pl = data[off:off + ln]; off += ln
        if len(pl) < ln: break
        codes[(rx, pl[0] if ln else -1)] += 1
        if ln and pl[0] == 0xbb:
            per[rx].append((t, parse_bfee(pl[1:])))
    return per, codes


def check(path):
    per, codes = load(path)
    warn = []
    print(f"file: {path}  ({os.path.getsize(path) / 1e6:.1f} MB)")
    print("records per (rx, code):", {f"rx{r} 0x{c:02x}": n for (r, c), n in sorted(codes.items())})
    if not per:
        print("VERDICT: BAD  (no CSI records at all)"); return
    counts = {}
    for rx in sorted(per):
        recs = per[rx]
        t = np.array([r[0] for r in recs]); b = [r[1] for r in recs]
        n = len(recs); span = t[-1] - t[0] if n > 1 else 0.0; rate = n / span if span else 0.0
        counts[rx] = n
        cnt = np.array([x['cnt'] for x in b]); ts = np.array([x['ts'] for x in b], dtype=np.int64)
        dcnt = np.diff(cnt) % 65536; dts = np.diff(ts) % (1 << 32)
        lost = int((dcnt[dcnt > 1] - 1).sum()); gaps = int((dcnt > 1).sum())
        rssi = np.array([x['rssi'] for x in b]); agc = np.array([x['agc'] for x in b])
        noise = sorted(set(x['noise'] for x in b))
        badlen = sum(1 for x in b if x['clen'] != x['calc'])
        shapes = collections.Counter((x['ntx'], x['nrx']) for x in b)
        rates = collections.Counter(hex(x['rate']) for x in b)
        perms = collections.Counter(x['perm'] for x in b)
        switches = sum(1 for i in range(1, n) if b[i]['perm'] != b[i - 1]['perm'])
        have = [x for x in b if x['csi'] is not None]
        zero = sum(1 for x in have if not np.any(x['csi']))
        dt = np.diff(t) * 1e3
        print(f"\n== rx{rx}: {n} CSI records over {span:.2f}s -> {rate:.0f} rec/s")
        print(f"   (Ntx,Nrx): {dict(shapes)}   rate field: {dict(rates)}   bad CSI len: {badlen}   all-zero CSI: {zero}")
        print(f"   loss (bfee_count gaps): {lost} pkts in {gaps} gaps   count reorder/wrap: {int((dcnt == 0).sum() + (dcnt > 60000).sum())}")
        print(f"   NIC inter-arrival [us]: median {np.median(dts):.0f}  p5 {np.percentile(dts, 5):.0f}  p95 {np.percentile(dts, 95):.0f}  max {dts.max()}")
        print(f"   control-PC inter-arrival [ms]: median {np.median(dt):.2f}  p95 {np.percentile(dt, 95):.2f}  max {dt.max():.1f}"
              f"   ({int((dt < 0.2).sum())} of {len(dt)} under 0.2ms = ssh/stdio bursts; use NIC timestamp_low for timing)")
        print(f"   RSSI a/b/c mean {rssi.mean(0).round(1)}  std {rssi.std(0).round(1)}   noise {noise}   agc mean {agc.mean():.1f}")
        print(f"   perm: {dict(perms)}   switches: {switches}   (apply perm per record before using phase / antenna order)")
        if have and have[0]['ntx'] * have[0]['nrx'] == 3:
            A = np.array([np.abs(x['csi']).mean(0) for x in have])          # (N, 3) mean |CSI| over subcarriers
            Ap = np.zeros_like(A)
            for i, x in enumerate(have):
                for col, ant in enumerate(x['perm']): Ap[i, ant - 1] = A[i, col]
            bins = (np.array([r[0] for r in recs if r[1]['csi'] is not None]) - t[0]).astype(int)
            sec = np.array([Ap[bins == k].mean(0) for k in range(bins.max() + 1) if (bins == k).any()])
            print(f"   |CSI| per antenna (perm applied): mean {Ap.mean(0).round(1)}  per-record std {Ap.std(0).round(2)}"
                  f"  1-s-mean range {(sec.max(0) - sec.min(0)).round(1)}")
        # warnings
        if lost: warn.append(f"rx{rx}: {lost} lost packets")
        if badlen: warn.append(f"rx{rx}: {badlen} records with wrong CSI length")
        if zero: warn.append(f"rx{rx}: {zero} all-zero CSI records")
        if span and abs(rate - EXPECTED_RATE) > 0.05 * EXPECTED_RATE: warn.append(f"rx{rx}: {rate:.0f} rec/s, expected ~{EXPECTED_RATE}")
        if len(shapes) > 1: warn.append(f"rx{rx}: mixed (Ntx,Nrx) {dict(shapes)}")
        if n < 1000: warn.append(f"rx{rx}: only {n} records")
    rxs = sorted(per)
    if len(rxs) >= 2:
        t0 = {rx: per[rx][0][0] for rx in rxs}; t1 = {rx: per[rx][-1][0] for rx in rxs}
        print(f"\n== cross-RX: start offset " + "  ".join(f"rx{r} {t0[r] - min(t0.values()):+.3f}s" for r in rxs)
              + "   end offset " + "  ".join(f"rx{r} {t1[r] - min(t1.values()):+.3f}s" for r in rxs))
        a = set((x['ts'], x['cnt']) for _, x in per[rxs[0]][:5000]); bb = set((x['ts'], x['cnt']) for _, x in per[rxs[1]][:5000])
        dup = len(a & bb)
        print(f"   identical (timestamp_low, bfee_count) pairs rx{rxs[0]} vs rx{rxs[1]} (first 5000): {dup}")
        if dup > 10: warn.append(f"rx{rxs[0]} and rx{rxs[1]} share payloads: two streams from the same node?")
        if max(counts.values()) - min(counts.values()) > 0.05 * max(counts.values()): warn.append(f"record counts differ between RX: {counts}")
        if max(abs(t0[r] - min(t0.values())) for r in rxs) > 5: warn.append("RX streams started more than 5 s apart")
    print()
    if warn:
        print("VERDICT: CHECK")
        for w in warn: print("   - " + w)
    else:
        print("VERDICT: OK   (no loss, sane shapes, expected rate, distinct RX streams)")


if __name__ == '__main__':
    files = sys.argv[1:]
    if not files:
        cands = glob.glob(os.path.expanduser('~/csi_data/*/*_merged.bin'))
        if not cands: sys.exit("no file given and no ~/csi_data/*/*_merged.bin found")
        files = [max(cands, key=os.path.getmtime)]
    for i, f in enumerate(files):
        if i: print("\n" + "=" * 70)
        check(f)

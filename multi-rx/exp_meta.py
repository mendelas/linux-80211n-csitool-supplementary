#!/usr/bin/env python3
"""Experiment config -> metadata sidecar, for run_experiment.sh (rule 2026-11-07: EVERY recording
has its own experiment config, so anyone can later tell what the situation and the experiment were).

  exp_meta.py check  EXP.json                  -> prints "LABEL SECONDS RATE", or the problems + exit 1
  exp_meta.py start  EXP.json META.json STAMP  -> writes the sidecar (radio / hosts / files from env)
  exp_meta.py event  META.json NAME EPOCH      -> appends a timed event (control-PC CLOCK_REALTIME,
                                                  the same clock as the merged records' t)
  exp_meta.py set    META.json KEY VALUE [KEY VALUE ...]  -> result fields (numbers parsed)

Experiment config (multi-rx/experiments/<YYYYMMDD>/<label>.json): see experiments/README.md.
The sidecar <stamp>_<label>_meta.json next to the .bin files embeds the experiment config AND the
setup file as they were at recording time, so it stands alone.
"""
import datetime, hashlib, json, os, re, socket, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SETUPS = os.path.join(HERE, 'experiments', 'setups')
RATE_STREAMS = {'0x4901': 1, '0x1c911': 3}     # the rate flags run_experiment.sh is used with
TRAJ_TYPES = {'static', 'square', 'line', 'radial', 'perimeter', 'free', 'other'}
PURPOSES = {'exploration', 'confirmation', 'pilot', 'calibration', 'other'}


def load_json(p):
    with open(p) as f:
        return json.load(f)


def problems(exp, path):
    bad = []
    g = lambda *ks: _get(exp, ks)
    lab = g('label')
    if not isinstance(lab, str) or not re.fullmatch(r'[A-Za-z0-9_]+', lab or ''):
        bad.append('label: [A-Za-z0-9_]+ が要る')
    elif os.path.splitext(os.path.basename(path))[0] != lab:
        bad.append(f'label "{lab}" とファイル名 "{os.path.basename(path)}" が違う')
    today = datetime.date.today().isoformat()
    if g('date') != today:
        bad.append(f'date が今日 ({today}) でない: {g("date")!r}  (実験ごとに今日の config を作る)')
    s = g('seconds')
    if not isinstance(s, int) or s <= 0:
        bad.append('seconds: 正の整数')
    st = g('setup')
    if not isinstance(st, str) or not os.path.isfile(os.path.join(SETUPS, f'{st}.json')):
        bad.append(f'setup: experiments/setups/<id>.json の id が要る (無い: {st!r})')
    rate = g('tx', 'rate')
    if rate not in RATE_STREAMS:
        bad.append(f'tx.rate は {sorted(RATE_STREAMS)} のどれか: {rate!r}')
    elif g('tx', 'streams') != RATE_STREAMS[rate]:
        bad.append(f'tx.streams ({g("tx", "streams")!r}) が rate {rate} ({RATE_STREAMS[rate]} ストリーム) と合わない')
    for k in (('tx', 'antennas'), ('trajectory', 'description'), ('purpose_note',), ('people',)):
        if not isinstance(g(*k), str) or not g(*k).strip():
            bad.append(f'{".".join(k)}: 空でない文字列が要る')
    if g('trajectory', 'type') not in TRAJ_TYPES:
        bad.append(f'trajectory.type は {sorted(TRAJ_TYPES)} のどれか')
    if g('purpose') not in PURPOSES:
        bad.append(f'purpose は {sorted(PURPOSES)} のどれか')
    return bad


def _get(d, ks):
    for k in ks:
        if not isinstance(d, dict) or k not in d:
            return None
        d = d[k]
    return d


def now_local():
    return datetime.datetime.now().astimezone().isoformat(timespec='milliseconds')


def write_atomic(path, obj):
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(tmp, path)


def git_state():
    try:
        rev = subprocess.run(['git', '-C', HERE, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
        dirty = subprocess.run(['git', '-C', HERE, 'status', '--porcelain', '--', '.'], capture_output=True, text=True).stdout.strip()
        return {'commit': rev, 'uncommitted_changes_in_multi_rx': dirty.splitlines()}
    except OSError:
        return None


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'check' and len(sys.argv) == 3:
        p = sys.argv[2]
        try:
            exp = load_json(p)
        except (OSError, ValueError) as e:
            sys.exit(f'experiment config を読めない: {p}: {e}')
        bad = problems(exp, p)
        if bad:
            print(f'experiment config の不備 ({p}):', file=sys.stderr)
            for b in bad:
                print('   - ' + b, file=sys.stderr)
            sys.exit(1)
        print(exp['label'], exp['seconds'], exp['tx']['rate'])
    elif cmd == 'start' and len(sys.argv) == 5:
        p, meta, stamp = sys.argv[2:5]
        raw = open(p, 'rb').read()
        exp = json.loads(raw)
        sp = os.path.join(SETUPS, f'{exp["setup"]}.json')
        e = os.environ.get
        write_atomic(meta, {
            'schema': 1,
            'what': 'run_experiment.sh の収録 1 本の記録。experiment = 実験 config、setup = 設置 (どちらも収録時点の写し)',
            'experiment_config': {'path': os.path.abspath(p), 'sha256': hashlib.sha256(raw).hexdigest()},
            'experiment': exp,
            'setup_file': os.path.abspath(sp),
            'setup': load_json(sp),
            'run': {
                'stamp': stamp, 'start_local': now_local(), 'control_pc': socket.gethostname(),
                'supplementary_git': git_state(),
                'radio': {k.lower(): e(k) for k in ('CH', 'BW', 'RATE', 'TXPWR', 'PAYLOAD', 'DELAY', 'NPKTS', 'IF')},
                'tx_host': e('TX'), 'rx_hosts': (e('RXS') or '').split(),
                'files': {'rx': (e('RFILES') or '').split(), 'merged': e('MG')},
            },
            'events': [],
            'result': {},
        })
    elif cmd == 'event' and len(sys.argv) == 5:
        meta, name, epoch = sys.argv[2:5]
        m = load_json(meta)
        m['events'].append({'name': name, 'epoch': float(epoch),
                            'local': datetime.datetime.fromtimestamp(float(epoch)).astimezone().isoformat(timespec='milliseconds')})
        write_atomic(meta, m)
    elif cmd == 'set' and len(sys.argv) >= 5 and len(sys.argv) % 2 == 1:
        meta = sys.argv[2]
        m = load_json(meta)
        for k, v in zip(sys.argv[3::2], sys.argv[4::2]):
            try:
                v = int(v)
            except ValueError:
                try:
                    v = float(v)
                except ValueError:
                    pass
            m['result'][k] = v
        write_atomic(meta, m)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()

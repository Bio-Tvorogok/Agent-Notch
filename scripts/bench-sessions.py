#!/usr/bin/env python3
"""Generate isolated logs, measure process CPU time/RSS, and enforce AN-0.6-9 budgets."""
import argparse
import datetime as dt
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import time


def stamp():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')


def row(vendor, text):
    if vendor == 'claude':
        return {'type': 'last-prompt', 'lastPrompt': text}
    return {'type': 'event_msg', 'timestamp': stamp(),
            'payload': {'type': 'user_message', 'message': text}}


def generate(root, pid):
    if root.exists():
        shutil.rmtree(root)
    claude = root / 'claude'
    codex = root / 'codex'
    logs = []
    for vendor, config in [('claude', claude), ('codex', codex)]:
        for i in range(100):
            directory = config / ('projects/p' if vendor == 'claude' else 'sessions/' + dt.datetime.now().strftime('%Y/%m/%d'))
            directory.mkdir(parents=True, exist_ok=True)
            path = directory / f'live-{i}.jsonl'
            rows = [row(vendor, f'live {i}')]
            if vendor == 'claude':
                rows.insert(0, {'type': 'user', 'timestamp': stamp(), 'cwd': '/tmp/an06-bench/project',
                                'message': {'content': f'live {i}'}})
            if vendor == 'codex':
                rows.insert(0, {'type': 'session_meta', 'timestamp': stamp(),
                               'payload': {'id': f'codex-{i}', 'cwd': '/tmp/an06-bench/project'}})
                rows.append({'type': 'event_msg', 'timestamp': stamp(), 'payload': {'type': 'task_started'}})
            path.write_text(''.join(json.dumps(r) + '\n' for r in rows))
            logs.append((vendor, path))
            if vendor == 'claude':
                live = config / 'sessions' / f'{i}.json'
                live.parent.mkdir(exist_ok=True)
                live.write_text(json.dumps({'sessionId': f'live-{i}', 'status': 'busy', 'pid': pid}))
        for i in range(5000):
            directory = config / (f'projects/archive-{i % 50}' if vendor == 'claude' else f'sessions/2020/01/{i % 28 + 1:02}')
            directory.mkdir(parents=True, exist_ok=True)
            path = directory / f'archive-{i}.jsonl'
            path.write_text(json.dumps(row(vendor, 'archived')) + '\n')
            os.utime(path, (1_600_000_000, 1_600_000_000))
    return logs, {'CLAUDE_CONFIG_DIR': str(claude), 'CODEX_HOME': str(codex)}


def sample(process):
    process.stdin.write('sample\n')
    process.stdin.flush()
    values = json.loads(process.stdout.readline())
    return time.monotonic(), values['cpu'], values['rss']


def phase(process, seconds, logs=None):
    first = sample(process)
    peak = first[2]
    end = first[0] + seconds
    next_sample, next_write, count = first[0], first[0], 0
    while time.monotonic() < end:
        now = time.monotonic()
        if logs and now >= next_write:
            vendor, path = logs[count % len(logs)]
            with path.open('a') as file:
                file.write(json.dumps(row(vendor, f'bench:{time.time():.6f}')) + '\n')
            count += 1
            next_write += 0.05  # 20 append operations/s, all 200 sessions every ten seconds.
        if now >= next_sample:
            peak = max(peak, sample(process)[2])
            next_sample += 1
        time.sleep(0.01)
    last = sample(process)
    return {'cpu_percent_one_core': 100 * (last[1] - first[1]) / (last[0] - first[0]),
            'rss_max_mb': max(peak, last[2]) / 1_000_000, 'appends': count}


def run(args, mode):
    root = args.root / ('fixture-' + mode)
    logs, config = generate(root, os.getpid())
    process = subprocess.Popen([str(args.root / mode), str(root)], env={**os.environ, **config},
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        ready = process.stdout.readline().strip()
        if ready != 'READY 200':
            raise RuntimeError(f'{mode}: expected 200 working sessions, got {ready!r}')
        time.sleep(3)
        idle = phase(process, args.duration)
        active = phase(process, args.duration, logs)
        time.sleep(2)  # let the last baseline polling interval observe its appends
        process.stdin.write('stop\n')
        process.stdin.flush()
        stdout, stderr = process.communicate(timeout=15)
        if process.returncode:
            raise RuntimeError(f'{mode} exited {process.returncode}: {stderr}')
        observation = json.loads(stdout.strip().splitlines()[-1])
        passed = idle['cpu_percent_one_core'] < 1 and active['cpu_percent_one_core'] < 5 and max(idle['rss_max_mb'], active['rss_max_mb']) < 150
        # Load must actually reach the scanner; a silent watcher cannot pass on low CPU.
        delivery = observation['observed_appends'] >= active['appends'] * 0.9
        return {'idle': idle, 'active': active, **observation, 'delivery_passed': delivery, 'passed': passed and delivery}
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--base', required=True)
    parser.add_argument('--duration', type=float, default=40)
    args = parser.parse_args()
    physical = str(args.root.resolve())
    if not physical.startswith(('/tmp/an06-', '/private/tmp/an06-')):
        parser.error('benchmark fixtures must stay under /tmp/an06-*')
    if args.duration < 30:
        parser.error('duration must cover at least one 30s safety interval')
    sources = sorted(Path('Sources/NotchCore').glob('*.swift')) + [Path('scripts/SessionBenchmark/main.swift')]
    digest = hashlib.sha256()
    for source in sources:
        digest.update(str(source).encode())
        digest.update(source.read_bytes())
    result = {'after_source_sha256': digest.hexdigest(), 'architecture': os.uname().machine,
              'base_revision': args.base, 'duration_per_phase_s': args.duration,
              'workload': {'live_sessions': 200, 'archived_files': 10000, 'appends_per_s': 20},
              'thresholds': {'idle_cpu_lt': 1, 'active_cpu_lt': 5, 'rss_mb_lt': 150},
              'before': run(args, 'before'), 'after': run(args, 'after')}
    (args.root / 'results.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return 0 if result['after']['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())

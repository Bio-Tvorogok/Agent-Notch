#!/usr/bin/env python3
"""Measure the installed app with its list and cards closed, after startup settles."""
import argparse
import json
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--duration', type=float, default=16)
parser.add_argument('--max-cpu', type=float, default=5)
parser.add_argument('--output')
args = parser.parse_args()
if not 5 <= args.duration <= 60:
    parser.error('duration must be between 5 and 60 seconds')
executable = '/Applications/Agent Notch.app/Contents/MacOS/AgentsNotch'
processes = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True)
pids = [int(parts[0]) for row in processes.splitlines()
        if len(parts := row.strip().split(maxsplit=1)) == 2 and parts[1] == executable]
if len(pids) != 1:
    raise SystemExit('Expected one running installed Agent Notch')

def sample():
    fields = subprocess.check_output(['/bin/ps', '-p', str(pids[0]), '-o', 'rss=,time='], text=True).split()
    cpu = sum(float(value) * 60 ** i for i, value in enumerate(reversed(fields[1].split(':'))))
    return {'wall': time.monotonic(), 'cpu': cpu, 'rss_mib': int(fields[0]) / 1024}

samples = [sample()]
while time.monotonic() - samples[0]['wall'] < args.duration:
    time.sleep(min(1, args.duration - (time.monotonic() - samples[0]['wall'])))
    samples.append(sample())
elapsed = samples[-1]['wall'] - samples[0]['wall']
cpu = 100 * (samples[-1]['cpu'] - samples[0]['cpu']) / elapsed
result = {'pid': pids[0], 'duration_seconds': elapsed, 'cpu_percent_one_core': cpu,
          'rss_min_mib': min(s['rss_mib'] for s in samples), 'rss_max_mib': max(s['rss_mib'] for s in samples),
          'max_cpu_percent': args.max_cpu, 'passed': cpu <= args.max_cpu}
if args.output:
    with open(args.output, 'w') as file:
        json.dump(result, file, indent=2)
print(json.dumps(result, indent=2))
raise SystemExit(0 if result['passed'] else 1)

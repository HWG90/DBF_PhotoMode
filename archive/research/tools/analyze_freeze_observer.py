"""Summarize the latest opt-in Freeze trace without inferring physics causes.

Reads an existing log once. No process access or live polling. Resource names
are asset identities, not unit identities; repeated rows are never counted as
distinct bodies. Exit 2 means no completed observer episode was found.
"""
import argparse
import json
import math
from pathlib import Path
import re

EVENT = re.compile(r"Freeze observer: episode=(\d+) (.*)")
DRIFT = re.compile(
    r"Freeze drift: episode=(\d+) sample=(\d+) resource=(.*?) "
    r"root_m=(\S+) root_deg=(\S+) bone_local_m=(\S+) bone_local_deg=(\S+)")
COMPLETE = re.compile(
    r"complete units=(\d+) scanned=(\d+) truncated=(true|false) "
    r"errors=(\d+) max_step_ms=(\S+) elapsed=(\S+);")


def analyze(text):
    episodes = {}
    armed = False
    disabled = None
    malformed = 0
    for line in text.splitlines():
        if 'Freeze observer armed for four ' in line:
            episodes = {}
            armed = True
            disabled = None
            malformed = 0
        if 'Freeze observer disabled: ' in line:
            disabled = line.split('Freeze observer disabled: ', 1)[1]
        event = EVENT.search(line)
        if event:
            number, detail = int(event[1]), event[2]
            if detail.startswith('started;'):
                episodes[number] = dict(episode=number, state='started', drift_rows=[])
            row = episodes.get(number)
            if row is None:
                malformed += 1
                continue
            if detail.startswith('stopped='):
                row.update(state='stopped', reason=detail[len('stopped='):])
            complete = COMPLETE.match(detail)
            if complete:
                try:
                    ms, elapsed = float(complete[5]), float(complete[6])
                except ValueError:
                    malformed += 1
                    continue
                if not all(math.isfinite(v) and v >= 0 for v in (ms, elapsed)):
                    malformed += 1
                    continue
                row.update(state='complete', sampled_units=int(complete[1]),
                           scanned_entries=int(complete[2]), truncated=complete[3] == 'true',
                           read_errors=int(complete[4]), max_step_ms=ms, elapsed_seconds=elapsed)
            elif detail.startswith('complete'):
                malformed += 1
        drift = DRIFT.search(line)
        if drift:
            number, sample = int(drift[1]), int(drift[2])
            row = episodes.get(number)
            try:
                values = [float(drift[i]) for i in range(4, 8)]
            except ValueError:
                malformed += 1
                continue
            if row is None or row['state'] != 'started' or sample not in (1, 2) or not all(
                    math.isfinite(v) and v >= 0 for v in values):
                malformed += 1
                continue
            root = values[0] > .001 or values[1] > .1
            bones = values[2] > .001 or values[3] > .1
            extra = re.search(r' bone_world_m=(\S+) bone_world_deg=(\S+) row=(\d+) lane=(\S+)', line)
            world_bones = False
            details = {}
            if extra:
                try:
                    world_values = [float(extra[1]), float(extra[2])]
                except ValueError:
                    malformed += 1
                    continue
                if not all(math.isfinite(v) and v >= 0 for v in world_values):
                    malformed += 1
                    continue
                world_bones = world_values[0] > .001 or world_values[1] > .1
                details = dict(bone_world_m=world_values[0], bone_world_deg=world_values[1],
                               row=int(extra[3]), lane=extra[4])
            row['drift_rows'].append(dict(
                sample=sample, resource=drift[3], root_m=values[0], root_deg=values[1],
                bone_local_m=values[2], bone_local_deg=values[3],
                motion='root_and_bones' if root and bones else 'root' if root else
                'bones' if bones else 'bone_world_only' if world_bones else
                'below_threshold_after_log_rounding', **details))
        elif 'Freeze drift:' in line:
            malformed += 1
    rows = list(episodes.values())
    for row in rows:
        row['motion_observed'] = bool(row['drift_rows'])
        row['coverage_limited'] = (row['state'] != 'complete' or row.get('truncated', False)
                                   or row.get('read_errors', 0) > 0 or row.get('sampled_units', 0) == 0)
    return dict(armed_marker_seen=armed, disabled_reason=disabled, malformed_events=malformed,
                completed_episodes=sum(row['state'] == 'complete' for row in rows), episodes=rows,
                limits=['Only the bounded sampled units and nodes are observed.',
                        'No drift rows does not prove all ragdolls were stationary.',
                        'Resources identify assets; rows cannot establish distinct body counts.',
                        'Observed transform drift does not establish its engine cause.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = analyze(args.log.read_text(encoding='utf-8', errors='replace'))
    encoded = json.dumps(result, indent=2) + '\n'
    if args.output:
        args.output.write_text(encoded, encoding='utf-8')
    print(encoded, end='')
    return 0 if result['completed_episodes'] else 2


if __name__ == '__main__':
    raise SystemExit(main())

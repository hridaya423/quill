#!/usr/bin/env python3
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(os.path.expanduser("~/Library/Application Support/Quill"))


def lines(name):
    path = root / name
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


days = defaultdict(lambda: defaultdict(int))
for turn in lines("turns.jsonl"):
    day = turn["at"][:10]
    days[day]["turns"] += 1
    days[day]["held"] += len(turn.get("held", []))
    for e in turn.get("exchanges", []):
        days[day]["edits"] += 1
        days[day][e["outcome"]] += 1
for event in lines("events.jsonl"):
    days[event["at"][:10]][event["event"]] += 1

if not days:
    sys.exit(f"No ledger at {root} yet.")
print(f"{'day':<12}{'turns':>6}{'edits':>6}{'kept':>7}{'undone':>8}{'rewrote':>9}{'held':>6}  first edit")
for day in sorted(days):
    d = days[day]
    edits = max(d["edits"], 1)
    rejected = d["undone"] + d["reverted"]
    first = next((e.get("detail") for e in lines("events.jsonl") if e["event"] == "first-edit" and e["at"].startswith(day)), "")
    print(f"{day:<12}{d['turns']:>6}{d['edits']:>6}{d['kept'] / edits:>7.0%}{rejected / edits:>8.0%}{d['rewritten'] / edits:>9.0%}{d['held']:>6}  {first + ' s' if first else ''}")

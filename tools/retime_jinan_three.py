#!/usr/bin/env python3
import json
from datetime import datetime, timedelta, timezone
import sys

TZ = timezone(timedelta(hours=8))

def iso(dt):
    return dt.strftime('%Y-%m-%dT%H:%M:%S+08:00')

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'img/events_mock_mannual.json'
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    # 找到前三个济南事件
    jinan_indices = [i for i, ev in enumerate(data) if ev.get('city') == '济南市'][:3]
    if not jinan_indices:
        print('No Jinan events found')
        return

    bases = [
        datetime(2025, 6, 1, 7, 30, tzinfo=TZ),
        datetime(2025, 6, 7, 7, 30, tzinfo=TZ),
        datetime(2025, 6, 13, 8, 0, tzinfo=TZ),
    ]
    for idx, ev_idx in enumerate(jinan_indices):
        base = bases[idx] if idx < len(bases) else bases[-1] + timedelta(days=6 * (idx - 2))
        step = timedelta(minutes=45)
        ev = data[ev_idx]
        for j, im in enumerate(ev.get('images', [])):
            ex = im.setdefault('exifInfo', {})
            ex['timestamp'] = iso(base + step * j)
        ts = [im['exifInfo']['timestamp'] for im in ev.get('images', []) if im.get('exifInfo', {}).get('timestamp')]
        if ts:
            ev['startTime'] = min(ts)
            ev['endTime'] = max(ts)

    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f'Retimed first {len(jinan_indices)} Jinan events in {path}')

if __name__ == '__main__':
    main()

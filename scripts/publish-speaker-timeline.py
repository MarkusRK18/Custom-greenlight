#!/usr/bin/env python3
"""Publish names and timed speaking events alongside BBB recording media."""
from pathlib import Path
import json
import xml.etree.ElementTree as ET

RAW = Path('/var/bigbluebutton/recording/raw')
PUBLISHED = Path('/var/bigbluebutton/published')


def event_time(event):
    try:
        return int(event.findtext('timestampUTC'))
    except (TypeError, ValueError):
        return None


def recording_intervals(events, end_time):
    intervals = []
    started = None
    for event in events:
        if event.get('eventname') != 'RecordStatusEvent':
            continue
        when = event_time(event)
        if when is None:
            continue
        if event.findtext('status') == 'true':
            if started is None:
                started = when
        elif started is not None and when > started:
            intervals.append((started, when))
            started = None
    if started is not None and end_time > started:
        intervals.append((started, end_time))
    return intervals


def timeline(raw_dir, published_dir):
    events = sorted(ET.parse(raw_dir / 'events.xml').iter('event'), key=lambda event: event_time(event) or 0)
    metadata = ET.parse(published_dir / 'metadata.xml').getroot()
    end_time = int(metadata.findtext('end_time'))
    intervals = recording_intervals(events, end_time)
    names = {}
    for event in events:
        if event.get('eventname') == 'ParticipantJoinEvent':
            user_id, name = event.findtext('userId'), event.findtext('name')
        elif event.get('eventname') == 'ParticipantJoinedEvent':
            user_id, name = event.findtext('participant'), event.findtext('callername')
        else:
            continue
        if user_id and name:
            names[user_id] = name[:120]

    active = {}
    talking = []
    for event in events:
        kind = event.get('eventname')
        if kind not in ('ParticipantTalkingEvent', 'ParticipantJoinedEvent', 'ParticipantLeftEvent', 'ParticipantMutedEvent'):
            continue
        user_id, when = event.findtext('participant'), event_time(event)
        if not user_id or when is None:
            continue
        if kind in ('ParticipantTalkingEvent', 'ParticipantJoinedEvent') and event.findtext('talking') == 'true':
            active.setdefault(user_id, when)
        elif user_id in active and (kind == 'ParticipantLeftEvent' or
                                    (kind == 'ParticipantMutedEvent' and event.findtext('muted') == 'true') or
                                    (kind == 'ParticipantTalkingEvent' and event.findtext('talking') == 'false')):
            talking.append((user_id, active.pop(user_id), when))
    talking.extend((user_id, start, end_time) for user_id, start in active.items())

    speakers = []
    elapsed = 0
    for begin, end in intervals:
        for user_id, talk_begin, talk_end in talking:
            clipped_begin, clipped_end = max(begin, talk_begin), min(end, talk_end)
            if clipped_end <= clipped_begin or user_id not in names:
                continue
            speakers.append({'participant_id': user_id, 'name': names[user_id], 'start': round((elapsed + clipped_begin - begin) / 1000, 2),
                             'end': round((elapsed + clipped_end - begin) / 1000, 2)})
        elapsed += end - begin
    speakers.sort(key=lambda item: item['start'])
    slides = published_dir / 'slides_new.xml'
    has_slides = slides.is_file() and len(ET.parse(slides).getroot()) > 0
    def has_files(folder):
        return any(path.is_file() and path.stat().st_size > 0 for path in (raw_dir / folder).rglob('*'))

    media = {
        'audio': has_files('audio'),
        'camera': has_files('video'),
        'screen': has_files('deskshare'),
        'slides': has_slides,
    }
    return {'participants': list(dict.fromkeys(names.values())),
            'participant_details': [{'id': user_id, 'name': name} for user_id, name in names.items()],
            'speakers': speakers, 'media': media}


def main():
    count = 0
    for published_dir in PUBLISHED.glob('presentation/*'):
        raw_dir = RAW / published_dir.name
        if not (raw_dir / 'events.xml').is_file() or not (published_dir / 'metadata.xml').is_file():
            continue
        try:
            data = timeline(raw_dir, published_dir)
        except (ET.ParseError, OSError, ValueError):
            continue
        serialized = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode()
        for format_name in ('presentation', 'video'):
            destination = PUBLISHED / format_name / published_dir.name / 'speakers.json'
            if not destination.parent.is_dir() or (destination.is_file() and destination.read_bytes() == serialized):
                continue
            destination.write_bytes(serialized)
            count += 1
    print(f'Published SIETConnect speaker data for {count} recording formats.')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Read the master tempo of an Ableton Live set (.als, gzip XML), read-only.

Returns the master/main track Tempo `Manual Value`, the time signature, and whether the
tempo is automated with more than one distinct value (such projects are skipped).
"""
import gzip
import re
import sys

TRACK_RE = re.compile(r"<(MainTrack|MasterTrack)[ >](.*?)</\1>", re.S)
TEMPO_RE = re.compile(r"<Tempo>\s*<LomId[^>]*/>\s*<Manual Value=\"([0-9.eE+-]+)\"\s*/>.*?<AutomationTarget Id=\"(\d+)\"", re.S)
SIG_RE = re.compile(r"<TimeSignature>.*?<Manual Value=\"(\d+)\"", re.S)


def read_als(path):
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    track = TRACK_RE.search(text)
    if not track:
        return {"error": "no master track"}
    body = track.group(2)
    tempo = TEMPO_RE.search(body)
    if not tempo:
        return {"error": "no tempo"}
    value, target = float(tempo.group(1)), tempo.group(2)
    values = set()
    for env in re.finditer(r"<AutomationEnvelope Id=\"\d+\">(.*?)</AutomationEnvelope>", body, re.S):
        if re.search(r"<PointeeId Value=\"%s\"\s*/>" % target, env.group(1)):
            values.update(float(v) for v in re.findall(r"<FloatEvent [^>]*Value=\"([0-9.eE+-]+)\"", env.group(1)))
    sig = SIG_RE.search(body)
    # Live encodes the signature as an index: numerator - 1 + 99 * log2(denominator).
    signature = None
    if sig:
        code = int(sig.group(1))
        signature = "%d/%d" % (code % 99 + 1, 2 ** (code // 99))
    major = re.search(r"Creator=\"([^\"]+)\"", text[:500])
    return {"tempo": value, "automatedValues": sorted(values), "tempoChanges": len({round(v, 3) for v in values} | {round(value, 3)}) > 1 if values else False,
            "signature": signature, "creator": major.group(1) if major else None}


if __name__ == "__main__":
    for p in sys.argv[1:]:
        print(p, read_als(p))

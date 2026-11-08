#!/usr/bin/env python3
"""Pair Ableton session tempos with audio rendered at that tempo (read-only).

Usage: KF_TEMPO_ROOTS=roots.json build_truth.py OUT_DIR

roots.json names the producer's own folders and stays outside the repository:
{"projects": DIR, "crash": [DIR, ...], "sets": [DIR, ...], "mixes": [DIR, ...]}
- projects: the Ableton Projects folder (one set per "* Project" folder);
- crash: Live's crash-recovery folders (older sets); sets: other folders holding sets;
- mixes: folders of finished mixes (catalog, exports, cloud-drive mirrors).

Truth is the master tempo `Manual Value` of a live set (see als_tempo.py). Copies of one
song are merged by normalized title; songs whose sets disagree on tempo, or that automate
tempo, are skipped.

Audio, all opened read-only and never copied:

- bounces inside the project (`Samples/Processed/Bounce`, `Samples/Processed/Freeze`);
- mixes whose file title equals the song title, in the mix folders. Stems and
  vocal-only files are excluded.

Filenames only pair audio and exclude conflicts (a tempo number in the name that is not
the set tempo, double or half; a mix older than the project folder). They are never truth. One file is chosen per song (a mixdown
inside the song's own project folder, then an in-project bounce, because their provenance
is certain; then wav before mp3, then
longest), so duplicates do not weigh twice.
Writes candidates.json (everything considered) and truth.json.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from als_tempo import read_als  # noqa: E402

def _roots() -> dict:
    """Folder roots from the JSON file named by KF_TEMPO_ROOTS (empty when unset)."""
    path = os.environ.get("KF_TEMPO_ROOTS")
    config = json.loads(Path(path).read_text()) if path else {}
    return {"projects": Path(config.get("projects", "/nonexistent")),
            **{key: [Path(p).expanduser() for p in config.get(key, [])] for key in ("crash", "sets", "mixes")}}


ROOTS = _roots()
PROJECTS = ROOTS["projects"]
CRASH_ROOTS = ROOTS["crash"]
SET_ROOTS = ROOTS["sets"]
MIX_ROOTS = ROOTS["mixes"]
AUDIO_EXT = {".wav", ".aif", ".aiff", ".mp3", ".flac", ".m4a"}
STEM_WORDS = re.compile(r"\b(vocals?|vox|acapella|acap|ad ?libs?|bass|drums|others?|guitar|stems?|"
                        r"kick|snare|hats?|perc|808s?|melody|chords?|group|audio)\b|\s\d{1,2}-\S", re.I)
# Titles too generic to pair with audio outside the project folder.
GENERIC_TITLES = {"", "untitled", "track", "set", "song", "beat", "audio", "mix", "d", "pk", "master",
                  "defaultliveset", "maintemp", "makingabletontooeasytemplate"}
SUFFIXES = ("remix", "beat", "song", "mix", "flip", "idea", "loop")
KEY_TOKEN = re.compile(r"^[a-g](#|b)?(m|min|maj|major|minor)?$", re.I)
MIN_SECONDS = 15.0
MIN_TITLE = 5


def title_of(name: str) -> str:
    """Normalized song title: no brackets, dates, tempo digits or trailing key token."""
    text = name.lower()
    text = re.sub(r"\[[^\]]*\]|\([^)]*\)", " ", text)
    text = re.sub(r"\bproject\b|\bprod\.?\s*ifeelvoid\b|\bbpm\b|\bmaster(ed)?\b|\bmixdown\b", " ", text)
    text = re.sub(r"\d+", " ", text)
    words = re.sub(r"[^a-z#]+", " ", text).split()
    while words and KEY_TOKEN.match(words[-1]):
        words.pop()
    return "".join(words)


def aliases(title: str) -> set:
    """The title plus the title without one generic suffix ("citymix" -> "city")."""
    out = {title}
    for suffix in SUFFIXES:
        if title.endswith(suffix) and len(title) - len(suffix) >= 4:
            out.add(title[: -len(suffix)])
    return out - GENERIC_TITLES


def label_bpm(path: Path):
    """First plausible tempo number in the folder or file name (pairing check only)."""
    stem = re.sub(r"\[[^\]]*\]", " ", path.stem)
    stem = re.sub(r"\b\d{4}-\d{2}-\d{2}\b", " ", stem)
    for m in re.finditer(r"(?<![\d-])(\d{2,3})(?![\d-])", path.parent.name + " " + stem):
        value = int(m.group(1))
        if 55 <= value <= 200:
            return value
    return None


def consistent(label: int, tempo: float) -> bool:
    return any(abs(label - tempo * r) <= 0.01 * tempo * r for r in (1, 2, 0.5))


def audio_files(root: Path):
    for dirpath, _, files in os.walk(root):
        for f in files:
            p = Path(dirpath) / f
            if not f.startswith("._") and p.suffix.lower() in AUDIO_EXT and "Backup" not in p.parts:
                yield p


def duration(path: Path) -> float:
    try:
        out = subprocess.run(["afinfo", str(path)], capture_output=True, text=True, timeout=60).stdout
        m = re.search(r"estimated duration: ([0-9.]+)", out)
        return float(m.group(1)) if m else 0.0
    except (subprocess.SubprocessError, OSError):
        return 0.0


def live_sets():
    """Yield (source, als path, song-group key, local project dir or None)."""
    for als in sorted(PROJECTS.rglob("*.als")):
        if not als.name.startswith("._") and "Backup" not in als.parts:
            yield "projects", als, "project:" + str(als.parent), als.parent
    for root in CRASH_ROOTS + SET_ROOTS:
        for als in sorted(root.rglob("*.als")) if root.exists() else []:
            if not als.name.startswith("._") and "Backup" not in als.parts:
                local = als.parent if als.parent.name.endswith("Project") else None
                yield ("crash" if root in CRASH_ROOTS else "protondrive"), als, None, local


def collect_songs(skipped: list) -> list:
    songs = {}
    for source, als, group, local in live_sets():
        info = read_als(als)
        if "tempo" not in info:
            skipped.append({"set": str(als), "reason": info.get("error", "unreadable")})
            continue
        titles = aliases(title_of(als.stem)) | (aliases(title_of(local.name)) if local else set())
        key = group or ("title:" + (sorted(titles)[0] if titles else str(als)))
        song = songs.setdefault(key, {"sets": [], "titles": set(), "local": set(), "sources": set()})
        song["sets"].append({"path": str(als), "tempo": info["tempo"], "changes": info["tempoChanges"]})
        song["titles"] |= titles
        song["sources"].add(source)
        if local:
            song["local"].add(local)
    # Merge songs that share a title (crash copy of a project, cloud-drive copy, ...).
    merged = []
    for song in songs.values():
        target = next((m for m in merged if m["titles"] & song["titles"]), None)
        if target:
            for field in ("sets",):
                target[field] += song[field]
            for field in ("titles", "local", "sources"):
                target[field] |= song[field]
        else:
            merged.append(song)
    return merged


def main(out_dir: str) -> None:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    mixes = []
    for root in MIX_ROOTS:
        for p in audio_files(root):
            if STEM_WORDS.search(p.stem) or any(s.lower() in ("stems", "stem") for s in p.parts):
                continue
            # The file's own title must match: a folder match alone also pairs samples
            # and imported loops that sit in a project folder.
            mixes.append((p, {title_of(p.stem)} - GENERIC_TITLES, p.stem.strip().lower()))
    skipped, candidates, truth = [], [], []
    for song in collect_songs(skipped):
        name = sorted(song["titles"])[0] if song["titles"] else song["sets"][0]["path"]
        tempos = {round(s["tempo"], 3) for s in song["sets"]}
        if any(s["changes"] for s in song["sets"]) or len(tempos) != 1:
            skipped.append({"song": name, "reason": "tempo automation" if any(s["changes"] for s in song["sets"])
                            else "sets disagree on tempo %s" % sorted(tempos), "sets": [s["path"] for s in song["sets"]]})
            continue
        tempo = tempos.pop()
        found = [(p, "bounce") for local in song["local"] for sub in ("Samples/Processed/Bounce", "Samples/Processed/Freeze")
                 for p in audio_files(local / sub)]
        stems = {Path(s["path"]).stem.strip().lower() for s in song["sets"]}
        stems |= {d.name[: -len(" Project")].strip().lower() for d in song["local"] if d.name.endswith(" Project")}
        # Short titles ("abc", "4X4X4" -> "xx") need the exact set or project name.
        found += [(p, "mix") for p, titles, stem in mixes
                  if (titles & song["titles"] and min(len(t) for t in titles & song["titles"]) >= MIN_TITLE)
                  or (stem in stems and (title_of(stem) not in GENERIC_TITLES
                                         or any(local in p.parents for local in song["local"])))]
        # A mix last modified well before the project folder existed is another song
        # with the same name (for example an older catalog beat with the same name).
        born = [d.stat().st_birthtime for d in song["local"] if PROJECTS in d.parents]
        earliest = min(born) - 2 * 86400 if born else None
        rows = []
        for p, kind in dict.fromkeys(found):
            label = label_bpm(p) if kind == "mix" else None
            seconds = duration(p)
            reason = None
            if label is not None and not consistent(label, tempo):
                reason = "filename tempo %d conflicts with set" % label
            elif kind == "mix" and earliest is not None and p.stat().st_mtime < earliest:
                reason = "mix predates the project folder"
            elif seconds < MIN_SECONDS:
                reason = "shorter than %.0f s" % MIN_SECONDS
            rows.append({"song": name, "tempo": tempo, "path": str(p), "kind": kind, "filenameBPM": label,
                         "seconds": round(seconds, 1), "usable": reason is None, "reason": reason})
        candidates += rows
        def provenance(row):
            # 0: mixdown saved in the song's own project folder, 1: in-project bounce, 2: elsewhere.
            inside = any(local in Path(row["path"]).parents for local in song["local"])
            return 0 if row["kind"] == "mix" and inside else 1 if row["kind"] == "bounce" else 2
        usable = sorted((r for r in rows if r["usable"]),
                        key=lambda r: (provenance(r), Path(r["path"]).suffix.lower() != ".wav", -r["seconds"], r["path"]))
        if not usable:
            skipped.append({"song": name, "reason": "no paired audio" if not rows else "no usable audio"})
            continue
        chosen = usable[0]
        truth.append({"id": hashlib.sha256(chosen["path"].encode()).hexdigest()[:16], "family": name,
                      "tempo": tempo, "path": chosen["path"], "kind": chosen["kind"], "seconds": chosen["seconds"],
                      "sources": sorted(song["sources"]), "sets": sorted(s["path"] for s in song["sets"]),
                      "alternatives": len(usable) - 1})
    truth.sort(key=lambda t: t["family"])
    (out / "candidates.json").write_text(json.dumps({"candidates": candidates, "skipped": skipped}, indent=1))
    (out / "truth.json").write_text(json.dumps(truth, indent=1))
    print("songs paired %d, skipped %d, candidate files %d" % (len(truth), len(skipped), len(candidates)))


if __name__ == "__main__":
    main(sys.argv[1])

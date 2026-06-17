#!/usr/bin/env python3
"""
Convert Quill .qm meeting files to readable markdown raws (vault schema).

Reads .qm files (QMv2 format) from raw/meetings/, extracts:
  - Meeting metadata (title, dates, participants, language, tags)
  - Speakers mapping (Quill stores real names in the .qm directly when known)
  - Quill-generated Notes (Minutes, 1:1 Summary, Follow-ups with blurb)
  - Raw transcript with speaker names substituted

Writes a .md file next to the .qm, following the vault raw schema:
  - Frontmatter (type, source, source_id, date, captured_at, title, channel,
    stable, ingested, ingested_in, qm_file, quill_tags, participants, language)
  - Brief = Quill's blurb (auto-extracted from followupsV3 note)
  - Body sections: Minutes, Summary 1:1, Follow-ups, raw Transcript

Speakers Quill doesn't recognize stay as SPK-<id> in the transcript — manual
find/replace in VSCode if needed.

Usage:
    python3 <vault>/tools/qm-to-md.py [path_or_dir] [--force]

If no path → processes all .qm in raw/meetings/ that don't have a matching .md.
--force → regenerate even if .md exists.
"""

import json
import sys
import re
from pathlib import Path
from datetime import datetime

VAULT = Path.home() / "Documents" / "your-vault"
MEETINGS_DIR = VAULT / "raw" / "meetings"


def parse_qm(qm_file: Path) -> list:
    """Parse the QMv2 file, return the top-level list of blocks."""
    content = qm_file.read_text()
    json_start = content.index("[")
    return json.loads(content[json_start:])


def get_meeting(data: list) -> dict:
    """Return the Meeting block data."""
    for item in data:
        if item.get("type") == "Meeting":
            return item["data"]
    raise ValueError("No Meeting block in .qm file")


def get_note(data: list, title: str = None, kind: str = None) -> dict | None:
    """Return the first Note block matching title or kind, or None."""
    for item in data:
        if item.get("type") != "Note":
            continue
            d = item["data"]
        d = item["data"]
        if title and d.get("title") == title:
            return d
        if kind and d.get("kind") == kind:
            return d
    return None


def build_speaker_map(meeting: dict) -> dict[str, str]:
    """Build {SPK-id: name} mapping from the .qm's speakers array."""
    mapping = {}
    for s in meeting.get("speakers", []):
        spk_id = s.get("id")
        name = s.get("name")
        if spk_id and name:
            mapping[spk_id] = name
        # Speakers without 'name' stay unmapped → SPK-id used as fallback
    return mapping


def format_transcript(meeting: dict, speaker_map: dict[str, str]) -> str:
    """Format the audio_transcript with speaker names substituted."""
    audio_str = meeting.get("audio_transcript", "{}")
    audio = json.loads(audio_str)
    blocks = audio.get("blocks", [])

    lines = []
    current_speaker = None
    current_text = []
    for b in blocks:
        spk_id = b.get("speaker_id", "Unknown")
        speaker = speaker_map.get(spk_id, spk_id)
        text = b.get("text", "").strip()
        if not text:
            continue
        if speaker != current_speaker:
            if current_text:
                lines.append(f"**{current_speaker}**: {' '.join(current_text)}")
                lines.append("")
            current_speaker = speaker
            current_text = [text]
        else:
            current_text.append(text)
    if current_text:
        lines.append(f"**{current_speaker}**: {' '.join(current_text)}")
    return "\n".join(lines)


def extract_brief(data: list) -> str:
    """Extract the blurb from followupsV3 note to use as Brief."""
    note = get_note(data, kind="followupsV3")
    if not note:
        return ""
    body = note.get("body", "")
    try:
        parsed = json.loads(body)
        blurb = parsed.get("blurb", "").strip()
        return blurb
    except (json.JSONDecodeError, AttributeError):
        return ""


def extract_followups_body(data: list) -> str:
    """Format followupsV3 note as readable markdown (blurb + action items)."""
    note = get_note(data, kind="followupsV3")
    if not note:
        return "_No follow-ups note found._"
    body = note.get("body", "")
    try:
        parsed = json.loads(body)
        out = []
        if blurb := parsed.get("blurb"):
            out.append(blurb.strip())
            out.append("")
        # followupsV3 may contain various fields; dump the rest as-is
        for k, v in parsed.items():
            if k == "blurb":
                continue
            if isinstance(v, list) and v:
                out.append(f"**{k}**:")
                for item in v:
                    out.append(f"- {item}")
                out.append("")
            elif isinstance(v, str) and v.strip():
                out.append(f"**{k}**: {v}")
                out.append("")
        return "\n".join(out).strip()
    except (json.JSONDecodeError, AttributeError):
        return body.strip()


def format_frontmatter(fm: dict) -> str:
    """Render a YAML frontmatter from a dict."""
    lines = ["---"]
    for k, v in fm.items():
        if v is None or v == "":
            continue
        if isinstance(v, list):
            if not v:
                lines.append(f"{k}: []")
            else:
                items = ", ".join(json.dumps(x, ensure_ascii=False) for x in v)
                lines.append(f"{k}: [{items}]")
        elif isinstance(v, bool):
            lines.append(f"{k}: {str(v).lower()}")
        elif isinstance(v, str) and (":" in v or v.startswith(("#", "[", "*"))):
            lines.append(f'{k}: "{v}"')
        else:
            lines.append(f"{k}: {v}")
    lines.append("---")
    return "\n".join(lines)


def convert(qm_file: Path) -> Path:
    """Convert a .qm to .md (raw schema). Returns the output path."""
    data = parse_qm(qm_file)
    meeting = get_meeting(data)
    speaker_map = build_speaker_map(meeting)

    # Frontmatter
    title = meeting.get("title", qm_file.stem)
    start = meeting.get("start", "")
    end = meeting.get("end", "")
    date = start[:10] if start else ""
    tags_str = meeting.get("tags", "")
    tags = [t.strip() for t in tags_str.split(",") if t.strip()]
    participants = [
        s.get("name", s["id"]) for s in meeting.get("speakers", []) if s.get("name")
    ]
    qm_relative = qm_file.relative_to(VAULT) if qm_file.is_relative_to(VAULT) else qm_file

    fm = {
        "type": "raw",
        "source": "quill",
        "source_id": meeting.get("id", ""),
        "date": date,
        "captured_at": end,
        "title": title,
        "channel": "Quill",
        "stable": False,
        "ingested": False,
        "ingested_in": [],
        "qm_file": str(qm_relative),
        "quill_tags": tags,
        "participants": participants,
        "language": meeting.get("language_code", ""),
    }

    # Body sections
    brief = extract_brief(data) or "(à remplir)"
    minutes_note = get_note(data, title="Minutes")
    summary_note = get_note(data, title="Employee 1:1 Summary")

    minutes_body = minutes_note.get("body", "_No Minutes note found._").strip() if minutes_note else "_No Minutes note found._"
    summary_body = summary_note.get("body", "_No 1:1 Summary note found._").strip() if summary_note else "_No 1:1 Summary note found._"
    followups_body = extract_followups_body(data)
    transcript = format_transcript(meeting, speaker_map)

    body = f"""Brief: {brief}

## Quill — Minutes

{minutes_body}

## Quill — Summary 1:1

{summary_body}

## Quill — Follow-ups

{followups_body}

## Transcript brut (reference)

{transcript}
"""

    md_content = format_frontmatter(fm) + "\n\n" + body
    output_path = qm_file.with_suffix(".md")
    output_path.write_text(md_content)
    return output_path


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv

    if args:
        arg = Path(args[0]).expanduser().resolve()
        if arg.is_file() and arg.suffix == ".qm":
            qm_files = [arg]
        elif arg.is_dir():
            qm_files = sorted(arg.glob("*.qm"))
        else:
            print(f"❌ {arg} is not a .qm file or directory")
            sys.exit(1)
    else:
        qm_files = sorted(MEETINGS_DIR.glob("*.qm"))

    if not force:
        qm_files = [f for f in qm_files if not f.with_suffix(".md").exists()]

    if not qm_files:
        print("Nothing to do (use --force to regenerate existing .md).")
        return

    for qm in qm_files:
        try:
            md = convert(qm)
            print(f"✅ {qm.name} → {md.name}")
        except Exception as e:
            print(f"❌ {qm.name}: {e}")


if __name__ == "__main__":
    main()

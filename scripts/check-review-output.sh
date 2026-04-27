#!/usr/bin/env bash
set -euo pipefail

STRICT=false

usage() {
  echo "usage: $0 [--strict] <review-file>" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=true
      shift
      ;;
    -*)
      usage
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -eq 1 ]] || usage
REVIEW_FILE="$1"
[[ -f "$REVIEW_FILE" ]] || {
  echo "pr-reviewer: review file not found: $REVIEW_FILE" >&2
  exit 2
}

python3 - "$REVIEW_FILE" "$STRICT" <<'PY'
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

review_path = Path(sys.argv[1])
strict = sys.argv[2].lower() == "true"
text = review_path.read_text(encoding="utf-8")
lines = text.splitlines()

required_sections = ["Summary", "Issues", "Suggestions", "Questions"]
missing_sections = [
    section for section in required_sections if f"## {section}" not in text
]
allowed_tags = ["BLOCKING", "HIGH", "MEDIUM", "LOW"]
severity_counts = {tag: 0 for tag in allowed_tags}
invalid_severity_tags: list[str] = []
issue_tag_pattern = re.compile(r"^\[(?P<tag>[A-Z_]+)\]")

for line in lines:
    match = issue_tag_pattern.match(line.strip())
    if not match:
        continue
    tag = match.group("tag")
    if tag in severity_counts:
        severity_counts[tag] += 1
    else:
        invalid_severity_tags.append(tag)

blocking_count = severity_counts["BLOCKING"]

payload = {
    "review_path": str(review_path),
    "blocking_count": blocking_count,
    "severity_counts": severity_counts,
    "has_required_sections": not missing_sections,
    "missing_sections": missing_sections,
    "invalid_severity_tags": invalid_severity_tags,
}

print(json.dumps(payload, indent=2))

if strict and (missing_sections or invalid_severity_tags):
    raise SystemExit(1)
PY

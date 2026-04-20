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
blocking_count = sum(1 for line in lines if line.startswith("[BLOCKING]"))

payload = {
    "review_path": str(review_path),
    "blocking_count": blocking_count,
    "has_required_sections": not missing_sections,
    "missing_sections": missing_sections,
}

print(json.dumps(payload, indent=2))

if strict and missing_sections:
    raise SystemExit(1)
PY

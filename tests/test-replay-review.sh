#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

"$REPO_ROOT/scripts/replay-review.sh" \
  --diff "$SCRIPT_DIR/fixtures/sample.diff" \
  --output-dir "$TMP_DIR" \
  --assemble-only

[[ -f "$TMP_DIR/user-prompt.md" ]] || {
  echo "FAIL: missing assembled prompt" >&2
  exit 1
}

grep -q "## Rubric" "$TMP_DIR/user-prompt.md" || {
  echo "FAIL: prompt missing rubric section" >&2
  exit 1
}

grep -q "## PR diff" "$TMP_DIR/user-prompt.md" || {
  echo "FAIL: prompt missing diff section" >&2
  exit 1
}

grep -q "print(add(1, 2))" "$TMP_DIR/user-prompt.md" || {
  echo "FAIL: prompt missing diff body" >&2
  exit 1
}

echo "PASS: replay review assembly"

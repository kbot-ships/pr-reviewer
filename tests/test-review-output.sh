#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GOOD_FIXTURE="$SCRIPT_DIR/fixtures/review-with-blocking.md"
BAD_FIXTURE="$SCRIPT_DIR/fixtures/review-missing-sections.md"
INVALID_TAG_FIXTURE="$SCRIPT_DIR/fixtures/review-invalid-severity.md"

GOOD_JSON="$("$REPO_ROOT/scripts/check-review-output.sh" "$GOOD_FIXTURE")"
echo "$GOOD_JSON" | grep -q '"blocking_count": 1' || {
  echo "FAIL: expected blocking_count=1" >&2
  exit 1
}
echo "$GOOD_JSON" | grep -q '"HIGH": 1' || {
  echo "FAIL: expected severity_counts.HIGH=1" >&2
  exit 1
}
echo "$GOOD_JSON" | grep -q '"has_required_sections": true' || {
  echo "FAIL: expected has_required_sections=true" >&2
  exit 1
}

if "$REPO_ROOT/scripts/check-review-output.sh" --strict "$BAD_FIXTURE" >/dev/null 2>&1; then
  echo "FAIL: strict validation should fail on missing sections" >&2
  exit 1
fi

if "$REPO_ROOT/scripts/check-review-output.sh" --strict "$INVALID_TAG_FIXTURE" >/dev/null 2>&1; then
  echo "FAIL: strict validation should fail on invalid severity tags" >&2
  exit 1
fi

echo "PASS: review output contract"

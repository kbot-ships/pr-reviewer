#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "pr" && "${2:-}" == "diff" ]]; then
  cat <<'DIFF'
diff --git a/example.py b/example.py
index 1111111..2222222 100644
--- a/example.py
+++ b/example.py
@@ -1 +1 @@
-print("old")
+print("new")
DIFF
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
SH
chmod +x "$TMP_DIR/bin/gh"

cat > "$TMP_DIR/bin/claude" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "Credit balance is too low" >&2
exit 1
SH
chmod +x "$TMP_DIR/bin/claude"

OUTPUT_FILE="$TMP_DIR/github-output.txt"

(
  export PATH="$TMP_DIR/bin:$PATH"
  export RUBRIC_PATH="$REPO_ROOT/.github/pr-reviewer.yml"
  export MODEL="claude-sonnet-4-6"
  export MAX_DIFF_BYTES="200000"
  export GH_TOKEN="test-token"
  export PR_NUMBER="4"
  export REPO="kbot-ships/pr-reviewer"
  export GITHUB_OUTPUT="$OUTPUT_FILE"
  export POST_COMMENT="false"
  export STICKY_UPDATE="true"
  export SUBMISSION_MODE="comment"
  export REVIEW_EVENT="auto"
  export FAIL_ON_BLOCKING="false"
  export MAX_RETRIES="0"
  export REVIEW_TIMEOUT_SECONDS="5"
  cd "$REPO_ROOT"
  bash "$REPO_ROOT/scripts/run-review.sh"
)

grep -q '^review-path=$' "$OUTPUT_FILE" || {
  echo "FAIL: expected skipped review-path output" >&2
  exit 1
}

grep -q '^blocking-count=0$' "$OUTPUT_FILE" || {
  echo "FAIL: expected zero blocking count" >&2
  exit 1
}

grep -q '^engine-used=skipped$' "$OUTPUT_FILE" || {
  echo "FAIL: expected engine-used=skipped" >&2
  exit 1
}

echo "PASS: run-review skips cleanly when Claude credits are exhausted"

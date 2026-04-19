#!/usr/bin/env bash
# Run a Claude-powered review against the current PR.
#
# Expects the following environment variables:
#   ANTHROPIC_API_KEY  -- Claude API key
#   RUBRIC_PATH        -- path to the rubric YAML
#   MODEL              -- Claude model ID
#   MAX_DIFF_BYTES     -- skip review if diff exceeds this size
#   POST_COMMENT       -- "true" to post review as PR comment
#   FAIL_ON_BLOCKING   -- "true" to exit non-zero on blocking issues
#   GH_TOKEN           -- GitHub token (for gh CLI)
#   PR_NUMBER          -- PR number
#   REPO               -- owner/repo

set -euo pipefail

COMMENT_MARKER="<!-- pr-reviewer -->"

require_var() {
  if [ -z "${!1:-}" ]; then
    echo "pr-reviewer: missing required env var: $1" >&2
    exit 2
  fi
}

for v in ANTHROPIC_API_KEY RUBRIC_PATH MODEL MAX_DIFF_BYTES GH_TOKEN PR_NUMBER REPO; do
  require_var "$v"
done

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR=".reviewer-output"
mkdir -p "$OUTPUT_DIR"

# 1. Resolve the rubric: per-repo if present, otherwise the built-in default.
if [ -f "$RUBRIC_PATH" ]; then
  RUBRIC_FILE="$RUBRIC_PATH"
  echo "pr-reviewer: using repo rubric at $RUBRIC_PATH"
else
  RUBRIC_FILE="$ACTION_DIR/prompts/rubric-default.yml"
  echo "pr-reviewer: no rubric at $RUBRIC_PATH, falling back to default"
fi

# 2. Pull the PR diff.
DIFF_FILE="$OUTPUT_DIR/pr.diff"
gh pr diff "$PR_NUMBER" --repo "$REPO" > "$DIFF_FILE"

DIFF_SIZE=$(wc -c < "$DIFF_FILE" | tr -d ' ')
if [ "$DIFF_SIZE" -gt "$MAX_DIFF_BYTES" ]; then
  echo "pr-reviewer: diff is $DIFF_SIZE bytes, exceeds max of $MAX_DIFF_BYTES"
  echo "pr-reviewer: skipping review. Increase max-diff-bytes if you want coverage on large PRs."
  echo "review-path=" >> "$GITHUB_OUTPUT"
  echo "blocking-count=0" >> "$GITHUB_OUTPUT"
  exit 0
fi

# 3. Assemble the prompt.
SYSTEM_PROMPT_FILE="$ACTION_DIR/prompts/system.md"
USER_PROMPT_FILE="$OUTPUT_DIR/user-prompt.md"

{
  echo "## Rubric"
  echo ""
  echo '```yaml'
  cat "$RUBRIC_FILE"
  echo '```'
  echo ""
  echo "## PR diff"
  echo ""
  echo '```diff'
  cat "$DIFF_FILE"
  echo '```'
} > "$USER_PROMPT_FILE"

# 4. Run Claude. In non-interactive mode the CLI writes errors to stdout,
#    so if the exit code is non-zero we surface the file contents to the log.
REVIEW_FILE="$OUTPUT_DIR/review.md"
set +e
claude -p --bare \
  --model "$MODEL" \
  --system-prompt "$(cat "$SYSTEM_PROMPT_FILE")" \
  < "$USER_PROMPT_FILE" \
  > "$REVIEW_FILE"
CLAUDE_EXIT=$?
set -e
if [ "$CLAUDE_EXIT" -ne 0 ]; then
  echo "pr-reviewer: claude exited $CLAUDE_EXIT. CLI output below:" >&2
  cat "$REVIEW_FILE" >&2
  exit "$CLAUDE_EXIT"
fi

echo "pr-reviewer: review written to $REVIEW_FILE"

# 5. Count blocking issues. The system prompt instructs Claude to mark
#    blocking issues with a literal "[BLOCKING]" tag. Accept either a
#    standalone line or a normal markdown list item.
BLOCKING_COUNT=$(grep -Ec '^[[:space:]]*(([-*][[:space:]]+)|([0-9]+[.)][[:space:]]+))?\[BLOCKING\]' "$REVIEW_FILE" || true)
echo "pr-reviewer: blocking issues flagged: $BLOCKING_COUNT"

write_comment_payload() {
  local source_file="$1"
  local output_file="$2"
  python - "$source_file" "$output_file" <<'PY'
import json
import pathlib
import sys

body = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
payload_path = pathlib.Path(sys.argv[2])
payload_path.write_text(json.dumps({"body": body}), encoding="utf-8")
PY
}

find_existing_comment_id() {
  local marker="$1"
  gh api "repos/$REPO/issues/$PR_NUMBER/comments?per_page=100" | python - "$marker" <<'PY'
import json
import sys

marker = sys.argv[1]
comments = json.load(sys.stdin)

for comment in comments:
    if comment.get("user", {}).get("login") != "github-actions[bot]":
        continue
    body = comment.get("body") or ""
    if marker in body:
        print(comment["id"])
        break
PY
}

# 6. Optionally post the review as a sticky PR comment.
if [ "${POST_COMMENT:-true}" = "true" ]; then
  COMMENT_FILE="$OUTPUT_DIR/comment.md"
  COMMENT_PAYLOAD_FILE="$OUTPUT_DIR/comment.json"
  {
    echo "$COMMENT_MARKER"
    echo ""
    cat "$REVIEW_FILE"
  } > "$COMMENT_FILE"

  EXISTING_COMMENT_ID="$(find_existing_comment_id "$COMMENT_MARKER")"
  if [ -n "$EXISTING_COMMENT_ID" ]; then
    write_comment_payload "$COMMENT_FILE" "$COMMENT_PAYLOAD_FILE"
    gh api \
      --method PATCH \
      "repos/$REPO/issues/comments/$EXISTING_COMMENT_ID" \
      --input "$COMMENT_PAYLOAD_FILE" \
      >/dev/null
    echo "pr-reviewer: updated existing review comment on PR #$PR_NUMBER"
  else
    gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file "$COMMENT_FILE"
    echo "pr-reviewer: posted new review comment to PR #$PR_NUMBER"
  fi
fi

echo "review-path=$REVIEW_FILE" >> "$GITHUB_OUTPUT"
echo "blocking-count=$BLOCKING_COUNT" >> "$GITHUB_OUTPUT"

if [ "${FAIL_ON_BLOCKING:-false}" = "true" ] && [ "$BLOCKING_COUNT" -gt 0 ]; then
  echo "pr-reviewer: failing job because fail-on-blocking=true and $BLOCKING_COUNT blocking issues were flagged"
  exit 1
fi

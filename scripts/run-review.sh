#!/usr/bin/env bash
# Run a Claude-powered review against the current PR, with optional
# fallback execution and flexible GitHub submission modes.

set -euo pipefail

COMMENT_MARKER="<!-- pr-reviewer -->"
ENGINE_USED=""
LAST_PRIMARY_EXIT=0
LAST_PRIMARY_OUTPUT=""

require_var() {
  if [ -z "${!1:-}" ]; then
    echo "pr-reviewer: missing required env var: $1" >&2
    exit 2
  fi
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

is_true() {
  case "$(lower "${1:-false}")" in
    true|1|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_review_state() {
  case "$(lower "$1")" in
    comment|commented) printf 'COMMENT' ;;
    approve|approved) printf 'APPROVE' ;;
    request_changes|changes_requested) printf 'REQUEST_CHANGES' ;;
    *) printf '%s' "$1" ;;
  esac
}

validate_submission_mode() {
  case "$(lower "${SUBMISSION_MODE:-comment}")" in
    comment|review) ;;
    *)
      echo "pr-reviewer: invalid submission-mode '$SUBMISSION_MODE' (expected comment or review)" >&2
      exit 2
      ;;
  esac
}

validate_review_event() {
  case "$(lower "${REVIEW_EVENT:-auto}")" in
    auto|comment|approve|request_changes) ;;
    *)
      echo "pr-reviewer: invalid review-event '$REVIEW_EVENT' (expected auto, comment, approve, or request_changes)" >&2
      exit 2
      ;;
  esac
}

resolve_review_event() {
  case "$(lower "${REVIEW_EVENT:-auto}")" in
    auto)
      if [ "${BLOCKING_COUNT:-0}" -gt 0 ]; then
        printf 'REQUEST_CHANGES'
      else
        printf 'COMMENT'
      fi
      ;;
    comment) printf 'COMMENT' ;;
    approve) printf 'APPROVE' ;;
    request_changes) printf 'REQUEST_CHANGES' ;;
  esac
}

write_body_payload() {
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

write_review_payload() {
  local source_file="$1"
  local output_file="$2"
  local event="$3"
  python - "$source_file" "$output_file" "$event" <<'PY'
import json
import pathlib
import sys

body = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
event = sys.argv[3]
payload = {"body": body, "event": event}
pathlib.Path(sys.argv[2]).write_text(json.dumps(payload), encoding="utf-8")
PY
}

find_existing_comment_id() {
  local marker="$1"
  gh api "repos/$REPO/issues/$PR_NUMBER/comments?per_page=100" | python - "$marker" <<'PY'
import json
import sys

marker = sys.argv[1]
comments = json.load(sys.stdin)
matches = [
    comment for comment in comments
    if comment.get("user", {}).get("login") == "github-actions[bot]"
    and marker in (comment.get("body") or "")
]
if matches:
    print(matches[-1]["id"])
PY
}

find_existing_review() {
  local marker="$1"
  gh api "repos/$REPO/pulls/$PR_NUMBER/reviews?per_page=100" | python - "$marker" <<'PY'
import json
import sys

marker = sys.argv[1]
reviews = json.load(sys.stdin)
matches = [
    review for review in reviews
    if review.get("user", {}).get("login") == "github-actions[bot]"
    and marker in (review.get("body") or "")
]
if matches:
    latest = matches[-1]
    print(f"{latest['id']}\t{latest.get('state', '')}")
PY
}

supports_timeout() {
  command -v timeout >/dev/null 2>&1
}

is_retryable_claude_failure() {
  local source_file="$1"
  grep -Eiq '(429|529|rate limit|timeout|timed out|temporarily unavailable|overloaded|try again|connection reset|network error|service unavailable)' "$source_file"
}

run_claude_attempt() {
  local attempt="$1"
  local output_file="$OUTPUT_DIR/review-claude-attempt-$attempt.md"
  local exit_code

  set +e
  if supports_timeout; then
    timeout "$REVIEW_TIMEOUT_SECONDS" \
      claude -p --bare \
        --model "$MODEL" \
        --system-prompt "$SYSTEM_PROMPT_CONTENT" \
        < "$USER_PROMPT_FILE" \
        > "$output_file" 2>&1
    exit_code=$?
  else
    claude -p --bare \
      --model "$MODEL" \
      --system-prompt "$SYSTEM_PROMPT_CONTENT" \
      < "$USER_PROMPT_FILE" \
      > "$output_file" 2>&1
    exit_code=$?
  fi
  set -e

  LAST_PRIMARY_EXIT="$exit_code"
  LAST_PRIMARY_OUTPUT="$output_file"

  if [ "$exit_code" -eq 0 ] && [ -s "$output_file" ]; then
    cp "$output_file" "$REVIEW_FILE"
    ENGINE_USED="claude"
    return 0
  fi

  return "$exit_code"
}

run_claude_with_retries() {
  local max_attempts=$((MAX_RETRIES + 1))
  local attempt=1
  local delay="$RETRY_DELAY_SECONDS"

  while [ "$attempt" -le "$max_attempts" ]; do
    echo "pr-reviewer: running Claude attempt $attempt/$max_attempts"
    if run_claude_attempt "$attempt"; then
      echo "pr-reviewer: Claude review succeeded on attempt $attempt"
      return 0
    fi

    echo "pr-reviewer: Claude attempt $attempt failed with exit $LAST_PRIMARY_EXIT" >&2
    if [ -s "$LAST_PRIMARY_OUTPUT" ]; then
      cat "$LAST_PRIMARY_OUTPUT" >&2
    fi

    if [ "$attempt" -lt "$max_attempts" ] && { [ "$LAST_PRIMARY_EXIT" -eq 124 ] || is_retryable_claude_failure "$LAST_PRIMARY_OUTPUT"; }; then
      echo "pr-reviewer: detected retryable Claude failure, sleeping ${delay}s before retry" >&2
      sleep "$delay"
      delay=$((delay * 2))
      attempt=$((attempt + 1))
      continue
    fi

    return 1
  done

  return 1
}

run_fallback_command() {
  if [ -z "${FALLBACK_COMMAND:-}" ]; then
    return 1
  fi

  local stdout_file="$OUTPUT_DIR/fallback.stdout"
  local stderr_file="$OUTPUT_DIR/fallback.stderr"
  : > "$stdout_file"
  : > "$stderr_file"
  : > "$REVIEW_FILE"

  echo "pr-reviewer: running fallback engine '${FALLBACK_NAME:-fallback}'" >&2

  set +e
  SYSTEM_PROMPT_FILE="$SYSTEM_PROMPT_FILE" \
  USER_PROMPT_FILE="$USER_PROMPT_FILE" \
  REVIEW_FILE="$REVIEW_FILE" \
  FALLBACK_MODEL="${FALLBACK_MODEL:-}" \
  bash -lc "$FALLBACK_COMMAND" >"$stdout_file" 2>"$stderr_file"
  local exit_code=$?
  set -e

  if [ "$exit_code" -ne 0 ]; then
    echo "pr-reviewer: fallback engine '${FALLBACK_NAME:-fallback}' exited $exit_code" >&2
    [ -s "$stdout_file" ] && cat "$stdout_file" >&2
    [ -s "$stderr_file" ] && cat "$stderr_file" >&2
    return "$exit_code"
  fi

  if [ ! -s "$REVIEW_FILE" ] && [ -s "$stdout_file" ]; then
    cp "$stdout_file" "$REVIEW_FILE"
  fi

  if [ ! -s "$REVIEW_FILE" ]; then
    echo "pr-reviewer: fallback engine '${FALLBACK_NAME:-fallback}' produced no review output" >&2
    [ -s "$stderr_file" ] && cat "$stderr_file" >&2
    return 1
  fi

  ENGINE_USED="${FALLBACK_NAME:-fallback}"
  echo "pr-reviewer: fallback engine '${ENGINE_USED}' produced review output"
  return 0
}

publish_issue_comment() {
  local source_file="$1"
  local payload_file="$OUTPUT_DIR/comment.json"
  local existing_comment_id=""

  if is_true "${STICKY_UPDATE:-true}"; then
    existing_comment_id="$(find_existing_comment_id "$COMMENT_MARKER")"
  fi

  if [ -n "$existing_comment_id" ]; then
    write_body_payload "$source_file" "$payload_file"
    gh api \
      --method PATCH \
      "repos/$REPO/issues/comments/$existing_comment_id" \
      --input "$payload_file" \
      >/dev/null
    echo "pr-reviewer: updated existing review comment on PR #$PR_NUMBER"
  else
    gh pr comment "$PR_NUMBER" --repo "$REPO" --body-file "$source_file"
    echo "pr-reviewer: posted new review comment to PR #$PR_NUMBER"
  fi
}

publish_pr_review() {
  local source_file="$1"
  local desired_event normalized_desired_state payload_file existing existing_id existing_state normalized_existing_state
  payload_file="$OUTPUT_DIR/review-payload.json"
  desired_event="$(resolve_review_event)"
  normalized_desired_state="$(normalize_review_state "$desired_event")"

  if is_true "${STICKY_UPDATE:-true}"; then
    existing="$(find_existing_review "$COMMENT_MARKER")"
  else
    existing=""
  fi

  if [ -n "$existing" ]; then
    IFS=$'\t' read -r existing_id existing_state <<<"$existing"
    normalized_existing_state="$(normalize_review_state "$existing_state")"
  else
    existing_id=""
    normalized_existing_state=""
  fi

  if [ -n "$existing_id" ] && [ "$normalized_existing_state" = "$normalized_desired_state" ]; then
    write_body_payload "$source_file" "$payload_file"
    gh api \
      --method PUT \
      "repos/$REPO/pulls/$PR_NUMBER/reviews/$existing_id" \
      --input "$payload_file" \
      >/dev/null
    echo "pr-reviewer: updated existing $normalized_desired_state review on PR #$PR_NUMBER"
  else
    write_review_payload "$source_file" "$payload_file" "$desired_event"
    gh api \
      --method POST \
      "repos/$REPO/pulls/$PR_NUMBER/reviews" \
      --input "$payload_file" \
      >/dev/null
    echo "pr-reviewer: posted new $normalized_desired_state review on PR #$PR_NUMBER"
  fi
}

for v in RUBRIC_PATH MODEL MAX_DIFF_BYTES GH_TOKEN PR_NUMBER REPO; do
  require_var "$v"
done

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR=".reviewer-output"
mkdir -p "$OUTPUT_DIR"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-$OUTPUT_DIR/github-output.txt}"

validate_submission_mode
validate_review_event

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "pr-reviewer: ANTHROPIC_API_KEY is not set; Claude CLI must rely on ambient auth or fall back to another engine" >&2
fi

# 1. Resolve the rubric: per-repo if present, otherwise the built-in default.
if [ -f "$RUBRIC_PATH" ]; then
  RUBRIC_FILE="$RUBRIC_PATH"
  echo "pr-reviewer: using repo rubric at $RUBRIC_PATH"
else
  RUBRIC_FILE="$ACTION_DIR/prompts/rubric-default.yml"
  echo "pr-reviewer: no rubric at $RUBRIC_PATH, falling back to default"
fi

"$ACTION_DIR/scripts/validate-rubric.sh" "$RUBRIC_FILE"

# 2. Pull the PR diff.
DIFF_FILE="$OUTPUT_DIR/pr.diff"
gh pr diff "$PR_NUMBER" --repo "$REPO" > "$DIFF_FILE"

DIFF_SIZE=$(wc -c < "$DIFF_FILE" | tr -d ' ')
if [ "$DIFF_SIZE" -gt "$MAX_DIFF_BYTES" ]; then
  echo "pr-reviewer: diff is $DIFF_SIZE bytes, exceeds max of $MAX_DIFF_BYTES"
  echo "pr-reviewer: skipping review. Increase max-diff-bytes if you want coverage on large PRs."
  echo "review-path=" >> "$GITHUB_OUTPUT"
  echo "blocking-count=0" >> "$GITHUB_OUTPUT"
  echo "engine-used=skipped" >> "$GITHUB_OUTPUT"
  exit 0
fi

# 3. Assemble the prompt.
SYSTEM_PROMPT_FILE="$ACTION_DIR/prompts/system.md"
SYSTEM_PROMPT_CONTENT="$(cat "$SYSTEM_PROMPT_FILE")"
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

# 4. Run Claude with retry semantics, then optional fallback.
REVIEW_FILE="$OUTPUT_DIR/review.md"
MAX_RETRIES="${MAX_RETRIES:-2}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-5}"
REVIEW_TIMEOUT_SECONDS="${REVIEW_TIMEOUT_SECONDS:-900}"

if ! run_claude_with_retries; then
  if [ -n "${FALLBACK_COMMAND:-}" ]; then
    echo "pr-reviewer: Claude failed after retries; invoking fallback engine" >&2
    run_fallback_command || {
      echo "pr-reviewer: both primary and fallback review engines failed" >&2
      exit 1
    }
  else
    echo "pr-reviewer: Claude failed after retries and no fallback engine is configured" >&2
    exit "${LAST_PRIMARY_EXIT:-1}"
  fi
fi

echo "pr-reviewer: review written to $REVIEW_FILE"

# 5. Count blocking issues and validate the output contract.
REVIEW_CHECK_JSON="$("$ACTION_DIR/scripts/check-review-output.sh" --strict "$REVIEW_FILE")"
BLOCKING_COUNT=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["blocking_count"])' <<<"$REVIEW_CHECK_JSON")
echo "pr-reviewer: blocking issues flagged: $BLOCKING_COUNT"

# 6. Optionally publish the review back to GitHub.
if is_true "${POST_COMMENT:-true}"; then
  PUBLISH_FILE="$OUTPUT_DIR/publish.md"
  {
    echo "$COMMENT_MARKER"
    echo ""
    cat "$REVIEW_FILE"
  } > "$PUBLISH_FILE"

  case "$(lower "${SUBMISSION_MODE:-comment}")" in
    comment) publish_issue_comment "$PUBLISH_FILE" ;;
    review) publish_pr_review "$PUBLISH_FILE" ;;
  esac
fi

echo "review-path=$REVIEW_FILE" >> "$GITHUB_OUTPUT"
echo "blocking-count=$BLOCKING_COUNT" >> "$GITHUB_OUTPUT"
echo "engine-used=${ENGINE_USED:-unknown}" >> "$GITHUB_OUTPUT"

if is_true "${FAIL_ON_BLOCKING:-false}" && [ "$BLOCKING_COUNT" -gt 0 ]; then
  echo "pr-reviewer: failing job because fail-on-blocking=true and $BLOCKING_COUNT blocking issues were flagged"
  exit 1
fi

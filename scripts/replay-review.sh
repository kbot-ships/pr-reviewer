#!/usr/bin/env bash
set -euo pipefail

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUBRIC_PATH=".github/pr-reviewer.yml"
MODEL="${MODEL:-claude-sonnet-4-6}"
OUTPUT_DIR=".reviewer-replay"
ASSEMBLE_ONLY=0
DIFF_FILE=""

usage() {
  cat <<EOF
usage: $0 --diff <path> [--rubric <path>] [--model <id>] [--output-dir <dir>] [--assemble-only]

Local replay harness for reviewing a saved PR diff with the same prompt structure
used by the GitHub Action.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diff)
      DIFF_FILE="${2:-}"
      shift 2
      ;;
    --rubric)
      RUBRIC_PATH="${2:-}"
      shift 2
      ;;
    --model)
      MODEL="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --assemble-only)
      ASSEMBLE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$DIFF_FILE" ]]; then
  echo "replay-review: --diff is required" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$DIFF_FILE" ]]; then
  echo "replay-review: diff file not found: $DIFF_FILE" >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR"

if [[ -f "$RUBRIC_PATH" ]]; then
  RUBRIC_FILE="$RUBRIC_PATH"
  echo "replay-review: using rubric at $RUBRIC_PATH"
else
  RUBRIC_FILE="$ACTION_DIR/prompts/rubric-default.yml"
  echo "replay-review: no rubric at $RUBRIC_PATH, falling back to default"
fi

"$ACTION_DIR/scripts/validate-rubric.sh" "$RUBRIC_FILE"

SYSTEM_PROMPT_FILE="$ACTION_DIR/prompts/system.md"
USER_PROMPT_FILE="$OUTPUT_DIR/user-prompt.md"
REVIEW_FILE="$OUTPUT_DIR/review.md"

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

echo "replay-review: wrote prompt to $USER_PROMPT_FILE"

if [[ "$ASSEMBLE_ONLY" == "1" ]]; then
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  echo "replay-review: claude CLI not found on PATH" >&2
  exit 2
fi

claude -p --bare \
  --model "$MODEL" \
  --system-prompt "$(cat "$SYSTEM_PROMPT_FILE")" \
  < "$USER_PROMPT_FILE" \
  > "$REVIEW_FILE"

echo "replay-review: wrote review to $REVIEW_FILE"

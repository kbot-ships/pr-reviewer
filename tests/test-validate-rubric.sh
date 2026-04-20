#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATOR="$REPO_ROOT/scripts/validate-rubric.sh"

pass() {
  echo "PASS: $*"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_success() {
  local file="$1"
  if ! "$VALIDATOR" "$file" >/tmp/pr-reviewer-validate.out 2>/tmp/pr-reviewer-validate.err; then
    cat /tmp/pr-reviewer-validate.err >&2 || true
    fail "expected success for $file"
  fi
}

expect_failure() {
  local file="$1" needle="$2"
  if "$VALIDATOR" "$file" >/tmp/pr-reviewer-validate.out 2>/tmp/pr-reviewer-validate.err; then
    fail "expected failure for $file"
  fi
  grep -q "$needle" /tmp/pr-reviewer-validate.err || {
    cat /tmp/pr-reviewer-validate.err >&2 || true
    fail "expected '$needle' in validator stderr for $file"
  }
}

expect_success "$REPO_ROOT/examples/code-repo.yml"
expect_success "$REPO_ROOT/examples/paper-repo.yml"
expect_success "$REPO_ROOT/examples/agent-safety.yml"
expect_failure "$SCRIPT_DIR/fixtures/invalid-rubric-top-level.yml" "top level"
expect_failure "$SCRIPT_DIR/fixtures/invalid-rubric-types.yml" "persona must be a String"

pass "rubric validator fixtures"

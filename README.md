# pr-reviewer

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A reusable GitHub Action that reviews pull requests with Claude, guided by a per-repo rubric.

## Quick start

1. Add your Anthropic API key as a repository secret named `ANTHROPIC_API_KEY`.
2. Create a workflow at `.github/workflows/review.yml`:

   ```yaml
   name: review
   on:
     pull_request:
       types: [opened, synchronize, reopened]

   jobs:
     review:
       runs-on: ubuntu-latest
       permissions:
         contents: read
         pull-requests: write
       steps:
         - uses: actions/checkout@v4
         - uses: kbot-ships/pr-reviewer@v1
           with:
             anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
   ```

3. (Optional) Drop a rubric at `.github/pr-reviewer.yml`. Start by copying one of the [examples](./examples). Without a rubric, the built-in default is used.

That's it. On every PR, Claude reads the diff, applies your rubric, and publishes the result back to GitHub.
By default it posts a sticky PR comment; you can also publish as a formal PR review event.

If the rubric file is malformed or uses the wrong top-level field types, the action now fails fast with an actionable validation error before the Claude call.

## What you get

A review comment shaped like this:

```
## Summary
<2-4 sentence overview>

## Issues
- [BLOCKING] <merge-and-break concern, file:line>
- [HIGH] <strong concern>
- [MEDIUM] <worth addressing>
- [LOW] <nit>

## Suggestions
<non-blocking improvements>

## Questions
<only if something is genuinely ambiguous>
```

The `[BLOCKING]` tag is machine-scanned. Set `fail-on-blocking: true` to fail the job when any blocking issue is flagged. The action accepts either a standalone `[BLOCKING] ...` line or a normal markdown list item like `- [BLOCKING] ...`.

## Review submission modes

The action can publish in two ways:

- `submission-mode: comment` (default) -- writes a sticky PR comment and updates it on later runs
- `submission-mode: review` -- creates a PR review event via the reviews API

When `submission-mode: review`, the review event is controlled by `review-event`:

- `auto` (default) -- `REQUEST_CHANGES` if any `[BLOCKING]` issues were found, otherwise `COMMENT`
- `comment`
- `approve`
- `request_changes`

If `sticky-update: true`, the action will update an existing bot-authored comment or review when possible instead of posting duplicates.

## Inputs

| Input | Default | Notes |
|-------|---------|-------|
| `anthropic-api-key` | empty | Usually provided as a GitHub secret. Leave unset only if your runner has ambient Claude auth or you intend to rely on a fallback engine. |
| `rubric-path` | `.github/pr-reviewer.yml` | Path to the rubric YAML, relative to repo root. Falls back to a built-in default if the file is missing. |
| `model` | `claude-sonnet-4-6` | Claude model ID. Override to `claude-opus-4-7` for deeper review or `claude-haiku-4-5-20251001` for cost. |
| `max-diff-bytes` | `200000` | Skip review if the diff is larger than this. Large diffs get diffuse reviews; better to skip than waste tokens. |
<<<<<<< HEAD
| `post-comment` | `true` | Publish the review back to GitHub. Set to `false` to just compute the review. |
| `submission-mode` | `comment` | `comment` or `review`. Controls whether the result is posted as an issue comment or a PR review event. |
| `review-event` | `auto` | Used when `submission-mode=review`. `auto`, `comment`, `approve`, or `request_changes`. |
| `sticky-update` | `true` | Update the bot's existing comment/review when possible instead of posting duplicates. |
| `fail-on-blocking` | `false` | Fail the job if Claude flags any `[BLOCKING]` issues. See [docs/fail-on-blocking.md](./docs/fail-on-blocking.md) for rollout patterns and caveats. |
| `max-retries` | `2` | Retry attempts for transient Claude CLI failures. |
| `retry-delay-seconds` | `5` | Base delay between Claude retries; later retries back off exponentially. |
| `review-timeout-seconds` | `900` | Best-effort timeout for one Claude attempt when `timeout(1)` is available on the runner. |
| `fallback-command` | empty | Optional shell command to run if Claude fails after retries. Receives `SYSTEM_PROMPT_FILE`, `USER_PROMPT_FILE`, `REVIEW_FILE`, and `FALLBACK_MODEL`. |
| `fallback-name` | `fallback` | Name used in logs and outputs for the fallback engine. |
| `fallback-model` | empty | Optional model identifier exposed to the fallback command as `FALLBACK_MODEL`. |
=======
| `post-comment` | `true` | Post the review as a PR comment. Set to `false` to just compute the review (useful for local testing or custom handling). |
| `fail-on-blocking` | `false` | Fail the job if Claude flags any `[BLOCKING]` issues. See [docs/fail-on-blocking.md](./docs/fail-on-blocking.md) for rollout patterns and caveats. |
>>>>>>> origin/main

## Outputs

| Output | Notes |
|--------|-------|
| `review-path` | Path to the generated review markdown (inside the runner). |
| `blocking-count` | Number of `[BLOCKING]` issues flagged. |
| `engine-used` | Which engine produced the final review (`claude`, fallback name, or `skipped`). |

## Fallback engines

If Claude fails after retries, you can run a fallback engine by setting `fallback-command`.

The fallback command contract is simple:

- it runs in `bash -lc`
- it receives:
  - `SYSTEM_PROMPT_FILE`
  - `USER_PROMPT_FILE`
  - `REVIEW_FILE`
  - `FALLBACK_MODEL`
- it should either write markdown review output to `$REVIEW_FILE` or print it to stdout

Minimal example:

```yaml
      - uses: kbot-ships/pr-reviewer@v1
        with:
          anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
          fallback-name: backup-reviewer
          fallback-command: >
            python .github/scripts/fallback_review.py
            "$SYSTEM_PROMPT_FILE"
            "$USER_PROMPT_FILE"
            "$REVIEW_FILE"
```

The action does not install the fallback engine for you. Keep the fallback command explicit so the repo owner controls the trust boundary and runtime dependencies.

The repo also ships `scripts/check-review-output.sh`, which validates that a
review contains the required sections, emits a small JSON severity summary,
and rejects unsupported severity tags in strict mode. The action now uses that
contract check before posting.

## Rubrics

A rubric tells the reviewer what to weight on your repo. It's YAML that gets passed verbatim as part of the user message. Three starting points:

- [`examples/paper-repo.yml`](./examples/paper-repo.yml) -- for LaTeX paper repositories.
- [`examples/code-repo.yml`](./examples/code-repo.yml) -- balanced defaults for a software project.
- [`examples/high-risk-code-repo.yml`](./examples/high-risk-code-repo.yml) -- stricter defaults for auth, billing, infra, and other high-consequence services.
- [`examples/paper-submission.yml`](./examples/paper-submission.yml) -- tighter review posture for near-submission paper passes.
- [`examples/agent-safety.yml`](./examples/agent-safety.yml) -- higher-stakes rubric for AI-agent-adjacent code.

See [`docs/rubric-schema.md`](./docs/rubric-schema.md) for the recommended fields and what the rubric cannot override.

## Local replay

Use the replay harness to review a saved PR diff locally with the same rubric and
prompt structure the action uses:

```bash
scripts/replay-review.sh --diff /path/to/pr.diff --assemble-only
scripts/replay-review.sh --diff /path/to/pr.diff
```

`--assemble-only` writes the prompt bundle without calling Claude, which is the
fastest way to inspect exactly what the action would send.

## Design notes

- **One Claude call per PR.** No multi-pass, no per-file fan-out. Keeps cost predictable and reviews coherent.
- **Transient failures are retried; hard failures can fall back.** Rate limits, overloads, and timeouts should not silently kill the review path.
- **Rubric over tuning.** Repo-specific guidance lives in YAML, not in code. Easier to iterate, easier to copy between repos.
- **Big diffs are skipped, not chunked.** A review of a 10k-line refactor is going to be superficial no matter how you slice it. The action logs a clear skip message so the author knows why.
- **The PR comment is sticky.** Re-runs update the existing bot comment instead of piling up duplicates on every push.
- **Review publishing is explicit.** Comments remain the safe default; review events are opt-in because they carry stronger workflow semantics.
- **`[BLOCKING]` is still a literal tag, but the parser tolerates normal markdown bullets.** Simple contract, low-friction formatting.
- **Fail-open by default.** The action doesn't block merges unless you opt in with `fail-on-blocking: true`.

## License

[MIT](./LICENSE).

## Status

Active. Self-review workflow runs on every PR against this repo as a dogfood test.

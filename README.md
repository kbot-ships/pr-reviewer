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

That's it. On every PR, Claude reads the diff, applies your rubric, and posts a review as a PR comment.

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

The `[BLOCKING]` tag is machine-scanned. Set `fail-on-blocking: true` to fail the job when any blocking issue is flagged.

## Inputs

| Input | Default | Notes |
|-------|---------|-------|
| `anthropic-api-key` | *(required)* | Store as a GitHub secret. |
| `rubric-path` | `.github/pr-reviewer.yml` | Path to the rubric YAML, relative to repo root. Falls back to a built-in default if the file is missing. |
| `model` | `claude-sonnet-4-6` | Claude model ID. Override to `claude-opus-4-7` for deeper review or `claude-haiku-4-5-20251001` for cost. |
| `max-diff-bytes` | `200000` | Skip review if the diff is larger than this. Large diffs get diffuse reviews; better to skip than waste tokens. |
| `post-comment` | `true` | Post the review as a PR comment. Set to `false` to just compute the review (useful for local testing or custom handling). |
| `fail-on-blocking` | `false` | Fail the job if Claude flags any `[BLOCKING]` issues. See [docs/fail-on-blocking.md](./docs/fail-on-blocking.md) for rollout patterns and caveats. |

## Outputs

| Output | Notes |
|--------|-------|
| `review-path` | Path to the generated review markdown (inside the runner). |
| `blocking-count` | Number of `[BLOCKING]` issues flagged. |

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
- **Rubric over tuning.** Repo-specific guidance lives in YAML, not in code. Easier to iterate, easier to copy between repos.
- **Big diffs are skipped, not chunked.** A review of a 10k-line refactor is going to be superficial no matter how you slice it. The action logs a clear skip message so the author knows why.
- **`[BLOCKING]` is a literal tag, not a structured parser.** Simple contract, one-line grep. Easy to audit, hard to break.
- **Fail-open by default.** The action doesn't block merges unless you opt in with `fail-on-blocking: true`.

## License

[MIT](./LICENSE).

## Status

Active. Self-review workflow runs on every PR against this repo as a dogfood test.

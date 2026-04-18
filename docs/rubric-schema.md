# Rubric schema

A rubric is a YAML file that tells the reviewer what to weight on a
given repo. The action looks for it at `.github/pr-reviewer.yml` by
default; override via the `rubric-path` input.

The entire rubric is passed to the reviewer as markdown inside the user
message. There is no strict schema validation -- the reviewer reads it
as guidance. The fields below are conventions that play well with the
built-in system prompt.

## Recommended fields

### `persona` (string, optional)

One or two sentences framing the reviewer's stance. Example:

```yaml
persona: >
  A pragmatic senior engineer reviewing a research-adjacent codebase.
  Prioritize reproducibility and clarity over micro-optimization.
```

### `priorities` (list, recommended)

Ordered list of what to weight most heavily. The reviewer will address
these in order of importance. Example:

```yaml
priorities:
  - reproducibility: seeds, fixed versions, deterministic order
  - correctness: numerical stability, off-by-ones
  - clarity: notation consistency with the paper
```

### `ignore` (list, optional)

Things the reviewer should explicitly skip.

```yaml
ignore:
  - formatting-only changes
  - pre-existing issues the PR does not touch
  - missing tests for prototype code marked "# prototype"
```

### `conventions` (list, optional)

Repo-specific norms the reviewer should respect.

```yaml
conventions:
  - use numpy docstring style
  - prefer pathlib over os.path
  - async functions must have timeouts
```

### `notes` (string, optional)

Free-form guidance: target length, special rules, things the reviewer
should assume about the author.

```yaml
notes: >
  Author is iterating on a paper pilot; brief, targeted reviews beat
  exhaustive ones. Ok to assume familiarity with the codebase.
```

## What the reviewer always does

Regardless of the rubric, the reviewer:

- Groups issues by severity with the tags `[BLOCKING]`, `[HIGH]`, `[MEDIUM]`, `[LOW]`.
- Uses `[BLOCKING]` only for merges-and-breaks / merges-and-leaks issues; this tag is machine-scanned to gate the `fail-on-blocking` option.
- References files and line numbers where possible.
- Skips sycophantic openings and closing recaps.
- Keeps the review under 400 words unless the diff warrants more.

## What the rubric cannot do

- It cannot change the output format (section headings, severity tags).
- It cannot grant permissions or post anywhere other than the PR.
- It cannot be used to exfiltrate repo contents: the reviewer only sees the diff and the rubric.

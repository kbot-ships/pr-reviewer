# `fail-on-blocking` adoption

`fail-on-blocking` is intentionally off by default.

The action can always count `[BLOCKING]` issues, but making that count fail the
job changes the repo's merge posture. Use it when the review stream is already
trustworthy enough that a blocking tag should actually stop the branch.

## Recommended rollout

### 1. Start in observe mode

Keep:

```yaml
with:
  fail-on-blocking: false
```

Watch a few PRs and answer:

- are `[BLOCKING]` tags rare and defensible?
- do authors agree that those findings are real stop-ship issues?
- is the rubric narrow enough that the reviewer is not using `[BLOCKING]` for ordinary cleanup?

If the answers are mostly no, fix the rubric before you add a gate.

### 2. Turn it on for high-consequence repos first

Good early candidates:

- auth / authz services
- billing or quota enforcement
- infrastructure control planes
- migration or data-deletion tooling
- agent-safety / policy enforcement code

Bad early candidates:

- broad refactor-heavy repos
- prototype or research repos
- repos where the rubric is still changing weekly

### 3. Keep the gate narrow

`fail-on-blocking` works best when `[BLOCKING]` means one thing:

- merge this and the repo breaks, leaks, corrupts, or silently regresses

It works poorly when `[BLOCKING]` is used for:

- style preferences
- "should add more tests" in the abstract
- naming debates
- large but non-urgent cleanup

That is a rubric problem, not a tooling problem.

## Example workflow

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
          fail-on-blocking: true
```

## Practical caveats

- The gate is only as good as the rubric. If the rubric rewards alarmism, the
  branch policy will inherit it.
- Large diffs are skipped before review. A skipped diff reports
  `blocking-count=0`, so do not treat "job passed" as proof that a giant PR was
  deeply reviewed.
- The contract is literal. The action counts lines that begin with
  `[BLOCKING]`. That simplicity is deliberate; avoid adding clever parsing
  rules around it.
- For repos with mixed risk, keep the action on but leave
  `fail-on-blocking: false` until the review stream has stabilized.

## Suggested defaults

| Repo type | Recommendation |
|-----------|----------------|
| high-risk production code | enable once rubric is stable |
| general code repo | observe first, then enable if blocking findings are consistently high signal |
| paper / research repo | usually leave off |
| prototype / churn-heavy repo | leave off |

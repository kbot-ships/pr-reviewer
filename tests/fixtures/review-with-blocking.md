## Summary

This change tightens auth middleware but misses one call site.

## Issues

[BLOCKING] `services/auth.py:42` still accepts unsigned tokens on the legacy path.
[HIGH] `tests/test_auth.py:10` does not cover the failure mode.

## Suggestions

Add a regression test for unsigned legacy tokens.

## Questions

None.

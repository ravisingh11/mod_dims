# Performance Baseline

This document captures how to gather a repeatable local performance baseline for `mod_dims`.

## Quick smoke benchmark

Run:

```bash
./tests/perf-smoke.sh
```

Environment knobs:

- `REQUESTS` (default: `100`)
- `P95_LIMIT_MS` (default: `250`)
- `IMAGE_TAG` (default: `mod-dims:perf-smoke`)

Example:

```bash
REQUESTS=500 P95_LIMIT_MS=300 ./tests/perf-smoke.sh
```

## Notes

- `tests/perf-smoke.sh` is a short guardrail benchmark, not a full capacity test.
- It uses local Docker + fixture traffic and reports p50/p95/p99 over identical requests.
- Use `DimsStatusExtended true` to inspect additional runtime metrics from `/dims-status/`.

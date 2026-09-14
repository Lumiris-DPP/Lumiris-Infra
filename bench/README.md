# LUMIRIS — k6 benchmarks

Four scenarios live here, one file per surface under load:

| File                            | Surface | Goal                                                    |
| -------------------------------- | ------- | -------------------------------------------------------- |
| `scenarios/browse.js`           | `web`   | Public pages stay fast under organic traffic.           |
| `scenarios/audit.js`            | `admin` | Auditors keep working through a busy day.               |
| `scenarios/scoring.js`          | `api`   | `/score` p95 stays under **250 ms**.                    |
| `scenarios/passport-lookup.js`  | `api`   | Public passport lookup p95 stays under **80 ms**.       |

## Run locally

```bash
make bench SCENARIO=scoring        # default BASE=http://localhost:4000
make bench SCENARIO=browse         # default BASE=http://localhost:3000
make bench SCENARIO=audit          # default BASE=http://localhost:3001

# passport-lookup needs a real public code — the Makefile target doesn't forward
# k6 -e flags, so run it directly for now:
k6 run bench/scenarios/passport-lookup.js -e BASE=http://localhost:8080 -e PUBLIC_CODE=<code seeded on the target env>
```

`make bench-prod` aims at `https://api.lumiris.io` (override with `BASE=…`). Always
get explicit authorization from infra before running prod benchmarks.

## Conventions

- Every scenario exports a `summaryHandler` that writes `bench/out/<scenario>.json`
  so CI can ingest it and trend p95/RPS over time.
- Thresholds are **failures**, not warnings: a regression breaks the build.
- `payloads/` holds shared fixtures — keep them realistic (no empty objects).

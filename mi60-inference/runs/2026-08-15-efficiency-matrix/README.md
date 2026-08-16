# 2026-08-15 efficiency matrix

Every thermal run used fixed 100% speed on the shared Noctua 140 mm fan and a
95 C junction cutoff. Requests, responses, status snapshots, and half-second
telemetry are stored in each run directory. `sweep-225-160-pp16` is an
infrastructure failure from when the inference container was stopped; it sent
no GPU workload and is superseded by the two `sweep-control-*` runs.

The prescribed `225/160`, `160/160`, and `225/145 W` long PP/TG profiles all
hit the cutoff. The completed long PP extensions were:

| Caps | Prompt tokens | PP tok/s | Peak junction |
| ---: | ---: | ---: | ---: |
| 160/145 W | 32,788 | 282.83 | 91/91 C |
| 170/145 W | 32,783 | 283.65 | 94/92 C |

The short 16K PP sweep retained more than 300 tok/s down through `170/145 W`.
Fixed-seed 768-token TG reached 28.66 tok/s at `170/160 W`; raising GPU0 or
raising GPU1 to 177 W did not improve it. See `../../thermal-power.md` for the
full tables and interpretation.

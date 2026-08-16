# Dual-fan position comparison

Both position tests use GPU0/GPU1 at `200/165 W`, the shared fan circuit fixed
at 96% PWM, cold starts at or below 45 C junction, 0.2-second telemetry, and a
99 C control cutoff protecting the accepted 100 C hard limit. The same MTP2
model and requests are used in each position.

| Position | Test | Result | Peak junction | Reported fan RPM |
| --- | --- | ---: | ---: | ---: |
| 1 | 2,048 TG | 31.90 tok/s | 85/88 C | 1,582 max |
| 1 | 32K PP | 290.03 tok/s | 95/91 C | 1,577 max |
| 2 | 2,048 TG | 32.66 tok/s | 87/90 C | 1,586 max |
| 2 | 32K PP | Aborted after 96.8 seconds | 99/94 C | 1,588 max |
| 3 | 2,048 TG | 31.55 tok/s | 90/92 C | 1,553 max |
| 3 | 32K PP | Aborted after 97.4 seconds | 99/93 C | 1,557 max |

Position 1 completed both long workloads. This is a substantial improvement
over the single-fan `200/165 W`, 96% tests, which reached the 99 C cutoff in
both workloads. Position 2 ran 2-5 C hotter at comparable points and failed
the 32K PP test, despite essentially identical reported fan speed. Its higher
TG throughput is not evidence of better cooling: MTP draft acceptance differed
between requests, while temperature is the controlled positional measurement.

Position 3 was hottest in TG and effectively tied position 2's failed PP32
result. Position 1 is the clear winner: it reduced TG peaks by 2-5 C and was
the only placement that completed PP32, with 4 C of margin below the control
cutoff on GPU0. The new fan should be returned to position 1.

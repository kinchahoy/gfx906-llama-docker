# Rejected 200/165 W, 96% fan profile

The exact requested caps and fan ceiling were tested from cold starts with a
99 C control cutoff and 100 C hard limit.

| Test | Result | Peak junction |
| --- | --- | ---: |
| 16K PP trial 1 | 286.64 tok/s | 78/78 C |
| 16K PP trial 2 | 307.40 tok/s | below cutoff |
| 32K PP | Aborted after 91.5 seconds | 99/95 C |
| 2,048 TG | Aborted at cutoff | 96/99 C |

An earlier `200/165 W` fixed-100% trial produced 300.33 PP and 28.64 TG tok/s.
The additional power did not outperform 180/160 W, and reducing the fan from
about 1,590 to 1,565 RPM exhausted the long-run thermal margin. The operator
nonetheless selected this exact profile for the prepared production installer.

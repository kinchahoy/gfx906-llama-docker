# Final settings validation

The accepted hard junction limit was 100 C. Tests sampled every 0.2 seconds
and used a 99 C control cutoff to prevent cancellation latency from crossing
the hard limit. The Noctua 140 mm manifold fan was fixed at 100%.

`180/160 W` won the direct comparison:

| Test | Throughput | Peak junction |
| --- | ---: | ---: |
| 16K PP | 305.81 tok/s | 77/78 C |
| 32K PP | 288.83 tok/s | 98/96 C |
| 768 TG, two runs | 28.78, 28.41 tok/s | below cutoff |
| 2,048 TG | 31.87 tok/s | 96/97 C |
| Three concurrent 768 TG | 37.07 aggregate tok/s | 87/90 C maximum |

The direct `200/165 W` comparison reached 300.33 PP and 28.64 TG tok/s, so the
additional 25 W did not improve either target. The production recommendation
from the measurements is 180/160 W. A subsequent 200/165 W, fixed-96% test hit
the 99 C control cutoff in both long workloads and was rejected.

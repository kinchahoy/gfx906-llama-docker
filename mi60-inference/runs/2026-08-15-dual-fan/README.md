# Dual-manifold-fan validation

The added Noctua 140 mm fan was tested on the shared control circuit with the
machine's still-active default profile: GPU0/GPU1 at `225/160 W` and the old
automatic CoolerControl curve. The requested `200/165 W`, 96% production
profile was not active during these measurements.

All long tests started at or below 45 C junction. Telemetry was sampled every
0.2 seconds, with a 99 C control cutoff protecting the accepted 100 C hard
limit.

| Test | Result | Peak junction | Max shared PWM |
| --- | ---: | ---: | ---: |
| 16K PP | 299.31 tok/s | 80/75 C | 71.0% |
| 32K PP | Aborted at the 99 C cutoff | 99/89 C | 92.2% |
| 2,048 TG | 31.30 tok/s | 91/91 C | 76.9% |

The 2,048-token TG run completed and was within 1.8% of the previous best
31.87 tok/s result. The 16K PP result was within 2.1% of the previous best
305.81 tok/s result. Sustained 32K PP remains unsafe at 225 W on GPU0.
With the earlier single fan fixed at 100%, the same `225/160 W` TG workload
aborted after 70.8 seconds at 95/94 C; the dual-fan run completed in 73.0
seconds at only 91/91 C despite topping out at 76.9% PWM. This is a material
cooling improvement.

During the failed 32K run, GPU0 edge/junction reached about 70/99 C while GPU1
reached about 69/89 C. Similar edge temperatures but a larger GPU0
junction-to-edge delta point more strongly to GPU0's extra 65 W and its local
die-to-heatsink thermal path than to gross manifold airflow starvation. Since
both fans share a circuit, only one trustworthy tach signal should be connected;
the recorded RPM cannot establish that both physical fans were spinning.

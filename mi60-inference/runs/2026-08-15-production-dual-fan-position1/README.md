# Dual-fan position-1 production comparison

Both profiles used the saved automatic curve (96% ceiling), the second Noctua
fan in position 1, cold starts at or below 45 C junction, identical uncached
requests, MTP depth 2, 0.2-second telemetry, and the 99 C control cutoff.

| Caps | Test | Throughput | Peak junction | MTP accepted/drafted |
| ---: | --- | ---: | ---: | ---: |
| 200/165 W | TG2048 | 32.25 tok/s | 84/88 C | 1,157/1,778 |
| 210/170 W | TG2048 | 32.98 tok/s | 84/89 C | 1,164/1,764 |
| 200/165 W | PP32 | 290.40 tok/s | 94/91 C | n/a |
| 210/170 W | PP32 | 290.36 tok/s | 97/92 C | n/a |

`210/170 W` improved this TG run by 2.3%, although its slightly better MTP
acceptance means the entire difference cannot be attributed to power. PP32 was
unchanged and GPU0 lost 3 C of thermal margin. The operator selected 210/170 W
for production despite the flat PP result; the 99 C cutoff remains mandatory
for future stress testing.

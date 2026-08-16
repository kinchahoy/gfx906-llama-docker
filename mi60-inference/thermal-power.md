# Thermal, fan, power, and clock notes

## Verdict

The fan-control architecture is good, but the current curve is not sufficient
for continuous full-rate prompt processing. A sustained uncached PP run reached
106 C junction on GPU0 and 104 C on GPU1. Their exposed critical limits are
100 C and 105 C respectively.

Thermal throttling is present but modest in this run: completed 16,413-token
passes fell from 305.8 to 296.8 prompt tokens/s (about 3%) as GPU0 active
average SCLK fell from about 1711 to 1614 MHz. Stop a test if either junction
reaches 100 C; performance is no longer the main concern there.

TG is not presently the thermal emergency. A cold/hot 768-token pair peaked at
80/80 C and 83/85 C. Throughput varied from 29.73 to 27.86 tokens/s, but active
clocks held nearly steady and MTP acceptance also changed. That is not enough
evidence to call the TG difference thermal throttling; repeat with a fixed seed
for a cleaner comparison.

This does **not** currently look like failed thermal pads:

- Peak HBM temperature was 83 C, below its 94 C critical limit.
- Hotspot-to-edge deltas were generally about 20--23 C before critical heat
  soak.
- Both cards heated similarly.

If servicing the cards later, inspect paste/contact before replacing pads.
Only change pad thickness with card-specific measurements; incorrect pads can
lift the cold plate off the die.

## Active cooling policy

`coolercontrold.service` applies profile `mi60blower` to motherboard `fan2`,
the Noctua 140 mm fan feeding the custom 3D-printed manifold.
Its source is the maximum of edge, junction, and memory temperature across both
AMD cards. The important curve points are:

```text
31.1 C -> 30%
95.5 C -> 95%
110 C  -> 100%
```

The function has a one-second response delay and 3 C deviance. During the hot
run the manifold fan reached about 1,586 RPM and 97% duty, but only after junctions
had already crossed critical temperature.

The later fixed-fan matrix held this fan at 100% from a cold start and still
reached the 95 C cutoff. An earlier curve ramp may reduce short transient
peaks, but it cannot solve sustained load. Inspect fan static pressure, duct
sealing, manifold balance, card spacing, and exhaust recirculation first.

## 2026-08-15 baseline

Input was `~/infer/llama.cpp/flake.nix`, repeated in uncached OpenAI-compatible
requests. Model was Qwen3.8-27B Q8_0 with tensor split across both cards.

| Prompt tokens | Pass | PP tok/s | Peak junction GPU0/GPU1 |
| ---: | ---: | ---: | ---: |
| 4,129 | 1 | 276.5 | 58/60 C |
| 8,223 | 1 | 308.3 | 70/70 C |
| 16,413 | 1 | 305.8 | 91/84 C |
| 16,413 | 2 | 302.0 | 100/92 C |
| 16,413 | 3 | 304.8 | 104/98 C |
| 16,413 | 4 | 296.8 | 104/101 C |

The next pass was aborted after live samples reached 104 C and then a recorded
peak of 106 C.

| TG start | Generated | TG tok/s | Peak junction | Active SCLK GPU0/GPU1 | Active MCLK GPU0/GPU1 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold | 768 | 29.73 | 80/80 C | 1725/1672 MHz | 971/971 MHz |
| Hot | 768 | 27.86 | 83/85 C | 1733/1654 MHz | 971/1000 MHz |

The TG runs accepted 432/668 and 422/688 MTP drafts respectively, so their
throughput is not a perfectly controlled thermal A/B.

Raw diagnostic logs may not survive reboot:

- PP: `/tmp/mi60-thermal.hGWPth`
- Cold TG: `/tmp/mi60-tg.4oMU1v`
- Hot TG: `/tmp/mi60-tg-hot.VtKJZC`

## Power and clocks

- Boot service: `/etc/systemd/system/VR-gpu-setup.service`
- Script: `/usr/local/bin/VR-gpu-init.sh`
- Configured caps: GPU0 225 W; GPU1 160 W.
- GPU1 default/firmware maximum: 178 W.
- Performance level is `auto` on both cards.
- Under PP, MCLK reaches 1000 MHz and falls to 800 MHz between bursts.
- Under PP, SCLK rises dynamically toward its maximum but falls between work
  bursts and declined during critical heat soak.

Prefer testing a fixed maximum MCLK before fixed SCLK. A fixed SCLK raises idle
and partial-load power and can consume power/thermal headroom. A 177 W GPU1
cap was tested because tensor-parallel steps wait for the slower card. It did
not improve end-to-end PP, so 160 W remains the preferred operating point.

## GPU1 160 W versus 177 W

The same uncached 16,413-token request was used. Both 177 W runs started below
50 C and completed below the 100 C safety cutoff.

| GPU1 cap | Trial | PP tok/s | Peak junction GPU0/GPU1 | Active SCLK GPU0/GPU1 | Active sampled power GPU0/GPU1 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 160 W | Reference | 305.8 | 91/84 C | 1711/1606 MHz | 204.7/174.4 W |
| 177 W | 1 | 302.6 | 85/83 C | 1710/1648 MHz | 203.4/188.5 W |
| 177 W | 2 | 308.8 | 87/87 C | 1713/1648 MHz | 204.2/187.9 W |

The 177 W average was 305.7 tok/s: no measurable improvement over 305.8 tok/s
at 160 W. GPU1 gained about 42 MHz and consumed about 14 W more in active
samples, so another part of tensor PP is gating throughput. Prefer 160 W for
lower heat and power.

The cap is temporarily 177 W after this test. Reboot, restart
`VR-gpu-setup.service`, or run the following to restore 160 W:

```bash
sudo rocm-smi -d 1 --setpoweroverdrive 160 --autorespond y
```

Raw 177 W logs:

- `/tmp/mi60-pp177.equK3E`
- `/tmp/mi60-pp177-repeat.HduL3c`

## Extended efficiency protocol

Use this protocol for the 160 W reference and each lower-power candidate:

1. Start at or below 45 C junction.
2. Temporarily hold the shared `nct6799` `fan2` manifold fan at 100% so power caps,
   not fan ramp timing, are the changed variable.
3. Use the same uncached `flake.nix` prompt and a fixed seed.
4. Run a 32K-token PP pass long enough to expose sustained clock behavior.
5. Run a 2,048-token TG pass with a fixed seed and record MTP acceptance.
6. Abort either test at 95 C junction.
7. Compare throughput plus first/last-quarter SCLK, MCLK, power, and
   temperature. Treat differences below 2% as measurement noise.
8. Validate the winning profile with three concurrent request slots and the
   intended automatic fan curve.

The reference is GPU0/GPU1 `225/160 W`. Profile A is `160/160 W` and doubles as
the equal-power airflow diagnostic below. Profile B is `225/145 W` and isolates
GPU1 efficiency headroom. This keeps the search to two non-baseline profiles.

## Equal-power airflow and contact test

Use this after the power-efficiency baseline. Its purpose is diagnosis, not a
new production profile.

1. Let both cards cool to within 2 C of each other and at or below 45 C.
2. Hold the shared Noctua 140 mm manifold fan at fixed 100%.
3. Temporarily cap both cards at the same value, initially 160 W.
4. Run the same uncached sustained 32K PP workload with a fixed seed.
5. Abort at 95 C junction.
6. Record each card's starting and peak edge, junction, and memory temperature,
   plus average active power.
7. Compare temperature rise per actual watt as well as absolute temperature;
   equal caps do not guarantee equal draw, and the card assemblies differ.

Interpret the result:

- Higher edge and memory rise per watt: weaker airflow through that card.
- Similar edge rise but larger `junction - edge`: suspect die paste, mounting
  pressure, or cold-plate contact.
- Larger `memory - edge`: suspect pad thickness or memory contact.
- Similar readings on both cards while both run too hot: improve total fan
  pressure, duct sealing, exhaust flow, or fan speed before changing the
  manifold split.

The original runs favored a total-flow limitation. The later equal-power run
added directional evidence of a weaker GPU1 branch while confirming that total
flow is still insufficient. HBM stayed well below its critical limit and
hotspot deltas were similar, so do not replace pads based on hotspot
temperature alone. Different MI50/MI60 board and cooler designs limit how
precisely the cards can be compared; treat one run as directional evidence,
not proof.

## 2026-08-15 fixed-fan matrix and power sweep

All new runs started at or below 45 C, used the same fixed seed and uncached
prompt, held the Noctua manifold fan at 100% (about 1,580--1,620 RPM), and
aborted at 95 C junction. Raw requests, responses, and half-second telemetry
are retained in `runs/2026-08-15-efficiency-matrix/`.

### Long matrix

| Caps GPU0/GPU1 | Workload | Outcome | Peak junction GPU0/GPU1 |
| ---: | --- | --- | ---: |
| 225/160 W | 32K PP | Aborted at cutoff | 96/88 C |
| 225/160 W | 2,048 TG | Aborted at cutoff | 95/94 C |
| 160/160 W | 32K PP | Aborted at cutoff | 91/95 C |
| 160/160 W | 2,048 TG | Aborted at cutoff | 89/95 C |
| 225/145 W | 32K PP | Aborted at cutoff | 95/84 C |
| 225/145 W | 2,048 TG | Aborted at cutoff | 97/90 C |
| 160/145 W | 32K PP | Completed, 282.83 tok/s | 91/91 C |
| 170/145 W | 32K PP | Completed, 283.65 tok/s | 94/92 C |

None of the prescribed reference, Profile A, or Profile B combinations is a
safe production winner. Fixed 100% fan already fails, so an earlier automatic
fan-curve ramp alone cannot solve the sustained cooling limit. The completed
32K results also show that a 300 PP tok/s target measured on 16K prompts does
not carry over to this longer prompt: raising GPU0 from 160 to 170 W changed
32K PP by only 0.3%.

### Manifold diagnosis

The equal-power `160/160 W` PP run began at GPU0/GPU1 edge temperatures of
42/42 C and peaked at 70/74 C. Active sampled power was nearly identical at
178.5/177.9 W, while both peak junction-to-edge deltas were 21 C. GPU1
therefore had about 4 C more edge rise at the same measured power without a
larger junction-to-edge delta. This is directional evidence of weaker bulk
airflow through GPU1's manifold branch, not worse die contact. Similar memory
behavior provides no reason to replace pads. Both branches still become too
hot, so total manifold pressure/flow is also insufficient.

Inspect the GPU1 branch for a smaller effective opening, tighter bend, leakage,
recirculation, or obstruction. Also verify that the 140 mm fan is a
pressure-optimized model and that the printed manifold is sealed to both card
inlets. A second fan, a higher-static-pressure fan, or independent branches is
more promising than changing thermal pads.

### Short PP and TG power boundary

The 16K PP sweep used the same prompt for every point:

| Caps GPU0/GPU1 | PP tok/s |
| ---: | ---: |
| 225/160 W | 297.57, 307.13 (302.35 mean) |
| 225/145 W | 305.23 |
| 210/145 W | 305.27 |
| 195/145 W | 304.68 |
| 180/145 W | 303.88 |
| 170/145 W | 303.08 |

GPU0 can be reduced to 170 W and GPU1 to 145 W while retaining greater than
300 PP tok/s on this 16K burst workload. That does not imply sustained 32K
performance or automatic-fan safety.

For fixed-seed 768-token TG with MTP depth 2:

| Caps GPU0/GPU1 | TG tok/s | Accepted/drafted |
| ---: | ---: | ---: |
| 170/145 W | 27.34 | 428/678 |
| 170/160 W | 28.66 | 424/685 |
| 180/160 W | 28.58 | 428/678 |
| 180/177 W | 28.62 | 424/685 |

Raising GPU1 from 145 to 160 W helped TG; raising GPU0 or raising GPU1 again to
177 W did not. MTP acceptance variance dominates the remaining spread. The two
earlier full-power TG runs averaged 28.80 tok/s despite one reaching 29.73, so
no tested cap reliably guarantees greater than 29 TG tok/s. `170/160 W` is the
lowest measured short-workload compromise, but it is not a validated
production profile and should not be persisted until cooling is improved and
the long automatic-fan/concurrency test passes.

## Final 100 C-limit validation

The operator accepted 100 C as the hard junction limit. The runner was changed
to sample every 0.2 seconds and cancel at 99 C to leave one degree for request
cancellation latency. The final comparison used fixed 100% manifold-fan speed.

`180/160 W` was the measured efficiency winner in the original single-fan
campaign:

| Test | Result | Peak junction GPU0/GPU1 |
| --- | ---: | ---: |
| 16K PP | 305.81 tok/s | 77/78 C |
| 768 TG, replicate 1 | 28.78 tok/s, 428/678 MTP | below cutoff |
| 768 TG, replicate 2 | 28.41 tok/s, 424/685 MTP | below cutoff |
| 32K PP | 288.83 tok/s | 98/96 C |
| 2,048 TG | 31.87 tok/s, 1,140/1,812 MTP | 96/97 C |
| Three concurrent 768 TG | 37.07 aggregate tok/s | 87/90 C maximum |

The 2,048-token run is the meaningful sustained TG result and clears the 29
tok/s target. Short 768-token rates are dominated more heavily by MTP
acceptance and setup behavior. Three-slot validation completed without an
abort; individual rates were 14.12, 11.45, and 11.51 tok/s.

The requested `200/165 W` comparison reached 300.33 PP and 28.64 TG tok/s. It
was slower than `180/160 W` in PP and indistinguishable in TG, so its extra 25 W
provides no measured benefit. It is not selected.

The fixed-fan long tests leave only 2--3 C of margin. The production
CoolerControl curve therefore retains quiet idle behavior but ramps earlier:

```text
31.1 C -> 30%
50.0 C -> 40%
60.0 C -> 60%
70.0 C -> 85%
75.0 C -> 96%
```

The requested `200/165 W`, fixed-96% alternative was then tested directly. Its
16K PP runs varied from 286.64 to 307.40 tok/s, while an earlier fixed-100% run
was 300.33 tok/s. More importantly, 32K PP reached the 99 C control cutoff
after 91.5 seconds and 2,048-token TG also reached 99 C before completion. Fan
speed fell only from about 1,590 to 1,565 RPM. This profile is rejected.

## Dual-fan manifold and production validation

A second Noctua 140 mm fan was added to the same PWM circuit and tested in all
three available manifold positions at `200/165 W` and fixed 96% duty. Position
1 was decisively best:

| Position | TG2048 peak | PP32 result |
| ---: | ---: | --- |
| 1 | 85/88 C | 290.03 tok/s, completed at 95/91 C |
| 2 | 87/90 C | cutoff after 96.8 s at 99/94 C |
| 3 | 90/92 C | cutoff after 97.4 s at 99/93 C |

With the new fan retained in position 1, the installed automatic curve and
`200/165 W` caps then completed TG2048 at 32.25 tok/s with 84/88 C peaks and
PP32 at 290.40 tok/s with 94/91 C peaks. This supersedes the rejected
single-fan `200/165 W` thermal result without erasing it.

The operator subsequently selected `210/170 W` for a final performance push.
`scripts/install-mi60-production-profile` now installs those caps, retains the
curve reaching and holding 96% at 75 C, and installs matching controller
restore defaults. It creates timestamped backups before modifying root-owned
files.

The automatic-curve A/B completed as follows:

| Caps | TG2048 | TG peak | PP32 | PP peak |
| ---: | ---: | ---: | ---: | ---: |
| 200/165 W | 32.25 tok/s | 84/88 C | 290.40 tok/s | 94/91 C |
| 210/170 W | 32.98 tok/s | 84/89 C | 290.36 tok/s | 97/92 C |

The higher caps improved the observed TG run by 2.3%, with slightly different
MTP acceptance, but did not improve PP32 and reduced GPU0 thermal margin by
3 C. The operator nevertheless retained `210/170 W` as the final production
choice.

# MI60 inference handoff

## State

- The production Docker container is intentionally stopped while the new
  Qwen context profile is staged.
- Qwen3.8-27B Q8_0 is configured for three slots sharing a 368,640-token
  unified KV pool; medium thinking and official samplers are defaults.
- The staged profile passed target + MTP + GPU mmproj loading and three
  concurrent requests with native-precision KV at batch 2048 / ubatch 1024. It
  left about 1.0 GiB free on GPU0 after that check and 825 MiB after the long
  benchmark. See
  [the unified-context run](runs/2026-08-16-qwen38-unified-context/README.md).
- The fixed-100%-fan matrix is complete. `225/160`, `160/160`, and `225/145 W`
  all reached the 95 C cutoff in both prescribed long workloads.
- The equal-power run showed about 4 C more edge rise on GPU1 at the same
  measured power, but the same junction-to-edge delta. This points to weaker
  airflow through GPU1's manifold branch, not paste or pad contact.
- A second Noctua 140 mm fan was added to the manifold. Position 1 was the
  clear winner: it completed PP32, while positions 2 and 3 reached the cutoff.
- The accepted hard limit is now 100 C; the runner cancels at 99 C and samples
  every 0.2 seconds.
- `180/160 W` remains the earlier efficiency winner: 305.81 tok/s on 16K PP,
  288.83 on 32K PP, and 31.87 on 2,048-token TG.
- Three concurrent 768-token requests completed at 37.07 aggregate tok/s and
  peaked at no more than 87/90 C with fixed 100% fan.
- With both fans in position 1 and the production automatic curve, `200/165 W`
  completed PP32 at 290.40 tok/s (94/91 C) and TG2048 at 32.25 tok/s
  (84/88 C).
- The `210/170 W` push completed TG2048 at 32.98 tok/s (84/89 C) and PP32 at
  290.36 tok/s (97/92 C). The operator selected it despite PP being flat.
- Detailed evidence is in [thermal-power.md](thermal-power.md).

## Next action

The repository's production profile is prepared for the selected `210/170 W`
caps and a 96% maximum automatic fan duty. Install it from the repository root:

```bash
sudo ./scripts/install-mi60-production-profile
```

This creates timestamped backups, installs 210/170 W boot and controller
restore defaults, and changes the saved manifold-fan curve to reach 96% at
75 C.

Keep the second fan in position 1. Do not replace pads based on current
evidence.

Raw data from this campaign is retained under
`mi60-inference/runs/2026-08-15-efficiency-matrix/`.

## Safety and scope

- Start at or below 45 C junction.
- Treat 100 C as the hard limit; automated tests cancel at 99 C.
- Change one variable at a time.
- The helper permits only bounded caps, manifold-fan 70--100%, status, restore,
  expiry, and revoke. It does not provide arbitrary root access.

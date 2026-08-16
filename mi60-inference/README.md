# MI60 inference knowledgebase

This is the master log for turning `mi60-server` into a fast, quiet, and
repeatable local inference server. Keep conclusions measured, commands safe,
and entries short.

## Current system

- GPUs: gfx906 card at `03:00.0` (210 W operator-selected production cap) plus
  gfx906 card at `87:00.0` (170 W selected cap; 178 W firmware maximum).
- Engine: custom `~/infer/mx-llama.cpp` build inside Docker.
- Runtime: current TheRock nightly with `device-gfx906`.
- Manager: Dockge stack `mi60-llamaswap`; API/UI at `http://localhost:8000`.
- Main profile: `qwen3.8-27b-q8_0-mtp2`, three slots sharing 261,888
  tokens, medium thinking, and MTP depth 2.
- Models: persistent host Hugging Face cache mounted at the standard container
  cache path.

See [operations.md](operations.md) for the few commands worth remembering and
[thermal-power.md](thermal-power.md) for cooling, clocks, and measured results.
The operations guide also documents a time-limited, narrowly scoped lab grant
for autonomous fan and power-cap testing.

For a fresh working context, start with [HANDOFF.md](HANDOFF.md).

## Prioritized idea log

| Priority | Idea | Why | Status |
| --- | --- | --- | --- |
| Done | Select combined PP/TG power profile | `180/160 W` reached 305.81 16K PP, 31.87 sustained TG, and passed three-slot fixed-fan validation | Measured 2026-08-15 |
| Done | Reject 200/165 W at 96% fan | Both 32K PP and 2,048 TG reached the 99 C control cutoff before completion | Measured 2026-08-15 |
| Done | Validate new automatic fan curve | Dual-fan position 1 at `200/165 W` completed 32K PP at 290.40 tok/s and TG2048 at 32.25 tok/s | Measured 2026-08-15 |
| Done | Place second manifold fan | Position 1 completed PP32; positions 2 and 3 both reached the 99 C cutoff | Measured 2026-08-15 |
| Done | Validate `210/170 W` push | TG2048 reached 32.98 tok/s; PP32 was flat at 290.36 tok/s and peaked at 97/92 C | Measured 2026-08-15 |
| Done | Keep GPU1 at 160 W | Two 177 W trials averaged 305.7 PP tok/s versus 305.8 at 160 W, with about 14 W more active sampled power | Measured 2026-08-15 |
| Done | Run fixed-fan matrix and equal-power diagnostic | No prescribed profile survived both long tests; evidence points to weaker GPU1-branch airflow plus insufficient total flow | Measured 2026-08-15 |
| Done | Find short PP power knee | `170/145 W` retained 303.08 tok/s for 16K PP, but 32K PP was only 283.65 tok/s | Measured 2026-08-15 |
| Done | Retest after manifold improvement | Position-1 automatic PP32 and TG2048 both completed at `200/165 W` | Measured 2026-08-15 |
| P1 | Compare auto clocks with max MCLK only | MCLK changes 800/1000 MHz during PP; fixed SCLK is likely wasteful | Planned |
| Done | Repeat TG with a fixed seed | Cap sweep ranged from 27.34 to 28.66 tok/s; more cap did not help and MTP acceptance remained the main source of spread | Measured 2026-08-15 |
| P2 | Investigate PCIe/all-reduce limits | Cards link at PCIe 3 x8 and PCIe 4 x4; tensor split synchronizes them | Backlog |
| Done | Compare Qwen3.8 Q8 MTP depth 2 versus 4 | Matched 1,024-token runs measured 30.04 versus 28.32 tok/s; depth 2 won by 6.1% | Measured 2026-08-15 |

When an experiment finishes, record the command, before/after throughput,
temperature, clocks, and power. Change one variable at a time.

## Current experiment

The dual-fan position-1 automatic baseline at `200/165 W` completed PP32 at
290.40 tok/s with 94/91 C peaks and TG2048 at 32.25 tok/s with 84/88 C peaks.
The operator then selected `210/170 W` with the same 96% maximum fan duty for
the final performance push. It produced 32.98 TG tok/s but PP32 remained flat
at 290.36 tok/s and peaked at 97/92 C. The maintained installer implements the
operator-selected caps exactly.

## Known-good design choices

- Docker owns the engine and ROCm runtime; stopping the container stops
  inference without losing model downloads.
- The custom build directory is selectable at image-build time.
- All live presets use llama.cpp `hf-repo` resolution; direct GGUF paths are
  reserved for explicitly approved diagnostics.
- Both cards use tensor split, direct I/O, PP2048 overlap, and BF16 transport.
- The fan controller watches the maximum edge, junction, and HBM temperature
  across both cards. That sensor selection is correct.

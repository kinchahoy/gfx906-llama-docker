# Qwen3.8 unified-context fit test

Tested 2026-08-16 on the dual-MI60 host with build 10279 (`46b95d97e`). The
production container remained stopped. Every disposable run held these options
constant:

- `-hf unsloth/Qwen3.8-27B-GGUF:Q8_0`, offline curated cache
- target, integrated MTP depth 2, and mmproj resident on `ROCm0,ROCm1`
- tensor split, flash attention, direct I/O, native-precision KV
- `--batch-size 2048 --ubatch-size 2048 --parallel 3 --kv-unified`
- medium reasoning and the documented Qwen samplers

`--ctx-size` is the unified KV capacity. Batch and ubatch were fixed performance
settings and did not determine context length. Since the model's training
context is 262,144, llama-server caps each individual slot at 262,144 while all
three slots compete for the configured shared pool.

## VRAM measurements

`rocm-smi --showmeminfo vram --showuse --showtemp --json` was captured after a
healthy full load and request processing. Each GPU reports 34,342,961,152 bytes
total (31.98 GiB).

| Unified context | GPU0 used | GPU1 used | GPU0 free | GPU1 free | Result |
| ---: | ---: | ---: | ---: | ---: | --- |
| 261,888 | 31,624,617,984 B | 30,422,802,432 B | 2,592.4 MiB | 3,738.6 MiB | Loaded; 3 concurrent requests passed |
| 288,000 | 33,041,412,096 B | 31,839,436,800 B | 1,241.3 MiB | 2,387.5 MiB | Loaded; 3 concurrent requests passed |
| 300,032 | 33,693,298,688 B | 32,491,450,368 B | 619.6 MiB | 1,765.7 MiB | Loaded; request passed, tight margin |
| 312,320 | 34,261,536,768 B | 33,171,443,712 B | 77.7 MiB | 1,117.2 MiB | Loaded; request passed, unsafe margin |
| 325,120 | 33,844,801,536 B | 33,836,445,696 B | 475.1 MiB | 483.1 MiB | Failed allocating 887.99 MiB for GPU mmproj |

The per-GPU split shifts slightly with allocator placement, but combined VRAM
growth is close to linear. Across the successful near-limit samples it is about
100--106 KiB per added context token in total. The 261,888 to 288,000
three-request measurements increased by 2,833,428,480 bytes over 26,112 tokens,
or 105.97 KiB/token.

Higher fixed-setting attempts failed before serving: 400,128, 450,048, and
500,224 could not reserve the GPU0 compute graph. Reducing batch/ubatch can
change graph workspace, but those are not context controls and doing so was
outside this test: the required tuned 2048/2048 values remained fixed.

## Decision

Use 288,000. It gives any single slot access to more than 200K tokens when the
shared pool is available, passes three-way concurrency, and preserves roughly
twice GPU0's margin at 300,032. It does not allow three simultaneous 200K
contexts; that would require at least a 600K shared pool, which does not fit
with this model, MTP, GPU mmproj, native KV, and the fixed performance settings.

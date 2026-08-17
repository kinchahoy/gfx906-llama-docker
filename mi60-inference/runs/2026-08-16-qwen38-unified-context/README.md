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

## Ubatch 1024 follow-up

The same stack was retested with logical batch held at 2048 and only ubatch
reduced to 1024. This changes physical graph workspace, not unified-context
semantics.

| Batch / ubatch | Unified context | GPU0 used | GPU1 used | GPU0 free | Result |
| ---: | ---: | ---: | ---: | ---: | --- |
| 2048 / 1024 | 325,120 | 31,262,539,776 B | 30,060,859,392 B | 2,937.7 MiB | Full GPU load passed |
| 2048 / 1024 | 368,640 | 33,272,406,016 B | 32,070,590,464 B | 1,021.0 MiB | Three concurrent requests passed |
| 2048 / 1024 | 384,000 | 33,916,641,280 B | 32,714,964,992 B | 406.6 MiB | Full GPU load passed; margin too tight |
| 2048 / 1024 | 400,128 | 34,248,560,640 B | 33,442,992,128 B | 90.0 MiB | Server started, but GPU mmproj graph allocation failed |

At 400,128, reducing logical batch to 1024 produced essentially identical VRAM
use and the same failed 248.10 MiB GPU mmproj graph allocation. Logical batch
therefore remains 2048.

The selected 368,640 run also completed the established 995-token prompt and
1,024-token output benchmark at 193.13 prompt tok/s and 30.68 generation tok/s,
with 596 of 853 draft tokens accepted. The earlier ubatch-2048 reference was
202.88 prompt tok/s and 30.04 generation tok/s. These are single runs, but they
show no material generation-rate penalty; prompt processing was 4.8% lower.
After this longer request, GPU0 had 825 MiB free and GPU1 had 1,899 MiB free.

## Decision

Use batch 2048, ubatch 1024, and 368,640 unified context. It gives any single
slot access to more than 200K tokens when the shared pool is available, passes
three-way concurrency and the long benchmark, and retains a practical GPU0
margin. It does not allow three simultaneous 200K
contexts; that would require at least a 600K shared pool, which does not fit
with this model, MTP, GPU mmproj, native KV, and the fixed performance settings.

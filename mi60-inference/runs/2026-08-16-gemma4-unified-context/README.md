# Gemma 4 31B-it unified-context fit test

Tested 2026-08-16 on the dual-MI60 host with build 10279 (`46b95d97e`). All
model artifacts came from the offline curated Hugging Face cache through:

```text
-hf unsloth/gemma-4-31B-it-GGUF:Q8_0
```

Both tests used tensor parallelism on `ROCm0,ROCm1`, flash attention, direct
I/O, logical batch 2048, ubatch 1024, three slots, unified KV, MTP depth 2, and
native KV precision. No direct model paths were used. The target Q8 weights,
HF-mapped Q8 MTP sidecar, and BF16 mmproj all loaded on the GPUs.

| Unified context | GPU0 used | GPU1 used | GPU0 free | Result |
| ---: | ---: | ---: | ---: | --- |
| 235,008 | 33,550,516,224 B | 32,193,241,088 B | 755.7 MiB | Three concurrent requests passed |
| 235,008 | 33,640,488,960 B | 32,407,511,040 B | 669.9 MiB | Long benchmark passed |
| 225,280 | 33,048,588,288 B | 31,691,313,152 B | 1,234.4 MiB | Three concurrent requests passed |

At the selected 235,008 setting, the established long request processed 1,072 prompt tokens at
189.95 tok/s and generated 1,024 tokens at 30.98 tok/s. MTP accepted 620 of 804
draft tokens (77.1%). It retained 756 MiB of GPU0 headroom after concurrency and
670 MiB after the long run, above the operator-approved half-GiB buffer. The
225,280 point remains documented as the more conservative alternative.

The pool is shared dynamically. Any one slot can grow to 235,008 tokens when
capacity is available, but three simultaneous 200K contexts would require at
least a 600K shared pool and do not fit. Gemma's template reports that reasoning
preservation is unsupported, so the configured `reasoning-preserve` option has
no effect for this model.

# Live model profiles

`llama-server-models.ini` is the single source of truth for the Docker router.
The Compose stack mounts it read-only at `/etc/mx-llama/models.ini`.

The catalog contains four cached weight sets and six selectable profiles:

| Request ID | Thinking | Context / parallelism |
| --- | --- | --- |
| `qwen3.8-27b-q8_0-mtp2` | medium (default) | 368,640 unified / 3 |
| `qwen3.8-27b-q8_0-mtp2-xhigh` | xhigh | 368,640 unified / 3 |
| `qwen3.8-27b-q8_0-mtp2-no-reasoning` | off | 368,640 unified / 3 |
| `gemma-4-31b-it-q8_0-mtp2` | on | 235,008 unified / 3 |
| `gpt-oss-120b-mxfp4-2x50k` | model default | 100,000 / 2 |
| `gpt-oss-20b-mxfp4-3x150k-tuned` | model default | 150,000 / 3 |

Qwen medium is the normal choice. The xhigh and no-reasoning IDs are
convenience profiles using the same weights, MTP configuration, and samplers.
Changing profile IDs can reload the worker. When Qwen is already loaded, a
request-level override is faster:

```json
{
  "model": "qwen3.8-27b-q8_0-mtp2",
  "chat_template_kwargs": {"reasoning_effort": "xhigh"}
}
```

Use `"reasoning_effort":"medium"` to return to the default. Use the dedicated
no-reasoning profile when thinking must be disabled. Qwen preserves prior
thinking across turns, and its samplers stay at temperature 1.0, top-p 0.95,
top-k 20, min-p 0, presence penalty 0, and repeat penalty 1.0 for both medium
and xhigh.

Qwen and Gemma use Unsloth Q8_0, tensor parallelism across `ROCm0,ROCm1`,
direct I/O, MTP depth 2, and three parallel slots. Qwen uses logical batch 2048,
ubatch 1024, and a 368,640-token unified KV pool. Each Qwen slot can grow as far
as the model's 262,144-token training limit when the shared pool has room; three simultaneous
200K conversations would still require at least 600K total capacity. Gemma uses
the same batch 2048, ubatch 1024, unified-KV, tensor-parallel approach with a
235,008-token shared pool. Its target, HF-mapped MTP sidecar, mmproj, and native
KV all remain GPU-resident. The GPT-OSS
profiles retain their measured, non-obvious settings exactly; their lower
context/concurrency values are deliberate VRAM/performance choices.

The Qwen pool was selected with target weights, integrated MTP, mmproj, and
native-precision KV all resident on the GPUs. Ubatch 1024 substantially reduces
graph workspace while keeping logical batch at 2048. A 384,000 pool loaded but
left only 406.6 MiB free on GPU0; 400,128 left only 90 MiB and failed a 248 MiB
GPU mmproj graph allocation. The selected 368,640 pool passed three concurrent
requests plus the standard 995-token/1,024-output benchmark. It left 1,021 MiB
free after the concurrency check and 825 MiB after the long benchmark.
Measurements and failed upper-bound tests are recorded in
[`../mi60-inference/runs/2026-08-16-qwen38-unified-context/README.md`](../mi60-inference/runs/2026-08-16-qwen38-unified-context/README.md).

Gemma also benefited from ubatch 1024. The selected 235,008-token unified pool
completed three concurrent requests and the long benchmark at 189.95 prompt
tok/s and 30.98 generation tok/s. It retained 756 MiB on GPU0 after concurrency
and 670 MiB after the long run, meeting the operator-approved half-GiB buffer.
See
[`../mi60-inference/runs/2026-08-16-gemma4-unified-context/README.md`](../mi60-inference/runs/2026-08-16-gemma4-unified-context/README.md).

Do not add `cache-type-*` options unless intentionally changing KV precision.
No cache type is configured, so target and draft KV use llama.cpp's native
default precision.

Every live profile uses `hf-repo`, the INI form of llama.cpp's `-hf` /
`--hf-repo` option. Do not use the INI `model` or `model-draft` keys, `-m`,
direct model URLs, or cache/snapshot paths unless the operator explicitly
approves an exception. With `spec-type = draft-mtp`, llama.cpp discovers and
maps the MTP companion from the selected Hugging Face repository.

## Offline curated cache

The normal Hugging Face cache can contain experiments and interrupted
downloads. The router does not scan it directly. Instead it uses the curated
`~/.cache/huggingface/mi60-router` cache index and starts with `--offline`.
Consequently, a request cannot silently download a model and only the four
approved weight sets appear in the router.

Build or refresh that index from complete files already in the normal cache:

```bash
./scripts/prepare-mi60-router-cache
./scripts/redeploy-container
```

The preparation script verifies that all four cached weight sets, both
multimodal projectors, and Gemma's MTP sidecar are complete. It hard-links
existing blobs, so model data is not duplicated. It does not remove the normal
cache or partial downloads, and it backs up an older curated index before
replacement.

To update a model deliberately, first populate the normal Hugging Face cache
with the desired revision using llama.cpp's `-hf` flow, including
`--spec-type draft-mtp` for Qwen or Gemma. Then rerun the two commands above.
The production router remains offline throughout normal use.

## Use the API

List the configured profiles and aliases:

```bash
./scripts/check-container
```

Send an OpenAI-compatible request using one of the request IDs in the table:

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gemma-4-31b-it-q8_0-mtp2",
    "messages": [{"role": "user", "content": "Say hello briefly."}],
    "max_tokens": 128
  }'
```

The router loads a requested profile on demand and keeps at most one worker in
VRAM. Switching weight sets—or switching between Qwen profile IDs—unloads the
previous worker. All files must already exist in the offline curated cache.

## Update configuration and runtime

After editing the profile INI, prepare the cache, validate Compose, and recreate
the container:

```bash
./scripts/prepare-mi60-router-cache
docker compose config --quiet
./scripts/redeploy-container
```

Recreation is intentional: an editor can atomically replace the INI while an
existing bind mount remains attached to its old inode. A plain container
restart can therefore continue using stale profiles.

To update the inference engine or TheRock runtime, run `./scripts/build-image`
and then the deploy sequence. Cached downloads are not deleted by either
operation. `redeploy-container` detects the production Dockge project and
recreates it through its owning stack; it refuses to replace a container owned
by an unexpected Compose project.

The full pre-cleanup catalogs are retained in
`archive/configs/2026-08-15-pre-four-model-cleanup/`.

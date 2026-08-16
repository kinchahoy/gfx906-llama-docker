# Live model presets

`llama-server-models.ini` is the single source of truth for the Docker router.
The Compose stack mounts it read-only at `/etc/mx-llama/models.ini`.

The catalog intentionally contains four presets:

- `REC-qwen3.8-27b-q8_0-mtp2`
- `REC-gemma-4-31b-it-q8_0-mtp2`
- `REC-gpt-oss-120b-mxfp4-2x50k`
- `gpt-oss-20b-mxfp4-3x150k-tuned`

Qwen and Gemma both use Unsloth Q8_0, tensor parallelism across `ROCm0,ROCm1`,
direct I/O, 2048 batch/ubatch, MTP depth 2, three parallel slots, and a 261,888
token shared context pool. The two GPT-OSS profiles retain their measured
settings exactly; their lower context/concurrency values are deliberate
VRAM/performance choices.

Do not add `cache-type-*` options unless intentionally changing KV precision.
No cache type is configured today, so target and draft KV use llama.cpp's native
default precision.

Every live model must use `hf-repo`, the INI form of llama.cpp's `-hf` /
`--hf-repo` option. Do not use `model`, `model-draft`, `-m`, direct model URLs,
or direct cache/snapshot paths unless the operator explicitly approves an
exception. With `spec-type = draft-mtp`, llama.cpp discovers and maps the MTP
companion provided by the selected Hugging Face repository.

## Use the API

List the four configured presets (cached Hub models are reported separately):

```bash
./scripts/check-container
```

Send an OpenAI-compatible request by selecting one preset ID:

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "REC-gemma-4-31b-it-q8_0-mtp2",
    "messages": [{"role": "user", "content": "Say hello briefly."}],
    "max_tokens": 128
  }'
```

The router loads the requested preset on demand and keeps at most one model in
VRAM. Switching model IDs unloads the previous worker; downloaded files remain
in the mounted Hugging Face cache.

## Update models and runtime

The two Q8 selectors are:

```ini
hf-repo = unsloth/Qwen3.8-27B-GGUF:Q8_0
hf-repo = unsloth/gemma-4-31B-it-GGUF:Q8_0
```

The [Unsloth Gemma repository](https://huggingface.co/unsloth/gemma-4-31B-it-GGUF)
provides both the Q8_0 target and its MTP companion. Do not insert either
filename or a file URL into the preset: llama.cpp resolves both from `hf-repo`
and `spec-type = draft-mtp`. The first request after a Hub update can download
tens of gigabytes, so expect a long cold start and watch progress with
`docker logs -f gfx906-llama-docker`.

After editing, check the Compose configuration and deploy with:

```bash
docker compose config --quiet
./scripts/redeploy-container
```

To change a repository or quantization, edit only its `hf-repo` selector, then
run the deploy sequence above. To update the inference engine or
TheRock runtime, run `./scripts/build-image` and then
`./scripts/redeploy-container`. For rollback, restore the prior `hf-repo` line
or rebuild with the previously recorded TheRock version, redeploy, and repeat
the smoke request. Cached downloads are not deleted by either operation.

After an update, smoke-test the models individually. Each request can unload the
previous model and may initiate a large Hub download:

```bash
for model_id in \
  REC-qwen3.8-27b-q8_0-mtp2 \
  REC-gemma-4-31b-it-q8_0-mtp2 \
  REC-gpt-oss-120b-mxfp4-2x50k \
  gpt-oss-20b-mxfp4-3x150k-tuned
do
  curl --fail-with-body --silent --show-error \
    http://127.0.0.1:8000/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${model_id}\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with OK.\"}],\"max_tokens\":16}" \
    | jq -e '.object == "chat.completion" and .usage.completion_tokens > 0'
done
```

Recreation is intentional: editors may atomically replace the INI, while an
existing bind mount remains attached to its old inode. A plain container restart
can therefore continue using stale presets.

`redeploy-container` detects the production Dockge project used on this host and
recreates it through the owning stack. If no container exists, it uses this
repository's Compose file. It refuses to replace a container owned by any other
Compose project.

The full pre-cleanup catalogs are retained in
`archive/configs/2026-08-15-pre-four-model-cleanup/`.

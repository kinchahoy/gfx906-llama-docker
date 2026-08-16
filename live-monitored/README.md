# Live model presets

`llama-server-models.ini` is the single source of truth for the Docker router.
The Compose stack mounts it read-only at `/etc/mx-llama/models.ini`.

The catalog intentionally contains four presets:

- `REC-qwen3.8-27b-q8_0-mtp2`
- `REC-gemma-4-31b-it-ud-q5_k_xl-mtp2`
- `REC-gpt-oss-120b-mxfp4-2x50k`
- `gpt-oss-20b-mxfp4-3x150k-tuned`

Qwen and Gemma use MTP depth 2, three parallel slots, and a 256K-class shared
context pool. The two GPT-OSS profiles retain their measured settings exactly;
their lower context/concurrency values are deliberate VRAM/performance choices.

Do not add `cache-type-*` options unless intentionally changing KV precision.
No cache type is configured today, so target and draft KV use llama.cpp's native
default precision.

After editing, validate and deploy with:

```bash
./scripts/check-model-presets
docker compose config --quiet
./scripts/redeploy-container
```

Qwen and Gemma use explicit snapshot paths in the mounted Hugging Face cache.
This prevents a moving Hub revision from silently replacing tens of gigabytes
at service startup. To update either model, download the desired model and MTP
sidecar into the host cache, update both snapshot paths together, run the
validator, recreate the container, and send a short test request. Keep the old
snapshot paths until that request succeeds so rollback is one INI edit.

Recreation is intentional: editors may atomically replace the INI, while an
existing bind mount remains attached to its old inode. A plain container restart
can therefore continue using stale presets.

`redeploy-container` detects the production Dockge project used on this host and
recreates it through the owning stack. If no container exists, it uses this
repository's Compose file. It refuses to replace a container owned by any other
Compose project.

The full pre-cleanup catalogs are retained in
`archive/configs/2026-08-15-pre-four-model-cleanup/`.

# gfx906 mx-llama.cpp container

Run a local `mx-llama.cpp` HIP build on MI50/MI60 inside a Docker container. The image installs the latest TheRock nightly runtime for `gfx906`, copies an existing CMake build into the image, and runs `llama-server` in native router mode.

The inference engine and ROCm runtime live in the image. Only model caches and the router preset are mounted from the host, so Docker remains the start, stop, and restart boundary.

Operational findings, tuning experiments, and the prioritized improvement log
live in the [`mi60-inference` knowledgebase](mi60-inference/README.md).

## Build

The default build directory is `~/infer/mx-llama.cpp/build`:

```bash
./scripts/build-image
```

Point at any other compatible CMake build directory:

```bash
./scripts/build-image ~/infer/another-llama.cpp/build
```

The directory must contain `CMakeCache.txt` and `bin/llama-server`. The helper rejects builds without HIP and `gfx906`, records the llama.cpp revision in the image, installs the latest TheRock nightly, and verifies the resulting binaries.

Set `THEROCK_VERSION` only when a nightly needs to be rolled back:

```bash
THEROCK_VERSION=10.1.0a20260807 ./scripts/build-image
```

Other useful overrides:

```bash
IMAGE_NAME=my-local/mx-llama:gfx906 ./scripts/build-image /path/to/build
```

## Run locally

```bash
cp .env.example .env
docker compose up -d
./scripts/check-container
```

The API and Web UI listen on `http://localhost:8000`. Router mode automatically loads the requested preset and keeps at most one model loaded, unloading the least-recently-used model when another is requested.

Model definitions live in [`live-monitored/llama-server-models.ini`](live-monitored/llama-server-models.ini). Requests select a preset through the OpenAI-compatible `model` field.

The live catalog is intentionally limited to Qwen3.8 27B Q8_0 with MTP,
Gemma 4 31B-it Q8_0 with MTP, and the measured GPT-OSS 120B and 20B
profiles. See [`live-monitored/README.md`](live-monitored/README.md) for the
model IDs, conventions, and update procedure. Keep every live preset on
`hf-repo` and leave KV-cache precision native unless the operator explicitly
approves an exception.

Preset edits require container recreation, not merely restart, because an
atomic editor save can replace the bind-mounted file's inode:

```bash
./scripts/redeploy-container
```

The helper detects the Dockge-owned production stack on this host, otherwise
uses the repository Compose file, then runs the container health check.

`REC-qwen3.8-27b-q8_0-mtp2` mirrors the validated two-MI60 launch in
`~/infer/QWEN38_GFX906_QUICKSTART.md`: Hugging Face Q8_0, tensor split, direct I/O,
2048 batch/ubatch, and integrated MTP speculative decoding at depth 2. The
Docker preset expands the guide's benchmark context to a native 256K total
pool shared by three parallel request slots. It allocates 261,888 tokens—the
largest three-way/256-token-aligned value below 262,144—providing 87,296 tokens
per slot without llama.cpp rounding above the model's native limit. The live
catalog always uses `hf-repo`; direct model paths and `-m` are prohibited unless
the operator explicitly approves an exception. Its runtime environment enables internal all-reduce and the private
gfx906 PP2048 overlap optimization. BF16 overlap transport is faster but is a
small precision tradeoff; set `GGML_CUDA_TP_OVERLAP=0` and
`GGML_CUDA_TP_OVERLAP_BF16=0` to retain the normal F32 path.

Thinking is enabled by default at `reasoning_effort=medium`, with preserved
thinking across turns. The preset uses Qwen's thinking-mode samplers:
temperature 1.0, top-p 0.95, top-k 20, min-p 0, presence penalty 0, and repeat
penalty 1.0. Clients can still override reasoning effort or disable thinking
per request through `chat_template_kwargs`.

## Dockge on mi60-server

The live Dockge container exposes port 5005 and mounts this host directory as `/opt/stacks`:

```text
/home/raistlin/docker-space/systemsandinfo/homenet-stacks/mi60-stacks
```

The installed stack is:

```text
mi60-llamaswap/
  compose.yaml
  .env
```

Dockge only controls the already-built local image. It does not need access to `LLAMA_BUILD_DIR`, which may be anywhere on the host. To change inference builds:

1. Run `./scripts/build-image /new/build/directory`.
2. In Dockge, redeploy the `mi60-llamaswap` stack to recreate the container from the refreshed local image.

The stack uses `pull_policy: never` so Dockge cannot replace the custom local image with a registry image.

## Persistent data

The container mounts:

- `~/.cache/huggingface` at the standard Hugging Face cache location. `--hf-repo`
  reuses existing snapshots and stores new downloads here.
- `~/.cache/llama.cpp` at the legacy llama.cpp cache location.
- The router INI read-only at `/etc/mx-llama/models.ini`.

GPU access is passed through with `/dev/kfd`, `/dev/dri`, video GID 44, and render GID 992.

## Lifecycle

```bash
docker stop gfx906-llama-docker
docker start gfx906-llama-docker
docker restart gfx906-llama-docker
docker logs -f gfx906-llama-docker
```

Stopping the container terminates the router and all model workers. Model downloads remain in the host cache.

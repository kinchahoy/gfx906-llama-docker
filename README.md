# rocm-docker-llama

Run `llama-server` on AMD MI50/MI60 (`gfx906`) using a Docker image that bundles `llama-swap` and patched ROCm `rocblas` Tensile libraries.

## What This Image Does

- Builds `llama-swap` from source in a build stage.
- Uses `rocm/llama.cpp` as the ROCM base.
- Copies the local `llama.cpp/build/bin` binaries into `/home/llama/bin`.
- Installs `gfx906` rocBLAS library files from `./rocblas-lib-gfx906/` into `/opt/rocm/lib/rocblas/library/`.
- Starts `llama-swap`, which launches `llama-server` from config (`live-monitored/llama-swap-config.yml`)

## Quick Start

Clone this repo:

```bash
git clone https://github.com/kinchahoy/rocm-docker-llama
cd rocm-docker-llama
```

Clone a `gfx906` optmized version of `llama.cpp` into a directory named `llama.cpp`.

- Ideally use the OG fork that has new capabilities added from time to time: [iacopPBK/llama.cpp-gfx906](https://github.com/iacopPBK/llama.cpp-gfx906)
- Occasionally I have a more up to date merge of iacopPBK's work with llama.cpp head (e.g. for Qwen 3.5 support as of Feb 2026): [kinchahoy/llama.cpp `gfx906-rebased-2026-02-24`](https://github.com/kinchahoy/llama.cpp/tree/gfx906-rebased-2026-02-24)

Build the `gfx906` fork (usually `llama.cpp/SCRIPT_compile_MI50.sh` from the forks will work. I assume you've got ROCM 7.1 etc. setup already).

Then:

1. Edit [`live-monitored/llama-swap-config.yml`](./live-monitored/llama-swap-config.yml) for your models and routes.
1a. I have GPT-OSS-120B and some Qwen 3.5 models nicely setup for 2x MI50s/60s in there

2. Build and run:

```bash
docker build -t kinchahoy/llama-gfx906-swap .
docker compose up -d
```

## Runtime Notes

- API endpoint: `http://localhost:8000`
- Required GPU devices passed through: `/dev/kfd` and `/dev/dri`.
- Model/cache mounts are from `~/.cache/llama.cpp`.
- Llama swap config comes from `live-monitored/llama-swap-config.yml`.

## Update Cycle

After recompiling `llama.cpp` binaries, `rocblas-lib-gfx906`, or config:

```bash
docker build -t kinchahoy/llama-gfx906-swap .
docker compose up -d
```

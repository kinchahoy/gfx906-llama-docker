# syntax=docker/dockerfile:1.7

########################
# Stage 1: build llama-swap (Go)
########################
FROM golang:latest AS swap-builder
WORKDIR /src

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs npm make ca-certificates git && \
    rm -rf /var/lib/apt/lists/*

ARG LLAMA_SWAP_REF=main

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/.npm \
    git clone https://github.com/mostlygeek/llama-swap.git . && \
    git checkout "${LLAMA_SWAP_REF}" && \
    make clean all

RUN ls -l /src/build && /src/build/llama-swap-linux-amd64 --version

########################
# Final runtime (starting from the ROCm llama.cpp base, but ignoring it's /app install)
########################
FROM rocm/llama.cpp:llama.cpp-b6652.amd0_rocm7.0.0_ubuntu24.04_full

ENV LLAMA_HOME=/home/llama \
    LLAMA_BIN=/home/llama/bin \
    LLAMA_SWAP_CONFIG=/home/llama/services/llama-swap/config.yml \
    PATH=/home/llama/bin:$PATH \
    # Add LLAMA_BIN to LD_LIBRARY_PATH so the .so files copied into bin/ are found
    LD_LIBRARY_PATH=/home/llama/bin:$LD_LIBRARY_PATH \
    PORT=8000 \
    LLAMA_EXEC=/home/llama/bin/llama-server \
    LLAMA_OPTS=

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends libomp5 ca-certificates curl tini libmkl-rt && \
    rm -rf /var/lib/apt/lists/*

# Probably not needed anymore given we run as root
    RUN useradd -m -u 10001 -s /bin/bash llama && \
    install -d -o llama -g llama \
      ${LLAMA_BIN} \
      /home/llama/services/llama-swap \
      /home/llama/models \
      /home/llama/logs \
      /home/llama/work

COPY --chown=llama:llama llama.cpp/build/bin/ ${LLAMA_BIN}/
# Got to pick the right binary
COPY --from=swap-builder /src/build/llama-swap-linux-amd64 ${LLAMA_BIN}/llama-swap
RUN chown llama:llama ${LLAMA_BIN}/llama-swap && chmod 0755 ${LLAMA_BIN}/llama-swap

COPY --chown=llama:llama llama-swap-config.yml ${LLAMA_SWAP_CONFIG}
COPY --chown=root:root rocblas-lib-gfx906/ /opt/rocm/lib/rocblas/library/

# Live as root to simplify gpu visibility
ENV HOME=/root

WORKDIR /home/llama/work

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/usr/bin/tini","--","/home/llama/bin/llama-swap"]
CMD ["--listen","0.0.0.0:8000","--config","/home/llama/services/llama-swap/config.yml","--","/home/llama/bin/llama-server"]

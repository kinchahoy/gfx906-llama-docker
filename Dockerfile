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

# Add LLAMA_BIN to LD_LIBRARY_PATH so the .so files copied into bin/ are found
ENV LLAMA_HOME=/home/llama \
    LLAMA_BIN=/home/llama/bin \
    LLAMA_SWAP_CONFIG=/home/llama/services/llama-swap/config.yml \
    PATH=/home/llama/bin:$PATH \
    LD_LIBRARY_PATH=/home/llama/bin:$LD_LIBRARY_PATH \
    PORT=8000 \
    LLAMA_EXEC=/home/llama/bin/llama-server \
    LLAMA_OPTS= \
    HOME=/home/llama

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends libomp5 ca-certificates curl tini libmkl-rt && \
    rm -rf /var/lib/apt/lists/*

# Create llama user with UID 1000, or use existing if ID 1000 is taken
RUN if ! getent group 1000; then groupadd -g 1000 llama; else groupadd -f llama; fi && \
    if ! getent passwd 1000; then useradd -m -u 1000 -g 1000 -s /bin/bash llama; else useradd -m -g 1000 -s /bin/bash llama || true; fi && \
    install -d -o 1000 -g 1000 \
      ${LLAMA_BIN} \
      /home/llama/services/llama-swap \
      /home/llama/models \
      /home/llama/logs \
      /home/llama/work \
      /home/llama/.cache

# Copy binaries and set ownership
COPY --chown=1000:1000 llama.cpp/build/bin/ ${LLAMA_BIN}/
COPY --from=swap-builder --chown=1000:1000 /src/build/llama-swap-linux-amd64 ${LLAMA_BIN}/llama-swap
RUN chmod 0755 ${LLAMA_BIN}/llama-swap

# ROCm libraries usually need to stay in /opt/rocm, but we ensure they are readable
COPY --chown=root:root rocblas-lib-gfx906/ /opt/rocm/lib/rocblas/library/

USER 1000
WORKDIR /home/llama/work

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/usr/bin/tini","--","/home/llama/bin/llama-swap"]
CMD ["--listen","0.0.0.0:8000","--config","/home/llama/services/llama-swap/config.yml","--","/home/llama/bin/llama-server"]

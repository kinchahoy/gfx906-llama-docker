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
# Renamed PORT to LLAMA_SERVICE_PORT to avoid conflict with llama-swap's ${PORT} token
ENV LLAMA_HOME=/home/llama \
    LLAMA_BIN=/home/llama/bin \
    LLAMA_SWAP_CONFIG=/home/llama/services/llama-swap/config.yml \
    PATH=/home/llama/bin:$PATH \
    LD_LIBRARY_PATH=/home/llama/bin:$LD_LIBRARY_PATH \
    LLAMA_SERVICE_PORT=8000 \
    LLAMA_EXEC=/home/llama/bin/llama-server \
    LLAMA_OPTS= \
    HOME=/home/llama

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends libomp5 libomp-dev ca-certificates curl tini libmkl-rt && \
    rm -rf /var/lib/apt/lists/* &&  \
    ln -sf /usr/lib/x86_64-linux-gnu/libomp.so.5 /usr/lib/x86_64-linux-gnu/libomp.so
    #create a link so libomp is found

# Remove existing ubuntu user if present to free up UID 1000.
# Re-create render group with GID 992 to match host permissions for /dev/kfd.
# Create llama user (UID 1000) and add to video/render.
RUN if id -u ubuntu >/dev/null 2>&1; then userdel -r ubuntu; fi && \
    if getent group ubuntu >/dev/null 2>&1; then groupdel ubuntu; fi && \
    if getent group render >/dev/null 2>&1; then groupdel render; fi && \
    groupadd -g 992 render && \
    groupadd -g 1000 llama && \
    useradd -m -u 1000 -g 1000 -s /bin/bash llama && \
    usermod -aG video llama && \
    usermod -aG render llama && \
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

# Ensure all files in home are owned by llama
# Also chown tini as requested
RUN chown -R 1000:1000 /home/llama && \
    chown 1000:1000 /usr/bin/tini

# ROCm libraries usually need to stay in /opt/rocm, but we ensure they are readable
COPY --chown=root:root rocblas-lib-gfx906/ /opt/rocm/lib/rocblas/library/

USER 1000
WORKDIR /home/llama/work

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${LLAMA_SERVICE_PORT}/health" || exit 1

ENTRYPOINT ["/usr/bin/tini","--","/home/llama/bin/llama-swap"]
CMD ["--listen","0.0.0.0:8000","--config","/home/llama/services/llama-swap/config.yml","--","/home/llama/bin/llama-server"]

# syntax=docker/dockerfile:1.7

FROM ghcr.io/astral-sh/uv:latest AS uv

FROM ubuntu:26.04

ARG THEROCK_REFRESH=manual
ARG THEROCK_VERSION=
ARG LLAMA_BUILD_REVISION=unknown

LABEL org.opencontainers.image.title="gfx906 mx-llama.cpp" \
      org.opencontainers.image.description="mx-llama.cpp router with TheRock nightly runtime for MI50/MI60" \
      org.opencontainers.image.revision="${LLAMA_BUILD_REVISION}"

COPY --from=uv /uv /usr/local/bin/uv

RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    mkdir -p /var/cache/apt/archives/partial && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      libomp5 \
      libssl3t64 \
      python3 \
      python3-venv \
      tini && \
    rm -rf /var/lib/apt/lists/*

# THEROCK_REFRESH intentionally invalidates only this layer. The build helper
# changes it for every build so an unpinned install always checks the nightly index.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv --python /usr/bin/python3 /opt/therock && \
    if [ -n "${THEROCK_VERSION}" ]; then \
      therock_spec="rocm[libraries,device-gfx906]==${THEROCK_VERSION}"; \
    else \
      therock_spec="rocm[libraries,device-gfx906]"; \
    fi && \
    echo "TheRock refresh: ${THEROCK_REFRESH}" && \
    uv pip install \
      --python /opt/therock/bin/python \
      --index-url https://rocm.nightlies.amd.com/whl-multi-arch/ \
      --prerelease allow \
      --link-mode copy \
      --upgrade \
      "${therock_spec}" && \
    site_packages="$(/opt/therock/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" && \
    ln -s "${site_packages}/_rocm_sdk_core" /opt/rocm-core && \
    ln -s "${site_packages}/_rocm_sdk_libraries" /opt/rocm-libraries && \
    /opt/therock/bin/python -c 'from importlib.metadata import version; print(version("rocm"))' > /opt/therock/VERSION

ENV HOME=/home/llama \
    PATH=/opt/mx-llama/bin:/opt/rocm-core/bin:/opt/therock/bin:$PATH \
    LD_LIBRARY_PATH=/opt/mx-llama/bin:/opt/rocm-libraries/lib:/opt/rocm-core/lib:/opt/rocm-core/lib/llvm/lib:/opt/rocm-core/lib/rocm_sysdeps/lib \
    ROCM_PATH=/opt/rocm-core \
    HIP_PATH=/opt/rocm-core \
    HIP_DEVICE_LIB_PATH=/opt/rocm-core/lib/llvm/amdgcn/bitcode \
    ROCBLAS_USE_HIPBLASLT=0 \
    HF_HOME=/home/llama/.cache/huggingface

# llama_build is a BuildKit named context. Point it at any CMake build directory
# containing bin/ with scripts/build-image or LLAMA_BUILD_DIR in Compose.
COPY --from=llama_build --chown=1000:1000 /bin/ /opt/mx-llama/bin/

RUN test -x /opt/mx-llama/bin/llama-server && \
    ldd /opt/mx-llama/bin/llama-server > /tmp/llama-server.ldd && \
    ! grep -q 'not found' /tmp/llama-server.ldd && \
    /opt/mx-llama/bin/llama-server --version && \
    rm /tmp/llama-server.ldd

RUN if getent passwd 1000 >/dev/null; then userdel --remove "$(getent passwd 1000 | cut -d: -f1)"; fi && \
    if ! getent group video >/dev/null; then groupadd --gid 44 video; fi && \
    if ! getent group render >/dev/null; then groupadd --gid 992 render; fi && \
    if getent group 1000 >/dev/null; then \
      groupmod --new-name llama "$(getent group 1000 | cut -d: -f1)"; \
    else \
      groupadd --gid 1000 llama; \
    fi && \
    useradd --uid 1000 --gid 1000 --groups video,render --create-home --shell /bin/bash llama && \
    install -d -o llama -g llama \
      /home/llama/.cache/huggingface \
      /home/llama/.cache/llama.cpp

USER llama
WORKDIR /home/llama

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8000/health || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/mx-llama/bin/llama-server"]
CMD ["--host", "0.0.0.0", "--port", "8000", "--offline", "--models-preset", "/etc/mx-llama/models.ini", "--models-max", "1", "--models-autoload"]

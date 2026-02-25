#!/usr/bin/env bash
set -euo pipefail

# inside-container mount of host source dir
HOST_DIR="/host-opt-rocm-lib"
# destination inside container (same path as image)
DEST="/opt/rocm/lib/rocblas/library"

echo "[entrypoint] starting pre-launch copy step"

# If mounted, copy only files with 'gfx906' in the filename
if [ -d "$HOST_DIR" ]; then
  echo "[entrypoint] found host dir: $HOST_DIR"
  shopt -s nullglob
  matches=("$HOST_DIR"/*gfx906*)
  if [ ${#matches[@]} -gt 0 ]; then
    echo "[entrypoint] copying ${#matches[@]} gfx906 file(s) -> $DEST"

    # create safe temp staging inside DEST so move into place is atomic-ish
    mkdir -p "$DEST"
    TMP_STAGING="$(mktemp -d "${DEST}/.tmp_rocm_gfx906.XXXXXX")"

    # copy preserving mode, timestamps, xattrs where possible
    for src in "${matches[@]}"; do
#      echo "[entrypoint] copying: $src"
      cp -a -- "$src" "$TMP_STAGING"/
    done

    # move staged files into final destination (overwrite same names)
    for f in "$TMP_STAGING"/*; do
      mv -f -- "$f" "$DEST"/
    done

    # remove staging dir
    rmdir "$TMP_STAGING" || true
    echo "[entrypoint] copy complete"
  else
    echo "[entrypoint] no gfx906 files found in $HOST_DIR; skipping copy"
  fi
else
  echo "[entrypoint] host dir $HOST_DIR not present (not mounted); skipping copy"
fi

# Check for openmp
echo "checking for libomp5"
apt update
apt-get install -y libomp5


# If LLAMA_OPTS env var set, use it (shell expands quoted args inside LLAMA_OPTS)
  echo "Using LLAMA_EXEC and LLAMA_OPTS settings"
  echo $LLAMA_EXEC
  echo $LLAMA_OPTS
  exec bash -lc "$LLAMA_EXEC $LLAMA_OPTS"



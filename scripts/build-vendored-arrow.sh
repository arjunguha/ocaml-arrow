#!/usr/bin/env bash
# Build Apache Arrow C++ from vendor/apache-arrow (git submodule) and install
# shared libraries + headers under vendor/arrow-install (ignored by git).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARROW_CPP="${ROOT}/vendor/apache-arrow/cpp"
BUILD_DIR="${ROOT}/vendor/arrow-build"
INSTALL_DIR="${ROOT}/vendor/arrow-install"

if [[ ! -f "${ARROW_CPP}/CMakeLists.txt" ]]; then
  echo "Missing ${ARROW_CPP}. Initialize submodules: git submodule update --init --recursive" >&2
  exit 1
fi

JOBS="${ARROW_BUILD_JOBS:-}"
if [[ -z "${JOBS}" && -n "${OPAMJOBS:-}" ]]; then
  JOBS="${OPAMJOBS}"
fi
if [[ -z "${JOBS}" ]]; then
  JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

# Invalidate CMake build dir when the project root moves (e.g. opam path pin copies the tree).
MARKER="${BUILD_DIR}/.arrow_ocaml_root"
if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]]; then
  if [[ ! -f "${MARKER}" ]] || [[ "$(<"${MARKER}")" != "${ROOT}" ]]; then
    rm -rf "${BUILD_DIR}"
  fi
fi

cmake -S "${ARROW_CPP}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DARROW_BUILD_SHARED=OFF \
  -DARROW_BUILD_STATIC=ON \
  -DARROW_DEPENDENCY_USE_SHARED=OFF \
  -DARROW_BROTLI_USE_SHARED=OFF \
  -DARROW_LZ4_USE_SHARED=OFF \
  -DARROW_SNAPPY_USE_SHARED=OFF \
  -DARROW_ZSTD_USE_SHARED=OFF \
  -DARROW_COMPUTE=OFF \
  -DARROW_CSV=ON \
  -DARROW_DATASET=OFF \
  -DARROW_FILESYSTEM=OFF \
  -DARROW_JSON=ON \
  -DARROW_PARQUET=ON \
  -DARROW_IPC=ON \
  -DARROW_WITH_SNAPPY=ON \
  -DARROW_WITH_ZLIB=ON \
  -DARROW_WITH_ZSTD=ON \
  -DARROW_WITH_LZ4=ON \
  -DARROW_WITH_BROTLI=ON \
  -DARROW_DEPENDENCY_SOURCE=BUNDLED

cmake --build "${BUILD_DIR}" --parallel "${JOBS}"
rm -rf "${INSTALL_DIR}"
cmake --install "${BUILD_DIR}"
printf '%s\n' "${ROOT}" > "${MARKER}"

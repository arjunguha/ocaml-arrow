#!/usr/bin/env sh
set -eu

# Linker flags as a dune list for statically linking the vendored Arrow C++
# libraries and their bundled third-party dependencies.
if test "$#" -gt 0; then
  root="$1"
else
  root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
fi

if ! test -d "$root/vendor/arrow-install/lib/pkgconfig"; then
  case "$(pwd)" in
  */_build/*)
    workspace_root="${PWD%%/_build/*}"
    if test -d "$workspace_root/vendor/arrow-install/lib/pkgconfig"; then
      root="$workspace_root"
    fi
    ;;
  esac
fi
libdir="$root/vendor/arrow-install/lib"
pcdir="$libdir/pkgconfig"

if ! command -v pkg-config >/dev/null 2>&1; then
  echo "pkg-config is required to generate Arrow static link flags" >&2
  exit 1
fi

pkg_config_flags="$(PKG_CONFIG_PATH="$pcdir${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
  pkg-config --libs --static parquet arrow)"

printf '('
if test -n "${OPAM_SWITCH_PREFIX:-}"; then
  printf ' "-L%s/lib/stublibs"' "$OPAM_SWITCH_PREFIX"
elif command -v opam >/dev/null 2>&1; then
  stublibs="$(opam var stublibs 2>/dev/null || true)"
  if test -n "$stublibs"; then
    printf ' "-L%s"' "$stublibs"
  fi
fi

for flag in $pkg_config_flags; do
  # Force the Arrow libraries to be archives. pkg-config emits -l...; if
  # shared libraries are present or installed later, downstream OCaml
  # executables should still link the vendored static archives.
  case "$flag" in
  -lparquet) flag="-l:libparquet.a" ;;
  -larrow) flag="-l:libarrow.a" ;;
  -larrow_bundled_dependencies) flag="-l:libarrow_bundled_dependencies.a" ;;
  esac
  printf ' "%s"' "$flag"
done
printf ' )\n'

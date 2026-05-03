#!/usr/bin/env sh
set -eu

# Linker flags as a dune list (for use with (:include ...) in c_library_flags).
flags=

case "$(uname -s)" in
Darwin*) flags='"-Wl,-rpath,@loader_path"' ;;
*) flags='"-Wl,-rpath,$ORIGIN"' ;;
esac

if test -n "${OPAM_SWITCH_PREFIX:-}"; then
  stublibs="$OPAM_SWITCH_PREFIX/lib/stublibs"
  flags="$flags \"-L$stublibs\" \"-Wl,-rpath,$stublibs\""
elif command -v opam >/dev/null 2>&1; then
  stublibs="$(opam var stublibs 2>/dev/null || true)"
  if test -n "$stublibs"; then
    flags="$flags \"-L$stublibs\" \"-Wl,-rpath,$stublibs\""
  fi
fi

printf '(%s)\n' "$flags"

#!/usr/bin/env sh
# Single linker flag as a dune string (for use with (:include ...) in c_library_flags).
case "$(uname -s)" in
Darwin*) printf '%s\n' '"-Wl,-rpath,@loader_path"' ;;
*) printf '%s\n' '"-Wl,-rpath,$ORIGIN"' ;;
esac

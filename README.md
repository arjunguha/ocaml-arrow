# ocaml-arrow

OCaml bindings for [Apache Arrow](https://arrow.apache.org/) using the C++ api.

Apache Arrow C++ is vendored as a git submodule at `vendor/apache-arrow` (tag `apache-arrow-5.0.0`). Run `git submodule update --init --recursive`, then `./scripts/build-vendored-arrow.sh`, before `opam install .` or `dune build`.

The current version has been tested with arrow 4.0.0, 4.0.1, and 5.0.0.

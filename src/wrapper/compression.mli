(** Compression codecs for Parquet and Feather output.

    These codec identifiers are passed to writers (e.g. [Writer.write],
    [Parquet_reader] writer counterparts, and the various [F]/[Builder]
    helpers) via their [?compression] argument. Not every codec is supported
    by every Arrow build; if the underlying library was compiled without a
    given codec, attempting to use it will raise at write time. [Snappy] and
    [Uncompressed] are the safest defaults for Parquet output. *)

type t =
  | Uncompressed
  | Snappy
  | Gzip
  | Brotli
  | Zstd
  | Lz4
  | Lz4_frame
  | Lzo
  | Bz2

(** [to_cint t] converts [t] to the integer enum value used by the
    underlying Arrow C API. Only needed when calling into the C bindings
    directly. *)
val to_cint : t -> int

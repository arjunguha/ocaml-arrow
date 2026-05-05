(** Re-export of the Arrow column-writer API.

    This module is a thin alias for {!Wrapper.Writer}, exposed under a
    friendlier name so callers do not have to refer to [Wrapper.Writer]
    directly. The functions here construct {!col} values from OCaml arrays
    or [Bigarray]s and write them out as Parquet or Feather files.

    Typical use:
    - Build columns with [int], [float], [utf8], [date], [time_ns],
      [bitset], etc., or with the [Bigarray]-based variants
      ([int64_ba], [float64_ba], …) when you already have a packed buffer.
    - Call [write ?compression filename ~cols] to persist a one-shot file,
      or [with_row_group_writer] to stream out one row group at a time
      (useful for tables too large to materialise in memory).
    - Use [create_table] to assemble columns into an in-memory {!Table.t}
      instead of writing to disk.

    See {!Wrapper.Writer} for the per-function documentation.

    The [_opt] variants of each constructor accept a {!Valid.t} mask in
    addition to the data, encoding nullability. The [_ba] variants share
    storage with the supplied [Bigarray], so the buffer must outlive the
    write call. *)

include module type of Wrapper.Writer with type col = Wrapper.Writer.col

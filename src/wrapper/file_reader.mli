(** Format-agnostic reader for tabular files.

    Dispatches to the appropriate Arrow reader based on the filename
    extension. Supported suffixes are [.csv], [.json], [.feather], and
    [.parquet]; any other extension raises. Use this when you want a single
    entry point that does not care which on-disk format is involved.

    For format-specific options (streaming row groups, choosing thread
    counts, memory mapping, etc.) use {!Parquet_reader} directly. *)

(** [schema filename] returns the Arrow schema of [filename], inferring the
    format from its extension. CSV and JSON files are read in full to
    determine the schema; Parquet and Feather files only read their footer
    metadata. *)
val schema : string -> Wrapper.Schema.t

(** [table ?columns filename] reads [filename] into an in-memory table.

    [columns] selects a subset of columns to read; it is honoured for
    Parquet and Feather (where projection is pushed down to the reader)
    and ignored for CSV and JSON (which always read all columns). Columns
    can be selected by index ([`indexes]) or by name ([`names]). *)
val table : ?columns:[ `indexes of int list | `names of string list ] -> string -> Table.t

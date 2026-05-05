(** OCaml interface to the Arrow C++ library.

    Most clients should prefer the smaller named files ({!Table}, {!Writer},
    {!Parquet_reader}, {!Builder}, …); they wrap the corresponding modules
    below with friendlier APIs and are oriented at end users. The modules
    {!Schema}, {!Column}, {!ChunkedArray}, and {!Feather_reader} have no
    alias and are reached directly here.

    Typical use:
    - Inspect a file's columns with {!Schema} / {!Schema.Flags} (returned by
      readers like {!Parquet_reader.schema}).
    - Read tabular data with {!Table.read_csv}, {!Table.read_json},
      {!Parquet_reader}, or {!Feather_reader}.
    - Pull typed column data out of a {!Table.t} with {!Column} (raw
      [Bigarray]/array readers) or via the higher-level {!Table.read} alias.
    - Construct columns with {!Writer} (one [col] per call) and emit a file
      with {!Writer.write} (one-shot, all-in-memory) or stream them out via
      {!Writer.with_row_group_writer} (incremental, memory-bounded).
    - Build columns row-by-row with the per-element builders
      ({!DoubleBuilder}, {!Int32Builder}, {!Int64Builder}, {!StringBuilder})
      and assemble them via {!Builder.make_table}.

    The data types under {!ChunkedArray} and {!Table.t} hold pointers into
    Arrow C++ memory; lifetimes are managed by the OCaml GC. *)

open! Base

(** Arrow schema description: the structure (type, nullability, child
    fields, metadata) of a table or column. *)
module Schema : sig
  (** Bit flags carried by every schema field. Combine with {!all}; query
      with the predicates. *)
  module Flags : sig
    type t [@@deriving sexp_of]

    (** [all flags] is the bitwise-or of every flag in the list. *)
    val all : t list -> t

    val dictionary_ordered_ : t
    val nullable_ : t
    val map_keys_sorted_ : t
    val dictionary_ordered : t -> bool
    val nullable : t -> bool
    val map_keys_sorted : t -> bool
  end

  (** A schema field. For a top-level table schema, [format] is ["+s"]
      (struct), [name] is empty, and [children] holds one entry per
      column. *)
  type t =
    { format : Datatype.t
    ; name : string
    ; metadata : (string * string) list
    ; flags : Flags.t
    ; children : t list
    }
  [@@deriving sexp_of]
end

(** Opaque handle to an Arrow [ChunkedArray] (a column whose values live in
    several contiguous chunks). Returned by {!Table.get_column} and accepted
    by {!Table.add_column}. There are no operations on this type beyond
    moving it between tables; if you need to read its values, fetch them
    via the {!Column} or {!Table} accessors instead. *)
module ChunkedArray : sig
  type t
end

(** In-memory Arrow tables: a list of named, typed columns. *)
module Table : sig
  type t

  (** [concatenate ts] stacks the tables in [ts] vertically. All inputs
      must share the same schema. *)
  val concatenate : t list -> t

  (** [slice t ~offset ~length] returns rows [offset .. offset + length - 1]
      as a zero-copy view into [t]. *)
  val slice : t -> offset:int -> length:int -> t

  val num_rows : t -> int
  val schema : t -> Schema.t

  (** [read_csv filename] parses [filename] as CSV. Header inference and
      type inference are handled by Arrow's CSV reader. *)
  val read_csv : string -> t

  (** [read_json filename] parses [filename] as line-delimited JSON. *)
  val read_json : string -> t

  (** [write_parquet ?chunk_size ?compression t filename] writes [t] as a
      single Parquet file. [chunk_size] (default ~1M rows) is the row-group
      size; [compression] defaults to [Snappy]. *)
  val write_parquet : ?chunk_size:int -> ?compression:Compression.t -> t -> string -> unit

  (** [write_feather ?chunk_size ?compression t filename] writes [t] as
      Feather (Arrow IPC). *)
  val write_feather : ?chunk_size:int -> ?compression:Compression.t -> t -> string -> unit

  (** [to_string_debug t] returns Arrow's human-readable rendering of [t].
      For debugging only; not stable. *)
  val to_string_debug : t -> string

  (** [add_column t name array] returns a new table with [array] appended
      as a column named [name]. *)
  val add_column : t -> string -> ChunkedArray.t -> t

  (** [get_column t name] returns the column named [name] as a
      {!ChunkedArray.t}. Raises if the column is missing. *)
  val get_column : t -> string -> ChunkedArray.t

  (** [add_all_columns t t'] returns [t] augmented with every column of
      [t']. The two tables must have the same row count. *)
  val add_all_columns : t -> t -> t
end

(** Streaming reader for Parquet files. The {!Parquet_reader} top-level
    file wraps this with {!Parquet_reader.iter_batches} /
    {!Parquet_reader.fold_batches} convenience functions; for one-shot
    reads, prefer {!Parquet_reader.table} over driving [create] / [next] /
    [close] by hand. *)
module Parquet_reader : sig
  type t

  (** [create ?use_threads ?column_idxs ?mmap ?buffer_size ?batch_size
      filename] opens a streaming reader. [column_idxs] projects a subset
      of columns; the others are skipped during decoding. *)
  val create
    :  ?use_threads:bool
    -> ?column_idxs:int list
    -> ?mmap:bool
    -> ?buffer_size:int
    -> ?batch_size:int
    -> string
    -> t

  (** [next t] returns the next batch, or [None] once the file is
      exhausted. *)
  val next : t -> Table.t option

  (** [close t] releases the file handle. *)
  val close : t -> unit

  (** [schema filename] reads only the Parquet footer to return the
      file's schema. *)
  val schema : string -> Schema.t

  (** [schema_and_num_rows filename] returns the schema and total row
      count, both from the file footer. *)
  val schema_and_num_rows : string -> Schema.t * int

  (** [table ?only_first ?use_threads ?column_idxs filename] reads the
      whole file into one table. [only_first n] caps the result to the
      first [n] rows. *)
  val table
    :  ?only_first:int
    -> ?use_threads:bool
    -> ?column_idxs:int list
    -> string
    -> Table.t
end

(** Reader for the Feather (Arrow IPC) format. *)
module Feather_reader : sig
  (** [schema filename] returns the schema by reading the file's footer. *)
  val schema : string -> Schema.t

  (** [table ?column_idxs filename] reads [filename] into a table.
      [column_idxs] projects a subset of columns. *)
  val table : ?column_idxs:int list -> string -> Table.t
end

(** Typed column readers.

    These functions extract a single column from a {!Table.t} as an OCaml
    array or [Bigarray]. The [_ba] variants share storage with Arrow's
    underlying buffer (zero-copy); ordinary [_ array] variants allocate.
    The [_opt] variants additionally return (or fold in) the column's
    null mask.

    For a higher-level interface that picks the right reader based on a
    type witness, use {!Table.read} / {!Table.read_opt}. *)
module Column : sig
  (** Selects a column by index or by name. *)
  type column =
    [ `Index of int
    | `Name of string
    ]

  val read_i32_ba
    :  Table.t
    -> column:column
    -> (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

  val read_i64_ba
    :  Table.t
    -> column:column
    -> (int64, Bigarray.int64_elt, Bigarray.c_layout) Bigarray.Array1.t

  val read_f64_ba
    :  Table.t
    -> column:column
    -> (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t

  val read_f32_ba
    :  Table.t
    -> column:column
    -> (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t

  val read_int : Table.t -> column:column -> int array
  val read_int32 : Table.t -> column:column -> Int32.t array
  val read_float : Table.t -> column:column -> float array
  val read_utf8 : Table.t -> column:column -> string array
  val read_binary : Table.t -> column:column -> string array
  val read_date : Table.t -> column:column -> Core_kernel.Date.t array
  val read_time_ns : Table.t -> column:column -> Core_kernel.Time_ns.t array
  val read_ofday_ns : Table.t -> column:column -> Core_kernel.Time_ns.Ofday.t array
  val read_span_ns : Table.t -> column:column -> Core_kernel.Time_ns.Span.t array

  (** [read_bitset t ~column] reads a [Boolean] column as a {!Valid.t}
      bitset. *)
  val read_bitset : Table.t -> column:column -> Valid.t

  (** [read_bitset_opt t ~column] returns [(values, valid)]: [values.(i)]
      is meaningful only when [valid.(i)] is set. *)
  val read_bitset_opt : Table.t -> column:column -> Valid.t * Valid.t

  val read_i32_ba_opt
    :  Table.t
    -> column:column
    -> (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t * Valid.t

  val read_i64_ba_opt
    :  Table.t
    -> column:column
    -> (int64, Bigarray.int64_elt, Bigarray.c_layout) Bigarray.Array1.t * Valid.t

  val read_f64_ba_opt
    :  Table.t
    -> column:column
    -> (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t * Valid.t

  val read_f32_ba_opt
    :  Table.t
    -> column:column
    -> (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t * Valid.t

  val read_int_opt : Table.t -> column:column -> int option array
  val read_int32_opt : Table.t -> column:column -> Int32.t option array
  val read_float_opt : Table.t -> column:column -> float option array
  val read_utf8_opt : Table.t -> column:column -> string option array
  val read_binary_opt : Table.t -> column:column -> string option array
  val read_date_opt : Table.t -> column:column -> Core_kernel.Date.t option array
  val read_time_ns_opt : Table.t -> column:column -> Core_kernel.Time_ns.t option array

  val read_ofday_ns_opt
    :  Table.t
    -> column:column
    -> Core_kernel.Time_ns.Ofday.t option array

  val read_span_ns_opt
    :  Table.t
    -> column:column
    -> Core_kernel.Time_ns.Span.t option array

  (** Result of {!fast_read}: a column packed with its inferred element
      type. [Unsupported_type] indicates the column has a type this
      shortcut path does not recognise; fall back to one of the typed
      readers above. *)
  type t =
    | Unsupported_type
    | String of string array
    | String_option of string option array
    | Int64 of (int64, Bigarray.int64_elt, Bigarray.c_layout) Bigarray.Array1.t
    | Int64_option of
        (int64, Bigarray.int64_elt, Bigarray.c_layout) Bigarray.Array1.t * Valid.ba
    | Double of (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t
    | Double_option of
        (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t * Valid.ba
  [@@deriving sexp_of]

  (** [fast_read t i] reads column [i] of [t] using a fast C path that
      dispatches on the column's element type at runtime. Useful when
      iterating over an unknown table; returns [Unsupported_type] for
      column types this path cannot handle. *)
  val fast_read : Table.t -> int -> t
end

(** Construct columns and write them out as Parquet or Feather files.

    A {!col} bundles a column's data and its name. Build them with the
    constructors below ({!int}, {!float}, {!utf8}, {!date}, {!bitset}, the
    [_ba] variants, …), then either:

    - call {!write} for a one-shot, all-in-memory write;
    - call {!with_row_group_writer} for an incremental, memory-bounded
      stream — useful when the dataset does not fit in memory; or
    - call {!create_table} to assemble the columns into an in-memory
      {!Table.t}.

    The [_opt] variants accept a {!Valid.t} mask for nullability. The
    [_ba] variants share storage with the supplied [Bigarray]; the buffer
    must outlive the resulting [col]. *)
module Writer : sig
  type col

  (** Construct an Arrow column of fixed-size values that uses the memory of a [Bigarray].
      The format must be specified based on
      https://arrow.apache.org/docs/format/CDataInterface.html#data-type-description-format-strings
      and must be compatible with the kind of array passed in.
  *)
  val fixed_ba
    : format:string
    -> ('a, 'b, Bigarray.c_layout) Bigarray.Array1.t
    -> name:string
    -> col

  (** As [fixed_ba], but also takes a bitfield specifying which array values are null. *)
  val fixed_ba_opt
    : format:string
    -> ('a, 'b, Bigarray.c_layout) Bigarray.Array1.t
    -> Valid.t
    -> name:string
    -> col

  (** Construct an Arrow-column of variable-sized values. This requires an array of the
      actual data as well as an array of offsets specifying where each value begins and
      ends. For n values, the offsets array is of length n+1: the nth offset stores where
      the nth value begins, and the n+1-th offset stores where the nth value ends.

      The format must be specified based on
      https://arrow.apache.org/docs/format/CDataInterface.html#data-type-description-format-strings
      and must be compatible with the kinds of array passed in (note in particular that
      [offsets] can be either an Int32 or an Int64 array.)
     *)
  val string_ba
    : format:string
    -> offsets:('a, 'b, Bigarray.c_layout) Bigarray.Array1.t
    -> data:(char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
    -> name:string
    -> col

  val string_ba_opt
    : format:string
    -> offsets:('a, 'b, Bigarray.c_layout) Bigarray.Array1.t
    -> data:(char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
    -> valid:Valid.t
    -> name:string
    -> col

  val int64_ba
    : (int64, Bigarray.int64_elt, Bigarray.c_layout) Bigarray.Array1.t
    -> name:string
    -> col

  val int64_ba_opt
    : (int64, Bigarray.int64_elt, Bigarray.c_layout) Bigarray.Array1.t
    -> Valid.t
    -> name:string
    -> col

  val int32_ba
    : (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
    -> name:string
    -> col

  val int32_ba_opt
    : (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
    -> Valid.t
    -> name:string
    -> col

  (** [int xs ~name] encodes a native [int array] as an Arrow [Int64]
      column. *)
  val int : int array -> name:string -> col

  val int_opt : int option array -> name:string -> col

  val float64_ba
    :  (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t
    -> name:string
    -> col

  val float64_ba_opt
    :  (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t
    -> Valid.t
    -> name:string
    -> col

  val float : float array -> name:string -> col
  val float_opt : float option array -> name:string -> col
  val utf8 : string array -> name:string -> col
  val utf8_opt : string option array -> name:string -> col
  val binary : string array -> name:string -> col
  val binary_opt : string option array -> name:string -> col
  val date : Core_kernel.Date.t array -> name:string -> col
  val date_opt : Core_kernel.Date.t option array -> name:string -> col

  (** Timestamps are encoded in a timezone-naive way, implicitly using
      GMT. *)
  val time_ns : Core_kernel.Time_ns.t array -> name:string -> col

  val time_ns_opt : Core_kernel.Time_ns.t option array -> name:string -> col
  val ofday_ns : Core_kernel.Time_ns.Ofday.t array -> name:string -> col
  val ofday_ns_opt : Core_kernel.Time_ns.Ofday.t option array -> name:string -> col
  val span_ns : Core_kernel.Time_ns.Span.t array -> name:string -> col
  val span_ns_opt : Core_kernel.Time_ns.Span.t option array -> name:string -> col

  (** [bitset bs ~name] encodes a {!Valid.t} as an Arrow [Boolean] column. *)
  val bitset : Valid.t -> name:string -> col

  (** [bitset_opt bs ~valid ~name] is like {!bitset}, but [valid.(i)]
      controls whether [bs.(i)] is null. *)
  val bitset_opt : Valid.t -> valid:Valid.t -> name:string -> col

  (** Streaming Parquet writer.

      An open writer holds a file handle and accepts one or more
      {!write_exn} calls; each call's columns must share the same names,
      types, and flags. Writes are accumulated up to the [batch_size]
      configured on {!with_row_group_writer}, then flushed as one Parquet
      row group; any remaining buffered rows are flushed at close time. *)
  module Row_group_writer : sig
    type t

    (** [write_exn t ~cols] queues [cols] for the file. All columns in a
        single call must have the same length; the schema (column names,
        formats, flags) must match every previous {!write_exn} on [t].
        Raises if [t] is closed, the columns are ragged, or the schema
        differs from earlier writes. *)
    val write_exn : t -> cols:col list -> unit
  end

  (** [write ?chunk_size ?compression filename ~cols] writes [cols] to
      [filename] as Parquet (or Feather, if the filename ends in
      [.feather]). The whole table must fit in memory; [chunk_size]
      controls the row-group size within the resulting file. *)
  val write
    :  ?chunk_size:int
    -> ?compression:Compression.t
    -> string
    -> cols:col list
    -> unit

  (** [with_row_group_writer ?batch_size ?compression filename ~f] opens a
      streaming Parquet writer for [filename], passes it to [f], and
      closes it (even if [f] raises). [batch_size] (default [1000]) is the
      number of rows accumulated in OCaml before a Parquet row group is
      emitted; pass a larger value to reduce row-group overhead, smaller
      to keep memory tight. Raises if [f] returns without writing any
      rows.

      Example: stream three row groups into one file:
      {[
        Writer.with_row_group_writer "out.parquet" ~batch_size:1 ~f:(fun w ->
          Writer.Row_group_writer.write_exn w
            ~cols:[ Writer.int [| 0; 1; 2 |] ~name:"x" ];
          Writer.Row_group_writer.write_exn w
            ~cols:[ Writer.int [| 3; 4 |] ~name:"x" ];
          Writer.Row_group_writer.write_exn w
            ~cols:[ Writer.int [| 5; 6; 7; 8 |] ~name:"x" ])
      ]} *)
  val with_row_group_writer
    :  ?batch_size:int
    -> ?compression:Compression.t
    -> string
    -> f:(Row_group_writer.t -> 'a)
    -> 'a

  (** [create_table ~cols] assembles [cols] into an in-memory {!Table.t}
      without writing to disk. *)
  val create_table : cols:col list -> Table.t
end

(** Per-element column builder for [Float64]. Append values one at a time
    (or skip a run of nulls with {!append_null}) and pass to
    {!Builder.make_table} once finished. *)
module DoubleBuilder : sig
  type t

  val create : unit -> t
  val append : t -> float -> unit
  val append_null : ?n:int -> t -> unit
  val length : t -> Int64.t
  val null_count : t -> Int64.t
end

(** Per-element column builder for [Int32]. *)
module Int32Builder : sig
  type t

  val create : unit -> t
  val append : t -> Int32.t -> unit
  val append_null : ?n:int -> t -> unit
  val length : t -> Int64.t
  val null_count : t -> Int64.t
end

(** Per-element column builder for [Int64]. *)
module Int64Builder : sig
  type t

  val create : unit -> t
  val append : t -> Int64.t -> unit
  val append_null : ?n:int -> t -> unit
  val length : t -> Int64.t
  val null_count : t -> Int64.t
end

(** Per-element column builder for UTF-8 strings. *)
module StringBuilder : sig
  type t

  val create : unit -> t
  val append : t -> string -> unit
  val append_null : ?n:int -> t -> unit
  val length : t -> Int64.t
  val null_count : t -> Int64.t
end

(** Tagged union over the per-element builders, used by
    {!Builder.make_table} to assemble a heterogeneous table from a list of
    finished builders. *)
module Builder : sig
  type t =
    | Double of DoubleBuilder.t
    | Int32 of Int32Builder.t
    | Int64 of Int64Builder.t
    | String of StringBuilder.t

  (** [make_table named_builders] turns [(name, builder)] pairs into a
      {!Table.t}. All builders must have the same length. *)
  val make_table : (string * t) list -> Table.t
end

(**/**)

(** Internal: keeps GC roots alive for buffers handed to C++. Do not
    reference. *)
val keep_alive : Obj.t list ref

(**/**)

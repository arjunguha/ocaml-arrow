(** High-level interface to in-memory Arrow tables.

    A [Table.t] is a columnar dataset: a list of named columns, each holding
    a sequence of values of a single logical type. This module re-exports
    the underlying {!Wrapper.Table} (so functions like [num_rows], [schema],
    [concatenate], [slice], [read_csv], [read_json], [write_parquet], and
    [write_feather] are available here directly), and adds a typed
    column-construction / column-reading API on top.

    Typical use:
    - Read a table with {!Wrapper.Table.read_csv}, {!File_reader.table}, or
      {!Parquet_reader.table}.
    - Inspect column values with {!read} / {!read_opt}, passing the
      appropriate {!col_type} witness.
    - Build a table from OCaml arrays by constructing columns with {!col} /
      {!col_opt} and assembling them with {!create}.
    - Persist with the inherited [write_parquet] / [write_feather]. *)

include module type of Wrapper.Table with type t = Wrapper.Table.t

(** Type witnesses describing the OCaml representation of a column. The
    constructor identifies an OCaml type (e.g. [Int : int col_type]); pairing
    a witness with an [_ array] gives a strongly-typed column. The witnesses
    are used by {!col}, {!col_opt}, {!read}, and {!read_opt} to dispatch to
    the appropriate Arrow encoding.

    For [Date], [Time_ns], [Span_ns], and [Ofday_ns], readers fall back to
    parsing the column as UTF-8 strings (using the [Core_kernel] [of_string]
    function for the type) when the Arrow column does not have the native
    encoding. *)
type _ col_type =
  | Int : int col_type
  | Float : float col_type
  | Utf8 : string col_type
  | Date : Core_kernel.Date.t col_type
  | Time_ns : Core_kernel.Time_ns.t col_type
  | Span_ns : Core_kernel.Time_ns.Span.t col_type
  | Ofday_ns : Core_kernel.Time_ns.Ofday.t col_type
  | Bool : bool col_type

(** A column packaged with its type witness, either as a plain array ([P])
    or an array of options ([O]) for nullable columns. Used by
    {!named_col} to construct a writer column without naming the type
    statically. *)
type packed_col =
  | P : 'a col_type * 'a array -> packed_col
  | O : 'a col_type * 'a option array -> packed_col

(** [create cols] builds an in-memory table from a list of columns produced
    by {!col}, {!col_opt}, {!named_col}, or any of the [Wrapper.Writer]
    constructors. *)
val create : Wrapper.Writer.col list -> t

(** [named_col packed_col ~name] turns a {!packed_col} into a writer column
    with the given name. *)
val named_col : packed_col -> name:string -> Wrapper.Writer.col

(** [col data ty ~name] constructs a writer column from the array [data]
    using the encoding selected by the type witness [ty]. *)
val col : 'a array -> 'a col_type -> name:string -> Wrapper.Writer.col

(** [col_opt data ty ~name] is like {!col}, but [data] is an array of
    options whose [None] entries become Arrow nulls. *)
val col_opt : 'a option array -> 'a col_type -> name:string -> Wrapper.Writer.col

(** [read t ~column ty] reads [column] (selected by name or index, see
    {!Wrapper.Column.column}) from [t] as an [_ array] of the OCaml type
    chosen by [ty]. Raises if the column is missing or if its values cannot
    be converted to [ty]. *)
val read : t -> column:Wrapper.Column.column -> 'a col_type -> 'a array

(** [read_opt t ~column ty] is like {!read}, but null entries are returned
    as [None]. *)
val read_opt : t -> column:Wrapper.Column.column -> 'a col_type -> 'a option array

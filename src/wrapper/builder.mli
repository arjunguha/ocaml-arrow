(** Incremental column builders and record-to-table helpers.

    This module offers two layers on top of the raw [Wrapper] builders:

    {1 Per-element builders}

    {!Double}, {!Int32}, {!Int64}, {!NativeInt}, and {!String} all share the
    {!Intf} signature: create an empty builder, [append] values one at a
    time (or [append_null] / [append_opt] for nullable data), and pass the
    finished builders to {!make_table} to produce a {!Table.t}. Useful when
    you assemble a column row-by-row and do not know the length up front.

    {1 Record-of-fields builders ({!C})}

    The {!C} sub-module turns a record's field accessors into a column
    layout, so an OCaml [array] of records can be converted to a table
    without writing per-column boilerplate. Pair it with [\[@@deriving
    fields\]] from [ppx_fields_conv] to derive the field accessors.

    Example with a record [type t = { x : int; y : float }] (after
    deriving [fields]):
    {[
      let packed_cols =
        Builder.C.(c Table.Int Fields.x @ c Table.Float Fields.y)
      let table = Builder.C.array_to_table packed_cols rows
    ]}

    [c] selects a non-null column, [c_opt] handles ['a option] fields,
    [c_map] / [c_map_opt] apply a transformation before encoding, [c_array]
    fans an ['a array] field out to one column per element (with the
    supplied [suffixes] appended to the base name), [c_ignore] drops a
    field, and [c_flatten] embeds the columns of a sub-record (renaming
    them by prefix or with a custom function).

    {1 Row-major buffering ({!Row})}

    Functor {!Row} produces a buffered builder for a record type: append
    rows one at a time, then call [to_table] to materialise. Useful when
    rows are produced incrementally and you want to amortise the table
    construction. *)

open! Core_kernel

(** Common interface implemented by every per-element builder. *)
module type Intf = sig
  type t
  type elem

  (** [create ()] returns an empty builder. *)
  val create : unit -> t

  (** [append t v] appends [v] as a non-null entry. *)
  val append : t -> elem -> unit

  (** [append_null ?n t] appends [n] null entries (default [1]). *)
  val append_null : ?n:int -> t -> unit

  (** [append_opt t v] is [append t v] when [v] is [Some _] and a single
      [append_null] when [v] is [None]. *)
  val append_opt : t -> elem option -> unit

  (** [length t] is the number of entries (null and non-null) appended. *)
  val length : t -> int

  (** [null_count t] is the number of null entries appended. *)
  val null_count : t -> int
end

module Double : sig
  include Intf with type elem := float and type t = Wrapper.DoubleBuilder.t
end

module Int32 : sig
  include Intf with type elem := Int32.t and type t = Wrapper.Int32Builder.t
end

module Int64 : sig
  include Intf with type elem := Int64.t and type t = Wrapper.Int64Builder.t
end

(** Builder for native OCaml [int]s, stored as Arrow [Int64]. Values are
    converted with [Int64.of_int] on append. *)
module NativeInt : sig
  include Intf with type elem := int and type t = Wrapper.Int64Builder.t
end

module String : sig
  include Intf with type elem := string and type t = Wrapper.StringBuilder.t
end

(** [make_table cols] turns a list of [(column_name, builder)] pairs into a
    [Table.t]. All builders must have the same length. *)
val make_table : (string * Wrapper.Builder.t) list -> Table.t

(** Record-of-fields column construction. See the module overview for an
    end-to-end example. *)
module C : sig
  (** A column described by its name, an accessor [get : 'row -> 'elem],
      and a {!Table.col_type} witness. *)
  type ('row, 'elem, 'col_type) col =
    { name : string
    ; get : 'row -> 'elem
    ; col_type : 'col_type Table.col_type
    }

  (** A {!col} packed with its nullability flag: [P] for non-null columns,
      [O] for columns whose entries are ['elem option]. *)
  type 'row packed_col =
    | P : ('row, 'elem, 'elem) col -> 'row packed_col
    | O : ('row, 'elem option, 'elem) col -> 'row packed_col

  type 'row packed_cols = 'row packed_col list

  (** [c ?name col_type field] declares one non-null column whose values
      come from [field]. The column name defaults to [Field.name field],
      override with [?name]. *)
  val c
    : ?name:string
    -> 'a Table.col_type
    -> ('b, 'c, 'a) Field.t_with_perm
    -> 'c packed_cols

  (** [c_opt ?name col_type field] is like {!c} but for fields of type
      ['a option]; [None] entries become Arrow nulls. *)
  val c_opt
    : ?name:string
    -> 'a Table.col_type
    -> ('b, 'c, 'a option) Field.t_with_perm
    -> 'c packed_cols

  (** [c_array ?name col_type field ~suffixes] fans a fixed-length
      [_ array] field out to one column per element. Column [i] is named
      [name ^ List.nth suffixes i]. Every row's array must have length
      [List.length suffixes].

      Example: turn a [[| x; y; z |]] coordinate field into three columns:
      {[
        c_array Table.Float Fields.coord ~suffixes:[ "_x"; "_y"; "_z" ]
      ]} *)
  val c_array
    :  ?name:string
    -> 'a Table.col_type
    -> ('b, 'c, 'a array) Field.t_with_perm
    -> suffixes:string list
    -> 'c packed_cols

  (** Like {!c_array} but for fields of [_ option array]. *)
  val c_array_opt
    :  ?name:string
    -> 'a Table.col_type
    -> ('b, 'c, 'a option array) Field.t_with_perm
    -> suffixes:string list
    -> 'c packed_cols

  (** [c_map ?name col_type field ~f] declares a column whose values are
      [f (Field.get field row)]. Use this to encode a domain type via a
      conversion to an Arrow-compatible representation.

      Example: serialise a [Date.t] field as a string:
      {[
        c_map Table.Utf8 Fields.day ~f:Core_kernel.Date.to_string
      ]} *)
  val c_map
    :  ?name:string
    -> 'a Table.col_type
    -> ('b, 'c, 'd) Field.t_with_perm
    -> f:('d -> 'a)
    -> 'c packed_cols

  (** Like {!c_map} but [f] returns an option, producing a nullable
      column. *)
  val c_map_opt
    :  ?name:string
    -> 'a Table.col_type
    -> ('b, 'c, 'd) Field.t_with_perm
    -> f:('d -> 'a option)
    -> 'c packed_cols

  (** [c_ignore field] declares no columns for [field], skipping it during
      table construction. *)
  val c_ignore : ('b, 'c, 'a) Field.t_with_perm -> 'c packed_cols

  (** [c_flatten ?rename sub_cols field] embeds the columns produced for a
      sub-record into the parent. [rename] controls how nested column
      names are produced from the sub-record's column names:
      - [`prefix] (the default) prepends [Field.name field ^ "_"];
      - [`keep] uses the sub-record names verbatim;
      - [`fn f] applies the user-supplied [f].

      Example: flatten an [address] sub-record into [address_street],
      [address_city], …:
      {[
        c_flatten Address.packed_cols Fields.address
      ]} *)
  val c_flatten
    :  ?rename:[ `fn of string -> string | `keep | `prefix ]
    -> 'a packed_cols
    -> ('b, 'c, 'a) Field.t_with_perm
    -> 'c packed_cols

  (** [array_to_table cols rows] applies the column descriptions [cols] to
      every row in [rows] and returns a {!Table.t}. *)
  val array_to_table : 'a packed_cols -> 'a array -> Table.t
end

(** Input signature for the {!Row} functor: a row type plus an
    [array_to_table] implementation (typically derived via [\[@@deriving
    arrow\]] or built by hand from {!C.array_to_table}). *)
module type Row_intf = sig
  type row

  val array_to_table : row array -> Table.t
end

(** Output signature of the {!Row} functor: a buffered row builder. *)
module type Row_builder_intf = sig
  type t
  type row

  (** [create ()] returns an empty row buffer. *)
  val create : unit -> t

  (** [append t row] adds [row] to [t]. *)
  val append : t -> row -> unit

  (** [length t] is the number of rows currently buffered. *)
  val length : t -> int

  (** [reset t] empties [t]. *)
  val reset : t -> unit

  (** [to_table t] converts the buffered rows to a {!Table.t}. The buffer
      is not cleared; call {!reset} afterwards if you want to reuse it. *)
  val to_table : t -> Table.t
end

(** [Row(R)] gives a buffered row builder. Append rows one at a time, then
    call [to_table] to materialise. *)
module Row (R : Row_intf) : Row_builder_intf with type row = R.row

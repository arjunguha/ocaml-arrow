(** Field-driven reader/writer for record types.

    This module composes a record's [Fields.make_creator] with a list of
    column-type combinators ({!i64}, {!f64}, {!str}, {!date}, {!stringable},
    …) to derive both a Parquet reader and a Parquet writer for that
    record from a single description.

    Each combinator binds one record field to one Arrow column, picking the
    column name from [Field.name] and the encoding from the combinator
    chosen. Pair this module with [\[@@deriving fields\]] from
    [ppx_fields_conv]; the {!Ppx_arrow} ppx is a higher-level alternative
    that emits these calls for you.

    Typical use:
    {[
      type t =
        { x : int
        ; y : float
        }
      [@@deriving sexp, fields]

      let `read read, `write write =
        F.(read_write_fn (Fields.make_creator ~x:i64 ~y:f64))

      let ts = read "/path/to/filename.parquet"
      let () = write ts "/path/to/another.parquet"
    ]}

    Submodules {!Reader} and {!Writer} expose the read-only and write-only
    halves directly when only one direction is needed. *)

open! Base

(** Build a reader from per-field column combinators. *)
module Reader : sig
  type t = string list
  type 'v col_ = t -> (Wrapper.Table.t * int -> 'v) * t
  type ('a, 'b, 'c, 'v) col = ('a, 'b, 'c) Field.t_with_perm -> 'v col_

  (** Read the field as a 64-bit Arrow integer, returned as a native
      [int]. Raises if any value does not fit. *)
  val i64 : ('a, 'b, 'c, int) col

  val f64 : ('a, 'b, 'c, float) col
  val str : ('a, 'b, 'c, string) col

  (** [stringable (module M) field] reads a UTF-8 column and parses each
      value with [M.of_string]. Use for domain types that round-trip via
      strings. *)
  val stringable : (module Stringable.S with type t = 'd) -> ('a, 'b, 'c, 'd) col

  val date : ('a, 'b, 'c, Core_kernel.Date.t) col
  val time_ns : ('a, 'b, 'c, Core_kernel.Time_ns.t) col
  val bool : ('a, 'b, 'c, bool) col
  val i64_opt : ('a, 'b, 'c, int option) col
  val f64_opt : ('a, 'b, 'c, float option) col
  val str_opt : ('a, 'b, 'c, string option) col
  val bool_opt : ('a, 'b, 'c, bool option) col

  val stringable_opt
    :  (module Stringable.S with type t = 'd)
    -> ('a, 'b, 'c, 'd option) col

  val date_opt : ('a, 'b, 'c, Core_kernel.Date.t option) col
  val time_ns_opt : ('a, 'b, 'c, Core_kernel.Time_ns.t option) col

  (** [map col ~f field] reads the column with [col] and post-processes
      each value with [f].

      Example: read a [date] column and lift it into a custom type:
      {[
        let event_day = F.Reader.map date ~f:(fun d -> { day = d })
      ]} *)
  val map : ('a, 'b, 'c, 'x) col -> f:('x -> 'y) -> ('a, 'b, 'c, 'y) col

  (** [read creator filename] applies [creator] (typically built with
      [Fields.make_creator] and the combinators above) to read [filename]
      into a list of records. Only the columns named by [creator] are
      decoded; any others in the file are ignored. *)
  val read : 'v col_ -> string -> 'v list
end

(** Build a writer from per-field column combinators. *)
module Writer : sig
  type 'a state = int * (unit -> Wrapper.Writer.col) list * (int -> 'a -> unit)
  type ('a, 'b, 'c) col = 'a state -> ('b, 'a, 'c) Field.t_with_perm -> 'a state

  val i64 : ('a, 'b, int) col
  val f64 : ('a, 'b, float) col
  val str : ('a, 'b, string) col
  val bool : ('a, 'b, bool) col

  (** [stringable (module M)] writes a domain field as UTF-8 by calling
      [M.to_string] on each value. *)
  val stringable
    :  (module Stringable.S with type t = 'd)
    -> 'a state
    -> ('c, 'a, 'd) Field.t_with_perm
    -> 'a state

  val date : ('a, 'b, Core_kernel.Date.t) col
  val time_ns : ('a, 'b, Core_kernel.Time_ns.t) col
  val i64_opt : ('a, 'b, int option) col
  val f64_opt : ('a, 'b, float option) col
  val str_opt : ('a, 'b, string option) col
  val date_opt : ('a, 'b, Core_kernel.Date.t option) col
  val time_ns_opt : ('a, 'b, Core_kernel.Time_ns.t option) col
  val bool_opt : ('a, 'b, bool option) col

  (** [write fold ?chunk_size ?compression filename rows] applies the
      fold built with [Fields.make_creator] and the combinators above to
      [rows] and writes the resulting table as Parquet. *)
  val write
    :  (init:'d state -> 'd state)
    -> ?chunk_size:int
    -> ?compression:Compression.t
    -> string
    -> 'd list
    -> unit
end

(** Unified column descriptor that both reads and writes. {!read_write_fn}
    threads a value of this type through [Fields.make_creator] to derive
    matching reader and writer in one shot. *)
type 'a t =
  | Read of Reader.t
  | Write of 'a Writer.state

type ('a, 'b, 'c) col =
  ('a, 'b, 'c) Field.t_with_perm -> 'b t -> (Wrapper.Table.t * int -> 'c) * 'b t

val i64 : ('a, 'b, int) col
val f64 : ('a, 'b, float) col
val str : ('a, 'b, string) col
val bool : ('a, 'b, bool) col
val bool_opt : ('a, 'b, bool option) col
val stringable : (module Stringable.S with type t = 'd) -> ('a, 'b, 'd) col
val date : ('a, 'b, Core_kernel.Date.t) col
val time_ns : ('a, 'b, Core_kernel.Time_ns.t) col
val i64_opt : ('a, 'b, int option) col
val f64_opt : ('a, 'b, float option) col
val str_opt : ('a, 'b, string option) col
val date_opt : ('a, 'b, Core_kernel.Date.t option) col
val time_ns_opt : ('a, 'b, Core_kernel.Time_ns.t option) col

(** [read_write_fn creator] returns matching read and write functions for
    a record described by [creator] (built from [Fields.make_creator] and
    the unified combinators above).

    Example: see the module-level overview. *)
val read_write_fn
  :  ('a t -> (Wrapper.Table.t * int -> 'a) * 'a t)
  -> [ `read of string -> 'a list ]
     * [ `write of
         ?chunk_size:int -> ?compression:Compression.t -> string -> 'a list -> unit
       ]

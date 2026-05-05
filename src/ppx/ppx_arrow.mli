(** [\[@@deriving arrow\]]: ppx that derives Parquet readers and writers
    for record types.

    Attaching [\[@@deriving arrow\]] to a record type [t] generates four
    functions:
    - [arrow_read_t : string -> t array] — read a Parquet file.
    - [arrow_write_t : t array -> string -> unit] — write a Parquet file.
    - [arrow_t_of_table : Arrow_c_api.Table.t -> t array] — decode an
      in-memory table.
    - [arrow_table_of_t : t array -> Arrow_c_api.Table.t] — encode rows
      into an in-memory table.

    Use {!Reader.deriver} or {!Writer.deriver} when you only need one
    direction (it generates only the corresponding subset of the four
    functions).

    Field types are mapped to Arrow columns automatically: [int] →
    [Int64], [float] → [Float64], [string] → [Utf8], [bool] →
    [Boolean], [Core_kernel.Date.t], [Core_kernel.Time_ns.t], and their
    [option] variants are also recognised. For other types, annotate the
    field with one of:
    - [\[\@arrow.intable\]] — store via [to_int_exn] / [of_int_exn].
    - [\[\@arrow.floatable\]] — store via [to_float] / [of_float].
    - [\[\@arrow.stringable\]] — store via [to_string] / [of_string].
    - [\[\@arrow.sexpable\]] — store the field's s-expression form.
    - [\[\@arrow.boolable\]] — store via [to_bool] / [of_bool].

    Example:
    {[
      module Foobar = struct
        type t = Foo | Bar | Foobar
        let to_string = function Foo -> "Foo" | Bar -> "Bar" | Foobar -> "FooBar"
        let of_string = function
          | "Foo" -> Foo | "Bar" -> Bar | "FooBar" -> Foobar
          | s -> failwith s
      end

      type t =
        { x : int
        ; y : float
        ; z : Foobar.t [@arrow.stringable]
        }
      [@@deriving arrow]

      let () = arrow_write_t rows "/tmp/out.parquet"
      let rows = arrow_read_t "/tmp/out.parquet"
    ]}

    The generated code calls into {!Arrow_c_api.Table} (the C wrapper) to
    materialise tables, so any project using this ppx must depend on the
    [arrow.c_api] library at runtime. *)

open Ppxlib

(** Combined deriver. Attaching [\[@@deriving arrow\]] generates both
    readers and writers. *)
val arrow : Deriving.t

(** Read-only variant. Attaching [\[@@deriving arrow_read\]] generates only
    [arrow_read_t] and [arrow_t_of_table]. *)
module Reader : sig
  val deriver : Deriving.t
end

(** Write-only variant. Attaching [\[@@deriving arrow_write\]] generates
    only [arrow_write_t] and [arrow_table_of_t]. *)
module Writer : sig
  val deriver : Deriving.t
end

(** OCaml view of Arrow logical data types.

    A {!t} describes the type of an Arrow column or schema field. Values of
    this type appear as the [format] of a {!Wrapper.Schema.t} returned by
    schema-introspection functions like {!File_reader.schema} and
    {!Parquet_reader.schema}. Use this module to inspect the layout of a
    file before reading it.

    The variants mirror Arrow's logical types. Parameterised variants
    (e.g. [Time32], [Timestamp], [Decimal128]) carry the same precision /
    scale / unit information you would see in the Arrow C++ API. The catch-all
    [Unknown of string] holds the raw Arrow format string for any type this
    binding does not yet decode. *)

open! Base

type t =
  | Null
  | Boolean
  | Int8
  | Uint8
  | Int16
  | Uint16
  | Int32
  | Uint32
  | Int64
  | Uint64
  | Float16
  | Float32
  | Float64
  | Binary
  | Large_binary
  | Utf8_string
  | Large_utf8_string
  | Decimal128 of
      { precision : int
      ; scale : int
      }
  | Fixed_width_binary of { bytes : int }
  | Date32 of [ `days ]
  | Date64 of [ `milliseconds ]
  | Time32 of [ `seconds | `milliseconds ]
  | Time64 of [ `microseconds | `nanoseconds ]
  | Timestamp of
      { precision : [ `seconds | `milliseconds | `microseconds | `nanoseconds ]
      ; timezone : string
      }
  | Duration of [ `seconds | `milliseconds | `microseconds | `nanoseconds ]
  | Interval of [ `months | `days_time ]
  | Struct
  | Map
  | Unknown of string
[@@deriving sexp]

(** [of_cstring s] parses an Arrow C-data-interface format string (see
    {{:https://arrow.apache.org/docs/format/CDataInterface.html#data-type-description-format-strings}
    the Arrow docs}) into a {!t}. Format strings the binding does not
    recognise are returned as [Unknown s]. *)
val of_cstring : string -> t

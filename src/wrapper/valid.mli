(** Packed bitsets used for Arrow null masks.

    Arrow represents nullability as a contiguous bit-per-element validity
    buffer: bit [i] is [1] when row [i] is present (non-null) and [0] when
    null. Many of the higher-level read/write functions in this library
    return or accept a [Valid.t] alongside a data array to express which
    entries are valid.

    Typical use:
    - {!create_all_valid} allocates a mask in which every entry is valid,
      after which you call {!set} to clear bits for null rows;
    - {!get} and {!set} read/write individual bits;
    - {!num_true} / {!num_false} count valid / null entries;
    - {!bigarray} exposes the raw byte buffer when you need to hand the
      mask to a function that takes a [Bigarray] directly. *)

(** Backing buffer type for a bitset: a 1D [Bigarray] of unsigned 8-bit
    bytes, with bits packed little-endian within each byte. *)
type ba = (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(** A bitset of a fixed length. The buffer holding the bits has
    [(length + 7) / 8] bytes; trailing bits beyond [length] in the last byte
    are unspecified. *)
type t

(** [of_bigarray ba ~length] wraps an existing buffer [ba] as a bitset of
    [length] bits. The buffer is shared (not copied), so subsequent writes
    through [t] are visible in [ba] and vice versa. *)
val of_bigarray : ba -> length:int -> t

(** [create_all_valid n] allocates a fresh bitset of [n] bits with every bit
    set to [true]. *)
val create_all_valid : int -> t

(** [length t] returns the number of bits in [t] (not the size in bytes). *)
val length : t -> int

(** [get t i] returns the value of bit [i]. Behaviour is undefined if
    [i < 0] or [i >= length t]. *)
val get : t -> int -> bool

(** [set t i b] sets bit [i] to [b]. Behaviour is undefined if [i < 0] or
    [i >= length t]. *)
val set : t -> int -> bool -> unit

(** [bigarray t] returns the underlying byte buffer, sharing storage with
    [t]. *)
val bigarray : t -> ba

(** [num_true t] is the number of bits set to [true] in [t]. *)
val num_true : t -> int

(** [num_false t] is the number of bits set to [false] in [t], i.e.
    [length t - num_true t]. *)
val num_false : t -> int

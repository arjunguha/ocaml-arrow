(** Streaming and one-shot readers for Parquet files.

    The {!t} type is a long-lived reader that yields one record-batch
    {!Table.t} at a time via {!next}. {!iter_batches} and {!fold_batches}
    are convenience wrappers that open a reader, drive it to exhaustion,
    and close it again — use them when you do not need to manage the
    reader's lifetime by hand. {!table} reads an entire Parquet file into
    a single table in one call.

    All entry points share the same set of optional tuning knobs:
    - [use_threads] enables Arrow's parallel decoder.
    - [column_idxs] projects a subset of columns by index. To project by
      name, look up indices via {!schema}.
    - [mmap] reads the file via [mmap] instead of buffered I/O.
    - [buffer_size] controls the read-ahead buffer.
    - [batch_size] controls the maximum number of rows per batch returned
      by {!next} / each call to [f].

    Closing a reader (manually with {!close}, or implicitly via
    {!iter_batches} / {!fold_batches}) releases the underlying file handle. *)

(** A streaming Parquet reader. Hold one open by calling {!create}. *)
type t

(** [create ?use_threads ?column_idxs ?mmap ?buffer_size ?batch_size
    filename] opens a Parquet reader. The caller is responsible for calling
    {!close} when finished. *)
val create
  :  ?use_threads:bool
  -> ?column_idxs:int list
  -> ?mmap:bool
  -> ?buffer_size:int
  -> ?batch_size:int
  -> string
  -> t

(** [next t] returns the next batch from [t], or [None] once the file has
    been fully consumed. Each returned [Table.t] holds at most [batch_size]
    rows. *)
val next : t -> Table.t option

(** [close t] closes [t], releasing its file handle. Calling [next] after
    [close] is an error. *)
val close : t -> unit

(** [iter_batches ?... filename ~f] opens [filename], calls [f] on each
    batch in order, and closes the reader (even if [f] raises).

    Example: count rows in a Parquet file without loading it all at once:
    {[
      let total = ref 0 in
      Parquet_reader.iter_batches "data.parquet" ~f:(fun batch ->
        total := !total + Wrapper.Table.num_rows batch);
      !total
    ]} *)
val iter_batches
  :  ?use_threads:bool
  -> ?column_idxs:int list
  -> ?mmap:bool
  -> ?buffer_size:int
  -> ?batch_size:int
  -> string
  -> f:(Table.t -> unit)
  -> unit

(** [fold_batches ?... filename ~init ~f] is the folding analogue of
    {!iter_batches}: [f] threads an accumulator through every batch.

    Example: sum a [float] column across the whole file without
    materialising it:
    {[
      let total =
        Parquet_reader.fold_batches "prices.parquet" ~init:0.0
          ~f:(fun acc batch ->
            Table.read batch ~column:(`Name "price") Float
            |> Array.fold ~init:acc ~f:(+.))
      in
      total
    ]} *)
val fold_batches
  :  ?use_threads:bool
  -> ?column_idxs:int list
  -> ?mmap:bool
  -> ?buffer_size:int
  -> ?batch_size:int
  -> string
  -> init:'a
  -> f:('a -> Table.t -> 'a)
  -> 'a

(** [schema filename] returns the schema of [filename] by reading only its
    Parquet footer. *)
val schema : string -> Wrapper.Schema.t

(** [schema_and_num_rows filename] returns both the schema and the total
    row count, also from the file footer. *)
val schema_and_num_rows : string -> Wrapper.Schema.t * int

(** [table ?only_first ?use_threads ?column_idxs filename] reads [filename]
    fully into an in-memory table. [only_first n] caps the number of rows
    returned to the first [n]. *)
val table
  :  ?only_first:int
  -> ?use_threads:bool
  -> ?column_idxs:int list
  -> string
  -> Table.t

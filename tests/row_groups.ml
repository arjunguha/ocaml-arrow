open Core_kernel
open Arrow_c_api

let parquet_num_row_groups filename =
  let in_channel, out_channel = Caml_unix.open_process "python" in
  Out_channel.output_lines
    out_channel
    [ "import pyarrow.parquet as pq"
    ; Printf.sprintf "print(pq.ParquetFile(%S).num_row_groups)" filename
    ];
  Out_channel.close out_channel;
  let output = In_channel.input_all in_channel |> String.strip in
  match Caml_unix.close_process (in_channel, out_channel) with
  | Ok () -> Int.of_string output
  | Error _ -> failwith output

let row_group offset length =
  let xs = Array.init length ~f:(fun i -> offset + i) in
  let labels = Array.map xs ~f:(Printf.sprintf "row-%d") in
  [ Writer.int xs ~name:"x"; Writer.utf8 labels ~name:"label" ]

let%expect_test "write parquet row groups incrementally" =
  let filename = Stdlib.Filename.temp_file "row-groups" ".parquet" in
  Exn.protect
    ~f:(fun () ->
      Writer.with_row_group_writer filename ~f:(fun writer ->
        Writer.Row_group_writer.write_exn writer ~cols:(row_group 0 3);
        Writer.Row_group_writer.write_exn writer ~cols:(row_group 3 2);
        Writer.Row_group_writer.write_exn writer ~cols:(row_group 5 4));
      Stdio.printf
        "row groups: %d\nrows: %d\n%!"
        (parquet_num_row_groups filename)
        (Parquet_reader.schema_and_num_rows filename |> snd))
    ~finally:(fun () -> Stdlib.Sys.remove filename);
  [%expect
    {|
    row groups: 3
    rows: 9
    |}]

let%expect_test "row groups reject ragged columns" =
  let filename = Stdlib.Filename.temp_file "row-groups" ".parquet" in
  Exn.protect
    ~f:(fun () ->
      Writer.with_row_group_writer filename ~f:(fun writer ->
        require_does_raise (fun () ->
          Writer.Row_group_writer.write_exn
            writer
            ~cols:
              [ Writer.int [| 1; 2 |] ~name:"x"
              ; Writer.utf8 [| "one" |] ~name:"label"
              ])))
    ~finally:(fun () -> if Stdlib.Sys.file_exists filename then Stdlib.Sys.remove filename);
  [%expect
    {|
    (Invalid_argument
      "Writer.Row_group_writer.write_exn: columns have different lengths (2 and 1)")
    |}]

let%expect_test "writer closes after with_row_group_writer returns" =
  let filename = Stdlib.Filename.temp_file "row-groups" ".parquet" in
  let writer =
    Exn.protect
      ~f:(fun () ->
        Writer.with_row_group_writer filename ~f:(fun writer ->
          Writer.Row_group_writer.write_exn writer ~cols:(row_group 0 1);
          writer))
      ~finally:(fun () -> if Stdlib.Sys.file_exists filename then Stdlib.Sys.remove filename)
  in
  require_does_raise (fun () ->
    Writer.Row_group_writer.write_exn writer ~cols:(row_group 1 1));
  [%expect
    {|
    (Invalid_argument "Writer.Row_group_writer.write_exn: writer is closed")
    |}]

let%expect_test "with_row_group_writer rejects empty files" =
  let filename = Stdlib.Filename.temp_file "row-groups" ".parquet" in
  Exn.protect
    ~f:(fun () ->
      require_does_raise (fun () -> Writer.with_row_group_writer filename ~f:ignore))
    ~finally:(fun () -> if Stdlib.Sys.file_exists filename then Stdlib.Sys.remove filename);
  [%expect
    {|
    (Invalid_argument "Writer.with_row_group_writer: no row groups were written")
    |}]

let%expect_test "writer rejects mixed row group schemas" =
  let filename = Stdlib.Filename.temp_file "row-groups" ".parquet" in
  Exn.protect
    ~f:(fun () ->
      Writer.with_row_group_writer filename ~f:(fun writer ->
        Writer.Row_group_writer.write_exn writer ~cols:(row_group 0 1);
        require_does_raise (fun () ->
          Writer.Row_group_writer.write_exn
            writer
            ~cols:[ Writer.int [| 1 |] ~name:"different" ])))
    ~finally:(fun () -> if Stdlib.Sys.file_exists filename then Stdlib.Sys.remove filename);
  [%expect
    {|
    (Invalid_argument "Writer.Row_group_writer.write_exn: row group schema changed")
    |}]

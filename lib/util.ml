let normalize_space value =
  value |> String.to_seq
  |> Seq.fold_left
       (fun (buffer, in_space) character ->
         if
           character = ' ' || character = '\n' || character = '\r'
           || character = '\t'
         then
           if in_space then (buffer, true)
           else (
             Buffer.add_char buffer ' ';
             (buffer, true))
         else (
           Buffer.add_char buffer character;
           (buffer, false)))
       (Buffer.create (String.length value), true)
  |> fst |> Buffer.contents |> String.trim

let split_once character value =
  match String.index_opt value character with
  | None -> (value, None)
  | Some index ->
      let left = String.sub value 0 index in
      let right =
        String.sub value (index + 1) (String.length value - index - 1)
      in
      (left, Some right)

let lowercase = String.lowercase_ascii

let starts_with ~prefix value =
  let prefix_length = String.length prefix in
  String.length value >= prefix_length
  && String.sub value 0 prefix_length = prefix

let ends_with ~suffix value =
  let suffix_length = String.length suffix in
  let value_length = String.length value in
  value_length >= suffix_length
  && String.sub value (value_length - suffix_length) suffix_length = suffix

let contains ~needle value =
  try
    ignore (Str.search_forward (Str.regexp_string needle) value 0);
    true
  with Not_found -> false

let rec mkdir_p path =
  if path = "" || path = "/" || Sys.file_exists path then ()
  else (
    mkdir_p (Filename.dirname path);
    Unix.mkdir path 0o700)

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let write_private_file path contents =
  mkdir_p (Filename.dirname path);
  let temporary = path ^ ".tmp" in
  let descriptor =
    Unix.openfile temporary [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ] 0o600
  in
  let channel = Unix.out_channel_of_descr descriptor in
  Fun.protect
    ~finally:(fun () -> close_out_noerr channel)
    (fun () -> output_string channel contents);
  Unix.chmod temporary 0o600;
  Unix.rename temporary path

let default_session_path () =
  let config_home =
    match Sys.getenv_opt "XDG_CONFIG_HOME" with
    | Some path when path <> "" -> path
    | _ -> (
        match Sys.getenv_opt "HOME" with
        | Some home -> Filename.concat home ".config"
        | None -> Filename.get_temp_dir_name ())
  in
  Filename.concat config_home "manaba-cli/session.json"

let read_password prompt =
  output_string stderr prompt;
  flush stderr;
  let descriptor = Unix.descr_of_in_channel stdin in
  let original = Unix.tcgetattr descriptor in
  let hidden = { original with Unix.c_echo = false } in
  Fun.protect
    ~finally:(fun () ->
      Unix.tcsetattr descriptor Unix.TCSANOW original;
      output_char stderr '\n';
      flush stderr)
    (fun () ->
      Unix.tcsetattr descriptor Unix.TCSANOW hidden;
      input_line stdin)

let trim_line_endings value =
  let rec end_index index =
    if index > 0 && (value.[index - 1] = '\n' || value.[index - 1] = '\r') then
      end_index (index - 1)
    else index
  in
  String.sub value 0 (end_index (String.length value))

let read_macos_clipboard () =
  let command = "/usr/bin/pbpaste" in
  if not (Sys.file_exists command) then
    Error "pbpaste が見つかりません。このオプションは macOS 専用です。"
  else
    let channel = Unix.open_process_in command in
    let buffer = Buffer.create 128 in
    let temporary = Bytes.create 4096 in
    let rec read () =
      match input channel temporary 0 (Bytes.length temporary) with
      | 0 -> ()
      | count ->
          Buffer.add_subbytes buffer temporary 0 count;
          read ()
    in
    read ();
    match Unix.close_process_in channel with
    | Unix.WEXITED 0 ->
        let value = Buffer.contents buffer |> trim_line_endings in
        if value = "" then Error "クリップボードが空です。"
        else if String.contains value '\n' || String.contains value '\r' then
          Error "クリップボードに複数行が含まれています。パスワードだけをコピーしてください。"
        else Ok value
    | _ -> Error "クリップボードを読み取れませんでした。"

let deduplicate_by key values =
  let seen = Hashtbl.create 32 in
  List.filter
    (fun value ->
      let candidate = key value in
      if Hashtbl.mem seen candidate then false
      else (
        Hashtbl.add seen candidate ();
        true))
    values

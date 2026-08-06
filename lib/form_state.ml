(* A saved manaba response, so a later invocation can submit the form it
   contains without re-fetching the page. manaba re-issues the hidden
   manaba-form / SessionValue tokens on every fetch and resets screen-local
   state such as a quiz's 経過時間, so re-fetching is not a neutral operation. *)

type t = { uri : Uri.t; body : string }
type error = File_error of string | Json_error of string | Invalid of string

let error_to_string = function
  | File_error message -> message
  | Json_error message -> "JSON: " ^ message
  | Invalid message -> message

let of_response (response : Http_client.response) =
  { uri = response.uri; body = response.body }

let to_response (state : t) : Http_client.response =
  {
    Http_client.uri = state.uri;
    status = `OK;
    headers = Cohttp.Header.init ();
    body = state.body;
  }

let to_yojson state =
  `Assoc
    [
      ("schemaVersion", `Int 1);
      ("uri", `String (Uri.to_string state.uri));
      ("body", `String state.body);
    ]

let of_yojson = function
  | `Assoc entries -> (
      match
        ( List.assoc_opt "schemaVersion" entries,
          List.assoc_opt "uri" entries,
          List.assoc_opt "body" entries )
      with
      | Some (`Int 1), Some (`String uri), Some (`String body) when uri <> "" ->
          Ok { uri = Uri.of_string uri; body }
      | Some (`Int version), _, _ when version <> 1 ->
          Error
            (Invalid (Printf.sprintf "schemaVersion %d には対応していません。" version))
      | _ -> Error (Invalid "schemaVersion・uri・body が必要です。"))
  | _ -> Error (Invalid "オブジェクトが必要です。")

(* 0600: the body carries the page's hidden form tokens. *)
let save path state =
  try
    Ok (Util.write_private_file path (Yojson.Safe.to_string (to_yojson state)))
  with Sys_error message | Unix.Unix_error (_, _, message) ->
    Error (File_error message)

let load path =
  try Util.read_file path |> Yojson.Safe.from_string |> of_yojson with
  | Sys_error message -> Error (File_error message)
  | Yojson.Json_error message -> Error (Json_error message)

type step = {
  form_index : int option;
  button_name : string option;
  fields : (string * string) list;
  uploads : Http_client.upload list;
}

type t = step list

type error =
  | Invalid_value of { path : string; message : string }
  | File_error of string
  | Json_error of string

let error_to_string = function
  | Invalid_value { path; message } -> Printf.sprintf "%s: %s" path message
  | File_error message -> message
  | Json_error message -> "JSON: " ^ message

let error path message = Error (Invalid_value { path; message })

let strings path = function
  | `String value -> Ok [ value ]
  | `List values ->
      let rec collect index result = function
        | [] -> Ok (List.rev result)
        | `String value :: rest -> collect (index + 1) (value :: result) rest
        | _ :: _ -> error (Printf.sprintf "%s[%d]" path index) "文字列が必要です"
      in
      collect 0 [] values
  | _ -> error path "文字列または文字列配列が必要です"

let pairs path = function
  | None -> Ok []
  | Some (`Assoc entries) ->
      let rec collect result = function
        | [] -> Ok (List.rev result |> List.concat)
        | (name, value) :: rest -> (
            match strings (path ^ "." ^ name) value with
            | Error _ as error -> error
            | Ok values ->
                let values = List.map (fun value -> (name, value)) values in
                collect (values :: result) rest)
      in
      collect [] entries
  | Some _ -> error path "オブジェクトが必要です"

let optional_string path = function
  | None | Some `Null -> Ok None
  | Some (`String value) -> Ok (Some value)
  | Some _ -> error path "文字列が必要です"

let optional_positive_int path = function
  | None | Some `Null -> Ok None
  | Some (`Int value) when value >= 1 -> Ok (Some value)
  | Some (`Int _) -> error path "1 以上で指定してください"
  | Some _ -> error path "整数が必要です"

let member name entries = List.assoc_opt name entries

let parse_step index = function
  | `Assoc entries -> (
      let path = Printf.sprintf "$[%d]" index in
      let known = [ "form"; "button"; "fields"; "files" ] in
      let unknown =
        List.find_opt (fun (name, _) -> not (List.mem name known)) entries
      in
      match unknown with
      | Some (name, _) -> error (path ^ "." ^ name) "未対応のキーです"
      | None -> (
          match
            ( optional_positive_int (path ^ ".form") (member "form" entries),
              optional_string (path ^ ".button") (member "button" entries),
              pairs (path ^ ".fields") (member "fields" entries),
              pairs (path ^ ".files") (member "files" entries) )
          with
          | Ok form_index, Ok button_name, Ok fields, Ok files ->
              let uploads =
                List.map
                  (fun (field, path) -> Http_client.{ field; path })
                  files
              in
              Ok { form_index; button_name; fields; uploads }
          | Error message, _, _, _
          | _, Error message, _, _
          | _, _, Error message, _
          | _, _, _, Error message ->
              Error message))
  | _ -> error (Printf.sprintf "$[%d]" index) "オブジェクトが必要です"

let of_yojson = function
  | `List [] -> error "$" "1 個以上のステップが必要です"
  | `List values ->
      let rec collect index result = function
        | [] -> Ok (List.rev result)
        | value :: rest -> (
            match parse_step index value with
            | Error _ as error -> error
            | Ok step -> collect (index + 1) (step :: result) rest)
      in
      collect 0 [] values
  | _ -> error "$" "ステップ配列が必要です"

let load path =
  try Util.read_file path |> Yojson.Safe.from_string |> of_yojson with
  | Sys_error message -> Error (File_error message)
  | Yojson.Json_error message -> Error (Json_error message)

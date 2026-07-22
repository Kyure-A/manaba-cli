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

val error_to_string : error -> string
val of_yojson : Yojson.Safe.t -> (t, error) result
val load : string -> (t, error) result

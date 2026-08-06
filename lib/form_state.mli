(** A saved manaba response, so a later invocation can submit the form it
    contains without re-fetching the page. manaba mints fresh hidden manaba-form
    / SessionValue tokens on every fetch and resets screen-local state such as a
    quiz's 経過時間, so re-fetching is not a neutral operation. *)

type t = { uri : Uri.t; body : string }
type error = File_error of string | Json_error of string | Invalid of string

val error_to_string : error -> string
val of_response : Http_client.response -> t
val to_response : t -> Http_client.response
val to_yojson : t -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> (t, error) result

val save : string -> t -> (unit, error) result
(** Writes with mode 0600: the body carries the page's hidden form tokens. *)

val load : string -> (t, error) result

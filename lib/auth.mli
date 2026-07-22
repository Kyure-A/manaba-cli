type error =
  | Network of string
  | Login_failed of string
  | Unsupported_flow of string

val error_to_string : error -> string

val credential_fields :
  Types.form -> username:string -> password:string -> (string * string) list

val login :
  Http_client.t ->
  base_uri:Uri.t ->
  username:string ->
  password:string ->
  (Http_client.response, error) result Lwt.t

val status :
  Http_client.t ->
  base_uri:Uri.t ->
  (Http_client.response, [ `Logged_out | `Network of string ]) result Lwt.t

val logout : Http_client.t -> unit

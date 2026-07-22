type response = {
  uri : Uri.t;
  status : Cohttp.Code.status_code;
  headers : Cohttp.Header.t;
  body : string;
}

type t
type upload = { field : string; path : string }

val create : session_path:string -> t
val save_session : t -> unit
val clear_session : t -> unit
val get : t -> Uri.t -> response Lwt.t
val post_form : t -> Uri.t -> (string * string) list -> response Lwt.t
val get_form : t -> Uri.t -> (string * string) list -> response Lwt.t

val post_multipart :
  t -> Uri.t -> (string * string) list -> upload list -> response Lwt.t

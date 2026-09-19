type response = {
  uri : Uri.t;
  status : Cohttp.Code.status_code;
  headers : Cohttp.Header.t;
  body : string;
}

type t
type upload = { field : string; path : string }

val create : ?timeout_seconds:float -> session_path:string -> unit -> t

(* Bounds each logical request, including redirects and response-body reads.
    Defaults to 30 seconds. Requests are never automatically retried. *)
val save_session : t -> unit
val clear_session : t -> unit
val get : t -> Uri.t -> response Lwt.t
val post_form : t -> Uri.t -> (string * string) list -> response Lwt.t
val get_form : t -> Uri.t -> (string * string) list -> response Lwt.t

val post_multipart :
  t -> Uri.t -> (string * string) list -> upload list -> response Lwt.t

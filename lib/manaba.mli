type t

type error =
  | Authentication_required
  | Http_error of int * string
  | Invalid_target of string
  | Form_error of string
  | Io_error of string

type 'a outcome = ('a, error) result Lwt.t

val error_to_string : error -> string
val create : string -> string option -> t
val http : t -> Http_client.t
val base_uri : t -> Uri.t
val session_path : t -> string
val resolve : t -> string -> (Uri.t, error) result
val get : t -> string -> Http_client.response outcome

val add_fields :
  (string * string) list -> (string * string) list -> (string * string) list

val run_flow : t -> target:string -> Flow_plan.t -> Http_client.response outcome

val submit_index :
  t ->
  target:string ->
  index:int ->
  fields:(string * string) list ->
  uploads:Http_client.upload list ->
  ?button_name:string ->
  unit ->
  Http_client.response outcome

val submit_named :
  t ->
  target:string ->
  button_name:string ->
  fields:(string * string) list ->
  uploads:Http_client.upload list ->
  Http_client.response outcome

(** [submit_response_index] and [submit_response_named] submit a form found in
    an already-held response instead of fetching the page again. manaba mints
    fresh hidden tokens on every fetch and resets screen-local state such as a
    quiz's 経過時間, so re-fetching is not a neutral operation. *)

val submit_response_index :
  t ->
  source_response:Http_client.response ->
  index:int ->
  fields:(string * string) list ->
  uploads:Http_client.upload list ->
  ?button_name:string ->
  unit ->
  Http_client.response outcome

val submit_response_named :
  t ->
  source_response:Http_client.response ->
  button_name:string ->
  fields:(string * string) list ->
  uploads:Http_client.upload list ->
  Http_client.response outcome

val memo_set : t -> class_:int -> text:string -> Http_client.response outcome

val thread_create :
  t ->
  course_id:int ->
  subject:string ->
  text:string ->
  Http_client.response outcome

val profile_update :
  t -> text:string -> image:string option -> Http_client.response outcome

val display_count : t -> int -> Http_client.response outcome

val registration_search :
  t ->
  course_code:string ->
  name:string ->
  teacher:string ->
  Http_client.response outcome

val registration_key : t -> string -> Http_client.response outcome
val report_is_submitted : string -> bool

val report_submit :
  t ->
  course_id:int ->
  report_id:int ->
  file:string ->
  Http_client.response outcome

val report_cancel :
  t -> course_id:int -> report_id:int -> Http_client.response outcome

val favorite :
  t -> course_id:int -> desired:bool -> Http_client.response outcome

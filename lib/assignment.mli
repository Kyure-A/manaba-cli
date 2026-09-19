type fact = { label : string; value : string }
(** Conservative assignment views. Missing/unrecognized evidence is [None],
    never a negative answer. Labels and dates are preserved verbatim. *)

type question = {
  name : string;
  prompt : string option;
  controls : Types.form_control list;
}

type t = {
  path : string;
  kind : Types.task_kind;
  course_id : int option;
  id : int option;
  title : string option;
  deadline : string option;
  resubmission : bool option;
  status : string option;
  submitted_at : string option;
  answer_count : int option;
  file_count : int option;
  submitted_files : Types.link list;
  questions : question list;
  facts : fact list;
  forms : Types.form list;
  warnings : string list;
}

val parse : path:string -> string -> t
val is_submitted : t -> bool

val verify_report :
  before:t -> preview:t -> fresh:t -> filename:string -> (unit, string) result

val to_yojson : t -> Yojson.Safe.t

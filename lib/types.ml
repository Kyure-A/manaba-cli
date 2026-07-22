type course = { id : int; name : string }
type task_kind = Quiz | Drill | Survey | Report | External | Unknown of string

type task = {
  kind : task_kind;
  id : int option;
  course_id : int option;
  title : string;
  course : string;
  starts_at : string option;
  ends_at : string option;
  href : string;
}

type link = { text : string; href : string }
type form_option = { value : string; label : string; selected : bool }

type form_control = {
  tag : string;
  input_type : string;
  name : string option;
  value : string option;
  options : form_option list;
  multiple : bool;
}

type form = {
  action : string;
  method_ : string;
  enctype : string;
  controls : form_control list;
}

let task_kind_to_string = function
  | Quiz -> "quiz"
  | Drill -> "drill"
  | Survey -> "survey"
  | Report -> "report"
  | External -> "external"
  | Unknown value -> value

let course_to_yojson (course : course) =
  `Assoc [ ("id", `Int course.id); ("name", `String course.name) ]

let option_to_yojson convert = function
  | None -> `Null
  | Some value -> convert value

let task_to_yojson (task : task) =
  `Assoc
    [
      ("kind", `String (task_kind_to_string task.kind));
      ("id", option_to_yojson (fun value -> `Int value) task.id);
      ("course_id", option_to_yojson (fun value -> `Int value) task.course_id);
      ("title", `String task.title);
      ("course", `String task.course);
      ("starts_at", option_to_yojson (fun value -> `String value) task.starts_at);
      ("ends_at", option_to_yojson (fun value -> `String value) task.ends_at);
      ("href", `String task.href);
    ]

let link_to_yojson (link : link) =
  `Assoc [ ("text", `String link.text); ("href", `String link.href) ]

let form_option_to_yojson (option : form_option) =
  `Assoc
    [
      ("value", `String option.value);
      ("label", `String option.label);
      ("selected", `Bool option.selected);
    ]

let public_form_control_to_yojson (control : form_control) =
  let sensitive =
    control.input_type = "hidden" || control.input_type = "password"
  in
  `Assoc
    ([
       ("tag", `String control.tag);
       ("type", `String control.input_type);
       ("name", option_to_yojson (fun value -> `String value) control.name);
       ("multiple", `Bool control.multiple);
       ("options", `List (List.map form_option_to_yojson control.options));
     ]
    @
    if sensitive then []
    else
      [ ("value", option_to_yojson (fun value -> `String value) control.value) ]
    )

let public_form_to_yojson (form : form) =
  `Assoc
    [
      ("action", `String form.action);
      ("method", `String form.method_);
      ("enctype", `String form.enctype);
      ("controls", `List (List.map public_form_control_to_yojson form.controls));
    ]

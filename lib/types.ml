type course = { id : int; name : string }
type task_kind = Quiz | Drill | Survey | Report | External | Unknown of string
type form_method = Get | Post | Other_method of string
type form_enctype = Url_encoded | Multipart | Other_enctype of string
type control_tag = Input | Textarea | Select | Button | Other_tag of string

type input_type =
  | Text
  | Password
  | Hidden
  | Checkbox
  | Radio
  | File
  | Submit
  | Image
  | Reset
  | Button_type
  | Select_type
  | Textarea_type
  | Other_input_type of string

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
  tag : control_tag;
  input_type : input_type;
  name : string option;
  value : string option;
  options : form_option list;
  multiple : bool;
}

type form = {
  action : string;
  method_ : form_method;
  enctype : form_enctype;
  controls : form_control list;
}

let task_kind_to_string = function
  | Quiz -> "quiz"
  | Drill -> "drill"
  | Survey -> "survey"
  | Report -> "report"
  | External -> "external"
  | Unknown value -> value

let form_method_of_string = function
  | "get" -> Get
  | "post" -> Post
  | value -> Other_method value

let form_method_to_string = function
  | Get -> "get"
  | Post -> "post"
  | Other_method value -> value

let form_enctype_of_string = function
  | "application/x-www-form-urlencoded" -> Url_encoded
  | "multipart/form-data" -> Multipart
  | value -> Other_enctype value

let form_enctype_to_string = function
  | Url_encoded -> "application/x-www-form-urlencoded"
  | Multipart -> "multipart/form-data"
  | Other_enctype value -> value

let control_tag_of_string = function
  | "input" -> Input
  | "textarea" -> Textarea
  | "select" -> Select
  | "button" -> Button
  | value -> Other_tag value

let control_tag_to_string = function
  | Input -> "input"
  | Textarea -> "textarea"
  | Select -> "select"
  | Button -> "button"
  | Other_tag value -> value

let input_type_of_string = function
  | "text" -> Text
  | "password" -> Password
  | "hidden" -> Hidden
  | "checkbox" -> Checkbox
  | "radio" -> Radio
  | "file" -> File
  | "submit" -> Submit
  | "image" -> Image
  | "reset" -> Reset
  | "button" -> Button_type
  | "select" -> Select_type
  | "textarea" -> Textarea_type
  | value -> Other_input_type value

let input_type_to_string = function
  | Text -> "text"
  | Password -> "password"
  | Hidden -> "hidden"
  | Checkbox -> "checkbox"
  | Radio -> "radio"
  | File -> "file"
  | Submit -> "submit"
  | Image -> "image"
  | Reset -> "reset"
  | Button_type -> "button"
  | Select_type -> "select"
  | Textarea_type -> "textarea"
  | Other_input_type value -> value

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
    control.input_type = Hidden || control.input_type = Password
  in
  `Assoc
    ([
       ("tag", `String (control_tag_to_string control.tag));
       ("type", `String (input_type_to_string control.input_type));
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
      ("method", `String (form_method_to_string form.method_));
      ("enctype", `String (form_enctype_to_string form.enctype));
      ("controls", `List (List.map public_form_control_to_yojson form.controls));
    ]

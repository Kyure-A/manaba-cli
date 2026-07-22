type course = { id : int; name : string }
type task_kind = Quiz | Drill | Survey | Report | External | Unknown of string
type form_method = private Get | Post | Other_method of string
type form_enctype = private Url_encoded | Multipart | Other_enctype of string

type control_tag = private
  | Input
  | Textarea
  | Select
  | Button
  | Other_tag of string

type input_type = private
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

val task_kind_to_string : task_kind -> string
val form_method_of_string : string -> form_method
val form_method_to_string : form_method -> string
val form_enctype_of_string : string -> form_enctype
val form_enctype_to_string : form_enctype -> string
val control_tag_of_string : string -> control_tag
val control_tag_to_string : control_tag -> string
val input_type_of_string : string -> input_type
val input_type_to_string : input_type -> string
val course_to_yojson : course -> Yojson.Safe.t
val task_to_yojson : task -> Yojson.Safe.t
val link_to_yojson : link -> Yojson.Safe.t
val public_form_to_yojson : form -> Yojson.Safe.t

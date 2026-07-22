val courses : string -> Types.course list
val tasks : string -> Types.task list
val links : string -> Types.link list
val forms : string -> Types.form list
val default_fields : Types.form -> (string * string) list

val submission_fields :
  ?button_name:string -> Types.form -> (string * string) list

val contains_password : Types.form -> bool
val contains_control : string -> Types.form -> bool
val find_form_by_control : string -> Types.form list -> Types.form option
val submit_controls : Types.form -> Types.form_control list
val file_controls : Types.form -> Types.form_control list
val main_text : string -> string
val is_logged_in : string -> bool

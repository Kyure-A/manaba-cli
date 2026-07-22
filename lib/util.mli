val normalize_space : string -> string
val split_once : char -> string -> string * string option
val lowercase : string -> string
val starts_with : prefix:string -> string -> bool
val ends_with : suffix:string -> string -> bool
val contains : needle:string -> string -> bool
val read_file : string -> string
val write_private_file : string -> string -> unit
val default_session_path : unit -> string
val read_password : string -> string
val read_macos_clipboard : unit -> (string, string) result
val deduplicate_by : ('a -> 'b) -> 'a list -> 'a list

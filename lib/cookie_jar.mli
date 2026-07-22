type t

val load : string -> t
val save : t -> unit
val clear : t -> unit
val header : t -> Uri.t -> string option
val absorb_headers : t -> origin:Uri.t -> Cohttp.Header.t -> unit

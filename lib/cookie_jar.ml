type cookie = {
  name : string;
  value : string;
  domain : string;
  path : string;
  secure : bool;
  host_only : bool;
}

type t = { mutable cookies : cookie list; path : string }

let cookie_to_yojson cookie =
  `Assoc
    [
      ("name", `String cookie.name);
      ("value", `String cookie.value);
      ("domain", `String cookie.domain);
      ("path", `String cookie.path);
      ("secure", `Bool cookie.secure);
      ("host_only", `Bool cookie.host_only);
    ]

let cookie_of_yojson json =
  let open Yojson.Safe.Util in
  {
    name = json |> member "name" |> to_string;
    value = json |> member "value" |> to_string;
    domain = json |> member "domain" |> to_string;
    path = json |> member "path" |> to_string;
    secure = json |> member "secure" |> to_bool;
    host_only = json |> member "host_only" |> to_bool;
  }

let load path =
  let cookies =
    if Sys.file_exists path then
      try
        Util.read_file path |> Yojson.Safe.from_string
        |> Yojson.Safe.Util.to_list |> List.map cookie_of_yojson
      with _ -> []
    else []
  in
  { cookies; path }

let save jar =
  jar.cookies |> List.map cookie_to_yojson |> fun cookies ->
  `List cookies |> Yojson.Safe.pretty_to_string
  |> Util.write_private_file jar.path

let clear jar =
  jar.cookies <- [];
  if Sys.file_exists jar.path then Sys.remove jar.path

let default_cookie_path request_path =
  if request_path = "" || request_path.[0] <> '/' then "/"
  else
    match String.rindex_opt request_path '/' with
    | None | Some 0 -> "/"
    | Some index -> String.sub request_path 0 index

let domain_matches ~host (cookie : cookie) =
  if cookie.host_only then host = cookie.domain
  else host = cookie.domain || Util.ends_with ~suffix:("." ^ cookie.domain) host

let path_matches ~request_path (cookie : cookie) =
  cookie.path = "/" || Util.starts_with ~prefix:cookie.path request_path

let header jar uri =
  let host = Uri.host uri |> Option.value ~default:"" |> Util.lowercase in
  let request_path = Uri.path uri in
  let is_secure = Uri.scheme uri = Some "https" in
  jar.cookies
  |> List.filter (fun cookie ->
      domain_matches ~host cookie
      && path_matches ~request_path cookie
      && ((not cookie.secure) || is_secure))
  |> List.map (fun cookie -> cookie.name ^ "=" ^ cookie.value)
  |> function
  | [] -> None
  | values -> Some (String.concat "; " values)

let replace jar cookie =
  jar.cookies <-
    cookie
    :: List.filter
         (fun current ->
           not
             (current.name = cookie.name
             && current.domain = cookie.domain
             && current.path = cookie.path))
         jar.cookies

let remove jar cookie =
  jar.cookies <-
    List.filter
      (fun current ->
        not
          (current.name = cookie.name
          && current.domain = cookie.domain
          && current.path = cookie.path))
      jar.cookies

let absorb_set_cookie jar ~origin value =
  let parts = String.split_on_char ';' value |> List.map String.trim in
  match parts with
  | [] -> ()
  | pair :: attributes -> (
      let name, value = Util.split_once '=' pair in
      match (String.trim name, value) with
      | "", _ | _, None -> ()
      | name, Some value ->
          let origin_host =
            Uri.host origin |> Option.value ~default:"" |> Util.lowercase
          in
          let domain = ref origin_host in
          let host_only = ref true in
          let path = ref (default_cookie_path (Uri.path origin)) in
          let secure = ref false in
          let delete = ref false in
          List.iter
            (fun attribute ->
              let key, attribute_value = Util.split_once '=' attribute in
              match (Util.lowercase (String.trim key), attribute_value) with
              | "domain", Some candidate ->
                  let candidate =
                    candidate |> String.trim |> Util.lowercase |> fun value ->
                    if Util.starts_with ~prefix:"." value then
                      String.sub value 1 (String.length value - 1)
                    else value
                  in
                  domain := candidate;
                  host_only := false
              | "path", Some candidate -> path := String.trim candidate
              | "secure", _ -> secure := true
              | "max-age", Some candidate when String.trim candidate = "0" ->
                  delete := true
              | _ -> ())
            attributes;
          let cookie =
            {
              name;
              value;
              domain = !domain;
              path = !path;
              secure = !secure;
              host_only = !host_only;
            }
          in
          if !delete then remove jar cookie else replace jar cookie)

let absorb_headers jar ~origin headers =
  Cohttp.Header.get_multi headers "set-cookie"
  |> List.iter (absorb_set_cookie jar ~origin)

type cookie = {
  name : string;
  value : string;
  domain : string;
  path : string;
  secure : bool;
  host_only : bool;
  expires_at : float option;
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
      ( "expires_at",
        Option.fold ~none:`Null
          ~some:(fun time -> `Float time)
          cookie.expires_at );
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
    expires_at =
      (match member "expires_at" json with
      | `Null -> None
      | value -> Some (to_number value));
  }

let expired ~now cookie =
  match cookie.expires_at with
  | Some time -> (not (Float.is_finite time)) || time <= now
  | None -> false

(* An OpenSAML request correlation cookie belongs to one login roundtrip.
   Carrying it between processes accumulates stale cookies at the SAML endpoint,
   eventually making Apache reject the Cookie header before authentication. *)
let persistent cookie =
  not (Util.starts_with ~prefix:"_opensaml_req_" cookie.name)

let load path =
  let cookies =
    if Sys.file_exists path then
      try
        Util.read_file path |> Yojson.Safe.from_string
        |> Yojson.Safe.Util.to_list |> List.map cookie_of_yojson
        |> List.filter (fun cookie ->
            persistent cookie
            && not (expired ~now:(Unix.gettimeofday ()) cookie))
      with _ -> []
    else []
  in
  { cookies; path }

let save jar =
  jar.cookies
  |> List.filter (fun cookie ->
      persistent cookie && not (expired ~now:(Unix.gettimeofday ()) cookie))
  |> List.map cookie_to_yojson
  |> fun cookies ->
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
  let now = Unix.gettimeofday () in
  jar.cookies
  |> List.filter (fun cookie ->
      (not (expired ~now cookie))
      && domain_matches ~host cookie
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

let cookie_date value =
  let day = ref None
  and month = ref None
  and year = ref None
  and time = ref None in
  let digits token min_length max_length =
    let length = String.length token in
    length >= min_length && length <= max_length
    && String.for_all (fun char -> char >= '0' && char <= '9') token
  in
  let months =
    [
      "jan";
      "feb";
      "mar";
      "apr";
      "may";
      "jun";
      "jul";
      "aug";
      "sep";
      "oct";
      "nov";
      "dec";
    ]
  in
  Str.split (Str.regexp "[^A-Za-z0-9:]+") value
  |> List.iter (fun token ->
      match String.split_on_char ':' token with
      | [ hour; minute; second ]
        when !time = None
             && List.for_all
                  (fun part -> digits part 1 2)
                  [ hour; minute; second ] ->
          time :=
            Some (int_of_string hour, int_of_string minute, int_of_string second)
      | _ when !day = None && digits token 1 2 -> day := int_of_string_opt token
      | _ when !month = None && List.mem (Util.lowercase token) months ->
          month :=
            List.mapi (fun index value -> (index, value)) months
            |> List.find_opt (fun (_, value) -> value = Util.lowercase token)
            |> Option.map fst
      | _ when !year = None && digits token 2 4 ->
          year := int_of_string_opt token
      | _ -> ());
  match (!day, !month, !year, !time) with
  | Some day, Some month, Some year, Some (hour, minute, second) ->
      let year =
        if year >= 70 && year <= 99 then year + 1900
        else if year <= 69 then year + 2000
        else year
      in
      let leap year =
        year mod 4 = 0 && (year mod 100 <> 0 || year mod 400 = 0)
      in
      let month_days =
        [|
          31;
          (if leap year then 29 else 28);
          31;
          30;
          31;
          30;
          31;
          31;
          30;
          31;
          30;
          31;
        |]
      in
      if
        year < 1601 || day < 1
        || day > month_days.(month)
        || hour > 23 || minute > 59 || second > 59
      then None
      else
        let days_before_year year =
          let previous = year - 1 in
          (365 * previous) + (previous / 4) - (previous / 100) + (previous / 400)
        in
        let days =
          ref (days_before_year year - days_before_year 1970 + day - 1)
        in
        for index = 0 to month - 1 do
          days := !days + month_days.(index)
        done;
        Some
          ((float_of_int !days *. 86400.)
          +. float_of_int ((hour * 3600) + (minute * 60) + second))
  | _ -> None

let max_age value =
  let value = String.trim value in
  if not (Str.string_match (Str.regexp "^-?[0-9]+$") value 0) then None
  else
    match Int64.of_string_opt value with
    | Some age -> Some age
    | None -> Some (if value.[0] = '-' then Int64.min_int else Int64.max_int)

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
          let expires = ref None and age = ref None in
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
              | "expires", Some candidate ->
                  Option.iter
                    (fun time -> expires := Some time)
                    (cookie_date candidate)
              | "max-age", Some candidate ->
                  Option.iter
                    (fun value -> age := Some value)
                    (max_age candidate)
              | _ -> ())
            attributes;
          let now = Unix.gettimeofday () in
          let expires_at =
            match !age with
            | Some seconds when seconds <= 0L -> Some 0.
            | Some seconds ->
                Some (min 253402300799. (now +. Int64.to_float seconds))
            | None -> !expires
          in
          let cookie =
            {
              name;
              value;
              domain = !domain;
              path = !path;
              secure = !secure;
              host_only = !host_only;
              expires_at;
            }
          in
          if expired ~now cookie then remove jar cookie else replace jar cookie)

let absorb_headers jar ~origin headers =
  Cohttp.Header.get_multi headers "set-cookie"
  |> List.iter (absorb_set_cookie jar ~origin)

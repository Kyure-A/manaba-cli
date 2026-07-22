open Lwt.Infix

type response = {
  uri : Uri.t;
  status : Cohttp.Code.status_code;
  headers : Cohttp.Header.t;
  body : string;
}

type t = {
  jar : Cookie_jar.t;
  user_agent : string;
  context : Cohttp_lwt_unix.Client.ctx;
}

let resolver () =
  Resolver_lwt.init ~service:Resolver_lwt_unix.static_service
    ~rewrites:[ ("", Resolver_lwt_unix.system_resolver) ]
    ()

let create ~session_path =
  {
    jar = Cookie_jar.load session_path;
    user_agent = "manaba-cli/0.1 (+https://github.com/Kyure-A/manaba-cli)";
    context = Cohttp_lwt_unix.Client.custom_ctx ~resolver:(resolver ()) ();
  }

let add_default_headers client uri headers =
  let headers =
    Cohttp.Header.add_unless_exists headers "user-agent" client.user_agent
  in
  let headers =
    Cohttp.Header.add_unless_exists headers "accept-language" "ja,en;q=0.8"
  in
  match Cookie_jar.header client.jar uri with
  | None -> headers
  | Some cookies -> Cohttp.Header.replace headers "cookie" cookies

let redirected_method status method_ body =
  match (Cohttp.Code.code_of_status status, method_) with
  | (301 | 302 | 303), (`POST | `PUT | `PATCH | `DELETE) -> (`GET, None)
  | _ -> (method_, body)

let rec request ?(headers = Cohttp.Header.init ()) ?body ?(redirects = 12)
    client method_ uri =
  let request_body = body in
  let headers = add_default_headers client uri headers in
  let body = Option.map Cohttp_lwt.Body.of_string body in
  Cohttp_lwt_unix.Client.call ~ctx:client.context ?body ~headers method_ uri
  >>= fun (response, body) ->
  Cohttp_lwt.Body.to_string body >>= fun body_string ->
  let status = Cohttp.Response.status response in
  let response_headers = Cohttp.Response.headers response in
  Cookie_jar.absorb_headers client.jar ~origin:uri response_headers;
  match (Cohttp.Header.get response_headers "location", redirects) with
  | Some location, remaining
    when remaining > 0
         && List.mem
              (Cohttp.Code.code_of_status status)
              [ 301; 302; 303; 307; 308 ] ->
      let destination = Uri.resolve "" uri (Uri.of_string location) in
      let next_method, next_body =
        redirected_method status method_ request_body
      in
      request ~headers:(Cohttp.Header.init ()) ?body:next_body
        ~redirects:(remaining - 1) client next_method destination
  | _ ->
      Lwt.return { uri; status; headers = response_headers; body = body_string }

let get client uri = request client `GET uri

let form_body fields =
  fields
  |> List.map (fun (name, value) -> (name, [ value ]))
  |> Uri.encoded_of_query

let post_form client uri fields =
  let headers =
    Cohttp.Header.init_with "content-type" "application/x-www-form-urlencoded"
  in
  request ~headers ~body:(form_body fields) client `POST uri

let get_form client uri fields =
  let query =
    fields
    |> List.fold_left
         (fun query (name, value) -> Uri.add_query_param' query (name, value))
         uri
  in
  get client query

type upload = { field : string; path : string }

let multipart_body fields uploads =
  let boundary =
    Printf.sprintf "----manaba-cli-%08x%08x" (Random.bits ()) (Random.bits ())
  in
  let buffer = Buffer.create 4096 in
  let line value =
    Buffer.add_string buffer value;
    Buffer.add_string buffer "\r\n"
  in
  List.iter
    (fun (name, value) ->
      line ("--" ^ boundary);
      line (Printf.sprintf "Content-Disposition: form-data; name=\"%s\"" name);
      line "";
      line value)
    fields;
  List.iter
    (fun upload ->
      let filename = Filename.basename upload.path in
      let contents = Util.read_file upload.path in
      line ("--" ^ boundary);
      line
        (Printf.sprintf
           "Content-Disposition: form-data; name=\"%s\"; filename=\"%s\""
           upload.field filename);
      line "Content-Type: application/octet-stream";
      line "";
      Buffer.add_string buffer contents;
      Buffer.add_string buffer "\r\n")
    uploads;
  line ("--" ^ boundary ^ "--");
  (boundary, Buffer.contents buffer)

let post_multipart client uri fields uploads =
  let boundary, body = multipart_body fields uploads in
  let headers =
    Cohttp.Header.init_with "content-type"
      ("multipart/form-data; boundary=" ^ boundary)
  in
  request ~headers ~body client `POST uri

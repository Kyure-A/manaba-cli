open Lwt.Infix

type error =
  | Network of string
  | Login_failed of string
  | Unsupported_flow of string

let error_to_string = function
  | Network message -> message
  | Login_failed message -> message
  | Unsupported_flow message -> message

let resolve_action response action =
  if action = "" then response.Http_client.uri
  else Uri.resolve "" response.uri (Uri.of_string action)

let merge_field name value fields =
  (name, value) :: List.remove_assoc name fields

let username_control control =
  match control.Types.name with
  | None -> false
  | Some name ->
      let name = Util.lowercase name in
      name = "j_username" || name = "username" || name = "user"
      || Util.contains ~needle:"username" name

let credential_fields form ~username ~password =
  List.fold_left
    (fun fields control ->
      match control.Types.name with
      | Some name
        when match control.input_type with Types.Password -> true | _ -> false
        ->
          merge_field name password fields
      | Some name when username_control control ->
          merge_field name username fields
      | _ -> fields)
    (Html.submission_fields form)
    form.Types.controls

let post_form client response form fields =
  let destination = resolve_action response form.Types.action in
  match form.method_ with
  | Types.Get -> Http_client.get_form client destination fields
  | Types.Post | Types.Other_method _ ->
      Http_client.post_form client destination fields

(* Keep diagnostics to fixed labels and counts. Authentication responses may
   contain credentials, assertions, cookies, or tokens even in their URLs. *)
let response_context ~base_uri ~step ~credentials_sent response forms =
  let origin uri =
    let scheme = Option.map Util.lowercase (Uri.scheme uri) in
    let port =
      match (Uri.port uri, scheme) with
      | Some port, _ -> Some port
      | None, Some "https" -> Some 443
      | None, Some "http" -> Some 80
      | _ -> None
    in
    (scheme, Option.map Util.lowercase (Uri.host uri), port)
  in
  let body = Util.lowercase response.Http_client.body in
  let page =
    if Util.contains ~needle:"stale request" body then "stale_request"
    else if Util.contains ~needle:"saving session information" body then
      "saving_session"
    else if Util.contains ~needle:"loading session information" body then
      "loading_session"
    else "unknown"
  in
  let soup = Soup.parse response.body in
  let logout_link =
    Html.links response.body
    |> List.exists (fun link ->
        Util.contains ~needle:"logout" (Util.lowercase link.Types.href))
  in
  let meta_refresh =
    Soup.select "meta[http-equiv]" soup
    |> Soup.to_list
    |> List.exists (fun node ->
        Option.map Util.lowercase (Soup.attribute "http-equiv" node)
        = Some "refresh")
  in
  let script_redirect =
    Soup.select "script" soup |> Soup.to_list
    |> List.exists (fun node ->
        let script =
          Soup.trimmed_texts node |> String.concat " " |> Util.lowercase
        in
        List.exists
          (fun needle -> Util.contains ~needle script)
          [
            "window.location";
            "location.href";
            "location.replace";
            "location.assign";
          ])
  in
  Printf.sprintf
    "http_status=%d step=%d credentials_sent=%b forms=%d password_form=%b \
     saml_form=%b origin=%s page=%s logout_link=%b logout_marker=%b \
     meta_refresh=%b script_redirect=%b"
    (Cohttp.Code.code_of_status response.status)
    step credentials_sent (List.length forms)
    (List.exists Html.contains_password forms)
    (List.exists (Html.contains_control "SAMLResponse") forms)
    (if origin response.uri = origin base_uri then "manaba" else "external")
    page logout_link
    (Html.is_logged_in response.body)
    meta_refresh script_redirect

let login client ~base_uri ~username ~password =
  let start = Uri.resolve "" base_uri (Uri.of_string "./") in
  let rec continue remaining credentials_sent response =
    if remaining = 0 then
      Lwt.return
        (Error (Unsupported_flow "認証画面の遷移回数が上限を超えました。サイトの認証方式が変更された可能性があります。"))
    else if Html.is_logged_in response.Http_client.body then (
      Http_client.save_session client;
      Lwt.return (Ok response))
    else
      let forms = Html.forms response.body in
      match List.find_opt Html.contains_password forms with
      | Some _ when credentials_sent ->
          Lwt.return
            (Error (Login_failed "ログインに失敗しました。統一認証 ID またはパスワードを確認してください。"))
      | Some form ->
          let fields = credential_fields form ~username ~password in
          post_form client response form fields
          >>= continue (remaining - 1) true
      | None -> (
          match List.find_opt (Html.contains_control "SAMLResponse") forms with
          | Some form ->
              post_form client response form (Html.default_fields form)
              >>= continue (remaining - 1) credentials_sent
          | None -> (
              match forms with
              | [ form ] ->
                  post_form client response form (Html.default_fields form)
                  >>= continue (remaining - 1) credentials_sent
              | _ ->
                  let detail =
                    response_context ~base_uri ~step:(11 - remaining)
                      ~credentials_sent response forms
                  in
                  Lwt.return
                    (Error
                       (Unsupported_flow
                          ("自動処理できない認証画面が表示されました。 (" ^ detail ^ ")")))))
  in
  Lwt.catch
    (fun () -> Http_client.get client start >>= continue 10 false)
    (fun exception_ ->
      Lwt.return (Error (Network (Printexc.to_string exception_))))

let status client ~base_uri =
  let uri = Uri.resolve "" base_uri (Uri.of_string "home") in
  Lwt.catch
    (fun () ->
      Http_client.get client uri >|= fun response ->
      if Html.is_logged_in response.body then Ok response else Error `Logged_out)
    (fun exception_ ->
      Lwt.return (Error (`Network (Printexc.to_string exception_))))

let logout = Http_client.clear_session

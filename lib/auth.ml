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
      | Some name when control.input_type = "password" ->
          merge_field name password fields
      | Some name when username_control control ->
          merge_field name username fields
      | _ -> fields)
    (Html.submission_fields form)
    form.Types.controls

let post_form client response form fields =
  let destination = resolve_action response form.Types.action in
  if form.method_ = "get" then Http_client.get_form client destination fields
  else Http_client.post_form client destination fields

let login client ~base_uri ~username ~password =
  let start = Uri.resolve "" base_uri (Uri.of_string "./") in
  let rec continue remaining credentials_sent response =
    if remaining = 0 then
      Lwt.return
        (Error (Unsupported_flow "認証画面の遷移回数が上限を超えました。サイトの認証方式が変更された可能性があります。"))
    else if Html.is_logged_in response.Http_client.body then (
      Cookie_jar.save client.Http_client.jar;
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
                  let visible = Html.main_text response.body in
                  let detail =
                    if
                      Util.contains ~needle:"Authentication failed" visible
                      || Util.contains ~needle:"認証" visible
                    then "ID またはパスワードを確認してください。"
                    else "自動処理できない確認画面が表示されました。ブラウザでログインできることを確認してください。"
                  in
                  Lwt.return (Error (Login_failed detail))))
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

let logout client = Cookie_jar.clear client.Http_client.jar

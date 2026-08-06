open Lwt.Infix

type t = { http : Http_client.t; base_uri : Uri.t; session_path : string }

type error =
  | Authentication_required
  | Http_error of int * string
  | Invalid_target of string
  | Form_error of string
  | Io_error of string

type 'a outcome = ('a, error) result Lwt.t

let error_to_string = function
  | Authentication_required -> "ログインが必要です。`manaba auth login` を実行してください。"
  | Http_error (status, message) -> Printf.sprintf "HTTP %d: %s" status message
  | Invalid_target message -> message
  | Form_error message -> message
  | Io_error message -> message

let normalize_base value =
  let value = if Util.ends_with ~suffix:"/" value then value else value ^ "/" in
  Uri.of_string value

let create base_url session_path =
  let session_path =
    match session_path with
    | Some path -> path
    | None -> Util.default_session_path ()
  in
  {
    http = Http_client.create ~session_path;
    base_uri = normalize_base base_url;
    session_path;
  }

let http client = client.http
let base_uri client = client.base_uri
let session_path client = client.session_path

let effective_port uri =
  match Uri.port uri with
  | Some port -> Some port
  | None -> (
      match Uri.scheme uri with
      | Some "https" -> Some 443
      | Some "http" -> Some 80
      | _ -> None)

let same_origin left right =
  Uri.scheme left = Uri.scheme right
  && Uri.host left = Uri.host right
  && effective_port left = effective_port right

let resolve client target =
  let candidate = Uri.of_string target in
  let uri =
    match Uri.scheme candidate with
    | Some _ -> candidate
    | None -> Uri.resolve "" client.base_uri candidate
  in
  if not (same_origin client.base_uri uri) then
    Error
      (Invalid_target "設定した manaba のオリジン（scheme・host・port）以外にはリクエストを送信しません。")
  else Ok uri

let looks_like_login client response =
  Uri.host response.Http_client.uri <> Uri.host client.base_uri
  || Util.contains ~needle:"Unified Authentication System" response.body

let validate client response =
  if looks_like_login client response then Error Authentication_required
  else
    let status = Cohttp.Code.code_of_status response.Http_client.status in
    if status >= 200 && status < 400 then Ok response
    else
      Error (Http_error (status, Cohttp.Code.string_of_status response.status))

let persist client = Http_client.save_session client.http

let get client target =
  match resolve client target with
  | Error error -> Lwt.return (Error error)
  | Ok uri ->
      Lwt.catch
        (fun () ->
          Http_client.get client.http uri >|= fun response ->
          let result = validate client response in
          (match result with Ok _ -> persist client | Error _ -> ());
          result)
        (fun exception_ ->
          Lwt.return (Error (Io_error (Printexc.to_string exception_))))

let add_fields defaults overrides =
  let overridden_names = List.map fst overrides in
  List.filter
    (fun (name, _) -> not (List.exists (( = ) name) overridden_names))
    defaults
  @ overrides

let selected_button form button_name =
  let buttons = Html.submit_controls form in
  let contains name =
    List.exists (fun control -> control.Types.name = Some name) buttons
  in
  match button_name with
  | Some name ->
      if contains name then Ok (Some name)
      else Error (Form_error (Printf.sprintf "送信ボタン %s がフォーム内にありません。" name))
  | None -> (
      match buttons with
      | [] -> Ok None
      | [ { Types.name = Some name; _ } ] -> Ok (Some name)
      | [ _ ] -> Ok None
      | _ -> Error (Form_error "送信ボタンが複数あります。--button で押すボタンの name を指定してください。"))

let submit_form client ~source_response ~form ~fields ~uploads ?button_name () =
  let action =
    if form.Types.action = "" then source_response.Http_client.uri
    else Uri.resolve "" source_response.uri (Uri.of_string form.action)
  in
  match
    (resolve client (Uri.to_string action), selected_button form button_name)
  with
  | Error error, _ -> Lwt.return (Error error)
  | _, Error error -> Lwt.return (Error error)
  | Ok uri, Ok button_name ->
      let fields =
        Html.submission_fields ?button_name form |> fun defaults ->
        add_fields defaults fields
      in
      let request =
        match form.method_ with
        | Types.Get -> Http_client.get_form client.http uri fields
        | Types.Post | Types.Other_method _ -> (
            match form.enctype with
            | Types.Multipart ->
                Http_client.post_multipart client.http uri fields uploads
            | Types.Url_encoded | Types.Other_enctype _ ->
                if uploads = [] then
                  Http_client.post_form client.http uri fields
                else Http_client.post_multipart client.http uri fields uploads)
      in
      Lwt.catch
        (fun () ->
          request >|= fun response ->
          let result = validate client response in
          (match result with Ok _ -> persist client | Error _ -> ());
          result)
        (fun exception_ ->
          Lwt.return (Error (Io_error (Printexc.to_string exception_))))

let select_form forms index =
  if index < 1 then Error (Form_error "フォーム番号は 1 以上で指定してください。")
  else
    match List.nth_opt forms (index - 1) with
    | Some form -> Ok form
    | None ->
        Error
          (Form_error
             (Printf.sprintf "フォーム %d はありません（検出数: %d）。" index
                (List.length forms)))

let form_has_button name form =
  Html.submit_controls form
  |> List.exists (fun control -> control.Types.name = Some name)

let flow_form response (step : Flow_plan.step) =
  let forms = Html.forms response.Http_client.body in
  match step.form_index with
  | Some index -> (
      match select_form forms index with
      | Error _ as error -> error
      | Ok form -> (
          match step.button_name with
          | Some name when not (form_has_button name form) ->
              Error
                (Form_error
                   (Printf.sprintf "フォーム %d に送信ボタン %s がありません。" index name))
          | _ -> Ok form))
  | None -> (
      match step.button_name with
      | None -> select_form forms 1
      | Some name -> (
          match List.filter (form_has_button name) forms with
          | [ form ] -> Ok form
          | [] -> Error (Form_error (Printf.sprintf "送信ボタン %s が見つかりません。" name))
          | _ ->
              Error
                (Form_error
                   (Printf.sprintf "送信ボタン %s を含むフォームが複数あります。form を指定してください。"
                      name))))

let run_flow client ~target (steps : Flow_plan.t) =
  let rec run index response = function
    | [] -> Lwt.return (Ok response)
    | step :: rest -> (
        match flow_form response step with
        | Error (Form_error message) ->
            Lwt.return
              (Error (Form_error (Printf.sprintf "ステップ %d: %s" index message)))
        | Error error -> Lwt.return (Error error)
        | Ok form -> (
            let fields =
              match step.auto with
              | Some Flow_plan.First_choice ->
                  add_fields (Html.first_choice_fields form) step.fields
              | None -> step.fields
            in
            submit_form client ~source_response:response ~form ~fields
              ~uploads:step.uploads ?button_name:step.button_name ()
            >>= function
            | Error (Form_error message) ->
                Lwt.return
                  (Error
                     (Form_error (Printf.sprintf "ステップ %d: %s" index message)))
            | Error error -> Lwt.return (Error error)
            | Ok next -> run (index + 1) next rest))
  in
  get client target >>= function
  | Error error -> Lwt.return (Error error)
  | Ok response -> run 1 response steps

let submit_response_index client ~source_response ~index ~fields ~uploads
    ?button_name () =
  match select_form (Html.forms source_response.Http_client.body) index with
  | Error error -> Lwt.return (Error error)
  | Ok form ->
      submit_form client ~source_response ~form ~fields ~uploads ?button_name ()

let submit_response_named client ~source_response ~button_name ~fields ~uploads
    =
  match
    Html.forms source_response.Http_client.body
    |> Html.find_form_by_control button_name
  with
  | None ->
      Lwt.return
        (Error (Form_error (Printf.sprintf "送信ボタン %s が見つかりません。" button_name)))
  | Some form ->
      submit_form client ~source_response ~form ~fields ~uploads ~button_name ()

let submit_index client ~target ~index ~fields ~uploads ?button_name () =
  get client target >>= function
  | Error error -> Lwt.return (Error error)
  | Ok source_response ->
      submit_response_index client ~source_response ~index ~fields ~uploads
        ?button_name ()

let submit_named client ~target ~button_name ~fields ~uploads =
  get client target >>= function
  | Error error -> Lwt.return (Error error)
  | Ok source_response ->
      submit_response_named client ~source_response ~button_name ~fields
        ~uploads

let find_link_by_prefix response prefix =
  Html.links response.Http_client.body
  |> List.find_opt (fun link -> Util.starts_with ~prefix link.Types.href)

let memo_set client ~class_ ~text =
  get client "home" >>= function
  | Error error -> Lwt.return (Error error)
  | Ok home -> (
      match find_link_by_prefix home "usermemo_" with
      | None -> Lwt.return (Error (Form_error "マイページにメモ追加リンクが見つかりません。"))
      | Some link ->
          submit_named client ~target:link.href
            ~button_name:"action_Usermemo_update"
            ~fields:[ ("MemoClass", string_of_int class_); ("MemoText", text) ]
            ~uploads:[])

let thread_create client ~course_id ~subject ~text =
  let target = Printf.sprintf "course_%d_topics?action=newthread" course_id in
  submit_named client ~target ~button_name:"action_BBSView_newthreaddone"
    ~fields:[ ("Subject", subject); ("Text", text) ]
    ~uploads:[]

let profile_update client ~text ~image =
  get client "home_preferences" >>= function
  | Error error -> Lwt.return (Error error)
  | Ok preferences -> (
      match
        Html.links preferences.body
        |> List.find_opt (fun link ->
            Util.ends_with ~suffix:"_profileedit" link.Types.href)
      with
      | None -> Lwt.return (Error (Form_error "プロフィール設定リンクが見つかりません。"))
      | Some link ->
          let uploads =
            match image with
            | None -> []
            | Some path -> [ Http_client.{ field = "ProfileImage"; path } ]
          in
          submit_named client ~target:link.href
            ~button_name:"action_UserProfileEdit_update"
            ~fields:[ ("Profile0", text) ]
            ~uploads)

let display_count client count =
  submit_named client ~target:"home_preferences_display"
    ~button_name:"action_ProfileDisplay_do"
    ~fields:[ ("ItemPerPage", string_of_int count) ]
    ~uploads:[]

let registration_search client ~course_code ~name ~teacher =
  let fields =
    [ ("CourseCode", course_code); ("NameAll", name); ("Teacher", teacher) ]
  in
  submit_named client ~target:"home_selfregistrationlist"
    ~button_name:"action_SelfRegistrationList_list" ~fields ~uploads:[]

let registration_commit_button response =
  let candidates =
    Html.forms response.Http_client.body
    |> List.concat_map (fun form ->
        Html.submit_controls form
        |> List.filter_map (fun control ->
            match control.Types.name with
            | Some name
              when Util.starts_with ~prefix:"action_SelfRegistration_" name
                   && (not (Util.contains ~needle:"confirm" name))
                   && (not (Util.contains ~needle:"cancel" name))
                   && not (Util.contains ~needle:"back" name) ->
                Some (form, name)
            | _ -> None))
  in
  match candidates with [ candidate ] -> Some candidate | _ -> None

let registration_key client key =
  submit_named client ~target:"home_selfregistration"
    ~button_name:"action_SelfRegistration_confirm"
    ~fields:[ ("CourseCode", key) ]
    ~uploads:[]
  >>= function
  | Error error -> Lwt.return (Error error)
  | Ok confirmation -> (
      match registration_commit_button confirmation with
      | None ->
          Lwt.return
            (Error (Form_error "登録確認後の確定ボタンが見つかりません。登録キーまたは画面のエラーを確認してください。"))
      | Some (form, button_name) ->
          submit_form client ~source_response:confirmation ~form ~fields:[]
            ~uploads:[] ~button_name ())

let report_target course_id report_id =
  Printf.sprintf "course_%d_report_%d" course_id report_id

let report_is_submitted html =
  let has_uncommit =
    Html.forms html
    |> List.exists (Html.contains_control "action_ReportStudent_uncommitdone")
  in
  let visible = Html.main_text html in
  has_uncommit
  || Util.contains ~needle:"提出済み" visible
  || Util.contains ~needle:"提出しました" visible

let report_submit client ~course_id ~report_id ~file =
  let target = report_target course_id report_id in
  get client target >>= function
  | Error error -> Lwt.return (Error error)
  | Ok source_response -> (
      let forms = Html.forms source_response.body in
      let with_file =
        List.find_opt (fun form -> Html.file_controls form <> []) forms
      in
      match with_file with
      | None ->
          Lwt.return (Error (Form_error "ファイル提出フォームが見つかりません。受付状態を確認してください。"))
      | Some form -> (
          match Html.file_controls form with
          | { Types.name = Some field; _ } :: _ -> (
              let upload = Http_client.{ field; path = file } in
              submit_form client ~source_response ~form ~fields:[]
                ~uploads:[ upload ] ()
              >>= function
              | Error error -> Lwt.return (Error error)
              | Ok preview_response -> (
                  let preview_forms = Html.forms preview_response.body in
                  let commit_name = "action_ReportStudent_commitdone" in
                  let commit_form =
                    List.find_opt
                      (fun candidate ->
                        Html.contains_control commit_name candidate)
                      preview_forms
                  in
                  match commit_form with
                  | Some commit_form -> (
                      submit_form client ~source_response:preview_response
                        ~form:commit_form ~fields:[] ~uploads:[]
                        ~button_name:commit_name ()
                      >>= function
                      | Error error -> Lwt.return (Error error)
                      | Ok _ -> (
                          get client target >|= function
                          | Ok verification
                            when report_is_submitted verification.body ->
                              Ok verification
                          | Ok _ ->
                              Error
                                (Form_error
                                   "最終送信後も提出済み状態を確認できませんでした。manaba \
                                    の画面を確認してください。")
                          | Error error -> Error error))
                  | None ->
                      Lwt.return
                        (Error
                           (Form_error
                              "ファイルはアップロードされましたが、最終の提出ボタンが見つかりません。画面構造が変更された可能性があります。"))
                  ))
          | _ -> Lwt.return (Error (Form_error "ファイル入力欄に name 属性がありません。"))))

let report_cancel client ~course_id ~report_id =
  let target = report_target course_id report_id in
  get client target >>= function
  | Error error -> Lwt.return (Error error)
  | Ok source_response -> (
      let forms = Html.forms source_response.body in
      let is_cancel_name = function
        | None -> false
        | Some name ->
            let name = Util.lowercase name in
            Util.contains ~needle:"cancel" name
            || Util.contains ~needle:"delete" name
            || Util.contains ~needle:"withdraw" name
            || Util.contains ~needle:"uncommit" name
      in
      let candidate =
        List.find_map
          (fun form ->
            List.find_opt
              (fun control ->
                (match control.Types.input_type with
                  | Types.Submit | Types.Button_type -> true
                  | _ -> false)
                && is_cancel_name control.name)
              form.Types.controls
            |> Option.map (fun control -> (form, control)))
          forms
      in
      match candidate with
      | Some (form, { Types.name = Some button_name; _ }) -> (
          submit_form client ~source_response ~form ~fields:[] ~uploads:[]
            ~button_name ()
          >>= function
          | Error error -> Lwt.return (Error error)
          | Ok _ -> (
              get client target >|= function
              | Ok verification when not (report_is_submitted verification.body)
                ->
                  Ok verification
              | Ok _ ->
                  Error (Form_error "取消送信後も提出済み状態のままです。manaba の画面を確認してください。")
              | Error error -> Error error))
      | _ ->
          Lwt.return (Error (Form_error "提出取消ボタンが見つかりません。現在は未提出か、取消不可の課題です。")))

let favorite client ~course_id ~desired =
  get client "home_course" >>= function
  | Error error -> Lwt.return (Error error)
  | Ok response -> (
      let prefix = Printf.sprintf "home_favoritecourse_%d_" course_id in
      let action =
        Html.links response.body
        |> List.find_opt (fun link -> Util.starts_with ~prefix link.Types.href)
      in
      match action with
      | None ->
          Lwt.return
            (Error (Form_error "指定したコースのお気に入り操作が見つかりません。コース ID を確認してください。"))
      | Some link ->
          let is_set_action = Util.contains ~needle:"_set_" link.href in
          if (desired && not is_set_action) || ((not desired) && is_set_action)
          then Lwt.return (Ok response)
          else get client link.href)

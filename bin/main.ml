open Cmdliner

let app_name = "manaba"

let base_url =
  let env = Cmd.Env.info "MANABA_BASE_URL" in
  Arg.(
    value
    & opt string "https://manaba.tsukuba.ac.jp/ct/"
    & info [ "base-url" ] ~env ~docv:"URL"
        ~doc:"manaba の /ct/ ベース URL。テスト用サーバーにも変更できます。")

let session_path =
  let env = Cmd.Env.info "MANABA_SESSION" in
  Arg.(
    value
    & opt (some string) None
    & info [ "session" ] ~env ~docv:"FILE"
        ~doc:"セッション Cookie の保存先。既定は XDG_CONFIG_HOME 以下です。")

let client = Term.(const Manaba.create $ base_url $ session_path)

let json = Arg.(value & flag & info [ "json" ] ~doc:"機械可読な JSON で出力します。")

let course_id =
  Arg.(required & pos 0 (some int) None & info [] ~docv:"COURSE_ID")

let report_id =
  Arg.(required & pos 1 (some int) None & info [] ~docv:"REPORT_ID")

let target = Arg.(required & pos 0 (some string) None & info [] ~docv:"PATH")
let error error = `Error (false, Manaba.error_to_string error)

let lwt_result promise on_success =
  match Lwt_main.run promise with
  | Ok value ->
      on_success value;
      `Ok ()
  | Error problem -> error problem

let command_info name doc = Cmd.info name ~doc

let read_username supplied =
  match supplied with
  | Some username -> username
  | None -> (
      match Sys.getenv_opt "MANABA_USERNAME" with
      | Some username when username <> "" -> username
      | _ ->
          output_string stderr "統一認証 ID: ";
          flush stderr;
          input_line stdin)

let read_login_password password_stdin password_clipboard =
  match Sys.getenv_opt "MANABA_PASSWORD" with
  | Some password when password <> "" -> Ok password
  | _ when password_clipboard -> Util.read_macos_clipboard ()
  | _ ->
      if password_stdin then Ok (input_line stdin)
      else Ok (Util.read_password "パスワード（入力・貼り付け内容は表示されません）: ")

let login username password_stdin password_clipboard client =
  if password_stdin && password_clipboard then
    `Error (false, "--password-stdin と --password-clipboard は同時に指定できません。")
  else
    let username = read_username username in
    match read_login_password password_stdin password_clipboard with
    | Error message -> `Error (false, message)
    | Ok password -> (
        match
          Lwt_main.run
            (Auth.login (Manaba.http client) ~base_uri:(Manaba.base_uri client)
               ~username ~password)
        with
        | Ok _ ->
            Printf.printf "ログインしました。セッションは %s に保存しました。\n"
              (Manaba.session_path client);
            `Ok ()
        | Error problem -> `Error (false, Auth.error_to_string problem))

let login_cmd =
  let username =
    Arg.(
      value
      & opt (some string) None
      & info [ "u"; "username" ] ~docv:"ID" ~doc:"統一認証 ID。省略時は対話入力します。")
  in
  let password_stdin =
    Arg.(
      value & flag & info [ "password-stdin" ] ~doc:"パスワードを標準入力の 1 行から読み取ります。")
  in
  let password_clipboard =
    Arg.(
      value & flag
      & info [ "password-clipboard" ] ~doc:"macOS のクリップボードからパスワードを読み取ります。")
  in
  Cmd.v
    (command_info "login" "筑波大学統一認証でログインし、Cookie だけを保存します。")
    Term.(
      ret (const login $ username $ password_stdin $ password_clipboard $ client))

let auth_status client =
  match
    Lwt_main.run
      (Auth.status (Manaba.http client) ~base_uri:(Manaba.base_uri client))
  with
  | Ok _ ->
      print_endline "logged in";
      `Ok ()
  | Error `Logged_out ->
      print_endline "logged out";
      `Ok ()
  | Error (`Network message) -> `Error (false, message)

let status_cmd =
  Cmd.v
    (command_info "status" "保存セッションが有効か確認します。")
    Term.(ret (const auth_status $ client))

let logout client =
  Auth.logout (Manaba.http client);
  print_endline "ローカルのセッションを削除しました。";
  `Ok ()

let logout_cmd =
  Cmd.v
    (command_info "logout" "保存した Cookie をローカルから削除します。")
    Term.(ret (const logout $ client))

let auth_cmd =
  Cmd.group
    (command_info "auth" "認証セッションを管理します。")
    [ login_cmd; status_cmd; logout_cmd ]

let courses client json =
  lwt_result (Manaba.get client "home_course") (fun response ->
      Html.courses response.Http_client.body |> Output.print_courses ~json)

let courses_cmd =
  Cmd.v
    (command_info "courses" "履修コースを一覧表示します。")
    Term.(ret (const courses $ client $ json))

let tasks client json =
  lwt_result (Manaba.get client "home_library_query") (fun response ->
      Html.tasks response.Http_client.body |> Output.print_tasks ~json)

let tasks_cmd =
  Cmd.v
    (command_info "tasks" "未提出課題を一覧表示します。")
    Term.(ret (const tasks $ client $ json))

let interesting_course_link course_id (link : Types.link) =
  let prefix = Printf.sprintf "course_%d_" course_id in
  Util.starts_with ~prefix link.href
  || link.href = Printf.sprintf "course_%d" course_id
  || Util.starts_with ~prefix:"page_" link.href
     && Util.contains ~needle:(Printf.sprintf "c%d" course_id) link.href

let course course_id client json =
  lwt_result
    (Manaba.get client (Printf.sprintf "course_%d" course_id))
    (fun response ->
      Html.links response.Http_client.body
      |> List.filter (interesting_course_link course_id)
      |> Output.print_links ~json)

let course_cmd =
  Cmd.v
    (command_info "course" "コースの機能・更新項目を一覧表示します。")
    Term.(ret (const course $ course_id $ client $ json))

let resource_link course_id suffix (link : Types.link) =
  let course_prefix value =
    Util.starts_with
      ~prefix:(Printf.sprintf "course_%d_%s_" course_id value)
      link.href
  in
  match suffix with
  | "query" -> course_prefix "query" || course_prefix "drill"
  | "page" ->
      Util.starts_with ~prefix:"page_" link.href
      && Util.contains ~needle:(Printf.sprintf "c%d" course_id) link.href
  | value -> course_prefix value

let resource suffix course_id client json =
  let path = Printf.sprintf "course_%d_%s" course_id suffix in
  lwt_result (Manaba.get client path) (fun response ->
      Html.links response.Http_client.body
      |> List.filter (resource_link course_id suffix)
      |> Output.print_links ~json)

let resource_cmd name suffix doc =
  Cmd.v (command_info name doc)
    Term.(ret (const (resource suffix) $ course_id $ client $ json))

let news_cmd = resource_cmd "news" "news" "コースニュースを一覧表示します。"

let quizzes_cmd = resource_cmd "quizzes" "query" "小テストとドリルを一覧表示します。"

let surveys_cmd = resource_cmd "surveys" "survey" "アンケートを一覧表示します。"

let reports_cmd = resource_cmd "reports" "report" "レポート課題を一覧表示します。"

let projects_cmd = resource_cmd "projects" "project" "プロジェクトを一覧表示します。"

let topics_cmd = resource_cmd "topics" "topics" "掲示板スレッドを一覧表示します。"

let contents_cmd = resource_cmd "contents" "page" "コースコンテンツを一覧表示します。"

let grades course_id client =
  let path = Printf.sprintf "course_%d_grade" course_id in
  lwt_result (Manaba.get client path) (fun response ->
      print_endline (Html.main_text response.Http_client.body))

let grades_cmd =
  Cmd.v
    (command_info "grades" "コース成績をテキスト表示します。")
    Term.(ret (const grades $ course_id $ client))

let fixed_page path client =
  lwt_result (Manaba.get client path) (fun response ->
      print_endline (Html.main_text response.Http_client.body))

let fixed_page_cmd name path doc =
  Cmd.v (command_info name doc) Term.(ret (const (fixed_page path) $ client))

let submissions_cmd =
  fixed_page_cmd "submissions" "home_submitlog" "提出記録を表示します。"

let portfolio_cmd =
  fixed_page_cmd "portfolio" "home_coursetable" "ポートフォリオを表示します。"

let reminders_cmd =
  fixed_page_cmd "reminders" "home_library_reminder" "リマインダを表示します。"

let memos_cmd = fixed_page_cmd "memos" "home_usermemo" "メモ一覧を表示します。"

let settings_cmd = fixed_page_cmd "settings" "home_preferences" "個人設定を表示します。"

let get raw target client =
  lwt_result (Manaba.get client target) (fun response ->
      if raw then print_string response.Http_client.body
      else print_endline (Html.main_text response.body))

let get_cmd =
  let raw = Arg.(value & flag & info [ "raw" ] ~doc:"HTML をそのまま出力します。") in
  Cmd.v
    (command_info "get" "任意の manaba ページを取得してテキスト表示します。")
    Term.(ret (const get $ raw $ target $ client))

let links target client json =
  lwt_result (Manaba.get client target) (fun response ->
      Html.links response.Http_client.body |> Output.print_links ~json)

let links_cmd =
  Cmd.v
    (command_info "links" "ページ上のリンクを一覧表示します。")
    Term.(ret (const links $ target $ client $ json))

let forms target client json =
  lwt_result (Manaba.get client target) (fun response ->
      Html.forms response.Http_client.body |> Output.print_forms ~json)

let forms_cmd =
  Cmd.v
    (command_info "forms" "ページ上のフォームと入力名を表示します。")
    Term.(ret (const forms $ target $ client $ json))

let download target output client =
  lwt_result (Manaba.get client target) (fun response ->
      let channel = open_out_bin output in
      Fun.protect
        ~finally:(fun () -> close_out_noerr channel)
        (fun () -> output_string channel response.Http_client.body);
      Printf.printf "%s\n" output)

let download_cmd =
  let output =
    Arg.(
      required
      & opt (some string) None
      & info [ "output"; "o" ] ~docv:"FILE" ~doc:"保存先ファイル。")
  in
  Cmd.v
    (command_info "download" "添付ファイルをダウンロードします。")
    Term.(ret (const download $ target $ output $ client))

let key_value =
  let parse value =
    match Util.split_once '=' value with
    | name, Some content when name <> "" -> Ok (name, content)
    | _ -> Error (`Msg "NAME=VALUE 形式で指定してください")
  in
  let print formatter (name, value) =
    Format.fprintf formatter "%s=%s" name value
  in
  Arg.conv (parse, print)

let confirm yes description =
  if yes then true
  else (
    Printf.eprintf "%s [y/N]: %!" description;
    match input_line stdin |> String.trim |> String.lowercase_ascii with
    | "y" | "yes" -> true
    | _ -> false)

let form_submit target index fields files button yes client =
  if not (confirm yes (Printf.sprintf "%s のフォーム %d を送信します。" target index)) then
    `Error (false, "送信を中止しました。")
  else
    let uploads =
      List.map (fun (field, path) -> Http_client.{ field; path }) files
    in
    lwt_result
      (Manaba.submit_index client ~target ~index ~fields ~uploads
         ?button_name:button ()) (fun response ->
        print_endline (Html.main_text response.Http_client.body))

let form_submit_cmd =
  let index =
    Arg.(value & opt int 1 & info [ "form" ] ~docv:"N" ~doc:"送信するフォーム番号。")
  in
  let fields =
    Arg.(
      value & opt_all key_value []
      & info [ "field"; "F" ] ~docv:"NAME=VALUE" ~doc:"フォーム値。複数指定できます。")
  in
  let files =
    Arg.(
      value & opt_all key_value []
      & info [ "file" ] ~docv:"NAME=PATH" ~doc:"アップロード欄とファイル。")
  in
  let button =
    Arg.(
      value
      & opt (some string) None
      & info [ "button" ] ~docv:"NAME" ~doc:"押す submit ボタンの name。")
  in
  let yes = Arg.(value & flag & info [ "yes"; "y" ] ~doc:"確認なしで送信します。") in
  Cmd.v
    (command_info "submit" "manaba のフォームを 1 ステップ送信します。")
    Term.(
      ret
        (const form_submit $ target $ index $ fields $ files $ button $ yes
       $ client))

let yes_flag = Arg.(value & flag & info [ "yes"; "y" ] ~doc:"確認なしで実行します。")

let flow target plan_path yes client =
  match Flow_plan.load plan_path with
  | Error problem -> `Error (false, Flow_plan.error_to_string problem)
  | Ok steps ->
      if
        not
          (confirm yes
             (Printf.sprintf "%s に %d ステップのフォーム操作を送信します。" target
                (List.length steps)))
      then `Error (false, "送信を中止しました。")
      else
        lwt_result (Manaba.run_flow client ~target steps) (fun response ->
            print_endline (Html.main_text response.Http_client.body))

let flow_cmd =
  let plan =
    Arg.(required & pos 1 (some file) None & info [] ~docv:"PLAN.json")
  in
  Cmd.v
    (command_info "flow" "JSON 手順に従って複数画面のフォームを連続送信します。")
    Term.(ret (const flow $ target $ plan $ yes_flag $ client))

let favorite desired course_id yes client =
  let description =
    if desired then Printf.sprintf "course %d をよく使うコースに登録します。" course_id
    else Printf.sprintf "course %d をよく使うコースから解除します。" course_id
  in
  if not (confirm yes description) then `Error (false, "変更を中止しました。")
  else
    lwt_result (Manaba.favorite client ~course_id ~desired) (fun _ ->
        Printf.printf "%d: %s\n" course_id
          (if desired then "favorite" else "not favorite"))

let favorite_action name desired doc =
  Cmd.v (command_info name doc)
    Term.(ret (const (favorite desired) $ course_id $ yes_flag $ client))

let favorite_cmd =
  Cmd.group
    (command_info "favorite" "よく使うコースを管理します。")
    [
      favorite_action "set" true "よく使うコースに登録します。";
      favorite_action "unset" false "よく使うコースから解除します。";
    ]

let memo_text = Arg.(required & pos 0 (some string) None & info [] ~docv:"TEXT")

let memo_set class_ text yes client =
  if class_ < 0 || class_ > 3 then `Error (false, "メモ分類は 0 から 3 で指定してください。")
  else if not (confirm yes "マイページの個人メモを更新します。") then `Error (false, "更新を中止しました。")
  else
    lwt_result (Manaba.memo_set client ~class_ ~text) (fun response ->
        print_endline (Html.main_text response.Http_client.body))

let memo_set_cmd =
  let class_ =
    Arg.(value & opt int 0 & info [ "class" ] ~docv:"0..3" ~doc:"メモの色分類。")
  in
  Cmd.v
    (command_info "set" "マイページの個人メモを更新します。")
    Term.(ret (const memo_set $ class_ $ memo_text $ yes_flag $ client))

let memo_cmd = Cmd.group (command_info "memo" "個人メモを操作します。") [ memo_set_cmd ]

let thread_subject =
  Arg.(required & pos 1 (some string) None & info [] ~docv:"SUBJECT")

let thread_body =
  Arg.(required & pos 2 (some string) None & info [] ~docv:"BODY")

let thread_create course_id subject body yes client =
  if
    not
      (confirm yes
         (Printf.sprintf "course %d の掲示板にスレッド「%s」を投稿します。" course_id subject))
  then `Error (false, "投稿を中止しました。")
  else
    lwt_result (Manaba.thread_create client ~course_id ~subject ~text:body)
      (fun response -> print_endline (Html.main_text response.Http_client.body))

let thread_create_cmd =
  Cmd.v
    (command_info "create" "掲示板に新しいスレッドを投稿します。")
    Term.(
      ret
        (const thread_create $ course_id $ thread_subject $ thread_body
       $ yes_flag $ client))

let thread_cmd =
  Cmd.group (command_info "thread" "掲示板への投稿を操作します。") [ thread_create_cmd ]

let profile_text =
  Arg.(required & pos 0 (some string) None & info [] ~docv:"TEXT")

let profile_update text image yes client =
  if not (confirm yes "プロフィール本文と指定画像を更新します。") then `Error (false, "更新を中止しました。")
  else
    lwt_result (Manaba.profile_update client ~text ~image) (fun response ->
        print_endline (Html.main_text response.Http_client.body))

let profile_update_cmd =
  let image =
    Arg.(
      value
      & opt (some file) None
      & info [ "image" ] ~docv:"FILE" ~doc:"プロフィール画像。")
  in
  Cmd.v
    (command_info "set" "プロフィールを更新します。")
    Term.(ret (const profile_update $ profile_text $ image $ yes_flag $ client))

let profile_cmd =
  Cmd.group (command_info "profile" "プロフィールを操作します。") [ profile_update_cmd ]

let display_count count yes client =
  if count <= 0 then `Error (false, "表示件数は正の整数で指定してください。")
  else if not (confirm yes (Printf.sprintf "1ページの表示件数を %d に変更します。" count)) then
    `Error (false, "変更を中止しました。")
  else
    lwt_result (Manaba.display_count client count) (fun response ->
        print_endline (Html.main_text response.Http_client.body))

let display_cmd =
  let count = Arg.(required & pos 0 (some int) None & info [] ~docv:"COUNT") in
  Cmd.v
    (command_info "display-count" "1ページの表示件数を変更します。")
    Term.(ret (const display_count $ count $ yes_flag $ client))

let registration_search code name teacher client json =
  lwt_result
    (Manaba.registration_search client ~course_code:code ~name ~teacher)
    (fun response ->
      let courses = Html.courses response.Http_client.body in
      if courses = [] then print_endline (Html.main_text response.body)
      else Output.print_courses ~json courses)

let registration_search_cmd =
  let code =
    Arg.(value & opt string "" & info [ "code" ] ~docv:"CODE" ~doc:"コースコード。")
  in
  let name =
    Arg.(value & opt string "" & info [ "name" ] ~docv:"NAME" ~doc:"コース名。")
  in
  let teacher =
    Arg.(value & opt string "" & info [ "teacher" ] ~docv:"NAME" ~doc:"担当教員名。")
  in
  Cmd.v
    (command_info "search" "自己登録可能なコースを検索します。")
    Term.(
      ret (const registration_search $ code $ name $ teacher $ client $ json))

let registration_key_value =
  Arg.(required & pos 0 (some string) None & info [] ~docv:"KEY")

let registration_key key yes client =
  if not (confirm yes "指定した登録キーでコース登録を確定します。") then `Error (false, "登録を中止しました。")
  else
    lwt_result (Manaba.registration_key client key) (fun response ->
        print_endline (Html.main_text response.Http_client.body))

let registration_key_cmd =
  Cmd.v
    (command_info "key" "登録キーを使ってコースを自己登録します。")
    Term.(
      ret (const registration_key $ registration_key_value $ yes_flag $ client))

let registration_cmd =
  Cmd.group
    (command_info "registration" "コースの自己登録を操作します。")
    [ registration_search_cmd; registration_key_cmd ]

let report_file = Arg.(required & pos 2 (some file) None & info [] ~docv:"FILE")

let report_submit course_id report_id file yes client =
  if
    not
      (confirm yes
         (Printf.sprintf "course %d の report %d に %s を提出します。" course_id
            report_id file))
  then `Error (false, "提出を中止しました。")
  else
    lwt_result (Manaba.report_submit client ~course_id ~report_id ~file)
      (fun response -> print_endline (Html.main_text response.Http_client.body))

let report_submit_cmd =
  let yes = Arg.(value & flag & info [ "yes"; "y" ] ~doc:"確認なしで提出します。") in
  Cmd.v
    (command_info "submit" "ファイル送信レポートを提出します。")
    Term.(
      ret
        (const report_submit $ course_id $ report_id $ report_file $ yes
       $ client))

let report_cancel course_id report_id yes client =
  if
    not
      (confirm yes
         (Printf.sprintf "course %d の report %d の提出を取り消します。" course_id report_id))
  then `Error (false, "取消を中止しました。")
  else
    lwt_result (Manaba.report_cancel client ~course_id ~report_id)
      (fun response -> print_endline (Html.main_text response.Http_client.body))

let report_cancel_cmd =
  let yes = Arg.(value & flag & info [ "yes"; "y" ] ~doc:"確認なしで取り消します。") in
  Cmd.v
    (command_info "cancel" "ファイル送信レポートの提出を取り消します。")
    Term.(ret (const report_cancel $ course_id $ report_id $ yes $ client))

let report_cmd =
  Cmd.group
    (command_info "report" "レポート提出を操作します。")
    [ report_submit_cmd; report_cancel_cmd ]

let main_cmd =
  Cmd.group
    (Cmd.info app_name ~version:"0.1.0" ~doc:"筑波大学 manaba を操作する OCaml 製 CLI")
    [
      auth_cmd;
      courses_cmd;
      tasks_cmd;
      course_cmd;
      news_cmd;
      quizzes_cmd;
      surveys_cmd;
      reports_cmd;
      projects_cmd;
      topics_cmd;
      contents_cmd;
      grades_cmd;
      submissions_cmd;
      portfolio_cmd;
      reminders_cmd;
      memos_cmd;
      settings_cmd;
      get_cmd;
      links_cmd;
      forms_cmd;
      download_cmd;
      form_submit_cmd;
      flow_cmd;
      favorite_cmd;
      memo_cmd;
      thread_cmd;
      profile_cmd;
      display_cmd;
      registration_cmd;
      report_cmd;
    ]

let () = exit (Cmd.eval main_cmd)

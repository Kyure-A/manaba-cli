let course_html =
  {|
  <html><body>
    <a href="course_123">Compiler Construction</a>
    <a href="course_123">Compiler Construction</a>
    <a href="course_456">Information Retrieval</a>
    <a href="course_456_calink">movie</a>
    <a href="usermemo_7_7"><img src="memo.png" alt="メモ追加"></a>
  </body></html>
  |}

let task_html =
  {|
  <html><body><table class="stdlist">
    <tr><th>タイプ</th><th>タイトル</th><th>コース</th><th>開始</th><th>終了</th></tr>
    <tr class="row0">
      <td>レポート</td>
      <td><div><a href="course_456_report_789">Exercise 2</a></div></td>
      <td><div><a href="course_456">Information Retrieval</a></div></td>
      <td>2026-07-01 09:00</td><td>2026-07-31 23:59</td>
    </tr>
    <tr class="row1">
      <td>ドリル</td>
      <td><a href="course_123_drill_42">Practice</a></td>
      <td><a href="course_123">Compiler Construction</a></td>
      <td>2026-04-01 00:00</td><td></td>
    </tr>
  </table></body></html>
  |}

let report_form_html =
  {|
  <html><body>
    <form action="course_456_report_789" method="post" enctype="multipart/form-data">
      <input type="file" name="RptSubmitFile">
      <input type="image" name="action_ReportStudent_datadelete_rptdata1">
      <input type="submit" name="action_ReportStudent_submitdone" value="アップロード">
      <input type="hidden" name="manaba-form" value="1">
      <input type="hidden" name="SessionValue1" value="opaque-token">
      <input type="hidden" name="SessionValue" value="@1">
      <input type="hidden" name="empty-token">
      <input type="checkbox" name="unchecked" value="bad">
      <select name="format"><option value="list" selected>List</option></select>
      <select name="audience" multiple>
        <option value="student" selected>Student</option>
        <option value="teacher" selected>Teacher</option>
      </select>
      <textarea name="notes">line one
  line two</textarea>
    </form>
  </body></html>
  |}

let test_courses () =
  match Html.courses course_html with
  | [ first; second ] ->
      Alcotest.(check int) "first id" 123 first.Types.id;
      Alcotest.(check string) "first name" "Compiler Construction" first.name;
      Alcotest.(check int) "second id" 456 second.id
  | courses ->
      Alcotest.failf "expected two courses, got %d" (List.length courses)

let test_tasks () =
  match Html.tasks task_html with
  | [ report; drill ] ->
      Alcotest.(check string)
        "report kind" "report"
        (Types.task_kind_to_string report.Types.kind);
      Alcotest.(check (option int)) "report id" (Some 789) report.id;
      Alcotest.(check (option int)) "course id" (Some 456) report.course_id;
      Alcotest.(check (option string))
        "deadline" (Some "2026-07-31 23:59") report.ends_at;
      Alcotest.(check string)
        "drill kind" "drill"
        (Types.task_kind_to_string drill.kind)
  | tasks -> Alcotest.failf "expected two tasks, got %d" (List.length tasks)

let test_image_link () =
  match
    Html.links course_html
    |> List.find_opt (fun link -> link.Types.href = "usermemo_7_7")
  with
  | Some link -> Alcotest.(check string) "alt text" "メモ追加" link.Types.text
  | None -> Alcotest.fail "image-only link was omitted"

let test_visible_text () =
  let html =
    {|
    <div class="contentbody-l">
      <p>Visible text</p>
      <script>secret_script()</script>
      <style>.hidden { display: none }</style>
      <noscript>fallback</noscript>
    </div>
    |}
  in
  Alcotest.(check string)
    "non-visible elements omitted" "Visible text" (Html.main_text html)

let test_report_form () =
  match Html.forms report_form_html with
  | [ form ] ->
      Alcotest.(check string)
        "method" "post"
        (Types.form_method_to_string form.Types.method_);
      Alcotest.(check string)
        "enctype" "multipart/form-data"
        (Types.form_enctype_to_string form.enctype);
      (match Html.file_controls form with
      | [ control ] ->
          Alcotest.(check (option string))
            "file field" (Some "RptSubmitFile") control.Types.name
      | controls ->
          Alcotest.failf "expected one file control, got %d"
            (List.length controls));
      let fields =
        Html.submission_fields ~button_name:"action_ReportStudent_submitdone"
          form
      in
      Alcotest.(check (option string))
        "submit button" (Some "アップロード")
        (List.assoc_opt "action_ReportStudent_submitdone" fields);
      Alcotest.(check (option string))
        "session" (Some "opaque-token")
        (List.assoc_opt "SessionValue1" fields);
      Alcotest.(check (option string))
        "empty hidden" (Some "")
        (List.assoc_opt "empty-token" fields);
      Alcotest.(check (option string))
        "unchecked omitted" None
        (List.assoc_opt "unchecked" fields);
      Alcotest.(check (option string))
        "unclicked image omitted" None
        (List.assoc_opt "action_ReportStudent_datadelete_rptdata1.x" fields);
      Alcotest.(check (option string))
        "selected option" (Some "list")
        (List.assoc_opt "format" fields);
      Alcotest.(check (list string))
        "multiple selection" [ "student"; "teacher" ]
        (List.filter_map
           (fun (name, value) -> if name = "audience" then Some value else None)
           fields);
      let public_json =
        Types.public_form_to_yojson form |> Yojson.Safe.to_string
      in
      Alcotest.(check bool)
        "hidden value redacted" false
        (Util.contains ~needle:"opaque-token" public_json);
      Alcotest.(check bool)
        "options shown" true
        (Util.contains ~needle:"teacher" public_json);
      Alcotest.(check (option string))
        "textarea whitespace" (Some "line one\n  line two")
        (List.assoc_opt "notes" fields);
      let delete_fields =
        Html.submission_fields
          ~button_name:"action_ReportStudent_datadelete_rptdata1" form
      in
      Alcotest.(check (option string))
        "image x" (Some "0")
        (List.assoc_opt "action_ReportStudent_datadelete_rptdata1.x"
           delete_fields);
      Alcotest.(check (option string))
        "image y" (Some "0")
        (List.assoc_opt "action_ReportStudent_datadelete_rptdata1.y"
           delete_fields)
  | forms -> Alcotest.failf "expected one form, got %d" (List.length forms)

let test_unknown_form_domains_preserved () =
  let html =
    {|
    <form action="custom" method="dialog" enctype="text/plain">
      <input type="color" name="shade" value="blue">
    </form>
    |}
  in
  match Html.forms html with
  | [ form ] ->
      Alcotest.(check string)
        "unknown method" "dialog"
        (Types.form_method_to_string form.Types.method_);
      Alcotest.(check string)
        "unknown enctype" "text/plain"
        (Types.form_enctype_to_string form.enctype);
      let actual = Types.public_form_to_yojson form in
      let expected =
        Yojson.Safe.from_string
          {|{
            "action": "custom",
            "method": "dialog",
            "enctype": "text/plain",
            "controls": [{
              "tag": "input",
              "type": "color",
              "name": "shade",
              "multiple": false,
              "options": [],
              "value": "blue"
            }]
          }|}
      in
      Alcotest.(check string)
        "public JSON contract"
        (Yojson.Safe.to_string expected)
        (Yojson.Safe.to_string actual)
  | forms -> Alcotest.failf "expected one form, got %d" (List.length forms)

let check_round_trips label of_string to_string values =
  List.iter
    (fun value ->
      Alcotest.(check string)
        (label ^ ": " ^ value)
        value
        (value |> of_string |> to_string))
    values

let test_form_domain_round_trips () =
  check_round_trips "method" Types.form_method_of_string
    Types.form_method_to_string
    [ "get"; "post"; "dialog" ];
  check_round_trips "enctype" Types.form_enctype_of_string
    Types.form_enctype_to_string
    [ "application/x-www-form-urlencoded"; "multipart/form-data"; "text/plain" ];
  check_round_trips "tag" Types.control_tag_of_string
    Types.control_tag_to_string
    [ "input"; "textarea"; "select"; "button"; "fieldset" ];
  check_round_trips "input type" Types.input_type_of_string
    Types.input_type_to_string
    [
      "text";
      "password";
      "hidden";
      "checkbox";
      "radio";
      "file";
      "submit";
      "image";
      "reset";
      "button";
      "select";
      "textarea";
      "color";
    ]

let test_oversized_task_identifiers () =
  let html =
    {|
    <table class="stdlist"><tr>
      <td>レポート</td>
      <td><a href="course_999999999999999999999_report_999999999999999999999">Large</a></td>
      <td>Course</td><td></td><td></td>
    </tr></table>
    |}
  in
  match Html.tasks html with
  | [ task ] ->
      Alcotest.(check (option int)) "course id" None task.Types.course_id;
      Alcotest.(check (option int)) "task id" None task.id
  | tasks -> Alcotest.failf "expected one task, got %d" (List.length tasks)

let test_repeated_field_overrides () =
  let fields =
    Manaba.add_fields
      [ ("tag", "default"); ("token", "opaque") ]
      [ ("tag", "first"); ("tag", "second") ]
  in
  Alcotest.(check (list (pair string string)))
    "same-name values preserved"
    [ ("token", "opaque"); ("tag", "first"); ("tag", "second") ]
    fields

let test_flow_plan () =
  let json =
    Yojson.Safe.from_string
      {|[
        {
          "form": 2,
          "button": "action_next",
          "auto": "first-choice",
          "fields": {"choice": ["a", "b"], "comment": "hello"},
          "files": {"Upload": "answer.txt"}
        }
      ]|}
  in
  match Flow_plan.of_yojson json with
  | Ok [ step ] -> (
      Alcotest.(check (option int)) "form" (Some 2) step.form_index;
      Alcotest.(check (option string))
        "button" (Some "action_next") step.button_name;
      Alcotest.(check (list (pair string string)))
        "fields"
        [ ("choice", "a"); ("choice", "b"); ("comment", "hello") ]
        step.fields;
      Alcotest.(check bool)
        "auto first-choice" true
        (match step.auto with
        | Some Flow_plan.First_choice -> true
        | _ -> false);
      match step.uploads with
      | [ upload ] ->
          Alcotest.(check string)
            "upload field" "Upload" upload.Http_client.field;
          Alcotest.(check string) "upload path" "answer.txt" upload.path
      | uploads ->
          Alcotest.failf "expected one upload, got %d" (List.length uploads))
  | Ok steps -> Alcotest.failf "expected one step, got %d" (List.length steps)
  | Error problem -> Alcotest.fail (Flow_plan.error_to_string problem)

let test_flow_plan_structured_error () =
  let json = Yojson.Safe.from_string {|[{"form": 0}]|} in
  match Flow_plan.of_yojson json with
  | Error (Flow_plan.Invalid_value { path; message }) ->
      Alcotest.(check string) "path" "$[0].form" path;
      Alcotest.(check string) "message" "1 以上で指定してください" message
  | Error problem ->
      Alcotest.failf "unexpected error: %s" (Flow_plan.error_to_string problem)
  | Ok _ -> Alcotest.fail "invalid form index was accepted"

let test_cookie_jar () =
  let path = Filename.temp_file "manaba-cookie-test" ".json" in
  Sys.remove path;
  let jar = Cookie_jar.load path in
  let origin = Uri.of_string "https://manaba.tsukuba.ac.jp/ct/home" in
  let headers =
    Cohttp.Header.init_with "set-cookie"
      "session=secret; Path=/ct; Secure; HttpOnly"
  in
  Cookie_jar.absorb_headers jar ~origin headers;
  Alcotest.(check (option string))
    "matching cookie" (Some "session=secret")
    (Cookie_jar.header jar
       (Uri.of_string "https://manaba.tsukuba.ac.jp/ct/home_course"));
  Alcotest.(check (option string))
    "wrong path" None
    (Cookie_jar.header jar
       (Uri.of_string "https://manaba.tsukuba.ac.jp/local/login"))

let test_target_origin () =
  let session = Filename.temp_file "manaba-origin" ".json" in
  Sys.remove session;
  let client = Manaba.create "https://manaba.example.test/ct/" (Some session) in
  let allowed target =
    match Manaba.resolve client target with Ok _ -> true | Error _ -> false
  in
  Alcotest.(check bool) "relative" true (allowed "home");
  Alcotest.(check bool)
    "same origin" true
    (allowed "https://manaba.example.test/ct/home");
  Alcotest.(check bool)
    "scheme blocked" false
    (allowed "http://manaba.example.test/ct/home");
  Alcotest.(check bool)
    "port blocked" false
    (allowed "https://manaba.example.test:444/ct/home");
  Alcotest.(check bool)
    "host blocked" false
    (allowed "https://example.test/ct/home")

let test_auth_fields () =
  let html =
    {|
    <form action="/idp/profile/SAML2/Redirect/SSO?execution=e1s2" method="post">
      <input type="text" name="j_username">
      <input type="password" name="j_password">
      <button type="submit" name="_eventId_proceed">Login</button>
    </form>
    |}
  in
  match Html.forms html with
  | [ form ] ->
      let fields =
        Auth.credential_fields form ~username:"0000000000000" ~password:"secret"
      in
      Alcotest.(check (option string))
        "username" (Some "0000000000000")
        (List.assoc_opt "j_username" fields);
      Alcotest.(check (option string))
        "password" (Some "secret")
        (List.assoc_opt "j_password" fields);
      Alcotest.(check (option string))
        "event" (Some "")
        (List.assoc_opt "_eventId_proceed" fields)
  | forms ->
      Alcotest.failf "expected one login form, got %d" (List.length forms)

let test_report_state () =
  let submitted =
    {|
    <div class="contentbody-l">状態 提出済み</div>
    <form><input type="submit" name="action_ReportStudent_uncommitdone" value="提出取消(再提出する)"></form>
    |}
  in
  let open_state =
    {|
    <div class="contentbody-l">状態 受付中</div>
    <form><input type="file" name="RptSubmitFile"></form>
    |}
  in
  Alcotest.(check bool) "submitted" true (Manaba.report_is_submitted submitted);
  Alcotest.(check bool) "open" false (Manaba.report_is_submitted open_state)

let test_report_round_trip () =
  let open Lwt.Infix in
  let submitted = ref false in
  let flow_completed = ref false in
  let initial_page =
    {|
    <div class="contentbody-l">状態 受付中</div>
    <form action="course_1_report_2" method="post" enctype="multipart/form-data">
      <input type="file" name="RptSubmitFile">
      <input type="submit" name="action_ReportStudent_submitdone" value="アップロード">
      <input type="hidden" name="manaba-form" value="1">
      <input type="hidden" name="SessionValue1" value="token-1">
      <input type="hidden" name="SessionValue" value="@1">
    </form>
    |}
  in
  let preview_page =
    {|
    <div class="contentbody-l">提出確認</div>
    <form action="course_1_report_2" method="post" enctype="multipart/form-data">
      <input type="image" name="action_ReportStudent_datadelete_rptdata1">
      <input type="submit" name="action_ReportStudent_submitdone" value="アップロード">
      <input type="submit" name="action_ReportStudent_commitdone" value="提出">
      <input type="hidden" name="manaba-form" value="1">
      <input type="hidden" name="SessionValue1" value="token-2">
      <input type="hidden" name="SessionValue" value="@1">
    </form>
    |}
  in
  let submitted_page =
    {|
    <div class="contentbody-l">状態 提出済み</div>
    <form action="course_1_report_2" method="post" enctype="multipart/form-data">
      <input type="submit" name="action_ReportStudent_uncommitdone" value="提出取消(再提出する)">
      <input type="hidden" name="manaba-form" value="1">
      <input type="hidden" name="SessionValue1" value="token-3">
      <input type="hidden" name="SessionValue" value="@1">
    </form>
    |}
  in
  let storage_form =
    {|
    <form action="/idp/start" method="post">
      <input type="hidden" name="shib_idp_ls_supported">
      <input type="hidden" name="_eventId_proceed">
    </form>
    |}
  in
  let login_form =
    {|
    <form action="/idp/login" method="post">
      <input type="text" name="j_username">
      <input type="password" name="j_password">
      <button type="submit" name="_eventId_proceed">Login</button>
    </form>
    |}
  in
  let saml_form =
    {|
    <form action="/Shibboleth.sso/SAML2/POST" method="post">
      <input type="hidden" name="RelayState" value="relay">
      <input type="hidden" name="SAMLResponse" value="assertion">
    </form>
    |}
  in
  let flow_first =
    {|
    <div class="contentbody-l">step one</div>
    <form action="/ct/flow" method="post">
      <input type="hidden" name="token" value="one">
      <button type="submit" name="action_next">Next</button>
      <button type="submit" name="action_cancel">Cancel</button>
    </form>
    |}
  in
  let flow_second =
    {|
    <div class="contentbody-l">step two</div>
    <form action="/ct/flow" method="post">
      <input type="hidden" name="token" value="two">
      <button type="submit" name="action_finish">Finish</button>
    </form>
    |}
  in
  let run =
    let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    Lwt_unix.setsockopt socket Unix.SO_REUSEADDR true;
    Lwt_unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0))
    >>= fun () ->
    Lwt_unix.listen socket 10;
    let port =
      match Lwt_unix.getsockname socket with
      | Unix.ADDR_INET (_, port) -> port
      | _ -> Alcotest.fail "expected TCP socket"
    in
    let stop, stop_wakener = Lwt.wait () in
    let callback _connection request body =
      Cohttp_lwt.Body.to_string body >>= fun request_body ->
      let method_ = Cohttp.Request.meth request in
      let path = Cohttp.Request.uri request |> Uri.path in
      match (method_, path) with
      | `GET, "/ct/" ->
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:storage_form
            ()
      | `POST, "/idp/start" ->
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:login_form ()
      | `POST, "/idp/login" ->
          Alcotest.(check bool)
            "auth username" true
            (Util.contains ~needle:"j_username=student" request_body);
          Alcotest.(check bool)
            "auth password" true
            (Util.contains ~needle:"j_password=password" request_body);
          Alcotest.(check bool)
            "auth proceed event" true
            (Util.contains ~needle:"_eventId_proceed=" request_body);
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:saml_form ()
      | `POST, "/Shibboleth.sso/SAML2/POST" ->
          Alcotest.(check bool)
            "SAML response" true
            (Util.contains ~needle:"SAMLResponse=assertion" request_body);
          let headers =
            Cohttp.Header.of_list
              [
                ("location", "/ct/home"); ("set-cookie", "session=ok; Path=/ct");
              ]
          in
          Cohttp_lwt_unix.Server.respond_string ~headers ~status:`Found ~body:""
            ()
      | `GET, "/ct/home" ->
          Alcotest.(check (option string))
            "session cookie" (Some "session=ok")
            (Cohttp.Header.get (Cohttp.Request.headers request) "cookie");
          Cohttp_lwt_unix.Server.respond_string ~status:`OK
            ~body:{|<a href="logout">ログアウト</a>|} ()
      | `GET, "/ct/course_1_report_2" ->
          Cohttp_lwt_unix.Server.respond_string ~status:`OK
            ~body:(if !submitted then submitted_page else initial_page)
            ()
      | `POST, "/ct/course_1_report_2"
        when Util.contains ~needle:"action_ReportStudent_submitdone"
               request_body ->
          Alcotest.(check bool)
            "file bytes" true
            (Util.contains ~needle:"smoke-test" request_body);
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:preview_page
            ()
      | `POST, "/ct/course_1_report_2"
        when Util.contains ~needle:"action_ReportStudent_commitdone"
               request_body ->
          Alcotest.(check bool)
            "delete button omitted on commit" false
            (Util.contains ~needle:"datadelete" request_body);
          submitted := true;
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:submitted_page
            ()
      | `POST, "/ct/course_1_report_2"
        when Util.contains ~needle:"action_ReportStudent_uncommitdone"
               request_body ->
          submitted := false;
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:initial_page
            ()
      | `GET, "/ct/flow" ->
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:flow_first ()
      | `POST, "/ct/flow" when Util.contains ~needle:"action_next=" request_body
        ->
          Alcotest.(check bool)
            "first flow token" true
            (Util.contains ~needle:"token=one" request_body);
          Alcotest.(check bool)
            "first repeated value" true
            (Util.contains ~needle:"choice=a%26b" request_body);
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:flow_second ()
      | `POST, "/ct/flow"
        when Util.contains ~needle:"action_finish=" request_body ->
          Alcotest.(check bool)
            "second flow token" true
            (Util.contains ~needle:"token=two" request_body);
          flow_completed := true;
          Cohttp_lwt_unix.Server.respond_string ~status:`OK
            ~body:{|<div class="contentbody-l">done</div>|} ()
      | _ ->
          Cohttp_lwt_unix.Server.respond_string ~status:`Not_found
            ~body:("unexpected request: " ^ path)
            ()
    in
    let server =
      Cohttp_lwt_unix.Server.create ~stop
        ~mode:(`TCP (`Socket socket))
        (Cohttp_lwt_unix.Server.make ~callback ())
    in
    Lwt.async (fun () -> server);
    Lwt.pause () >>= fun () ->
    let session = Filename.temp_file "manaba-session" ".json" in
    Sys.remove session;
    let upload = Filename.temp_file "manaba-upload" ".txt" in
    let channel = open_out_bin upload in
    output_string channel "smoke-test";
    close_out channel;
    let client =
      Manaba.create
        (Printf.sprintf "http://127.0.0.1:%d/ct/" port)
        (Some session)
    in
    ( Auth.login (Manaba.http client) ~base_uri:(Manaba.base_uri client)
        ~username:"student" ~password:"password"
    >>= function
      | Error problem -> Alcotest.fail (Auth.error_to_string problem)
      | Ok _ -> Lwt.return_unit )
    >>= fun () ->
    ( ( Manaba.report_submit client ~course_id:1 ~report_id:2 ~file:upload
      >>= function
        | Error problem -> Alcotest.fail (Manaba.error_to_string problem)
        | Ok _ ->
            Alcotest.(check bool) "committed" true !submitted;
            Manaba.report_cancel client ~course_id:1 ~report_id:2 )
    >>= function
      | Error problem -> Alcotest.fail (Manaba.error_to_string problem)
      | Ok _ ->
          Alcotest.(check bool) "cancelled" false !submitted;
          let steps : Flow_plan.t =
            [
              {
                form_index = None;
                button_name = Some "action_next";
                fields = [ ("choice", "a&b"); ("choice", "second") ];
                uploads = [];
                auto = None;
              };
              {
                form_index = Some 1;
                button_name = None;
                fields = [];
                uploads = [];
                auto = None;
              };
            ]
          in
          Manaba.run_flow client ~target:"flow" steps )
    >>= function
    | Error problem -> Alcotest.fail (Manaba.error_to_string problem)
    | Ok _ ->
        Alcotest.(check bool) "flow completed" true !flow_completed;
        Lwt.wakeup_later stop_wakener ();
        Lwt.return_unit
  in
  Lwt_main.run run

(* manaba reissues a screen's hidden tokens on every entry and restarts a
   quiz's 経過時間 from that entry. Pressing スタート again to reach the answer
   form therefore throws away the time actually spent on the quiz, so the
   answer has to be submitted against the response already in hand. *)
let test_form_state_resumes_without_reentry () =
  let open Lwt.Infix in
  let start_page =
    {|
    <div class="contentbody-l">start</div>
    <form action="/ct/quiz" method="post">
      <input type="hidden" name="manaba-form" value="1">
      <input type="submit" name="action_start" value="スタート">
    </form>
    |}
  in
  let answer_page token =
    Printf.sprintf
      {|
    <div class="contentbody-l">answer</div>
    <form action="/ct/quiz" method="post">
      <input type="hidden" name="token" value="%s">
      <input type="submit" name="action_confirm" value="提出確認">
      <textarea name="qid1"></textarea>
    </form>
    |}
      token
  in
  let confirm_page token =
    Printf.sprintf
      {|
    <div class="contentbody-l">confirm</div>
    <form action="/ct/quiz" method="post">
      <input type="hidden" name="token" value="%s">
      <input type="submit" name="action_done" value="提出">
    </form>
    |}
      token
  in
  let entries = ref 0 in
  let submitted_token = ref None in
  let token_of body =
    try
      ignore (Str.search_forward (Str.regexp "token=\\([^&]*\\)") body 0);
      Some (Str.matched_group 1 body)
    with Not_found -> None
  in
  let run =
    let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    Lwt_unix.setsockopt socket Unix.SO_REUSEADDR true;
    Lwt_unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0))
    >>= fun () ->
    Lwt_unix.listen socket 10;
    let port =
      match Lwt_unix.getsockname socket with
      | Unix.ADDR_INET (_, port) -> port
      | _ -> Alcotest.fail "expected TCP socket"
    in
    let stop, stop_wakener = Lwt.wait () in
    let callback _connection request body =
      Cohttp_lwt.Body.to_string body >>= fun request_body ->
      let method_ = Cohttp.Request.meth request in
      let path = Cohttp.Request.uri request |> Uri.path in
      match (method_, path) with
      | `GET, "/ct/quiz" ->
          Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:start_page ()
      | `POST, "/ct/quiz"
        when Util.contains ~needle:"action_start=" request_body ->
          incr entries;
          Cohttp_lwt_unix.Server.respond_string ~status:`OK
            ~body:(answer_page (Printf.sprintf "t%d" !entries))
            ()
      | `POST, "/ct/quiz"
        when Util.contains ~needle:"action_confirm=" request_body ->
          Alcotest.(check bool)
            "answer reached the confirm screen" true
            (Util.contains ~needle:"qid1=answer" request_body);
          Cohttp_lwt_unix.Server.respond_string ~status:`OK
            ~body:
              (confirm_page (Option.value (token_of request_body) ~default:""))
            ()
      | `POST, "/ct/quiz" when Util.contains ~needle:"action_done=" request_body
        ->
          submitted_token := token_of request_body;
          Cohttp_lwt_unix.Server.respond_string ~status:`OK
            ~body:{|<div class="contentbody-l">done</div>|} ()
      | _ ->
          Cohttp_lwt_unix.Server.respond_string ~status:`Not_found
            ~body:("unexpected request: " ^ path)
            ()
    in
    let server =
      Cohttp_lwt_unix.Server.create ~stop
        ~mode:(`TCP (`Socket socket))
        (Cohttp_lwt_unix.Server.make ~callback ())
    in
    Lwt.async (fun () -> server);
    Lwt.pause () >>= fun () ->
    let session = Filename.temp_file "manaba-session" ".json" in
    Sys.remove session;
    let state_path = Filename.temp_file "manaba-state" ".json" in
    let client =
      Manaba.create
        (Printf.sprintf "http://127.0.0.1:%d/ct/" port)
        (Some session)
    in
    (* Entering the quiz starts the clock. *)
    Manaba.submit_named client ~target:"quiz" ~button_name:"action_start"
      ~fields:[] ~uploads:[]
    >>= function
    | Error problem -> Alcotest.fail (Manaba.error_to_string problem)
    | Ok entered -> (
        Alcotest.(check int) "entered once" 1 !entries;
        (match Form_state.save state_path (Form_state.of_response entered) with
        | Ok () -> ()
        | Error problem -> Alcotest.fail (Form_state.error_to_string problem));
        Alcotest.(check int)
          "state file is private" 0o600
          ((Unix.stat state_path).Unix.st_perm land 0o777);
        let resumed =
          match Form_state.load state_path with
          | Ok state -> Form_state.to_response state
          | Error problem -> Alcotest.fail (Form_state.error_to_string problem)
        in
        (* The work happens here in real use; the point is that resuming from the
           saved response neither re-fetches nor re-enters the quiz. *)
        ( Manaba.submit_response_named client ~source_response:resumed
            ~button_name:"action_confirm"
            ~fields:[ ("qid1", "answer") ]
            ~uploads:[]
        >>= function
          | Error problem -> Alcotest.fail (Manaba.error_to_string problem)
          | Ok confirmation ->
              Alcotest.(check int) "no re-entry to confirm" 1 !entries;
              Manaba.submit_response_named client ~source_response:confirmation
                ~button_name:"action_done" ~fields:[] ~uploads:[] )
        >>= function
        | Error problem -> Alcotest.fail (Manaba.error_to_string problem)
        | Ok _ ->
            Alcotest.(check int) "no re-entry overall" 1 !entries;
            Alcotest.(check (option string))
              "submitted under the first entry's token" (Some "t1")
              !submitted_token;
            Lwt.wakeup_later stop_wakener ();
            Lwt.return_unit)
  in
  Lwt_main.run run

let test_form_state_rejects_unknown_schema () =
  let json = `Assoc [ ("schemaVersion", `Int 2); ("uri", `String "x") ] in
  match Form_state.of_yojson json with
  | Error (Form_state.Invalid message) ->
      Alcotest.(check bool)
        "names the version" true
        (Util.contains ~needle:"schemaVersion 2" message)
  | Error problem ->
      Alcotest.failf "unexpected error: %s" (Form_state.error_to_string problem)
  | Ok _ -> Alcotest.fail "accepted an unsupported schema version"

let () =
  Alcotest.run "manaba-cli"
    [
      ( "html",
        [
          Alcotest.test_case "courses" `Quick test_courses;
          Alcotest.test_case "tasks" `Quick test_tasks;
          Alcotest.test_case "image-only link" `Quick test_image_link;
          Alcotest.test_case "visible text" `Quick test_visible_text;
          Alcotest.test_case "report form" `Quick test_report_form;
          Alcotest.test_case "unknown form domains" `Quick
            test_unknown_form_domains_preserved;
          Alcotest.test_case "form domain round trips" `Quick
            test_form_domain_round_trips;
          Alcotest.test_case "oversized task identifiers" `Quick
            test_oversized_task_identifiers;
          Alcotest.test_case "repeated field overrides" `Quick
            test_repeated_field_overrides;
          Alcotest.test_case "flow plan" `Quick test_flow_plan;
          Alcotest.test_case "flow plan structured error" `Quick
            test_flow_plan_structured_error;
        ] );
      ( "cookies",
        [
          Alcotest.test_case "scope" `Quick test_cookie_jar;
          Alcotest.test_case "target origin" `Quick test_target_origin;
        ] );
      ( "auth",
        [ Alcotest.test_case "credential fields" `Quick test_auth_fields ] );
      ( "report",
        [
          Alcotest.test_case "submission state" `Quick test_report_state;
          Alcotest.test_case "auth, upload, commit, cancel" `Quick
            test_report_round_trip;
        ] );
      ( "form state",
        [
          Alcotest.test_case "resumes without re-entry" `Quick
            test_form_state_resumes_without_reentry;
          Alcotest.test_case "rejects unknown schema" `Quick
            test_form_state_rejects_unknown_schema;
        ] );
    ]

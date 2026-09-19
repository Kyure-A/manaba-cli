(* Synthetic semantic HTML, not a captured manaba page. Unknown markup is tested
   explicitly so these examples cannot imply coverage of unobserved variants. *)
let path = "course_10_report_20"

let row label value =
  Printf.sprintf "<tr><th>%s</th><td>%s</td></tr>" label value

let report ?(status = "提出済み") ?(count = "2") ?(time = "new") names =
  "<table>" ^ row "状態" status ^ row "提出日時" time
  ^ row "提出ファイル数" count
  ^ row "提出ファイル"
      (String.concat " "
         (List.map
            (fun name -> Printf.sprintf "<a href='file_%s'>%s</a>" name name)
            names))
  ^ "</table>"

let parse html = Assignment.parse ~path html

let test_structured () =
  let html =
    {|<table>
    <tr><th>タイトル</th><td>確認テスト</td></tr>
    <tr><th>提出期限</th><td>2026-09-30 23:59</td></tr>
    <tr><th>再提出</th><td>不可</td></tr>
    <tr><th>回答数</th><td>1 問</td></tr>
    <tr><th>状態</th><td>回答済み</td></tr>
    <tr><th>回答日時</th><td>2026-09-20 00:00</td></tr>
    </table><form>
    <fieldset><legend>どちらですか？</legend>
    <label><input type="radio" name="qid1" value="1" checked>〇</label>
    <label><input type="radio" name="qid1" value="2">×</label></fieldset>
    <label for="essay">理由</label><textarea id="essay" name="qid2">理由です</textarea>
    <input type="hidden" name="qid3" value="private-token">
    <input type="hidden" name="SessionValue" value="private-token">
    <input type="submit" name="action_QueryStudent_querydone" value="提出">
    </form>|}
  in
  let item = Assignment.parse ~path:"course_10_query_20" html in
  Alcotest.(check (option int)) "course" (Some 10) item.course_id;
  Alcotest.(check (option string))
    "deadline" (Some "2026-09-30 23:59") item.deadline;
  Alcotest.(check (option bool)) "resubmission" (Some false) item.resubmission;
  Alcotest.(check (option int)) "answers" (Some 1) item.answer_count;
  Alcotest.(check int)
    "two questions, not radio controls or hidden fields" 2
    (List.length item.questions);
  let first = List.hd item.questions in
  Alcotest.(check (option string)) "prompt" (Some "どちらですか？") first.prompt;
  let labels =
    first.controls
    |> List.concat_map (fun (control : Types.form_control) ->
        List.map
          (fun (option : Types.form_option) -> option.label)
          control.options)
  in
  Alcotest.(check (list string)) "option labels" [ "〇"; "×" ] labels;
  let json = Assignment.to_yojson item |> Yojson.Safe.to_string in
  Alcotest.(check bool)
    "no hidden tokens" false
    (Util.contains ~needle:"private-token" json)

let test_unknown () =
  let item = parse "<p>提出済みを確認してください。<a href='file_handout'>old.pdf</a></p>" in
  Alcotest.(check bool)
    "instructions aren't receipts" false
    (Assignment.is_submitted item);
  Alcotest.(check int)
    "attachments aren't submitted files" 0
    (List.length item.submitted_files);
  Alcotest.(check (option int)) "unknown count isn't zero" None item.file_count;
  Alcotest.(check bool)
    "unknown structure" true
    (List.mem "unrecognized_assignment_markup" item.warnings);
  let ambiguous =
    parse
      "<table><tr><th>状態</th><td>提出済み</td></tr><tr><th>状態</th><td>未提出</td></tr></table>"
  in
  Alcotest.(check (option string))
    "conflicting facts aren't guessed" None ambiguous.status;
  let fractional = parse "<table><tr><th>回答数</th><td>1/5</td></tr></table>" in
  Alcotest.(check (option int))
    "unknown count grammar" None fractional.answer_count

let test_report_evidence () =
  let before = parse (report ~status:"未提出" ~time:"old" []) in
  let preview = parse (report ~status:"確認" [ "a.pdf"; "b.pdf" ]) in
  let check name expected fresh =
    let actual =
      Assignment.verify_report ~before ~preview ~fresh ~filename:"b.pdf"
      |> Result.is_ok
    in
    Alcotest.(check bool) name expected actual
  in
  check "fresh matching files" true (parse (report [ "a.pdf"; "b.pdf" ]));
  check "old submitted page misses this upload" false
    (parse (report ~count:"1" [ "a.pdf" ]));
  check "same names with wrong count" false
    (parse (report ~count:"3" [ "a.pdf"; "b.pdf" ]));
  check "same state but old timestamp" false
    (parse (report ~time:"old" [ "a.pdf"; "b.pdf" ]));
  check "extra file" false
    (parse (report ~count:"3" [ "a.pdf"; "b.pdf"; "other.pdf" ]));
  check "not submitted" false
    (parse (report ~status:"未提出" [ "a.pdf"; "b.pdf" ]));
  let unknown =
    parse
      "<table><tr><th>状態</th><td>提出済み</td></tr><tr><th>提出ファイル</th><td><a \
       href='a'>a.pdf</a><a href='b'>b.pdf</a></td></tr></table>"
  in
  check "unknown date/count remain nullable, file set still verified" true
    unknown;
  Alcotest.(check bool)
    "missing date flagged" true
    (List.mem "submission_time_not_observed" unknown.warnings)

let test_unverifiable_resubmission () =
  let before =
    parse
      "<table><tr><th>状態</th><td>提出済み</td></tr><tr><th>提出ファイル</th><td><a \
       href='a'>a.pdf</a></td></tr></table>"
  in
  let result =
    Assignment.verify_report ~before ~preview:before ~fresh:before
      ~filename:"a.pdf"
  in
  Alcotest.(check bool)
    "same-name previous receipt without date cannot verify a new submission"
    true (Result.is_error result);
  let cancel =
    parse
      {|<form><input type="submit" name="action_ReportStudent_uncommitdone" value="取消"></form>|}
  in
  Alcotest.(check (option bool))
    "withdrawal availability isn't resubmission permission" None
    cancel.resubmission

let test_stale_http missing_preview () =
  let open Lwt.Infix in
  Lwt_main.run
    (let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
     Lwt_unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0))
     >>= fun () ->
     Lwt_unix.listen socket 8;
     let port =
       match Lwt_unix.getsockname socket with
       | Unix.ADDR_INET (_, port) -> port
       | _ -> assert false
     in
     let stop, wake = Lwt.wait () in
     let upload = Filename.temp_file "manaba-evidence" ".pdf" in
     let session = Filename.temp_file "manaba-session" ".json" in
     Sys.remove session;
     let filename = Filename.basename upload in
     let commits = ref 0 and uploads = ref 0 and gets = ref 0 in
     let initial =
       {|<form method="post" enctype="multipart/form-data"><input type="file" name="RptSubmitFile"><input type="image" name="action_ReportStudent_datadelete_rptdata1"><input type="submit" name="action_ReportStudent_submitdone" value="アップロード"></form>|}
     in
     let preview =
       report ~status:"確認" ~count:"1"
         [ (if missing_preview then "older.pdf" else filename) ]
       ^ {|<form method="post"><input type="hidden" name="token" value="preview-only"><input type="submit" name="action_ReportStudent_commitdone" value="提出"></form>|}
     in
     let callback _ request body =
       Cohttp_lwt.Body.to_string body >>= fun body ->
       let html =
         match Cohttp.Request.meth request with
         | `GET ->
             incr gets;
             if !gets = 1 then initial else report ~count:"1" [ "older.pdf" ]
         | `POST
           when Util.contains ~needle:"action_ReportStudent_commitdone" body ->
             incr commits;
             Alcotest.(check bool)
               "uses preview token" true
               (Util.contains ~needle:"preview-only" body);
             report ~count:"1" [ filename ]
         | `POST ->
             incr uploads;
             preview
         | _ -> assert false
       in
       Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:html ()
     in
     Lwt.async (fun () ->
         Cohttp_lwt_unix.Server.create ~stop
           ~mode:(`TCP (`Socket socket))
           (Cohttp_lwt_unix.Server.make ~callback ()));
     Lwt.finalize
       (fun () ->
         let client =
           Manaba.create
             (Printf.sprintf "http://127.0.0.1:%d/ct/" port)
             (Some session)
         in
         Manaba.report_submit client ~course_id:10 ~report_id:20 ~file:upload
         >|= fun result ->
         Alcotest.(check bool)
           "post success cannot mask stale fresh state" true
           (Result.is_error result);
         Alcotest.(check int) "one upload" 1 !uploads;
         Alcotest.(check int)
           "one commit, no retry"
           (if missing_preview then 0 else 1)
           !commits;
         Alcotest.(check int)
           "initial GET plus independent verification"
           (if missing_preview then 1 else 2)
           !gets)
       (fun () ->
         Lwt.wakeup_later wake ();
         Sys.remove upload;
         if Sys.file_exists session then Sys.remove session;
         Lwt.return_unit))

let test_http_timeout () =
  let open Lwt.Infix in
  Lwt_main.run
    (let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
     Lwt_unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0))
     >>= fun () ->
     Lwt_unix.listen socket 8;
     let port =
       match Lwt_unix.getsockname socket with
       | Unix.ADDR_INET (_, port) -> port
       | _ -> assert false
     in
     let stop, wake = Lwt.wait () in
     let hits = ref 0 in
     let callback _ _ _ =
       incr hits;
       Lwt_unix.sleep 0.3 >>= fun () ->
       Cohttp_lwt_unix.Server.respond_string ~status:`OK ~body:"late" ()
     in
     Lwt.async (fun () ->
         Cohttp_lwt_unix.Server.create ~stop
           ~mode:(`TCP (`Socket socket))
           (Cohttp_lwt_unix.Server.make ~callback ()));
     let session = Filename.temp_file "manaba-timeout" ".json" in
     Sys.remove session;
     Lwt.finalize
       (fun () ->
         let client =
           Http_client.create ~timeout_seconds:0.05 ~session_path:session ()
         in
         Lwt.catch
           (fun () ->
             Http_client.get client
               (Uri.of_string (Printf.sprintf "http://127.0.0.1:%d/" port))
             >|= fun _ -> Alcotest.fail "unbounded request")
           (fun problem ->
             Alcotest.(check bool)
               "timeout explains uncertain write outcome" true
               (Util.contains ~needle:"write may already have been applied"
                  (Printexc.to_string problem));
             Alcotest.(check bool) "never retried" true (!hits <= 1);
             Lwt.return_unit))
       (fun () ->
         Lwt.wakeup_later wake ();
         Lwt.return_unit))

let () =
  Alcotest.run "assignment"
    [
      ( "parser",
        [
          Alcotest.test_case "structured quiz" `Quick test_structured;
          Alcotest.test_case "unknown and conflicting evidence" `Quick
            test_unknown;
        ] );
      ( "verification",
        [
          Alcotest.test_case "report evidence" `Quick test_report_evidence;
          Alcotest.test_case "unverifiable resubmission" `Quick
            test_unverifiable_resubmission;
          Alcotest.test_case "stale HTTP state" `Quick (test_stale_http false);
          Alcotest.test_case "missing preview prevents commit" `Quick
            (test_stale_http true);
          Alcotest.test_case "bounded HTTP request" `Quick test_http_timeout;
        ] );
    ]

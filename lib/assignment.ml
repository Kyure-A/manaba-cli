type fact = { label : string; value : string }

type question = {
  name : string;
  prompt : string option;
  controls : Types.form_control list;
}

type t = {
  path : string;
  kind : Types.task_kind;
  course_id : int option;
  id : int option;
  title : string option;
  deadline : string option;
  resubmission : bool option;
  status : string option;
  submitted_at : string option;
  answer_count : int option;
  file_count : int option;
  submitted_files : Types.link list;
  questions : question list;
  facts : fact list;
  forms : Types.form list;
  warnings : string list;
}

let text node =
  Soup.trimmed_texts node |> String.concat " " |> Util.normalize_space

let nonempty value = if value = "" then None else Some value

let label value =
  let value = Util.normalize_space value in
  List.fold_left
    (fun value suffix ->
      if Util.ends_with ~suffix value then
        String.sub value 0 (String.length value - String.length suffix)
        |> String.trim
      else value)
    value [ ":"; "：" ]

(* Only semantic key/value rows are read. Page-wide substring matching would
   turn instructions such as “提出済みを確認してください” into a false receipt. *)
let rows soup =
  let tables =
    Soup.select "tr" soup |> Soup.to_list
    |> List.filter_map (fun row ->
        match
          Soup.children row |> Soup.elements |> Soup.to_list
          |> List.filter (fun node -> List.mem (Soup.name node) [ "th"; "td" ])
        with
        | [ key; value ] -> Some (label (text key), value)
        | _ -> None)
  in
  let definitions =
    Soup.select "dt" soup |> Soup.to_list
    |> List.filter_map (fun key ->
        match Soup.next_element key with
        | Some value when Soup.name value = "dd" ->
            Some (label (text key), value)
        | _ -> None)
  in
  tables @ definitions

let matching names key = List.mem key names

let value names facts =
  let values =
    facts
    |> List.filter (fun fact -> matching names fact.label)
    |> List.map (fun fact -> fact.value)
    |> List.sort_uniq String.compare
  in
  match values with [ value ] -> nonempty value | _ -> None

let count = function
  | None -> None
  | Some value ->
      let re = Str.regexp "^\\([0-9]+\\) *\\(件\\|個\\|問\\|ファイル\\)?$" in
      if Str.string_match re value 0 then
        int_of_string_opt (Str.matched_group 1 value)
      else None

let status_labels = [ "状態"; "提出状況"; "提出状態"; "回答状況"; "Status" ]

let time_labels = [ "提出日時"; "提出日"; "回答日時"; "Submission time" ]

let file_labels = [ "提出ファイル"; "提出済みファイル"; "Submitted files" ]

let parse ~path html =
  let soup = Soup.parse html in
  List.iter
    (fun selector ->
      Soup.select selector soup |> Soup.to_list |> List.iter Soup.delete)
    [ "script"; "style"; "noscript" ];
  let rows = rows soup in
  let facts =
    rows |> List.map (fun (label, node) -> { label; value = text node })
  in
  let forms = Html.forms html in
  let has name = List.exists (Html.contains_control name) forms in
  let resubmission =
    match value [ "再提出"; "再提出可否"; "Resubmission" ] facts with
    | Some ("可" | "可能" | "可（受付期間内）" | "Allowed") -> Some true
    | Some ("不可" | "できません" | "Not allowed") -> Some false
    | _ -> None
  in
  let explicit_status = value status_labels facts in
  let status =
    match explicit_status with
    | Some _ -> explicit_status
    | None
      when (not
              (List.exists
                 (fun fact -> matching status_labels fact.label)
                 facts))
           && has "action_ReportStudent_uncommitdone" ->
        Some "提出済み"
    | None -> None
  in
  let submitted_files =
    rows
    |> List.filter (fun (key, _) -> matching file_labels key)
    |> List.concat_map (fun (_, node) ->
        Soup.select "a[href]" node |> Soup.to_list)
    |> List.filter_map (fun node ->
        match (Soup.attribute "href" node, nonempty (text node)) with
        | Some href, Some text -> Some Types.{ href; text }
        | _ -> None)
    |> Util.deduplicate_by (fun (file : Types.link) ->
        file.href ^ "\000" ^ file.text)
  in
  let file_count = value [ "提出ファイル数"; "ファイル数"; "File count" ] facts |> count in
  let controls =
    forms |> List.concat_map (fun (form : Types.form) -> form.controls)
  in
  let question_names =
    controls
    |> List.filter_map (fun (control : Types.form_control) ->
        match (control.name, control.input_type) with
        | ( Some name,
            ( Types.Hidden | Types.Password | Types.Submit | Types.Image
            | Types.Reset | Types.Button_type ) ) ->
            ignore name;
            None
        | Some name, _ when Str.string_match (Str.regexp "^qid[0-9]+$") name 0
          ->
            Some name
        | _ -> None)
    |> Util.deduplicate_by Fun.id
  in
  let questions =
    question_names
    |> List.map (fun name ->
        let nodes =
          [ "input"; "textarea"; "select" ]
          |> List.concat_map (fun selector ->
              Soup.select selector soup |> Soup.to_list)
          |> List.filter (fun node -> Soup.attribute "name" node = Some name)
        in
        let prompts =
          nodes
          |> List.filter_map (fun node ->
              let legend =
                Option.bind
                  (Soup.ancestors node |> Soup.to_list
                  |> List.find_opt (fun node -> Soup.name node = "fieldset"))
                  (fun node -> Soup.select_one "> legend" node)
                |> Option.map text
              in
              match legend with
              | Some prompt -> nonempty prompt
              | None
                when List.mem
                       (Soup.attribute "type" node)
                       [ Some "radio"; Some "checkbox" ] ->
                  None
              | None -> (
                  match Soup.attribute "aria-label" node with
                  | Some prompt -> nonempty prompt
                  | None -> (
                      match Soup.attribute "id" node with
                      | None -> None
                      | Some id ->
                          Soup.select "label[for]" soup
                          |> Soup.to_list
                          |> List.find_opt (fun label ->
                              Soup.attribute "for" label = Some id)
                          |> Option.map text
                          |> fun result -> Option.bind result nonempty)))
          |> List.sort_uniq String.compare
        in
        let prompt =
          match prompts with [ prompt ] -> Some prompt | _ -> None
        in
        let controls =
          List.filter
            (fun (control : Types.form_control) -> control.name = Some name)
            controls
        in
        let controls =
          List.map
            (fun (control : Types.form_control) ->
              let options =
                List.map
                  (fun (option : Types.form_option) ->
                    let node =
                      List.find_opt
                        (fun node ->
                          Soup.attribute "value" node = Some option.value)
                        nodes
                    in
                    let label =
                      Option.bind node (fun node ->
                          let direct =
                            Soup.ancestors node |> Soup.to_list
                            |> List.find_opt (fun node ->
                                Soup.name node = "label")
                          in
                          match direct with
                          | Some _ -> direct
                          | None ->
                              Option.bind (Soup.attribute "id" node) (fun id ->
                                  Soup.select "label[for]" soup
                                  |> Soup.to_list
                                  |> List.find_opt (fun label ->
                                      Soup.attribute "for" label = Some id)))
                      |> Option.map text
                    in
                    match label with
                    | None -> option
                    | Some label -> { option with label })
                  control.options
              in
              { control with options })
            controls
        in
        { name; prompt; controls })
  in
  let path = Uri.path (Uri.of_string path) |> Filename.basename in
  let course_id, id =
    let re =
      Str.regexp
        "^course_\\([0-9]+\\)_\\(query\\|drill\\|survey\\|report\\)_\\([0-9]+\\)$"
    in
    if Str.string_match re path 0 then
      ( int_of_string_opt (Str.matched_group 1 path),
        int_of_string_opt (Str.matched_group 3 path) )
    else (None, None)
  in
  let kind =
    if Util.contains ~needle:"_query_" path then Types.Quiz
    else if Util.contains ~needle:"_drill_" path then Types.Drill
    else if Util.contains ~needle:"_survey_" path then Types.Survey
    else if Util.contains ~needle:"_report_" path then Types.Report
    else Types.Unknown "unknown"
  in
  let title =
    value [ "タイトル"; "課題名"; "小テスト名"; "レポート名"; "アンケート名"; "Title" ] facts
  in
  let deadline =
    value [ "受付終了日時"; "受付終了"; "提出期限"; "回答期限"; "終了日時"; "Deadline" ] facts
  in
  let submitted_at = value time_labels facts in
  let answer_count =
    value [ "回答数"; "回答済み設問数"; "Answer count" ] facts |> count
  in
  let warnings =
    (if id = None then [ "unrecognized_assignment_path" ] else [])
    @ (if facts = [] && questions = [] && status = None then
         [ "unrecognized_assignment_markup" ]
       else [])
    @ (if deadline = None then [ "deadline_not_observed" ] else [])
    @ (if resubmission = None then [ "resubmission_not_observed" ] else [])
    @ (if status = None then [ "status_not_observed" ] else [])
    @ (if submitted_at = None then [ "submission_time_not_observed" ] else [])
    @ (if answer_count = None && kind <> Types.Report then
         [ "answer_count_not_observed" ]
       else [])
    @ (if kind = Types.Report && file_count = None then
         [ "file_count_not_observed" ]
       else [])
    @ (if kind = Types.Report && submitted_files = [] then
         [ "submitted_files_not_observed" ]
       else [])
    @ (if List.exists (fun question -> question.prompt = None) questions then
         [ "question_prompt_not_observed" ]
       else [])
    @
    if kind <> Types.Report then [ "questions_cover_current_response_only" ]
    else []
  in
  {
    path;
    kind;
    course_id;
    id;
    title;
    deadline;
    resubmission;
    status;
    submitted_at;
    answer_count;
    file_count;
    submitted_files;
    questions;
    facts;
    forms;
    warnings;
  }

let is_submitted item =
  match item.status with
  | Some ("提出済み" | "提出済" | "提出しました" | "Submitted" | "回答済み" | "合格済み") -> true
  | _ -> false

let filenames item =
  List.map (fun (file : Types.link) -> file.text) item.submitted_files
  |> List.sort String.compare

let verify_report ~before ~preview ~fresh ~filename =
  let expected = filenames preview in
  if not (List.mem filename expected) then
    Error "アップロードしたファイル名を提出確認画面で確認できません。自動再送信しないでください。"
  else if not (is_submitted fresh) then
    Error "最終送信後の再取得で提出済み状態を確認できません。自動再送信しないでください。"
  else if filenames fresh <> expected then
    Error "最終送信後の提出ファイル一覧が確認画面と一致しません。自動再送信しないでください。"
  else if
    List.exists
      (fun item ->
        match item.file_count with
        | Some count -> count <> List.length expected
        | None -> false)
      [ preview; fresh ]
  then Error "提出ファイル数とファイル一覧が一致しません。自動再送信しないでください。"
  else if
    before.submitted_at <> None && before.submitted_at = fresh.submitted_at
  then Error "提出日時が以前と同じため今回の提出を識別できません。自動再送信しないでください。"
  else if
    is_submitted before
    && filenames before = filenames fresh
    && (before.submitted_at = None || fresh.submitted_at = None)
  then Error "同名ファイルの過去の提出と今回の提出を識別する日時を確認できません。自動再送信しないでください。"
  else Ok ()

let option_to_yojson f = function None -> `Null | Some value -> f value

let to_yojson item =
  let string = option_to_yojson (fun value -> `String value) in
  let int = option_to_yojson (fun value -> `Int value) in
  `Assoc
    [
      ("path", `String item.path);
      ("kind", `String (Types.task_kind_to_string item.kind));
      ("course_id", int item.course_id);
      ("id", int item.id);
      ("title", string item.title);
      ("deadline", string item.deadline);
      ( "resubmission",
        option_to_yojson (fun value -> `Bool value) item.resubmission );
      ("status", string item.status);
      ("submitted_at", string item.submitted_at);
      ("answer_count", int item.answer_count);
      ("file_count", int item.file_count);
      ( "submitted_files",
        `List (List.map Types.link_to_yojson item.submitted_files) );
      ( "questions",
        `List
          (List.map
             (fun question ->
               `Assoc
                 [
                   ("name", `String question.name);
                   ("prompt", string question.prompt);
                   ( "controls",
                     `List
                       (List.map Types.public_form_control_to_yojson
                          question.controls) );
                 ])
             item.questions) );
      ( "facts",
        `List
          (List.map
             (fun fact ->
               `Assoc
                 [
                   ("label", `String fact.label); ("value", `String fact.value);
                 ])
             item.facts) );
      ("forms", `List (List.map Types.public_form_to_yojson item.forms));
      ("warnings", `List (List.map (fun value -> `String value) item.warnings));
    ]

open Types

let parse = Soup.parse

let text node =
  Soup.trimmed_texts node |> String.concat " " |> Util.normalize_space

let attribute name node = Soup.attribute name node

let integer_match expression value group =
  if Str.string_match expression value 0 then
    try Some (int_of_string (Str.matched_group group value)) with _ -> None
  else None

let courses html =
  let soup = parse html in
  let expression = Str.regexp "^course_\\([0-9]+\\)$" in
  Soup.select "a[href]" soup |> Soup.to_list
  |> List.filter_map (fun anchor ->
      match attribute "href" anchor with
      | Some href -> (
          match integer_match expression href 1 with
          | Some id ->
              let name = text anchor in
              if name = "" then None else Some { id; name }
          | None -> None)
      | None -> None)
  |> Util.deduplicate_by (fun (course : course) -> course.id)

let task_kind visible href =
  let visible = Util.lowercase visible in
  if
    Util.contains ~needle:"drill" (Util.lowercase href)
    || Util.contains ~needle:"ドリル" visible
  then Drill
  else if
    Util.contains ~needle:"survey" (Util.lowercase href)
    || Util.contains ~needle:"アンケート" visible
  then Survey
  else if
    Util.contains ~needle:"report" (Util.lowercase href)
    || Util.contains ~needle:"レポート" visible
  then Report
  else if Util.contains ~needle:"外部教材" visible then External
  else if
    Util.contains ~needle:"query" (Util.lowercase href)
    || Util.contains ~needle:"小テスト" visible
  then Quiz
  else Unknown visible

let cell cells index = List.nth_opt cells index
let nonempty = function Some value when value <> "" -> Some value | _ -> None
let first_link node = Soup.select_one "a[href]" node

let parse_task_href href =
  let expression =
    Str.regexp
      "^course_\\([0-9]+\\)_\\(query\\|drill\\|survey\\|report\\)_\\([0-9]+\\)"
  in
  if Str.string_match expression href 0 then
    let course_id = int_of_string (Str.matched_group 1 href) in
    let item_id = int_of_string (Str.matched_group 3 href) in
    (Some course_id, Some item_id)
  else (None, None)

let tasks html =
  let soup = parse html in
  Soup.select "table.stdlist tr" soup
  |> Soup.to_list
  |> List.filter_map (fun row ->
      let cells = Soup.select "> td" row |> Soup.to_list in
      match (cell cells 0, cell cells 1, cell cells 2) with
      | Some kind_cell, Some title_cell, Some course_cell -> (
          match first_link title_cell with
          | Some anchor -> (
              match attribute "href" anchor with
              | Some href ->
                  let course_id, id = parse_task_href href in
                  let starts_at = cell cells 3 |> Option.map text |> nonempty in
                  let ends_at = cell cells 4 |> Option.map text |> nonempty in
                  Some
                    {
                      kind = task_kind (text kind_cell) href;
                      id;
                      course_id;
                      title = text anchor;
                      course = text course_cell;
                      starts_at;
                      ends_at;
                      href;
                    }
              | None -> None)
          | None -> None)
      | _ -> None)

let links html =
  let soup = parse html in
  Soup.select "a[href]" soup |> Soup.to_list
  |> List.filter_map (fun anchor ->
      match attribute "href" anchor with
      | Some href ->
          let visible =
            let direct = text anchor in
            if direct <> "" then direct
            else
              match Soup.select_one "img[alt]" anchor with
              | Some image -> Option.value ~default:"" (attribute "alt" image)
              | None ->
                  attribute "aria-label" anchor
                  |> Option.value
                       ~default:
                         (Option.value ~default:"" (attribute "title" anchor))
          in
          if visible = "" then None else Some { text = visible; href }
      | None -> None)
  |> Util.deduplicate_by (fun (link : link) -> link.href ^ "\000" ^ link.text)

let control_of_node node =
  let tag = Soup.name node in
  let input_type =
    match attribute "type" node with
    | Some value -> Util.lowercase value
    | None -> if tag = "textarea" then "textarea" else tag
  in
  let multiple = Soup.has_attribute "multiple" node in
  let options =
    if tag = "select" then
      Soup.select "option" node |> Soup.to_list
      |> List.map (fun option ->
          {
            value =
              Option.value ~default:(text option) (attribute "value" option);
            label = text option;
            selected = Soup.has_attribute "selected" option;
          })
    else []
  in
  let options =
    if multiple || List.exists (fun option -> option.selected) options then
      options
    else
      match options with
      | [] -> []
      | (first : form_option) :: rest -> { first with selected = true } :: rest
  in
  let value =
    match (tag, input_type) with
    | "input", ("checkbox" | "radio") ->
        if Soup.has_attribute "checked" node then
          Some (Option.value ~default:"on" (attribute "value" node))
        else None
    | "input", "file" -> None
    | "select", _ ->
        let selected = List.find_opt (fun option -> option.selected) options in
        let selected =
          match (selected, multiple) with
          | Some option, _ -> Some option
          | None, false -> (
              match options with option :: _ -> Some option | [] -> None)
          | None, true -> None
        in
        Option.map (fun (option : form_option) -> option.value) selected
    | "textarea", _ -> Some (Soup.texts node |> String.concat "")
    | "button", _ -> Some (Option.value ~default:"" (attribute "value" node))
    | "input", _ -> Some (Option.value ~default:"" (attribute "value" node))
    | _ -> attribute "value" node
  in
  { tag; input_type; name = attribute "name" node; value; options; multiple }

let forms html =
  let soup = parse html in
  Soup.select "form" soup |> Soup.to_list
  |> List.map (fun form ->
      let action = Option.value ~default:"" (attribute "action" form) in
      let method_ =
        attribute "method" form |> Option.value ~default:"get" |> Util.lowercase
      in
      let enctype =
        attribute "enctype" form
        |> Option.value ~default:"application/x-www-form-urlencoded"
        |> Util.lowercase
      in
      let controls =
        [ "input"; "textarea"; "select"; "button" ]
        |> List.concat_map (fun selector ->
            Soup.select selector form |> Soup.to_list)
        |> List.map control_of_node
      in
      { action; method_; enctype; controls })

let default_fields form =
  form.controls
  |> List.concat_map (fun control ->
      match (control.name, control.input_type) with
      | Some _, ("submit" | "button" | "image" | "file" | "password" | "reset")
        ->
          []
      | Some name, "select" ->
          let selected =
            List.filter (fun option -> option.selected) control.options
          in
          let selected =
            match (selected, control.multiple) with
            | [], false -> (
                match control.options with
                | option :: _ -> [ option ]
                | [] -> [])
            | _ -> selected
          in
          List.map (fun (option : form_option) -> (name, option.value)) selected
      | Some name, _ ->
          Option.to_list (Option.map (fun value -> (name, value)) control.value)
      | None, _ -> [])

let submission_fields ?button_name form =
  let defaults = default_fields form in
  let buttons =
    form.controls
    |> List.filter_map (fun control ->
        match (control.name, control.value, control.input_type) with
        | Some _, Some _, ("submit" | "image") -> Some control
        | _ -> None)
  in
  let fields control =
    match (control.name, control.value, control.input_type) with
    | Some name, _, "image" -> [ (name ^ ".x", "0"); (name ^ ".y", "0") ]
    | Some name, Some value, _ -> [ (name, value) ]
    | _ -> []
  in
  match button_name with
  | Some requested -> (
      match
        List.find_opt (fun control -> control.name = Some requested) buttons
      with
      | Some button -> fields button @ defaults
      | None -> defaults)
  | None -> (
      match buttons with
      | [ button ] -> fields button @ defaults
      | _ -> defaults)

let contains_password form =
  List.exists (fun control -> control.input_type = "password") form.controls

let contains_control name form =
  List.exists (fun control -> control.name = Some name) form.controls

let find_form_by_control name forms =
  List.find_opt (contains_control name) forms

let submit_controls form =
  form.controls
  |> List.filter (fun control ->
      control.input_type = "submit" || control.input_type = "image")

let file_controls form =
  List.filter (fun control -> control.input_type = "file") form.controls

let main_text html =
  let soup = parse html in
  let node =
    match Soup.select_one ".contentbody-l" soup with
    | Some node -> node
    | None -> (
        match Soup.select_one ".contentbody" soup with
        | Some node -> node
        | None -> (
            match Soup.select_one ".pagebody" soup with
            | Some node -> node
            | None -> Soup.R.select_one "html" soup))
  in
  [ "script"; "style"; "noscript" ]
  |> List.iter (fun selector ->
      Soup.select selector node |> Soup.to_list |> List.iter Soup.delete);
  Soup.trimmed_texts node
  |> List.map Util.normalize_space
  |> List.filter (fun value -> value <> "")
  |> String.concat "\n"

let is_logged_in html =
  let soup = parse html in
  Soup.select "a[href='logout']" soup |> Soup.count > 0

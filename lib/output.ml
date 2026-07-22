open Types

let print_json value =
  Yojson.Safe.pretty_to_channel stdout value;
  output_char stdout '\n'

let print_courses ~json courses =
  if json then print_json (`List (List.map course_to_yojson courses))
  else
    List.iter
      (fun (course : course) -> Printf.printf "%d\t%s\n" course.id course.name)
      courses

let show_option = Option.value ~default:"-"

let print_tasks ~json tasks =
  if json then print_json (`List (List.map task_to_yojson tasks))
  else (
    Printf.printf "TYPE\tCOURSE_ID\tITEM_ID\tDEADLINE\tCOURSE\tTITLE\n";
    List.iter
      (fun (task : task) ->
        Printf.printf "%s\t%s\t%s\t%s\t%s\t%s\n"
          (task_kind_to_string task.kind)
          (Option.map string_of_int task.course_id |> show_option)
          (Option.map string_of_int task.id |> show_option)
          (show_option task.ends_at) task.course task.title)
      tasks)

let print_links ~json links =
  if json then print_json (`List (List.map link_to_yojson links))
  else
    List.iter
      (fun (link : link) -> Printf.printf "%s\t%s\n" link.href link.text)
      links

let print_control (control : form_control) =
  let name = Option.value ~default:"(unnamed)" control.name in
  let sensitive =
    match control.input_type with Hidden | Password -> true | _ -> false
  in
  let current =
    if sensitive then ""
    else
      match control.value with
      | None -> ""
      | Some value -> Printf.sprintf " value=%S" value
  in
  Printf.printf "    %-10s %-12s %s%s%s\n"
    (control_tag_to_string control.tag)
    (input_type_to_string control.input_type)
    name
    (if control.multiple then " multiple" else "")
    current;
  List.iter
    (fun (option : form_option) ->
      Printf.printf "        option value=%S%s  %s\n" option.value
        (if option.selected then " selected" else "")
        option.label)
    control.options

let print_forms ~json forms =
  if json then print_json (`List (List.map public_form_to_yojson forms))
  else
    List.iteri
      (fun index (form : form) ->
        Printf.printf "[%d] %s %s (%s)\n" (index + 1)
          (form.method_ |> form_method_to_string |> String.uppercase_ascii)
          form.action
          (form_enctype_to_string form.enctype);
        List.iter print_control form.controls)
      forms

(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Css_census.mli *)

let read (path : string) : string = In_channel.with_open_bin path In_channel.input_all

let counted (table : (string, int) Hashtbl.t) (k : string) : unit = Hashtbl.replace table k (1 + Option.value (Hashtbl.find_opt table k) ~default:0)

let sorted (table : (string, 'a) Hashtbl.t) (count : 'a -> int) : (string * 'a) list =
  Hashtbl.fold (fun k v acc -> (k, v) :: acc) table [] |> List.sort (fun (_, a) (_, b) -> compare (count b) (count a))

(* a selector the engine does not read: what in it is the likely cause *)
let cause (selector : string) : string =
  let has s = try ignore (Str.search_forward (Str.regexp_string s) selector 0); true with Not_found -> false in
  match List.find_opt has [ ":has("; ":host"; "::slotted"; "::part"; ":nth-"; ":dir("; ":lang("; ":focus-within"; ":target"; ":any-link"; "::-"; ":-"; "::"; "|"; "&" ] with
  | Some c -> c
  | None -> "other"

let rec all_rules (rules : Css_syntax.rule list) (visit : Css_syntax.rule -> unit) : unit =
  List.iter
    (fun (r : Css_syntax.rule) ->
      visit r;
      match r with At_rule { block = Some b; name; _ } when List.mem name [ "media"; "supports"; "layer"; "container" ] -> all_rules (Css_syntax.rules_of_block b) visit | _ -> ())
    rules

(* at=SELECTOR: the first elements it matches (three at most), each
 * with the declarations that win for it and the rule each comes from:
 * a developer tools' Styles pane, in a terminal *)
let explain (root : Dom.element) (parsed : Css_syntax.rule list list) ~(width : float) ~(height : float) (selectors : string list) : unit =
  let media : Cascade.media = { width; height } in
  let all = Computed.browser_sheets ~quirks:false @ List.map (fun rules : Cascade.sheet -> { origin = Author; rules }) parsed in
  List.iter
    (fun text ->
      match Selectors.parse_string text with
      | None -> Printf.printf "%s: a selector not read\n" text
      | Some complexes ->
          let found = ref [] in
          let rec visit (ancestors : Dom.element list) (e : Dom.element) =
            if List.length !found < 3 && List.exists (fun c -> Selectors.matches c ancestors e) complexes then found := (ancestors, e) :: !found;
            List.iter (fun (c : Dom.node) -> match c with Element c -> visit (e :: ancestors) c | Text _ -> ()) e.children
          in
          visit [] root;
          if !found = [] then Printf.printf "%s: no element\n" text;
          List.iter
            (fun ((ancestors : Dom.element list), (e : Dom.element)) ->
              Printf.printf "\n%s: <%s%s>  in  %s\n" text e.name
                (String.concat "" (List.map (fun (k, v) -> Printf.sprintf " %s=%S" k (if String.length v > 50 then String.sub v 0 50 ^ "..." else v)) e.attributes))
                (String.concat " < " (List.map (fun (a : Dom.element) -> a.name ^ match Dom.attribute "class" a with Some c -> "." ^ List.hd (String.split_on_char ' ' c) | None -> "") (List.filteri (fun i _ -> i < 6) ancestors)));
              (* what it comes to, up its ancestors: who is not shown *)
              let computed = Computed.styles media all root in
              List.iter
                (fun (a : Dom.element) ->
                  let c = computed a in
                  let rgba (k : Css_values.color) = Printf.sprintf "%d,%d,%d,%.2g" k.r k.g k.b k.a in
                  Printf.printf "  = %-10s %s%s%s color %s on %s, font %g\n" a.name
                    (match c.display with Display_none -> "NONE" | Block -> "block" | Inline -> "inline" | Flex -> "flex" | Inline_block -> "inline-block" | _ -> "other")
                    (if c.visible then "" else " HIDDEN")
                    (match c.position with Static -> "" | Relative -> " relative" | Absolute -> " absolute" | Fixed -> " fixed" | Sticky -> " sticky")
                    (rgba c.color) (rgba c.background) c.font_size)
                (e :: List.filteri (fun i _ -> i < 4) ancestors);
              List.iter
                (fun (name, value, (source : Cascade.source), important) ->
                  if Sys.getenv_opt "VARS" <> None || String.length name < 2 || String.sub name 0 2 <> "--" then
                    Printf.printf "  %-26s %-44s %s%s\n" name
                      (let v = String.trim (Css_syntax.to_string value) in if String.length v > 44 then String.sub v 0 41 ^ "..." else v)
                      (match source with Rule { sheet; selector } -> Printf.sprintf "[%d] %s" sheet (Selectors.to_string selector) | Hint -> "(attribute)" | Style_attribute -> "(style=)")
                      (if important then " !" else ""))
                (Cascade.explain media all root e))
            (List.rev !found))
    selectors

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let size, args = List.partition (fun a -> Str.string_match (Str.regexp "^[0-9]+x[0-9]+$") a 0) args in
  let width, height = match size with s :: _ -> Scanf.sscanf s "%fx%f" (fun w h -> (w, h)) | [] -> (1200., 800.) in
  match args with
  | [] -> prerr_endline "usage: Css_census.exe page.html sheet.css ... [WIDTHxHEIGHT]"
  | page :: sheets ->
      let asked, sheets = List.partition (fun a -> String.starts_with ~prefix:"at=" a) sheets in
      let root = Html_tree.of_string (read page) in
      let parsed = List.map (fun path -> Css_syntax.parse_stylesheet (read path)) sheets in
      if asked <> [] then explain root parsed ~width ~height (List.map (fun a -> String.sub a 3 (String.length a - 3)) asked) else
      (* the at-rules, and the selectors not read *)
      let at_rules = Hashtbl.create 16 and unread = Hashtbl.create 16 and examples = Hashtbl.create 16 and style_rules = ref 0 in
      List.iter
        (fun rules ->
          all_rules rules (fun r ->
              match r with
              | At_rule { name; _ } -> counted at_rules name
              | Style_rule { prelude; _ } ->
                  incr style_rules;
                  if Selectors.parse prelude = None then (
                    let text = String.trim (Css_syntax.to_string prelude) in
                    let c = cause text in
                    counted unread c;
                    if not (Hashtbl.mem examples c) then Hashtbl.replace examples c text)))
        parsed;
      Printf.printf "%d sheets, %d style rules\n\nat-rules:\n" (List.length sheets) !style_rules;
      List.iter
        (fun (name, n) -> Printf.printf "  %6d  @%s%s\n" n name (if List.mem name [ "media"; "supports"; "layer"; "charset" ] then "" else "   (skipped)"))
        (sorted at_rules Fun.id);
      Printf.printf "\nselectors not read (the rule dropped):\n%!";
      List.iter
        (fun (c, n) ->
          let e = Hashtbl.find examples c in
          Printf.printf "  %6d  %-14s %s\n" n c (if String.length e > 90 then String.sub e 0 90 ^ "..." else e))
        (sorted unread Fun.id);
      (* the page's elements: what each is given, and whether it counts *)
      let media : Cascade.media = { width; height } in
      let all = Computed.browser_sheets ~quirks:false @ List.map (fun rules : Cascade.sheet -> { origin = Author; rules }) parsed in
      let style decls = Computed.compute media ~root_font_size:16. ~parent:Computed.initial decls in
      (* the cascade made once for the tree (its rules indexed): a function of an element *)
      let cascaded = Cascade.cascade media all root in
      let given : (string, int * bool * string) Hashtbl.t = Hashtbl.create 64 in
      let elements = ref 0 in
      let rec visit (e : Dom.element) =
        incr elements;
        let decls = cascaded e in
        let whole = style decls in
        List.iter
          (fun (name, value) ->
            if String.length name < 2 || String.sub name 0 2 <> "--" then (
              let counts = style (List.filter (fun (n, _) -> n <> name) decls) <> whole in
              let n, any, sample = Option.value (Hashtbl.find_opt given name) ~default:(0, false, "") in
              Hashtbl.replace given name (n + 1, any || counts, if sample = "" then String.trim (Css_syntax.to_string value) else sample)))
          decls;
        List.iter (fun (c : Dom.node) -> match c with Element c -> visit c | Text _ -> ()) e.children
      in
      visit root;
      Printf.printf "\n%d elements; the properties given to some that change nothing for any (elements given it, a value):\n" !elements;
      List.iter
        (fun (name, (n, any, sample)) -> if not any then Printf.printf "  %6d  %-28s %s\n" n name (if String.length sample > 60 then String.sub sample 0 60 ^ "..." else sample))
        (sorted given (fun (n, _, _) -> n))

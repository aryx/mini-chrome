(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Page_bench.mli *)

let now = Unix.gettimeofday

(* [f ()], and its best time of [runs] said *)
let timed ?(runs = 1) (what : string) (f : unit -> 'a) : 'a =
  let once () =
    let t0 = now () in
    let r = f () in
    (r, (now () -. t0) *. 1000.)
  in
  let r, ms = once () in
  let ms = List.fold_left (fun ms _ -> Float.min ms (snd (once ()))) ms (List.init (runs - 1) Fun.id) in
  Printf.printf "%-50s %8.1f ms\n%!" what ms;
  r

let said fmt = Printf.printf ("    " ^^ fmt ^^ "\n%!")

let rec elements (e : Dom.element) : int =
  1 + List.fold_left (fun n (c : Dom.node) -> match c with Element c -> n + elements c | Text _ -> n) 0 e.children

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let url = match List.filter (fun a -> String.contains a ':') args with u :: _ -> u | [] -> "https://en.wikipedia.org/wiki/OCaml" in
  let width, height =
    match List.find_map (fun a -> try Scanf.sscanf a "%fx%f%!" (fun w h -> Some (w, h)) with _ -> None) args with
    | Some size -> size
    | None -> (1400., 713.)
  in
  if List.mem "opti=off" args then Mini_opti.enabled := false;
  Cap.main (fun caps ->
      let get u = match Http_client.get caps u with Ok r -> r.body | Error e -> failwith e in
      Printf.printf "%s, %.0f by %.0f%s\n\n" url width height (if !Mini_opti.enabled then "" else ", opti=off");
      let bytes = timed "network: the page (roots read, name resolved)" (fun () -> get url) in
      ignore (timed "network: the page again" (fun () -> get url));
      said "%d bytes" (String.length bytes);
      let sheets : (string * string) list ref = ref [] in
      let settings () : Browser_page.settings =
        { extensions = true; css = true; boxes = true; width; height; breaker = Html_layout.greedy; visited = (fun _ -> false);
          picture = (fun _ -> None); sheet = (fun u -> List.assoc_opt u !sheets) }
      in
      (* the stages before the styles *)
      let text = timed ~runs:3 "Charset: to UTF-8" (fun () -> Charset.to_utf_8 (Charset.detect ~content_type:"text/html" bytes) bytes) in
      let tokens = timed ~runs:3 "Html_lexer.tokenize" (fun () -> Html_lexer.tokenize text) in
      let tree = timed ~runs:3 "Html_tree.parse" (fun () -> Html_tree.parse tokens) in
      said "%d tokens, %d elements" (List.length tokens) (elements tree);
      (* the whole, as the browser does: first without the sheets, then
       * with them once they have come *)
      print_newline ();
      let p = timed "Browser_page.read, no sheet yet" (fun () -> Browser_page.read (settings ()) url 200 (Some "text/html") bytes) in
      said "the page %.0f high, %d things drawn" p.layout.height (List.length p.drawn);
      let rec fetch_sheets () =
        match Browser_page.sheets_wanted (settings ()) p with
        | [] -> ()
        | wanted ->
            List.iter
              (fun u ->
                let t = timed "network: a sheet" (fun () -> get u) in
                said "%d bytes" (String.length t);
                sheets := (u, t) :: !sheets)
              wanted;
            fetch_sheets ()
      in
      fetch_sheets ();
      let p = timed "Browser_page.laid_out, the sheets come" (fun () -> Browser_page.laid_out (settings ()) p) in
      said "the page %.0f high, %d things drawn" p.layout.height (List.length p.drawn);
      let p = timed ~runs:3 "Browser_page.laid_out again (styles memoized)" (fun () -> Browser_page.laid_out (settings ()) p) in
      (* what the view asks for: the window's lines, then (scrolled to
       * the end) all of them *)
      ignore (timed "Browser_draw.between: the first window's shapes" (fun () -> Browser_draw.between ~top:0. ~bottom:height p.drawn));
      ignore (timed "Browser_draw.between: the same again" (fun () -> Browser_draw.between ~top:0. ~bottom:height p.drawn));
      ignore (timed "Browser_draw.between: the whole page's" (fun () -> Browser_draw.between ~top:0. ~bottom:infinity p.drawn));
      (* the pieces of that relayout; the sheets parsed here as
       * Browser_page does (their order is not the page's: the same work) *)
      print_newline ();
      let media : Cascade.media = { width; height } in
      let parse what t = timed ~runs:3 (Printf.sprintf "Css_syntax.parse_stylesheet, %s" what) (fun () -> Css_syntax.parse_stylesheet t) in
      let author = List.rev_map (fun (_, t) -> { Cascade.origin = Author; rules = parse (Printf.sprintf "%d KB" (String.length t / 1024)) t }) !sheets in
      let inline = List.map (fun e -> { Cascade.origin = Cascade.Author; rules = Css_syntax.parse_stylesheet (Dom.text_content e) }) (Dom.find_all "style" p.tree) in
      let styles =
        timed ~runs:3 "Computed.styles (cascade + computed)" (fun () ->
            let styles = Computed.styles media (author @ inline) p.tree in
            ignore (styles p.tree);
            styles)
      in
      let boxes = timed ~runs:3 "Box_layout.layout" (fun () -> Box_layout.layout Browser_text.metrics ~viewport:(width, height) styles p.tree) in
      ignore (timed ~runs:3 "Box_tree.as_html_layout" (fun () -> Box_tree.as_html_layout boxes));
      ignore (timed ~runs:3 "Browser_boxes.draw (the page's shapes)" (fun () -> Browser_boxes.draw ~visited:(fun _ -> false) ~picture_of:(fun _ -> None) boxes)))

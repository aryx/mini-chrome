(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_survey.mli *)

let read (file : string) : string = In_channel.with_open_bin file In_channel.input_all

(* the source's line [n] (from 1), cut to a screen's width *)
let line_of (source : string) (n : int) : string =
  match List.nth_opt (String.split_on_char '\n' source) (n - 1) with
  | Some l -> if String.length l > 110 then String.sub l 0 110 ^ " ..." else l
  | None -> ""

(* a message without what is the script's own in it (a name, a
 * number), so that the same mistake of two scripts counts as one *)
let kind (message : string) : string =
  let b = Buffer.create 64 in
  let quoted = ref false in
  String.iter
    (fun c ->
      if c = '"' || c = '\'' then (
        if not !quoted then Buffer.add_string b "\"..\"";
        quoted := not !quoted)
      else if not !quoted then Buffer.add_char b c)
    message;
  Buffer.contents b

(* a library used, not only loaded: for a file whose name starts so, a
 * page, a script run in it after the library, and what the script's
 * last expression must be *)
let uses : (string * string * string * string) list =
  [ ("jquery",
     "<ul id=l><li class=a>one</li><li>two</li></ul><p id=out></p>",
     {|var clicks = 0; $('#out').on('click', function () { clicks++ });
       $('#out').text('hi').addClass('x').trigger('click');
       $('<li>three</li>').appendTo('#l');
       [$('#l li').length, $('li.a').text(), $('#out').attr('class'), $('#out').text(), clicks, $('li:last').text(), $('li').filter(':contains(tw)').index()].join(' ')|},
     "3 one x hi 1 three 1");
    ("underscore", "", {|[_.map([1, 2, 3], function (x) { return x * 2 }), _.uniq([1, 1, 2]).length, _.template('<%= n %>!')({ n: 5 })].join(' ')|}, "2,4,6 2 5!");
    ("preact", "", {|preact.render(preact.h('p', { id: 'x' }, 'hi ', preact.h('b', null, 'there')), document.body); document.body.innerHTML|}, {|<p id="x">hi <b>there</b></p>|});
    ("react", "", {|var e = React.createElement('p', { id: 'x' }, 'hi'); [e.type, e.props.id, e.props.children, React.Children.count([e, e])].join(' ')|}, "p x hi 2");
    ("mithril", "", {|m.render(document.body, m('ul.list', [m('li', 'one'), m('li', { class: 'b' }, 'two')])); document.body.innerHTML|}, {|<ul class="list"><li>one</li><li class="b">two</li></ul>|});
    ("vue", "<div id=app></div>",
     {|Vue.createApp({ data: function () { return { n: 1, items: ['a', 'b'] } }, template: '<p>{{ n + 1 }}</p><ul><li v-for="i in items">{{ i }}</li></ul>' }).mount('#app');
       document.getElementById('app').innerHTML|},
     "<p>2</p><ul><li>a</li><li>b</li></ul>");
    ("alpine", {|<div x-data="{ n: 1 }"><span id=s x-text="n + 1"></span></div>|}, {|Alpine.start(); document.getElementById('s').textContent|}, "2");
    ("htmx", "<button id=b hx-get=/x>go</button>", {|htmx.addClass(htmx.find('#b'), 'on'); htmx.process(document.body); [htmx.find('#b').className, htmx.findAll('button').length, typeof htmx.ajax].join(' ')|}, "on 1 function") ]

let () =
  let files = List.tl (Array.to_list Sys.argv) in
  let counts : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let count k = Hashtbl.replace counts k (1 + Option.value (Hashtbl.find_opt counts k) ~default:0) in
  let console_errors t = List.filter (fun l -> String.length l > 5 && (String.sub l 0 5 = "Uncau" || String.sub l 0 4 = "Type" || String.sub l 0 4 = "Refe")) (Browser_script.console t) in
  List.iter
    (fun file ->
      let source = read file in
      let name = Filename.basename file in
      Printf.printf "%-24s %9d bytes  " name (String.length source);
      let use = List.find_opt (fun (prefix, _, _, _) -> String.starts_with ~prefix name) uses in
      let body = match use with Some (_, body, _, _) -> body | None -> "" in
      match Js_parse.parse source with
      | Error (e : Js_parse.error) ->
          Printf.printf "PARSE line %d: %s\n      | %s\n" e.line e.message (String.trim (line_of source e.line));
          count ("parse: " ^ kind e.message)
      | Ok _ -> (
          let page = Html_tree.of_string ("<!doctype html><html><head><title>survey</title></head><body>" ^ body ^ "</body></html>") in
          let t = Browser_script.create ~base:"http://survey.test/" page in
          match Browser_script.eval t source with
          | Error (e : Js_eval.error) ->
              Printf.printf "RUN  line %d: %s\n      | %s\n" e.line e.message (String.trim (line_of source e.line));
              count ("run: " ^ kind e.message)
          | Ok _ -> (
              (* what it said on the console, its errors (uncaught in a callback) *)
              match (console_errors t, use) with
              | (_ :: _ as errors), _ -> Printf.printf "RUN  (on the console) %s\n" (List.hd (List.rev errors)); count ("run: " ^ kind (List.hd (List.rev errors)))
              | [], None -> Printf.printf "ok\n"; count "ok"
              | [], Some (_, _, script, expected) -> (
                  let r = Browser_script.eval t script in
                  (* its timers too: a library may do its work a moment later *)
                  Browser_script.advance t 100.;
                  let r = match r with Ok _ when String.starts_with ~prefix:"alpine" name -> Browser_script.eval t "document.getElementById('s').textContent" | r -> r in
                  match (r, console_errors t) with
                  | Ok v, [] when Js_value.to_string v = expected -> Printf.printf "ok, and used: works\n"; count "ok, and works"
                  | Ok v, [] -> Printf.printf "USE  gave %s\n      | for %s\n" (Js_value.display v) expected; count "use: another answer"
                  | Ok _, errors -> Printf.printf "USE  (on the console) %s\n" (List.hd (List.rev errors)); count ("use: " ^ kind (List.hd (List.rev errors)))
                  | Error (e : Js_eval.error), _ -> Printf.printf "USE  line %d of the test: %s\n" e.line e.message; count ("use: " ^ kind e.message)))))
    files;
  print_newline ();
  List.iter (fun (k, n) -> Printf.printf "%3d  %s\n" n k) (List.sort (fun (_, a) (_, b) -> compare b a) (Hashtbl.fold (fun k n l -> (k, n) :: l) counts []))

(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_tab.mli *)

type state = Loading of string | Shown of Browser_page.t
type view = Page | Source
type entry = { at : string; kept : (Browser_page.t * Browser_script.t option) option; scrolled_to : int; document : Pdf_viewer.t option }

type kind = Document | Sheet | Script | Picture | Media | Fetch
type request = { url : string; kind : kind; status : int option; bytes : int }

type t = {
  state : state;
  view : view;
  scroll : int;
  history : entry Browser_history.t;
  visited : string list;
  fragment : string option;
  pictures : (string * Browser_picture.t) list;
  pdf : Pdf_viewer.t option; (* the page shown is a PDF file's: its pages are pictures drawn as they come into view *)
  sheets : (string * string) list;
  sheet_urls : string list;
  queue : string list;
  in_flight : string list;
  total : int;
  images : bool;
  focus : Dom.element option;
  script : Browser_script.t option;
  requests : request list;
  sources : (string * string) list; (* the texts of the pages' scripts of their own file, by URL: a cache *)
  pending_scripts : string list; (* the page's still to come: its scripts run once they have *)
  media : (string * string) list; (* the bytes of <video>s' and <audio>s' files, by URL: a cache *)
  media_urls : string list; (* the URLs asked for as media *)
}

type 'msg config = {
  settings : t -> Browser_page.settings;
  about : string -> (string * string) option;
  got : string -> (Fetch.response, Fetch.error) result -> 'msg;
  got_picture : string -> (Fetch.response, Fetch.error) result -> 'msg;
  (* the answer to a script's request, by its number and its URL *)
  got_answer : int -> string -> (Fetch.response, Fetch.error) result -> 'msg;
  socket : Script_types.socket_ask -> 'msg;
  fetch : 'msg Fetch.request -> 'msg;
  connections : int;
  visible : int;
  line_height : float;
  scripts : string -> bool;
  cookies : Cookie_jar.t;
  seed : int;
}

let empty ~(images : bool) : t =
  {
    state = Loading "";
    view = Page;
    scroll = 0;
    history = Browser_history.empty;
    visited = [];
    fragment = None;
    pictures = [];
    pdf = None;
    sheets = [];
    sheet_urls = [];
    queue = [];
    in_flight = [];
    total = 0;
    images;
    focus = None;
    script = None;
    requests = [];
    sources = [];
    pending_scripts = [];
    media = [];
    media_urls = [];
  }

(* a request logged (the network panel's): replacing the one for the
 * same URL, the newest first *)
let logged ?status ?(bytes = 0) (kind : kind) (url : string) (tab : t) : t =
  { tab with requests = { url; kind; status; bytes } :: List.filter (fun (r : request) -> r.url <> url) tab.requests }

let kind_of (tab : t) (url : string) : kind =
  if List.mem url tab.sheet_urls then Sheet
  else if List.mem url tab.pending_scripts then Script
  else if List.mem url tab.media_urls then Media
  else Picture

(* a media file had (or not: empty), kept for the browser's player *)
let with_media (tab : t) (url : string) (bytes : string) : t = { tab with media = (url, bytes) :: List.remove_assoc url tab.media }

(* the files of a page's <video>s and <audio>s: their src=, else their
 * first <source src=> *)
let media_sources (p : Browser_page.t) : string list =
  Dom.find_all "video" p.tree @ Dom.find_all "audio" p.tree
  |> List.filter_map (fun (e : Dom.element) ->
         match Dom.attribute "src" e with
         | Some s -> Some s
         | None -> List.find_map (fun (c : Dom.element) -> Dom.attribute "src" c) (Dom.find_all "source" e))
  |> List.map (Browser_url.resolve p.url)

let current_url (tab : t) : string = match tab.state with Loading url -> url | Shown p -> p.url
let starts_with = Browser_url.starts_with

(*****************************************************************************)
(* Scrolling *)
(*****************************************************************************)

let line_count (cfg : 'msg config) (tab : t) : int =
  match (tab.state, tab.view) with
  | Shown p, Page ->
      let lines = int_of_float (Float.ceil (p.layout.height /. cfg.line_height)) in
      (* a page that fits the window (a body of min-height: 100vh
       * is exactly as high) does not scroll: [cfg.visible] is the whole
       * lines shown, one less than the page's when a part of a line is *)
      if p.layout.height <= (cfg.settings tab).height +. 0.5 then min lines cfg.visible else lines
  | Shown p, Source -> List.length p.lines
  | _ -> 0

(* a PDF file's pages: those in view, and a window's height before
 * and after, are drawn (a fraction of a second each) and kept; the
 * others' pictures are let go, a page's being megabytes *)
let pdf_pages (cfg : 'msg config) (tab : t) : t =
  match (tab.pdf, tab.state) with
  | Some v, Shown p ->
      let s = cfg.settings tab in
      let top = float_of_int tab.scroll *. cfg.line_height in
      let wanted =
        List.filter_map
          (fun (f : Html_layout.fragment) ->
            match f.picture with
            | Some pic -> ( match Pdf_viewer.page_of_src pic.src with Some n when f.baseline >= top -. s.height && f.baseline -. pic.height <= top +. (2. *. s.height) -> Some n | _ -> None)
            | None -> None)
          (Html_layout.fragments p.layout)
      in
      let kept = List.filter (fun (url, _) -> match Pdf_viewer.page_of_src url with Some n -> List.mem n wanted | None -> true) tab.pictures in
      let missing = List.filter (fun n -> not (List.mem_assoc (Pdf_viewer.src n) kept)) wanted in
      if missing = [] && List.length kept = List.length tab.pictures then tab
      else
        let tab = { tab with pictures = List.map (fun n -> (Pdf_viewer.src n, Browser_picture.Arrived (Pdf_viewer.picture v n))) missing @ kept } in
        { tab with state = Shown (Browser_page.laid_out (cfg.settings tab) p) }
  | _ -> tab

let scrolled (cfg : 'msg config) (by : int) (tab : t) : t =
  pdf_pages cfg { tab with scroll = max 0 (min (line_count cfg tab - cfg.visible) (tab.scroll + by)) }

let to_fragment (cfg : 'msg config) (tab : t) : t =
  match (tab.state, tab.fragment) with
  | Shown p, Some name -> (
      let tab = { tab with fragment = None } in
      match Hit.anchor p.layout name with
      | Some y -> scrolled cfg 0 { tab with scroll = int_of_float (y /. cfg.line_height) }
      | None -> pdf_pages cfg tab)
  | _ -> pdf_pages cfg tab

(*****************************************************************************)
(* A page shown *)
(*****************************************************************************)

let relaid (cfg : 'msg config) (tab : t) : t =
  match tab.state with Shown p -> { tab with state = Shown (Browser_page.laid_out (cfg.settings tab) p) } | Loading _ -> tab

(* a page just read: its scripts run first, if the browser has them,
 * and the page laid out from the tree they leave *)
(* the page's scripts run, all of them had: the page laid out from the
 * tree they leave *)
let run_page_scripts (cfg : 'msg config) (tab : t) : t =
  match (tab.state, tab.script) with
  | Shown p, Some s ->
      Browser_script.run_scripts ~source:(fun u -> List.assoc_opt u tab.sources) s;
      { tab with state = Shown (Browser_page.with_tree (cfg.settings tab) p (Browser_script.tree s)) }
  | _ -> tab

let arrive (cfg : 'msg config) (tab : t) (url : string) (status : int) (content_type : string option) (bytes : string) : t =
  (* a PDF file, whatever its type is said to be: shown as a page of
   * ours, a picture a page (Pdf_viewer) *)
  let pdf, content_type, bytes =
    if not (Pdf_viewer.sniff bytes) then (None, content_type, bytes)
    else
      let name = Filename.basename (fst (Browser_url.split_fragment url)) in
      match Pdf_viewer.open_ bytes with
      | Ok v -> (Some v, Some "text/html", Pdf_viewer.html v ~name)
      | Error why -> (None, Some "text/html", Printf.sprintf "<title>%s</title><h1>%s</h1><p>A PDF file that could not be shown: %s." name name (Browser_text.escape_html why))
  in
  (* the settings of the page that came, not of the one asked for
   * (a redirect to another host, whose zoom is its own) *)
  let tab = { tab with state = Loading url; pdf; pictures = List.filter (fun (u, _) -> Pdf_viewer.page_of_src u = None) tab.pictures } in
  let p = Browser_page.read (cfg.settings tab) url status content_type bytes in
  if not (cfg.scripts url) then { tab with state = Shown p; script = None; pending_scripts = [] }
  else
    (* document.cookie: the jar's for the page's address (a page
     * of the built-in site has none: no host) *)
    let cookies =
      match Url.parse p.url with
      | Ok url -> ((fun () -> Cookie_jar.script_cookies cfg.cookies url), fun v -> Cookie_jar.set_from_script cfg.cookies url v)
      | Error _ -> ((fun () -> ""), fun _ -> ())
    in
    (* with -v, what the page's scripts say on their console
     * (their errors too) is said on the terminal *)
    let log line = Logs.info (fun m -> m "console: %s" line) in
    let s = Browser_script.create ~log ~seed:cfg.seed ~base:p.url ~viewport:((cfg.settings tab).width, (cfg.settings tab).height) ~cookies p.tree in
    (* its scripts of their own file fetched first (the queue's), then
     * all run in order; the page shown meanwhile, as it came *)
    let missing = List.filter (fun u -> not (List.mem_assoc u tab.sources)) (Browser_script.script_sources s) in
    let tab = { tab with state = Shown p; script = Some s; pending_scripts = missing } in
    if missing = [] then run_page_scripts cfg tab else tab

(* a script's text had (or not: then nothing): the page's scripts run
 * when it was the last *)
let with_script (cfg : 'msg config) (tab : t) (url : string) (text : string) : t =
  let tab = { tab with sources = (url, text) :: List.remove_assoc url tab.sources; pending_scripts = List.filter (( <> ) url) tab.pending_scripts } in
  if tab.pending_scripts = [] then run_page_scripts cfg tab else tab

let failed (cfg : 'msg config) (tab : t) (url : string) (why : string) : t = arrive cfg tab url 0 None (Browser_page.error_html url why)

(*****************************************************************************)
(* Pictures, four at a time; style sheets first *)
(*****************************************************************************)

(* a picture had (or not): the page laid out again with it *)
let with_arrived (cfg : 'msg config) (tab : t) (url : string) (pic : Browser_picture.t) : t =
  relaid cfg { tab with pictures = (url, pic) :: List.remove_assoc url tab.pictures }

(* a style sheet had (or not: then empty): the page laid out again with
 * it -- its colours, its boxes, as a picture moves the text *)
let with_sheet (cfg : 'msg config) (tab : t) (url : string) (text : string) : t =
  let tab = relaid cfg { tab with sheets = (url, text) :: List.remove_assoc url tab.sheets } in
  (* its @imports, first in the queue; the backgrounds' pictures it
   * gave the boxes, last *)
  match tab.state with
  | Shown p ->
      let fresh u = not (List.mem u tab.queue || List.mem u tab.in_flight || List.mem_assoc u tab.pictures) in
      let more = List.filter fresh (Browser_page.sheets_wanted (cfg.settings tab) p) in
      let pictures = if tab.images then List.filter fresh p.backgrounds else [] in
      { tab with queue = more @ tab.queue @ pictures; sheet_urls = more @ tab.sheet_urls; total = tab.total + List.length more + List.length pictures }
  | Loading _ -> tab

(* more pictures on their way, while fewer than [connections] are:
 * Netscape's way, where Mosaic had one; a built-in one decoded at once *)
let rec fetch_more (cfg : 'msg config) (network : < Cap.network ; .. >) ((tab, cmd) : t * 'msg Cmd.t) : t * 'msg Cmd.t =
  match tab.queue with
  | url :: rest when List.length tab.in_flight < cfg.connections ->
      let tab = { tab with queue = rest } in
      (match Browser_url.data_url url with
      | Some bytes ->
          (* a data: URL: its bytes are in it *)
          let tab = logged ~status:200 ~bytes:(String.length bytes) (kind_of tab url) url tab in
          if List.mem url tab.pending_scripts then fetch_more cfg network (with_script cfg tab url bytes, cmd)
          else if List.mem url tab.media_urls then fetch_more cfg network (with_media tab url bytes, cmd)
          else if List.mem url tab.sheet_urls then fetch_more cfg network (with_sheet cfg tab url bytes, cmd)
          else fetch_more cfg network (with_arrived cfg tab url (Browser_picture.decode bytes), cmd)
      | None ->
      if starts_with "about:" url && List.mem url tab.media_urls then
        let bytes = match cfg.about (String.sub url 6 (String.length url - 6)) with Some (b, _) -> b | None -> "" in
        let tab = logged ~status:(if bytes = "" then 404 else 200) ~bytes:(String.length bytes) Media url tab in
        fetch_more cfg network (with_media tab url bytes, cmd)
      else if starts_with "about:" url && List.mem url tab.pending_scripts then
        let text = match cfg.about (String.sub url 6 (String.length url - 6)) with Some (bytes, _) -> bytes | None -> "" in
        let tab = logged ~status:(if text = "" then 404 else 200) ~bytes:(String.length text) Script url tab in
        (* the GETs its scripts queue go with the next task's *)
        fetch_more cfg network (with_script cfg tab url text, cmd)
      else if starts_with "about:" url && List.mem url tab.sheet_urls then
        let text = match cfg.about (String.sub url 6 (String.length url - 6)) with Some (bytes, _) -> bytes | None -> "" in
        let tab = logged ~status:(if text = "" then 404 else 200) ~bytes:(String.length text) Sheet url tab in
        fetch_more cfg network (with_sheet cfg tab url text, cmd)
      else if starts_with "about:" url then
        let pic =
          match cfg.about (String.sub url 6 (String.length url - 6)) with
          | Some (bytes, _) -> Browser_picture.decode bytes
          | None -> Browser_picture.Broken
        in
        let bytes = match cfg.about (String.sub url 6 (String.length url - 6)) with Some (b, _) -> String.length b | None -> 0 in
        let tab = logged ~status:(if pic = Browser_picture.Broken then 404 else 200) ~bytes Picture url tab in
        fetch_more cfg network (with_arrived cfg tab url pic, cmd)
      else
        let get = Cmd.Msg (cfg.fetch (Fetch.get network url (cfg.got_picture url))) in
        fetch_more cfg network (logged (kind_of tab url) url { tab with in_flight = url :: tab.in_flight }, Cmd.batch [ cmd; get ]))
  | _ -> (tab, cmd)

(* a page shown: its style sheets not had yet queued (by the box
 * model: Browser_page.sheets_wanted), then its pictures (if Auto Load
 * Images), the ones of the page before dropped *)
let with_pictures (cfg : 'msg config) (network : < Cap.network ; .. >) ((tab, cmd) : t * 'msg Cmd.t) : t * 'msg Cmd.t =
  match tab.state with
  | Loading _ -> (tab, cmd)
  | Shown p ->
      let had url = match List.assoc_opt url tab.pictures with Some (Arrived _ | Broken) -> true | _ -> false in
      let fresh = List.fold_left (fun acc u -> if List.mem u acc || List.mem u tab.in_flight then acc else acc @ [ u ]) [] in
      let sheets = fresh (Browser_page.sheets_wanted (cfg.settings tab) p) in
      let pictures =
        (Dom.find_all "img" p.tree |> List.filter_map (fun e -> Option.map (Browser_url.resolve p.url) (Box_tree.picture_src e)))
        @ p.backgrounds
        |> List.filter (fun u -> not (had u) && Pdf_viewer.page_of_src u = None)
        |> fresh
      in
      let pictures = if tab.images then pictures else [] in
      (* the scripts' files between: the page's style first, its
       * pictures last *)
      let scripts = fresh (List.filter (fun u -> not (List.mem u sheets)) tab.pending_scripts) in
      (* the players' files last: the page is whole before *)
      let media = fresh (List.filter (fun u -> not (List.mem_assoc u tab.media)) (media_sources p)) in
      let urls = sheets @ scripts @ pictures @ media in
      fetch_more cfg network
        ({ tab with queue = urls; sheet_urls = sheets @ tab.sheet_urls; media_urls = media @ tab.media_urls; total = List.length urls + List.length tab.in_flight }, cmd)

let load_images cfg network tab = with_pictures cfg network ({ tab with images = true }, Cmd.none)

(*****************************************************************************)
(* Going places *)
(*****************************************************************************)

let load ?post (cfg : 'msg config) (network : < Cap.network ; .. >) (url : string) (tab : t) : t * 'msg Cmd.t =
  (* a new page: a new network log *)
  let tab = { tab with scroll = 0; focus = None; queue = []; total = 0; requests = [] } in
  if starts_with "about:" url then
    (* with -v; the web's pages are said by Fetch *)
    let () = Logs.info (fun m -> m "built-in page %s" url) in
    let name, query = Browser_url.split_query (String.sub url 6 (String.length url - 6)) in
    let show bytes content_type =
      let tab = logged ~status:200 ~bytes:(String.length bytes) Document url tab in
      with_pictures cfg network (to_fragment cfg (arrive cfg tab url 200 (Some content_type) bytes), Cmd.none) in
    match (name, post) with
    | "echo", Some (_, body) -> show (Browser_page.echo_html "POST" body) "text/html; charset=utf-8"
    | "echo", None -> show (Browser_page.echo_html "GET" (Option.value query ~default:"")) "text/html; charset=utf-8"
    | _ -> (
        match cfg.about name with
        | Some (bytes, content_type) -> show bytes content_type
        | None -> (failed cfg tab url "There is no such page in the built-in site.", Cmd.none))
  else
    let tab = logged Document url { tab with state = Loading url } in
    match post with
    | None -> (tab, Cmd.Msg (cfg.fetch (Fetch.get network url (cfg.got url))))
    | Some (content_type, body) -> (tab, Cmd.Msg (cfg.fetch (Fetch.post network url ~content_type ~body (cfg.got url))))

let entry_of (tab : t) : entry =
  match tab.state with
  | Shown p -> { at = p.url; kept = Some (p, tab.script); scrolled_to = tab.scroll; document = tab.pdf }
  | Loading url -> { at = url; kept = None; scrolled_to = 0; document = None }

let visit ?post (cfg : 'msg config) (network : < Cap.network ; .. >) (url : string) (tab : t) : t * 'msg Cmd.t =
  let target, fragment = Browser_url.split_fragment url in
  let tab =
    {
      tab with
      history = Browser_history.visit (entry_of tab) tab.history;
      visited = (if List.mem target tab.visited then tab.visited else target :: tab.visited);
      fragment;
    }
  in
  match tab.state with
  | Shown p when post = None && fragment <> None && target = fst (Browser_url.split_fragment p.url) ->
      (to_fragment cfg (relaid cfg tab), Cmd.none)
  | _ -> load ?post cfg network target tab

(* what a task of the page's scripts leaves for the browser to do: the
 * requests they queued (XMLHttpRequest, fetch) sent and logged, each
 * one's answer to come back by its number ([got_answer]); and the page
 * left for another, if a script said so (location.href = url) *)
let send_requests (cfg : 'msg config) (network : < Cap.network ; .. >) ((tab, cmd) : t * 'msg Cmd.t) : t * 'msg Cmd.t =
  match tab.script with
  | Some s -> (
      let navigation = Browser_script.take_navigation s in
      let tab, cmd =
      match Browser_script.take_requests s with
      | [] -> (tab, cmd)
      | requests ->
          let tab = List.fold_left (fun tab (r : Script_types.request) -> logged ~status:0 Fetch r.url tab) tab requests in
          let send (r : Script_types.request) =
            let k = cfg.got_answer r.rid r.url in
            Cmd.Msg (cfg.fetch (match r.post with Some (content_type, body) -> Fetch.post network r.url ~content_type ~body k | None -> Fetch.get network r.url k))
          in
          (tab, Cmd.batch (cmd :: List.map send requests))
      in
      (* its WebSockets' asks, handed to the program as they are *)
      let cmd = match Browser_script.take_socket_asks s with [] -> cmd | asks -> Cmd.batch (cmd :: List.map (fun a -> Cmd.Msg (cfg.socket a)) asks) in
      match navigation with
      | Some (url, replace) ->
          Logs.info (fun m -> m "a script goes to %s" url);
          let tab, go = if replace then load cfg network url tab else visit cfg network url tab in
          (tab, Cmd.batch [ cmd; go ])
      | None -> (tab, cmd))
  | None -> (tab, cmd)

let restore (cfg : 'msg config) (network : < Cap.network ; .. >) (e : entry) (tab : t) : t * 'msg Cmd.t =
  match e.kept with
  | Some (p, script) ->
      with_pictures cfg network (scrolled cfg 0 { (relaid cfg { tab with state = Shown p; script; pdf = e.document }) with scroll = e.scrolled_to }, Cmd.none)
  | None -> load cfg network e.at tab

let back cfg network tab =
  match Browser_history.back (entry_of tab) tab.history with
  | Some (e, history) -> restore cfg network e { tab with history }
  | None -> (tab, Cmd.none)

let forward cfg network tab =
  match Browser_history.forward (entry_of tab) tab.history with
  | Some (e, history) -> restore cfg network e { tab with history }
  | None -> (tab, Cmd.none)

let stop (cfg : 'msg config) (tab : t) : t =
  let tab =
    match tab.state with
    | Loading url -> failed cfg tab url "Stopped."
    | Shown _ -> tab
  in
  { tab with queue = []; in_flight = []; total = 0 }

(* the page's <meta http-equiv=refresh content="N; url=X">, N a second
 * or less (a later one, a slide show's, is not followed); one inside a
 * <noscript> only when its scripts do not run *)
let refresh (cfg : 'msg config) (tab : t) : string option =
  match tab.state with
  | Loading _ -> None
  | Shown p ->
      let scripts = cfg.scripts p.url in
      let rec find (in_noscript : bool) (e : Dom.element) : string option =
        let in_noscript = in_noscript || e.name = "noscript" in
        let here =
          if e.name = "meta" && (not (in_noscript && scripts))
             && Option.map String.lowercase_ascii (Dom.attribute "http-equiv" e) = Some "refresh"
          then
            match Dom.attribute "content" e with
            | Some c -> (
                match String.index_opt c ';' with
                | Some i -> (
                    let delay = float_of_string_opt (String.trim (String.sub c 0 i)) in
                    let rest = String.trim (String.sub c (i + 1) (String.length c - i - 1)) in
                    let target =
                      if String.length rest > 4 && String.lowercase_ascii (String.sub rest 0 4) = "url=" then String.sub rest 4 (String.length rest - 4)
                      else rest
                    in
                    let target = String.trim target in
                    let target =
                      if String.length target >= 2 && (target.[0] = '\'' || target.[0] = '"') then String.sub target 1 (String.length target - 2) else target
                    in
                    match delay with Some d when d <= 1. && target <> "" -> Some (Browser_url.resolve p.url target) | _ -> None)
                | None -> None)
            | None -> None
          else None
        in
        match here with
        | Some _ -> here
        | None -> List.find_map (fun (n : Dom.node) -> match n with Element c -> find in_noscript c | Text _ -> None) e.children
      in
      find false p.tree

let got (cfg : 'msg config) (network : < Cap.network ; .. >) (url : string) (result : (Fetch.response, Fetch.error) result) (tab : t) :
    t * 'msg Cmd.t =
  match result with
  | Ok r -> (
      let content_type =
        List.find_map (fun (name, value) -> if String.lowercase_ascii name = "content-type" then Some value else None) r.headers
      in
      let tab = logged ~status:r.status ~bytes:(String.length r.body) Document url tab in
      let tab, cmd = send_requests cfg network (with_pictures cfg network (to_fragment cfg (arrive cfg tab r.url r.status content_type r.body), Cmd.none)) in
      (* a <meta http-equiv=refresh content="0;url=...">: gone to at
       * once, in the page's place (DuckDuckGo's links, sites moved) *)
      match refresh cfg tab with
      | Some target when target <> r.url && target <> url -> load cfg network target tab
      | _ -> (tab, cmd))
  | Error e -> (failed cfg (logged ~status:0 Document url tab) url (String.capitalize_ascii (Fetch.error_to_string e) ^ "."), Cmd.none)

let got_picture (cfg : 'msg config) (network : < Cap.network ; .. >) (url : string) (result : (Fetch.response, Fetch.error) result)
    (tab : t) : t * 'msg Cmd.t =
  if not (List.mem url tab.in_flight) then (* one Stop said not to wait for, or a script's GET *) (tab, Cmd.none)
  else if List.mem url tab.pending_scripts then
    (* a script's file: the page's scripts run when it is the last *)
    let text = match result with Ok r when r.status / 100 = 2 -> r.body | _ -> "" in
    let status = match result with Ok r -> r.status | Error _ -> 0 in
    let tab = logged ~status ~bytes:(String.length text) Script url tab in
    let tab = with_script cfg { tab with in_flight = List.filter (( <> ) url) tab.in_flight } url text in
    send_requests cfg network (fetch_more cfg network (tab, Cmd.none))
  else if List.mem url tab.media_urls then
    let bytes = match result with Ok r when r.status / 100 = 2 -> r.body | _ -> "" in
    let tab = match result with Ok r -> logged ~status:r.status ~bytes:(String.length r.body) Media url tab | Error _ -> logged ~status:0 Media url tab in
    fetch_more cfg network (with_media { tab with in_flight = List.filter (( <> ) url) tab.in_flight } url bytes, Cmd.none)
  else if List.mem url tab.sheet_urls then
    (* a style sheet: laid out with it, its @imports queued *)
    let text = match result with Ok r when r.status / 100 = 2 -> r.body | _ -> "" in
    let status = match result with Ok r -> r.status | Error _ -> 0 in
    let tab = logged ~status ~bytes:(String.length text) Sheet url tab in
    fetch_more cfg network (with_sheet cfg { tab with in_flight = List.filter (( <> ) url) tab.in_flight } url text, Cmd.none)
  else
    let pic = match result with Ok r when r.status / 100 = 2 -> Browser_picture.decode r.body | _ -> Browser_picture.Broken in
    let tab = match result with Ok r -> logged ~status:r.status ~bytes:(String.length r.body) Picture url tab | Error _ -> logged ~status:0 Picture url tab in
    fetch_more cfg network (with_arrived cfg { tab with in_flight = List.filter (( <> ) url) tab.in_flight } url pic, Cmd.none)

(*****************************************************************************)
(* Forms, and the scripts' tasks *)
(*****************************************************************************)

(* where an element is in its tree: the indexes of the elements down to
 * it -- how the field in focus is found again in a tree a script froze
 * anew *)
let rec path_to (root : Dom.element) (e : Dom.element) : int list option =
  if root == e then Some []
  else
    let children = List.filter_map (fun (n : Dom.node) -> match n with Element c -> Some c | Text _ -> None) root.children in
    List.find_map (fun (i, c) -> Option.map (fun p -> i :: p) (path_to c e)) (List.mapi (fun i c -> (i, c)) children)

let rec at_path (root : Dom.element) (path : int list) : Dom.element option =
  match path with
  | [] -> Some root
  | i :: rest -> (
      let children = List.filter_map (fun (n : Dom.node) -> match n with Element c -> Some c | Text _ -> None) root.children in
      match List.nth_opt children i with Some c -> at_path c rest | None -> None)

let after_task (cfg : 'msg config) (network : < Cap.network ; .. >) (tab : t) : t * 'msg Cmd.t =
  send_requests cfg network
    (match (tab.state, tab.script) with
    | Shown p, Some s when Browser_script.changed s ->
        let tree = Browser_script.tree s in
        let focus = Option.bind tab.focus (fun e -> Option.bind (path_to p.tree e) (at_path tree)) in
        with_pictures cfg network ({ tab with state = Shown (Browser_page.with_tree (cfg.settings tab) p tree); focus }, Cmd.none)
    | _ -> (tab, Cmd.none))

(* the answer to a request a script made (XMLHttpRequest,
 * fetch): given to the script, a task -- the page laid out again if it
 * changed it, the requests it made in turn sent *)
let got_answer (cfg : 'msg config) (network : < Cap.network ; .. >) (rid : int) (url : string) (result : (Fetch.response, Fetch.error) result) (tab : t) :
    t * 'msg Cmd.t =
  match tab.script with
  | None -> (tab, Cmd.none)
  | Some s ->
      let tab = match result with Ok r -> logged ~status:r.status ~bytes:(String.length r.body) Fetch url tab | Error _ -> logged ~status:0 Fetch url tab in
      Browser_script.answer s rid
        (match result with
        | Ok r -> Ok { Script_types.status = r.status; headers = r.headers; body = r.body; final = r.url }
        | Error e -> Error (Fetch.error_to_string e));
      after_task cfg network tab

(* what a script's WebSocket's connection said: given to the script, a
 * task. The script of another page (this one came after) does not
 * know the socket: closed, the page it was for being gone *)
let got_socket (cfg : 'msg config) (network : < Cap.network ; .. >) (id : int) (event : Websocket_client.event) (tab : t) : t * 'msg Cmd.t =
  let gone = match event with Closed _ -> Cmd.none | _ -> Cmd.Msg (cfg.socket (Socket_close (id, 1001, ""))) in
  match tab.script with
  | Some s when Browser_script.socket_event s id event -> after_task cfg network tab
  | _ -> (tab, gone)

(* a click in a <details>'s <summary> (Browser_details): opened, or
 * closed; the page laid out again. With scripts, in their copy of the
 * tree, the page's own after the next freeze *)
let details (cfg : 'msg config) (network : < Cap.network ; .. >) (clicked : Dom.element) (tab : t) : (t * 'msg Cmd.t) option =
  match tab.state with
  | Shown p -> (
      match (Browser_details.clicked p.tree clicked, tab.script) with
      | None, _ -> None
      | Some d, Some s ->
          Browser_script.set_attribute s d "open" (if Browser_details.is_open d then None else Some "");
          Some (after_task cfg network tab)
      | Some d, None ->
          Some (with_pictures cfg network ({ tab with state = Shown (Browser_page.with_tree (cfg.settings tab) p (Browser_details.toggled p.tree d)) }, Cmd.none)))
  | _ -> None

let form_effect (cfg : 'msg config) (network : < Cap.network ; .. >) ~(keep_focus : bool) (outcome : Browser_forms.outcome) (tab : t) :
    t * 'msg Cmd.t =
  match outcome with
  | Nothing -> (tab, Cmd.none)
  | Focus e -> ({ tab with focus = Some e }, Cmd.none)
  | Unfocus -> ({ tab with focus = None }, Cmd.none)
  | Changed p -> (
      let tab = { tab with state = Shown p; focus = (if keep_focus then tab.focus else None) } in
      (* the script told: the field's text in its value=, its input event *)
      match (tab.script, tab.focus) with
      | Some s, Some e ->
          Browser_script.input s e (Browser_page.value_of p e).text;
          after_task cfg network tab
      | _ -> (tab, Cmd.none))
  | Submit { url; post; page } -> visit ?post cfg network url { tab with state = Shown page; focus = None }

(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Window_update.mli *)
open Playground
open Window_model
open Window_layout (* the model read *)
open Window_tabs (* the model changed *)

let resolve = Browser_url.resolve

(* the first pages: url=X, and the words of the command line
 * that are not a flag's name -- an address or words to search, as
 * typed in the omnibox (the Playground cuts a word at its first =: put
 * back, for an address with a query) *)
let flag_names = [ "url"; "css"; "panel"; "search"; "scripts"; "threads"; "profile"; "scale"; "opti"; "letters"; "pdf"; "js"; "timings"; "cache" ]

let first_pages (engine : string) (flags : flags) : string list =
  let words = List.filter (fun (name, _) -> not (List.mem name flag_names)) flags in
  match Option.to_list (List.assoc_opt "url" flags) @ List.map (fun (name, value) -> Omnibox.destination engine (if value = "" then name else name ^ "=" ^ value)) words with
  | [] -> [ home ]
  | urls -> urls

let init (network : < Cap.network ; .. >) ?jar ?cache ((profile, profile_dir) : Browser_profile.t * string option) ~(desktop : float) ~(window : int * int) (flags : flags) : model * msg Cmd.t =
  let panel = match List.assoc_opt "panel" flags with Some "elements" -> Elements | Some "network" -> Network | _ -> Closed in
  let m =
    { tabs = []; current = 0; next_id = 0; omnibox = None; mouse = (1000., 1000.); time = 0.; busy = None;
      css = List.assoc_opt "css" flags <> Some "off"; panel; inspecting = false; selected = None;
      engine = Option.value (List.assoc_opt "search" flags) ~default:"wikipedia";
      allowed = (match List.assoc_opt "scripts" flags with Some "off" -> [] | Some "on" -> [ everywhere ] | Some hosts -> String.split_on_char ',' hosts | None -> default_allowed);
      (* threads on, as in TinyNetscape (N2): a name resolved, an
       * https:// page fetched, on threads of their own; threads=off,
       * the frame waits *)
      fetches = Fetch.create ~threads:(List.assoc_opt "threads" flags <> Some "off") ?jar ?cache ~agent:Browser_agent.for_host ();
      (* until the platform says (Resized, before the first frame) *)
      screen = (Playground.default_width, Playground.default_height); ctrl = false; profile; profile_dir; saved = profile; changed = 0.; menu = None; window; desktop; selecting = false; last_click = -1.; pressed = false; fresh = []; late = []; dots = 1.; shift = false; grab = None }
  in
  (* a tab a page, the first one shown *)
  let m, cmd =
    List.fold_left (fun (m, cmd) url -> let m, c = open_tab network url m in (m, Cmd.batch [ cmd; c ])) (m, Cmd.none) (first_pages m.engine flags)
  in
  let m = { m with current = 0 } in
  (* with the elements' view open, the page's <body> shown in it *)
  let selected = match (panel, (current_tab m).state) with Elements, Shown p -> List.nth_opt (Dom.find_all "body" p.tree) 0 | _ -> None in
  ({ m with selected }, cmd)

let edit_omnibox (network : < Cap.network ; .. >) (key : string) (field : Gui_field.t) (m : model) : model * msg Cmd.t =
  match Omnibox.key ~ctrl:m.ctrl ~shift:m.shift key field with
  | Edit field -> ({ m with omnibox = Some field }, Cmd.none)
  | Go typed -> visit network (Omnibox.destination m.engine typed) m
  | Leave -> ({ m with omnibox = None }, Cmd.none)
  | Nothing -> (m, Cmd.none)

(* a task of the page's scripts done by [f], then the page laid out
 * again if its tree changed (Browser_tab.after_task) *)
let task (network : < Cap.network ; .. >) (m : model) (f : Browser_script.t -> bool) : model * msg Cmd.t * bool =
  match (current_tab m).script with
  | Some s ->
      let r = f s in
      let m, cmd = on_current m (fun cfg tab -> Browser_tab.after_task cfg network tab) in
      (m, cmd, r)
  | None -> (m, Cmd.none, false)

(* what a click or a key made of a form, done. A form to send is told
 * to the page's scripts first (its submit event): one may prevent it,
 * or change a hidden field as the form goes, and it is sent with the
 * fields as they then are *)
let form (network : < Cap.network ; .. >) ~(keep_focus : bool) (outcome : Browser_forms.outcome) (m : model) : model * msg Cmd.t =
  let outcome, m, told =
    match outcome with
    | Submit { form = f; submitter; page; _ } when (current_tab m).script <> None ->
        let now = ref [] in
        let m, cmd, prevented =
          task network m (fun s ->
              let prevented = Browser_script.submit s f.element in
              now := List.filter_map (fun (c : Forms.control) -> if c.kind = Hidden then Option.map (fun v -> (c.element, v)) (Browser_script.value_now s c.element) else None) f.controls;
              prevented)
        in
        if prevented then (Browser_forms.Nothing, m, cmd)
        else
          let url, post = Browser_forms.submission ~now:(fun e -> List.assq_opt e !now) page f ~submitter in
          (Browser_forms.Submit { url; post; page; form = f; submitter }, m, cmd)
    | o -> (o, m, Cmd.none)
  in
  let m, cmd = on_current m (fun cfg tab -> Browser_tab.form_effect cfg network ~keep_focus outcome tab) in
  (m, Cmd.batch [ told; cmd ])

let click_page (network : < Cap.network ; .. >) (m : model) : model * msg Cmd.t =
  match ((current_tab m).state, page_point m) with
  | Shown p, Some (x, y) when m.inspecting -> ({ m with inspecting = false; selected = Hit.element_at p.layout ~x ~y }, Cmd.none)
  (* a player: played or paused *)
  | Shown p, Some (x, y)
    when (match Hit.fragment_at p.layout ~x ~y with
         | Some f -> Browser_media.click ~now:m.time ~media:(fun u -> List.assoc_opt u (current_tab m).media) p f.element
         | None -> false) ->
      (m, Cmd.none)
  | Shown p, Some (x, y) -> (
      (* the page's scripts first (the element under the pointer, its
       * click bubbling); then, unless one prevented it, the browser's *)
      let control = pointed_control m and link = hovered m and element = Hit.element_at p.layout ~x ~y in
      let m, cmd, prevented = task network m (fun s -> match Hit.element_at p.layout ~x ~y with Some e -> Browser_script.click s e | None -> false) in
      (* with -v: what was clicked, and what became of it *)
      Logs.info (fun f ->
          f "click on %s: %s%s"
            (match element with Some e -> "<" ^ e.name ^ (match Dom.attribute "class" e with Some c -> " class=\"" ^ c ^ "\"" | None -> "") ^ ">" | None -> "nothing")
            (match (control, link) with
             | Some _, _ -> "a control"
             | _, Some href -> "a link to " ^ href
             | _ ->
                 (* no link: what it is in, to see why *)
                 let rec chain (root : Dom.element) (e : Dom.element) : string list option =
                   if root == e then Some []
                   else List.find_map (fun (n : Dom.node) -> match n with Element c -> Option.map (fun l -> root.name :: l) (chain c e) | Text _ -> None) root.children
                 in
                 "no link, in " ^ String.concat " > " (Option.value (Option.bind element (chain p.tree)) ~default:[ "?" ]))
            (if prevented then ", taken by the page's script" else ""));
      if prevented then (m, cmd)
      else
        let m, cmd2 =
          match (control, link, (current_tab m).state) with
          | Some e, _, Shown p -> form network ~keep_focus:false (Browser_forms.click p e) m
          | _, Some href, Shown p -> visit network (resolve p.url href) m
          (* a <button> of a form: the form sent *)
          | None, None, Shown p when Option.bind element (Forms.submitting p.tree) <> None ->
              let f, button = Option.get (Option.bind element (Forms.submitting p.tree)) in
              form network ~keep_focus:false (Browser_forms.submit p f ~submitter:(Some button)) m
          | _ ->
              (* a <details>'s summary: opened or closed; else the field
               * typed into gives up the keys *)
              on_current m (fun cfg tab ->
                  match Option.bind element (fun e -> Browser_tab.details cfg network e tab) with
                  | Some opened -> opened
                  | None -> ({ tab with focus = None }, Cmd.none))
        in
        (m, Cmd.batch [ cmd; cmd2 ]))
  | _ -> (m, Cmd.none)

(* what an item of the right click's menu does *)
let menu_action (caps : < Cap.network ; Cap.exec ; .. >) (menu : Browser_menu.action Gui_menu.t) (action : Browser_menu.action) (m : model) : model * msg Cmd.t =
  let network = (caps :> < Cap.network >) in
  match action with
  (* a helper program, beside the browser (Browser_helpers) *)
  | Open_with command ->
      (match Browser_helpers.launch caps command with Ok () -> () | Error why -> Logs.warn (fun l -> l "%s" why));
      (m, Cmd.none)
  | Open_in_new_tab url ->
      (* behind the tab shown, which stays the current one *)
      let opened, cmd = open_tab network url m in
      ({ opened with current = m.current; selected = m.selected }, cmd)
  | Back -> on_current m (fun cfg tab -> Browser_tab.back cfg network tab)
  | Forward -> on_current m (fun cfg tab -> Browser_tab.forward cfg network tab)
  | Reload -> load ~reload:true network (current_url m) m
  | Inspect ->
      (* the element that was under the right click, in the tools *)
      let selected = match ((current_tab m).state, page_point_at m menu.at) with Shown p, Some (x, y) -> Hit.element_at p.layout ~x ~y | _ -> None in
      (with_panel Elements { m with inspecting = false; selected }, Cmd.none)

(* what the user does, as the event a page's script would be told of
 * (Browser_script.window_event): a key down or up when nothing of the
 * browser's is typed in, the pointer over the page moved, pressed, let
 * go, the wheel -- its place in the page's window, y down *)
let told (m : model) (msg : msg) : (string * (string * Js_value.value) list) option =
  let number f = Js_value.Number f and flag b = Js_value.Bool b in
  let key k = [ ("key", Js_value.String k); ("ctrlKey", flag m.ctrl); ("shiftKey", flag m.shift); ("altKey", flag false); ("metaKey", flag false) ] in
  let z = zoom_of m (current_tab m) in
  let place (x, y) = ((x -. area_left m) /. z, (area_top m -. y) /. z) in
  let pointer ?(moved = (0., 0.)) at ~button ~buttons =
    let x, y = place at in
    [ ("clientX", number x); ("clientY", number y); ("button", number button); ("buttons", number buttons); ("movementX", number (fst moved)); ("movementY", number (snd moved)) ]
  in
  let free = m.omnibox = None && (current_tab m).focus = None && m.menu = None in
  let over_page at = page_point_at m at <> None && Gui_scrollbar.at (scrollbar m) at = None in
  match msg with
  | Key k when free -> Some ("keydown", key k)
  | Key_up k when free -> Some ("keyup", key k)
  | Mouse_move (x, y) ->
      let at = (x /. scale_of m, y /. scale_of m) in
      let (x0, y0), (x1, y1) = (place m.mouse, place at) in
      if over_page at then Some ("mousemove", pointer at ~moved:(x1 -. x0, y1 -. y0) ~button:0. ~buttons:(if m.pressed then 1. else 0.)) else None
  | Click when m.menu = None && over_page m.mouse -> Some ("mousedown", pointer m.mouse ~button:0. ~buttons:1.)
  | Mouse_up when m.pressed -> Some ("mouseup", pointer m.mouse ~button:0. ~buttons:0.)
  | Wheel notches when (not m.ctrl) && over_page m.mouse -> Some ("wheel", ("deltaY", number (-100. *. notches)) :: ("deltaMode", number 0.) :: pointer m.mouse ~button:0. ~buttons:0.)
  | _ -> None

(* a message: for the page's scripts, then for the browser *)
let rec step (caps : < Cap.network ; Cap.open_out ; Cap.exec ; Cap.env ; .. >) (msg : msg) (m : model) : model * msg Cmd.t =
  let network = (caps :> < Cap.network >) in
  (* a page that is a program (a game, the Playground's own web
   * platform) is told first; then the browser does its own, unless a
   * script prevented it *)
  match (told m msg, (current_tab m).script) with
  | Some (typ, fields), Some s when Browser_script.listens s typ ->
      (* the pointer's events are of the element under it *)
      let at =
        match (msg, (current_tab m).state, page_point m) with
        | (Click | Mouse_up | Mouse_move _ | Wheel _), Shown p, Some (x, y) -> Hit.element_at p.layout ~x ~y
        | _ -> None
      in
      let m, cmd, prevented = task network m (fun s -> Browser_script.window_event ?at s typ fields) in
      let m = match msg with Click -> { m with pressed = true } | Mouse_up -> { m with pressed = false } | _ -> m in
      (* what went down, until the page's next frame ([update]) *)
      let m = match msg with Key k -> { m with fresh = String.lowercase_ascii k :: m.fresh } | Click -> { m with fresh = "mouse" :: m.fresh } | _ -> m in
      if prevented then (m, cmd) else let m, cmd' = update_browser caps msg m in (m, Cmd.batch [ cmd; cmd' ])
  | _ -> update_browser caps msg m

(* [step], and a tap not lost. A program reads the keys held at each
 * of its frames (the Playground's games do); a key down and up between
 * two of them was never held for it, and a page whose frame is long --
 * ours of a program compiled to JavaScript: a sixth of a second -- loses
 * most taps. So a key, or the button, let go before the page has run a
 * frame since it went down is kept ([late]) and told right after that
 * frame, which is this Tick's (the page's timers run on it) *)
and update (caps : < Cap.network ; Cap.open_out ; Cap.exec ; Cap.env ; .. >) (msg : msg) (m : model) : model * msg Cmd.t =
  match msg with
  | Key_up k when List.mem (String.lowercase_ascii k) m.fresh -> ({ m with late = m.late @ [ msg ] }, Cmd.none)
  | Mouse_up when List.mem "mouse" m.fresh -> ({ m with late = m.late @ [ msg ] }, Cmd.none)
  | Tick _ when m.fresh <> [] ->
      let late = m.late in
      let m, cmd = step caps msg { m with fresh = []; late = [] } in
      (m, Cmd.batch (cmd :: List.map (fun msg -> Cmd.Msg msg) late))
  | _ -> step caps msg m

and update_browser (caps : < Cap.network ; Cap.open_out ; Cap.exec ; Cap.env ; .. >) (msg : msg) (m : model) : model * msg Cmd.t =
  let network = (caps :> < Cap.network >) in
  (* the menu is over a page that stays as it is: closed by what
   * moves the page, and by Escape *)
  let m = match msg with Wheel _ | Resized _ | Key ("Escape" | "escape") -> { m with menu = None } | _ -> m in
  Browser_media.install ();
  (* a script's sound (AudioContext) goes where the players' does *)
  AudioContext.output := { now = Audio_queue.now; play = Audio_queue.play };
  match msg with
  | Got (id, url, r) ->
      (* a content the profile has a helper program for: given to it, and the tab told *)
      let r =
        match r with
        | Ok ({ headers; body; _ } as answer) -> (
            let kind = List.find_map (fun (name, value) -> if String.lowercase_ascii name = "content-type" then Some value else None) headers in
            match Option.bind kind (Browser_helpers.for_type (Browser_helpers.table caps m.profile.helpers)) with
            | Some rule ->
                let headers = ("Content-Type", "text/html; charset=utf-8") :: List.filter (fun (name, _) -> String.lowercase_ascii name <> "content-type") headers in
                Ok { answer with headers; body = Browser_helpers.opened caps rule ~url body }
            | None -> r)
        | Error _ -> r
      in
      on_tab m id (fun cfg tab -> Browser_tab.got cfg network url r tab)
  | Got_picture (id, url, r) -> on_tab m id (fun cfg tab -> Browser_tab.got_picture cfg network url r tab)
  | Got_answer (id, rid, url, r) -> on_tab m id (fun cfg tab -> Browser_tab.got_answer cfg network rid url r tab)
  | Start_fetch r ->
      Fetch.perform m.fetches r;
      (m, Cmd.none)
  | Got_socket (id, sid, event) -> on_tab m id (fun cfg tab -> Browser_tab.got_socket cfg network sid event tab)
  | Socket (id, ask) ->
      let sockets = Fetch.sockets m.fetches in
      (match ask with
      | Socket_open (sid, url, origin) -> Web_sockets.open_ sockets network ~key:(id, sid) ~origin url (fun event -> Got_socket (id, sid, event))
      | Socket_send (sid, message) -> Web_sockets.send sockets (id, sid) message
      | Socket_close (sid, code, reason) -> Web_sockets.close sockets (id, sid) ~code ~reason);
      (m, Cmd.none)
  | Tick time ->
      (* the shown tab's timers on the frame clock (the others wait, as
       * Chrome slows a hidden tab's) *)
      (* the screen's dots for a point, which the platform knows once
       * it has drawn, and which change with the screen the window is on *)
      let dots = Playground_platform.pixel_ratio () in
      let m =
        if dots = m.dots then m
        else (
          Logs.info (fun f -> f "the screen's dots for a point: %g" dots);
          { m with dots })
      in
      let m, cmd, _ = task network (saved caps { m with time }) (fun s -> Browser_script.advance s (1000. /. 60.); false) in
      (* the layouts owed since the frame before, one a tab *)
      let m, cmd =
        List.fold_left
          (fun (m, cmd) (t : tab) -> if t.tab.stale then (let m, c = on_tab m t.id (fun cfg tab -> Browser_tab.settle cfg network tab) in (m, Cmd.batch [ cmd; c ])) else (m, cmd))
          (m, cmd) m.tabs
      in
      (* the requests in flight stepped: the answers, Got and
       * Got_picture, as the next messages *)
      let answered = Fetch.step m.fetches in
      (m, Cmd.batch (cmd :: List.map (fun msg -> Cmd.Msg msg) answered))
  (* the wheel's notches, positive scrolling up (the platform's
   * meaning): the page goes up, so its scroll down the page decreases.
   * The system's natural scrolling, where it is the driver's (X11,
   * libinput), is in the notches already *)
  | Wheel notches when m.ctrl -> (zoomed (Browser_zoom.step (notches > 0.)) m, Cmd.none)
  | Wheel notches -> (wheeled notches m, Cmd.none)
  (* the pointer, from the window's dots to the program's units *)
  | Mouse_move (x, y) -> (
      let m = { m with mouse = (x /. scale_of m, y /. scale_of m) } in
      (* the scrollbar's thumb held: the page follows the pointer *)
      (* the button held since a click in the omnibox: its selection follows the pointer *)
      let m = if m.selecting then { m with omnibox = Omnibox.dragged (omnibox m) (fst m.mouse) } else m in
      match m.grab with
      | Some grab -> (scrolled (int_of_float (Float.round (Gui_scrollbar.dragged (scrollbar m) ~grab (snd m.mouse))) - (current_tab m).scroll) m, Cmd.none)
      | None -> (m, Cmd.none))
  | Mouse_up -> ({ m with grab = None; selecting = false }, Cmd.none)
  (* the window's size changed (not the first time, when it is
   * told the size it started at): kept in the profile, and every tab's
   * page laid out again at its new width *)
  | Resized (w, h) ->
      let profile = if (w, h) = m.window then m.profile else { m.profile with window = Some (w, h) } in
      (rescreened (with_profile profile { m with window = (w, h) }), Cmd.none)
  (* a right click on the page: its menu, for what is under the
   * pointer; elsewhere, an open menu closed *)
  | Right_click -> (
      let tab = current_tab m in
      match (tab.state, page_point m) with
      | Shown p, Some _ ->
          let link = Option.map (resolve p.url) (hovered m) in
          (* the helper program for the link, or for the page *)
          let target = Option.value link ~default:p.url in
          let helper = Option.map (fun r -> (Browser_helpers.name r, Browser_helpers.command r ~url:target ~file:None)) (Browser_helpers.for_url (Browser_helpers.table caps m.profile.helpers) target) in
          let items = Browser_menu.items ?helper ~link ~back:(tab.history.behind <> []) ~forward:(tab.history.ahead <> []) () in
          ({ m with menu = Some (Gui_menu.opened ~screen:m.screen ~at:m.mouse items); omnibox = None }, Cmd.none)
      | _ -> ({ m with menu = None }, Cmd.none))
  (* a click with the menu open is the menu's: on an item, done;
   * anywhere, the menu closed, the page under it not clicked *)
  | Click when m.menu <> None -> (
      let menu = Option.get m.menu in
      let m = { m with menu = None } in
      match Gui_menu.chosen menu m.mouse with Some action -> menu_action caps menu action m | None -> (m, Cmd.none))
  (* a press on the scrollbar: its thumb held until the button
   * is let go, or a page up or down *)
  | Click when Gui_scrollbar.at (scrollbar m) m.mouse <> None -> (
      let m = { m with omnibox = None } in
      match Gui_scrollbar.at (scrollbar m) m.mouse with
      | Some (Thumb grab) -> ({ m with grab = Some grab }, Cmd.none)
      | Some Before -> (scrolled (pages m (-1)) m, Cmd.none)
      | Some After -> (scrolled (pages m 1) m, Cmd.none)
      | None -> (m, Cmd.none))
  | Click -> (
      let double = m.time -. m.last_click < 0.4 and before = m.omnibox in
      let m = { m with omnibox = None; last_click = m.time } in
      if on_omnibox m then
        (* a first click takes it, its address all selected; then a click
         * puts the caret, and a drag from it selects (Omnibox.clicked) *)
        let field = Omnibox.clicked (omnibox { m with omnibox = before }) ~double (fst m.mouse) in
        on_current { m with omnibox = Some field; selecting = before <> None && not double } (fun _ tab -> ({ tab with focus = None }, Cmd.none))
      else if near (wrench_x m -. 12.) (toolbar_y m) 24. 28. m then (toggle_panel m, Cmd.none)
      else if near (js_x m) (toolbar_y m) 22. 20. m then
        (* scripts on or off, for every site, and the page loaded again;
         * with a list of hosts (scripts=a,b), this page's host in or
         * out of it *)
        let host = host_of (current_url m) in
        let allowed =
          if scripts_on m then []
          else if m.allowed = [] then [ everywhere ]
          else if List.mem host m.allowed then List.filter (( <> ) host) m.allowed
          else host :: m.allowed
        in
        Logs.info (fun f -> f "scripts: %s" (match allowed with [] -> "off" | [ "*" ] -> "on, every site's" | hosts -> String.concat ", " hosts));
        load network (current_url m) { m with allowed }
      else
        match (Gui_tabs.at (strip m) m.mouse, panel_button m, Gui_toolbar.at (buttons m) m.mouse) with
        | Some (Close id), _, _ -> close_tab network id m
        | Some (Show id), _, _ -> ({ m with current = id; selected = None; inspecting = false }, Cmd.none)
        | Some New, _, _ -> open_tab network home m
        | None, Some "Inspect", _ -> ({ m with inspecting = not m.inspecting }, Cmd.none)
        | None, Some "Elements", _ -> (with_panel Elements m, Cmd.none)
        | None, Some "Network", _ -> (with_panel Network { m with inspecting = false }, Cmd.none)
        | None, _, Some Gui_toolbar.Back -> on_current m (fun cfg tab -> Browser_tab.back cfg network tab)
        | None, _, Some Gui_toolbar.Forward -> on_current m (fun cfg tab -> Browser_tab.forward cfg network tab)
        | None, _, Some Gui_toolbar.Reload -> load ~reload:true network (current_url m) m
        | None, _, Some Gui_toolbar.Stop -> on_current m (fun cfg tab -> (Browser_tab.stop cfg tab, Cmd.none))
        | _ -> if page_point m <> None then click_page network m else (m, Cmd.none))
  (* Ctrl held (SDL's names, or the web's), and the page zoomed;
   * the character such a key may also type is not the omnibox's *)
  | Key ("Left Ctrl" | "Right Ctrl" | "left ctrl" | "right ctrl" | "Control") -> ({ m with ctrl = true }, Cmd.none)
  | Key ("Left Shift" | "Right Shift" | "left shift" | "right shift" | "Shift") -> ({ m with shift = true }, Cmd.none)
  | Key_up key ->
      let up names = List.mem (String.lowercase_ascii key) names in
      ({ m with ctrl = m.ctrl && not (up [ "left ctrl"; "right ctrl"; "control" ]); shift = m.shift && not (up [ "left shift"; "right shift"; "shift" ]) }, Cmd.none)
  (* with Shift too, the window's scale: a step of the zoom's
   * levels, or the desktop's again (0) *)
  | Key key when m.ctrl && m.shift && Browser_zoom.key key <> None ->
      let scale = match Option.get (Browser_zoom.key key) with Reset -> None | change -> Some (Browser_zoom.apply change (scale_of m)) in
      (rescreened (with_profile { m.profile with scale } m), Cmd.none)
  | Key key when m.ctrl && Browser_zoom.key key <> None -> (zoomed (Browser_zoom.apply (Option.get (Browser_zoom.key key))) m, Cmd.none)
  | Typed s when m.ctrl && Browser_zoom.key s <> None -> (m, Cmd.none)
  (* with Ctrl held a letter is a command (edit_omnibox), not typed *)
  | Typed s when m.omnibox <> None -> ({ m with omnibox = Option.map (Omnibox.typed ~ctrl:m.ctrl s) m.omnibox }, Cmd.none)
  | Key key when m.omnibox <> None -> edit_omnibox network key (Option.get m.omnibox) m
  | Typed s when (current_tab m).focus <> None -> (
      match ((current_tab m).state, (current_tab m).focus) with
      | Shown p, Some e -> form network ~keep_focus:true (Changed (Browser_forms.typed p e s)) m
      | _ -> (m, Cmd.none))
  | Key key when (current_tab m).focus <> None && not (List.mem (String.lowercase_ascii key) [ "arrowdown"; "arrowup"; "pagedown"; "pageup" ]) -> (
      match ((current_tab m).state, (current_tab m).focus) with
      | Shown p, Some e -> form network ~keep_focus:true (Browser_forms.key p e (String.lowercase_ascii key)) m
      | _ -> (m, Cmd.none))
  | Typed _ -> (m, Cmd.none)
  | Key key -> (
      match String.lowercase_ascii key with
      | "arrowdown" | "down" -> (scrolled 2 m, Cmd.none)
      | "arrowup" | "up" -> (scrolled (-2) m, Cmd.none)
      | "pagedown" | " " | "space" -> (scrolled (pages m 1) m, Cmd.none)
      | "pageup" -> (scrolled (pages m (-1)) m, Cmd.none)
      | "home" -> (scrolled (-(current_tab m).scroll) m, Cmd.none)
      | "f12" -> (toggle_panel m, Cmd.none)
      | "backspace" -> on_current m (fun cfg tab -> Browser_tab.back cfg network tab)
      | _ -> (m, Cmd.none))

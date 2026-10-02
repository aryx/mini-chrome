(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Script_window.mli *)
open Js_value
open Script_types
open Script_dom
open Script_host

let fn (name : string) (f : value list -> value) : value = host_function name (fun ~this:_ args -> f args)

let object_of (fields : (string * value) list) : value =
  let o = new_object () in
  List.iter (fun (k, v) -> set_own o k v) fields;
  Object o

let nothing (name : string) : string * value = (name, fn name (fun _ -> Undefined))

(*****************************************************************************)
(* The classes of the host objects *)
(*****************************************************************************)

(* each class and the one it extends; its constructor does nothing (a
 * page's class may extend HTMLElement), its prototype is behind its
 * instances' *)
let classes =
  [ ("EventTarget", None); ("Node", Some "EventTarget"); ("Element", Some "Node"); ("HTMLElement", Some "Element"); ("SVGElement", Some "Element");
    ("CharacterData", Some "Node"); ("Text", Some "CharacterData"); ("Comment", Some "CharacterData"); ("DocumentFragment", Some "Node");
    ("ShadowRoot", Some "DocumentFragment"); ("Document", Some "Node"); ("HTMLDocument", Some "Document"); ("Window", Some "EventTarget") ]
  @ List.map (fun tag -> ("HTML" ^ tag ^ "Element", Some "HTMLElement")) [ "Input"; "Form"; "Anchor"; "Image"; "Template"; "Select"; "TextArea"; "Button"; "Script"; "Style"; "IFrame"; "Slot"; "Option" ]

let install_classes (t : t) (define : string -> value -> unit) : unit =
  let protos : (string, obj) Hashtbl.t = Hashtbl.create 32 in
  List.iter
    (fun (name, parent) ->
      let p = { (new_object ()) with proto = Option.bind parent (Hashtbl.find_opt protos) } in
      let c = fn name (fun _ -> Undefined) in
      (match c with Object c -> set_own c "prototype" (Object p) | _ -> ());
      set_own p "constructor" c;
      Hashtbl.replace protos name p;
      define name c)
    classes;
  (match Js_eval.global t.engine "Node" with
  | Some (Object node) ->
      List.iter (fun (k, v) -> set_own node k (Number v)) [ ("ELEMENT_NODE", 1.); ("TEXT_NODE", 3.); ("COMMENT_NODE", 8.); ("DOCUMENT_NODE", 9.); ("DOCUMENT_FRAGMENT_NODE", 11.) ]
  | _ -> ());
  t.protos <- List.map (fun (kind, name) -> (kind, Hashtbl.find protos name)) [ ("element", "HTMLElement"); ("text", "Text"); ("comment", "Comment"); ("fragment", "DocumentFragment"); ("document", "HTMLDocument"); ("window", "Window") ]

(*****************************************************************************)
(* What a page is given *)
(*****************************************************************************)

(* the element's own style=, and a few defaults: not the cascade's answer *)
let computed_style (n : node) : value =
  let decls () = match attribute n "style" with Some s -> Css.declarations s | None -> [] in
  let value (k : string) : string =
    match (List.assoc_opt (kebab k) (decls ()), kebab k) with
    | Some v, _ -> v
    | None, "display" -> if attribute n "hidden" <> None then "none" else "block"
    | None, "visibility" -> "visible"
    | None, "position" -> "static"
    | None, "opacity" -> "1"
    | None, _ -> ""
  in
  host_object
    {
      class_name = "CSSStyleDeclaration";
      get = (fun k -> if k = "getPropertyValue" then fn k (fun args -> String (value (str (arg args 0)))) else String (value k));
      set = (fun _ _ -> ());
      show = (fun () -> "CSSStyleDeclaration");
    }

(* an observer that is never told anything *)
let observer (name : string) : value =
  let c = fn name (fun _ -> object_of [ nothing "observe"; nothing "unobserve"; nothing "disconnect"; ("takeRecords", fn "takeRecords" (fun _ -> Object (new_array []))) ]) in
  c

(* localStorage: kept as long as the page *)
let storage () : value =
  let items : (string * string) list ref = ref [] in
  let set k v = items := List.remove_assoc k !items @ [ (k, v) ] in
  host_object
    {
      class_name = "Storage";
      get =
        (fun k ->
          match k with
          | "getItem" -> fn k (fun args -> match List.assoc_opt (str (arg args 0)) !items with Some v -> String v | None -> Null)
          | "setItem" -> fn k (fun args -> set (str (arg args 0)) (str (arg args 1)); Undefined)
          | "removeItem" -> fn k (fun args -> items := List.remove_assoc (str (arg args 0)) !items; Undefined)
          | "clear" -> fn k (fun _ -> items := []; Undefined)
          | "key" -> fn k (fun args -> match List.nth_opt !items (int_of_float (to_number (arg args 0))) with Some (k, _) -> String k | None -> Null)
          | "length" -> Number (float_of_int (List.length !items))
          | k -> ( match List.assoc_opt k !items with Some v -> String v | None -> Undefined));
      set = (fun k v -> set k (str v));
      show = (fun () -> "Storage");
    }

let install (t : t) ~(viewport : float * float) (define : string -> value -> unit) : value =
  install_classes t define;
  define "getComputedStyle" (fn "getComputedStyle" (fun args -> computed_style (node_of t (arg args 0))));
  List.iter (fun name -> define name (observer name)) [ "MutationObserver"; "ResizeObserver"; "IntersectionObserver"; "PerformanceObserver" ];
  define "localStorage" (storage ());
  define "sessionStorage" (storage ());
  define "performance" (object_of [ ("now", fn "now" (fun _ -> Number t.now)); nothing "mark"; nothing "measure"; ("timeOrigin", Number 0.) ]);
  define "matchMedia"
    (fn "matchMedia" (fun args ->
         object_of [ ("matches", Bool false); ("media", arg args 0); nothing "addListener"; nothing "removeListener"; nothing "addEventListener"; nothing "removeEventListener" ]));
  define "history" (object_of [ ("length", Number 1.); ("state", Null); nothing "pushState"; nothing "replaceState"; nothing "back"; nothing "forward"; nothing "go" ]);
  define "screen" (object_of [ ("width", Number (fst viewport)); ("height", Number (snd viewport)); ("availWidth", Number (fst viewport)); ("availHeight", Number (snd viewport)) ]);
  define "getSelection" (fn "getSelection" (fun _ -> object_of [ ("rangeCount", Number 0.); nothing "removeAllRanges"; nothing "addRange"; ("toString", fn "toString" (fun _ -> String "")) ]));
  define "customElements" (object_of [ nothing "define"; nothing "get"; nothing "upgrade"; ("whenDefined", fn "whenDefined" (fun _ -> Undefined)) ]);
  define "CSS" (object_of [ ("supports", fn "supports" (fun _ -> Bool false)); ("escape", fn "escape" (fun args -> arg args 0)) ]);
  (* new Image(): an <img> in no tree *)
  define "Image" (fn "Image" (fun _ -> wrap t (make "img")));
  let global k = Option.value (Js_eval.global t.engine k) ~default:Undefined in
  (* what window has of its own, as globals: in a browser the global
   * object is the window, so innerWidth alone is window.innerWidth,
   * and addEventListener(...) is the window's. Its listeners are the
   * document's, its size the window's *)
  List.iter (fun k -> define k (Number (fst viewport))) [ "innerWidth"; "outerWidth" ];
  List.iter (fun k -> define k (Number (snd viewport))) [ "innerHeight"; "outerHeight" ];
  define "devicePixelRatio" (Number 1.);
  List.iter (fun k -> define k (Number 0.)) [ "scrollX"; "scrollY"; "pageXOffset"; "pageYOffset"; "screenX"; "screenY"; "length" ];
  List.iter
    (fun k ->
      define k
        (fn k (fun args ->
             match global "document" with
             | Object { kind = Host_object h; _ } as document -> Js_eval.call_in_run t.engine (h.get k) ~this:document args
             | _ -> Undefined)))
    [ "addEventListener"; "removeEventListener"; "dispatchEvent" ];
  List.iter (fun k -> define k (fn k (fun _ -> Undefined))) [ "scrollTo"; "scrollBy"; "scroll"; "focus"; "blur"; "postMessage"; "print"; "close"; "stop" ];
  define "open" (fn "open" (fun _ -> Null));
  define "confirm" (fn "confirm" (fun _ -> Bool true));
  define "prompt" (fn "prompt" (fun _ -> Null));
  define "origin" (String (Script_fetch.origin t.base));
  define "isSecureContext" (Bool (Browser_url.starts_with "https://" t.base));
  define "name" (String "");
  define "closed" (Bool false);
  List.iter (fun k -> define k Null) [ "opener"; "frameElement"; "onerror"; "onload"; "onpopstate"; "onunhandledrejection" ];
  (* window: the global object -- a global read or set through it *)
  let window =
    host_object
      {
        class_name = "Window";
        get = global;
        (* window.location = url goes there, as location.href = url *)
        set = (fun k v -> match (k, v) with "location", String url -> t.navigation <- Some (Browser_url.resolve t.base url, false) | _ -> Js_eval.define t.engine k v);
        show = (fun () -> "Window");
      }
  in
  (match window with Object o -> o.proto <- List.assoc_opt "window" t.protos | _ -> ());
  List.iter (fun name -> define name window) [ "window"; "self"; "globalThis"; "top"; "parent"; "frames" ];
  window

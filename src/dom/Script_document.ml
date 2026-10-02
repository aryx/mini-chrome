(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Script_document.mli *)
open Js_value
open Script_types
open Script_dom
open Script_host

let document (t : t) : value =
  let root = t.root in
  let title () = find root "title" in
  let named name = nodes_array t (List.filter (fun e -> e.name = name) (elements root)) in
  (* a page of its own: enough of a document to parse HTML into *)
  let other_document ?(html_text = "") () =
    let html = make "html" and body = make "body" in
    html.children <- [ body ];
    adopt html [ body ];
    body.children <- parse_fragment html_text;
    adopt body body.children;
    let o = new_object () in
    set_own o "body" (wrap t body);
    set_own o "documentElement" (wrap t html);
    set_own o "nodeType" (Number 9.);
    set_own o "querySelector" (method_ "querySelector" (fun args -> match select t (str (arg args 0)) ~within:html with e :: _ -> wrap t e | [] -> Null));
    set_own o "querySelectorAll" (method_ "querySelectorAll" (fun args -> nodes_array t (select t (str (arg args 0)) ~within:html)));
    set_own o "createElement" (method_ "createElement" (fun args -> wrap t (make (String.lowercase_ascii (str (arg args 0))))));
    Object o
  in
  let d =
  host_object
    {
      class_name = "HTMLDocument";
      get =
        (fun k ->
          match k with
          | "body" -> ( match find root "body" with Some b -> wrap t b | None -> Null)
          | "head" -> ( match find root "head" with Some h -> wrap t h | None -> Null)
          | "documentElement" | "firstChild" | "lastChild" | "firstElementChild" -> wrap t root
          (* the document as a node *)
          | "nodeType" -> Number 9.
          | "nodeName" -> String "#document"
          | "childNodes" | "children" -> nodes_array t [ root ]
          | "ownerDocument" | "parentNode" -> Null
          | "contains" -> method_ k (fun args -> Bool (match arg args 0 with Object _ as o -> top (node_of t o) == root | _ -> false))
          | "compatMode" -> String "CSS1Compat"
          | "characterSet" | "charset" -> String "UTF-8"
          | "hidden" -> Bool false
          | "visibilityState" -> String "visible"
          | "activeElement" -> ( match find root "body" with Some b -> wrap t b | None -> Null)
          | "scripts" -> named "script"
          | "forms" -> named "form"
          | "images" -> named "img"
          | "links" -> named "a"
          | "styleSheets" -> nodes_array t []
          | "currentScript" -> Null
          | "createDocumentFragment" -> method_ k (fun _ -> wrap t (make fragment_name))
          | "createComment" -> method_ k (fun args -> wrap t (make comment_name ~text:(str (arg args 0))))
          | "createElementNS" -> method_ k (fun args -> wrap t (make (String.lowercase_ascii (str (arg args 1)))))
          | "createEvent" -> method_ k (fun _ -> Script_events.create ())
          | "dispatchEvent" -> method_ k (fun args -> Bool (not (t.dispatch None (arg args 0))))
          | "implementation" ->
              let o = new_object () in
              set_own o "createHTMLDocument" (method_ "createHTMLDocument" (fun _ -> other_document ()));
              set_own o "hasFeature" (method_ "hasFeature" (fun _ -> Bool true));
              Object o
          | "getElementsByName" ->
              method_ k (fun args -> nodes_array t (List.filter (fun e -> attribute e "name" = Some (str (arg args 0))) (elements root)))
          | "title" -> String (match title () with Some n -> String.trim (text_content n) | None -> "")
          | "getElementById" ->
              method_ k (fun args ->
                  let id = str (arg args 0) in
                  match List.find_opt (fun e -> attribute e "id" = Some id) (elements root) with Some e -> wrap t e | None -> Null)
          | "querySelector" -> method_ k (fun args -> match select t (str (arg args 0)) ~within:root with e :: _ -> wrap t e | [] -> Null)
          | "querySelectorAll" -> method_ k (fun args -> nodes_array t (select t (str (arg args 0)) ~within:root))
          | "createElement" -> method_ k (fun args -> wrap t (make (String.lowercase_ascii (str (arg args 0)))))
          | "getElementsByClassName" | "getElementsByTagName" -> ( match wrap t root with Object { kind = Host_object h; _ } -> h.get k | _ -> Undefined)
          | "location" -> location t
          | "URL" -> String t.base
          (* claude: "a=1; b=2", the browser's for this page *)
          | "cookie" -> String (fst t.cookies ())
          | "referrer" -> String ""
          | "readyState" -> String "complete"
          | "defaultView" -> Option.value (Js_eval.global t.engine "window") ~default:Undefined
          | "createTextNode" -> method_ k (fun args -> wrap t (make text_name ~text:(str (arg args 0))))
          | "addEventListener" ->
              method_ k (fun args ->
                  t.document_listeners <- t.document_listeners @ [ (str (arg args 0), arg args 1) ];
                  listening_once t args;
                  Undefined)
          | "removeEventListener" ->
              method_ k (fun args ->
                  let typ = str (arg args 0) and f = arg args 1 in
                  t.document_listeners <- List.filter (fun (ty, g) -> not (ty = typ && strict_equal g f)) t.document_listeners;
                  Undefined)
          | _ -> Undefined);
      set =
        (fun k v ->
          match (k, title ()) with
          (* claude: document.cookie = "name=value; Path=/": one cookie
           * set (not the whole string replaced: its odd meaning) *)
          | "cookie", _ -> snd t.cookies (str v)
          | "title", Some n ->
              n.children <- [ make text_name ~text:(str v) ];
              adopt n n.children;
              touch t
          | "title", None -> (
              match find root "head" with
              | Some h ->
                  let n = make "title" in
                  n.children <- [ make text_name ~text:(str v) ];
                  adopt n n.children;
                  h.children <- h.children @ [ n ];
                  adopt h [ n ];
                  touch t
              | None -> ())
          | _ -> ());
      show = (fun () -> "#document");
    }
  in
  (match d with Object o -> o.proto <- List.assoc_opt "document" t.protos | _ -> ());
  (* new DOMParser().parseFromString(html, "text/html"): a page of its
   * own with that HTML in its body -- how a library reads the HTML a
   * server sent before putting it in the page (htmx) *)
  Js_eval.define t.engine "DOMParser"
    (host_function "DOMParser" (fun ~this _ ->
         (match this with
         | Object o -> set_own o "parseFromString" (method_ "parseFromString" (fun args -> other_document ~html_text:(str (arg args 0)) ()))
         | _ -> ());
         Undefined));
  d

(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Script_host.mli *)
open Js_value
open Script_types
open Script_dom (* the copy: its nodes read and changed *)

(* a script has changed the tree: the page to be laid out again *)
let touch (t : t) : unit = t.changed <- true
let str (v : value) : string = to_string v
let arg (args : value list) (i : int) : value = Option.value (List.nth_opt args i) ~default:Undefined

(* the node a host object stands for *)
let node_of (t : t) (v : value) : node =
  match v with
  | Object o -> ( match Hashtbl.find_opt t.nodes o.id with Some n -> n | None -> throw "TypeError" "parameter 1 is not of type 'Node'")
  | _ -> throw "TypeError" "parameter 1 is not of type 'Node'"

(* backgroundColor, the property; background-color, the CSS *)
let kebab (s : string) : string =
  String.concat "" (List.map (fun c -> if c >= 'A' && c <= 'Z' then "-" ^ String.make 1 (Char.lowercase_ascii c) else String.make 1 c) (List.init (String.length s) (String.get s)))

(* el.style: its style= attribute's declarations, read and written one
 * by one *)
let style_object (t : t) (n : node) : value =
  let decls () = match attribute n "style" with Some s -> Css.declarations s | None -> [] in
  host_object
    {
      class_name = "CSSStyleDeclaration";
      get = (fun k -> match List.assoc_opt (kebab k) (decls ()) with Some v -> String v | None -> String "");
      set =
        (fun k v ->
          let k = kebab k and v = str v in
          let others = List.remove_assoc k (decls ()) in
          let all = if v = "" then others else others @ [ (k, v) ] in
          set_attribute n "style" (String.concat "; " (List.map (fun (k, v) -> k ^ ": " ^ v) all));
          touch t);
      show = (fun () -> "CSSStyleDeclaration");
    }

let rec wrap (t : t) (n : node) : value =
  match n.wrapper with
  | Some v -> v
  | None ->
      let v = host_object { class_name = (if is_text n then "Text" else "HTMLElement"); get = get t n; set = set t n; show = (fun () -> show n) } in
      (match v with Object o -> Hashtbl.replace t.nodes o.id n | _ -> ());
      n.wrapper <- Some v;
      v

(* how the console shows an element: its start tag *)
and show (n : node) : string =
  if is_text n then Printf.sprintf "%S" n.text
  else "<" ^ n.name ^ String.concat "" (List.map (fun (k, v) -> Printf.sprintf " %s=\"%s\"" k v) n.attributes) ^ ">"

and nodes_array (t : t) (ns : node list) : value = Object (new_array (List.map (wrap t) ns))

and method_ (name : string) (f : value list -> value) : value = host_function name (fun ~this:_ args -> f args)

and get (t : t) (n : node) (k : string) : value =
  let elements_of ns = List.filter (fun c -> not (is_text c)) ns in
  let opt = function Some c -> wrap t c | None -> Null in
  match k with
  | "tagName" | "nodeName" -> String (if is_text n then "#text" else String.uppercase_ascii n.name)
  | "nodeType" -> Number (if is_text n then 3. else 1.)
  | "id" -> String (Option.value (attribute n "id") ~default:"")
  | "className" -> String (Option.value (attribute n "class") ~default:"")
  | "textContent" | "innerText" | "data" | "nodeValue" -> String (text_content n)
  | "innerHTML" -> String (inner_html n)
  | "outerHTML" -> String (html_of n)
  | "value" -> String (if n.name = "textarea" then text_content n else Option.value (attribute n "value") ~default:"")
  | "checked" -> Bool (attribute n "checked" <> None)
  | "style" -> style_object t n
  | "children" -> nodes_array t (elements_of n.children)
  | "childNodes" -> nodes_array t n.children
  | "firstChild" -> opt (List.nth_opt n.children 0)
  | "lastChild" -> opt (List.nth_opt (List.rev n.children) 0)
  | "firstElementChild" -> opt (List.nth_opt (elements_of n.children) 0)
  | "parentNode" | "parentElement" -> opt n.parent
  (* its siblings: the next or previous node, or element *)
  | "nextSibling" | "previousSibling" | "nextElementSibling" | "previousElementSibling" -> (
      match n.parent with
      | None -> Null
      | Some p ->
          let sibs = if String.ends_with ~suffix:"ElementSibling" k then elements_of p.children else p.children in
          let sibs = if String.starts_with ~prefix:"previous" k then List.rev sibs else sibs in
          let rec after l = match l with x :: y :: _ when x == n -> Some y | _ :: r -> after r | [] -> None in
          opt (after sibs))
  | "getElementsByClassName" ->
      method_ k (fun args ->
          let wanted = List.filter (( <> ) "") (String.split_on_char ' ' (str (arg args 0))) in
          nodes_array t (List.filter (fun e -> e != n && has_classes e wanted) (elements n)))
  | "getElementsByTagName" ->
      method_ k (fun args ->
          let name = String.lowercase_ascii (str (arg args 0)) in
          nodes_array t (List.filter (fun e -> e != n && (name = "*" || e.name = name)) (elements n)))
  | "classList" -> class_list t n
  | "href" when n.name = "a" || n.name = "link" || n.name = "area" -> (
      match attribute n "href" with Some h -> String (Browser_url.resolve t.base h) | None -> String "")
  | "src" when n.name = "img" || n.name = "script" -> ( match attribute n "src" with Some h -> String (Browser_url.resolve t.base h) | None -> String "")
  (* what a page does that has no effect here: nothing to scroll to, no
   * focus to move *)
  | "scrollIntoView" | "focus" | "blur" -> method_ k (fun _ -> Undefined)
  | "insertAdjacentHTML" ->
      method_ k (fun args ->
          let nodes = parse_fragment (str (arg args 1)) in
          (match String.lowercase_ascii (str (arg args 0)) with
          | "beforeend" -> n.children <- n.children @ nodes; adopt n nodes
          | "afterbegin" -> n.children <- nodes @ n.children; adopt n nodes
          | ("beforebegin" | "afterend") as where -> (
              match n.parent with
              | Some p ->
                  p.children <- List.concat_map (fun c -> if c == n then (if where = "beforebegin" then nodes @ [ c ] else c :: nodes) else [ c ]) p.children;
                  adopt p nodes
              | None -> ())
          | _ -> ());
          touch t;
          Undefined)
  | "getAttribute" -> method_ k (fun args -> match attribute n (str (arg args 0)) with Some v -> String v | None -> Null)
  | "setAttribute" ->
      method_ k (fun args ->
          set_attribute n (String.lowercase_ascii (str (arg args 0))) (str (arg args 1));
          touch t;
          Undefined)
  | "removeAttribute" ->
      method_ k (fun args ->
          n.attributes <- List.remove_assoc (str (arg args 0)) n.attributes;
          touch t;
          Undefined)
  | "appendChild" -> method_ k (fun args -> insert t n (arg args 0) ~before:None)
  | "insertBefore" -> method_ k (fun args -> insert t n (arg args 0) ~before:(match arg args 1 with Null | Undefined -> None | v -> Some (node_of t v)))
  | "removeChild" ->
      method_ k (fun args ->
          let c = node_of t (arg args 0) in
          (match c.parent with
          | Some p when p == n -> ()
          | _ -> throw "NotFoundError" "The node to be removed is not a child of this node.");
          detach c;
          touch t;
          arg args 0)
  | "remove" -> method_ k (fun _ -> detach n; touch t; Undefined)
  | "querySelector" -> method_ k (fun args -> opt (List.nth_opt (select t (str (arg args 0)) ~within:n) 0))
  | "querySelectorAll" -> method_ k (fun args -> nodes_array t (select t (str (arg args 0)) ~within:n))
  | "addEventListener" ->
      method_ k (fun args ->
          n.listeners <- n.listeners @ [ (str (arg args 0), arg args 1) ];
          Undefined)
  | "removeEventListener" ->
      method_ k (fun args ->
          let typ = str (arg args 0) and f = arg args 1 in
          n.listeners <- List.filter (fun (ty, g) -> not (ty = typ && strict_equal g f)) n.listeners;
          Undefined)
  | _ -> Option.value (List.assoc_opt k n.expando) ~default:Undefined

(* whether an element has every class of [wanted] *)
and has_classes (e : node) (wanted : string list) : bool =
  let have = match attribute e "class" with Some c -> String.split_on_char ' ' c | None -> [] in
  wanted <> [] && List.for_all (fun w -> List.mem w have) wanted

(* el.classList: its class= as a set of words *)
and class_list (t : t) (n : node) : value =
  let words () = List.filter (( <> ) "") (String.split_on_char ' ' (Option.value (attribute n "class") ~default:"")) in
  let write ws = set_attribute n "class" (String.concat " " ws); touch t in
  host_object
    {
      class_name = "DOMTokenList";
      get =
        (fun k ->
          match k with
          | "length" -> Number (float_of_int (List.length (words ())))
          | "contains" -> method_ k (fun args -> Bool (List.mem (str (arg args 0)) (words ())))
          | "add" -> method_ k (fun args -> write (words () @ List.filter (fun c -> not (List.mem c (words ()))) (List.map str args)); Undefined)
          | "remove" -> method_ k (fun args -> write (List.filter (fun c -> not (List.mem (String c) args || List.exists (fun a -> str a = c) args)) (words ())); Undefined)
          | "toggle" ->
              method_ k (fun args ->
                  let c = str (arg args 0) in
                  if List.mem c (words ()) then (write (List.filter (( <> ) c) (words ())); Bool false) else (write (words () @ [ c ]); Bool true))
          | _ -> Undefined);
      set = (fun _ _ -> ());
      show = (fun () -> String.concat " " (words ()));
    }

and set (t : t) (n : node) (k : string) (v : value) : unit =
  let replace_children (cs : node list) =
    List.iter (fun c -> c.parent <- None) n.children;
    n.children <- cs;
    adopt n cs;
    touch t
  in
  match k with
  | "id" -> set_attribute n "id" (str v); touch t
  | "className" -> set_attribute n "class" (str v); touch t
  | "textContent" | "innerText" | "data" | "nodeValue" ->
      if is_text n then (n.text <- str v; touch t) else replace_children [ make text_name ~text:(str v) ]
  | "innerHTML" -> replace_children (parse_fragment (str v))
  | "value" -> if n.name = "textarea" then replace_children [ make text_name ~text:(str v) ] else (set_attribute n "value" (str v); touch t)
  | "checked" ->
      (if truthy v then set_attribute n "checked" "" else n.attributes <- List.remove_assoc "checked" n.attributes);
      touch t
  | _ -> n.expando <- (k, v) :: List.remove_assoc k n.expando

(* child put in [parent], before [before] or at the end: moved if it
 * was elsewhere; never inside itself *)
and insert (t : t) (parent : node) (child_v : value) ~(before : node option) : value =
  let child = node_of t child_v in
  let rec inside (p : node option) = match p with Some p -> p == child || inside p.parent | None -> false in
  if inside (Some parent) then throw "HierarchyRequestError" "The new child element contains the parent.";
  detach child;
  (parent.children <-
     match before with
     | None -> parent.children @ [ child ]
     | Some b -> List.concat_map (fun c -> if c == b then [ child; c ] else [ c ]) parent.children);
  child.parent <- Some parent;
  touch t;
  child_v

(* the first element named so, at any depth *)
let find (n : node) (name : string) : node option = List.find_opt (fun e -> e.name = name) (elements n)

(* a URL's parts, as location and URL give them: href, protocol, host,
 * pathname, search, hash... *)
let url_parts (href : string) : (string * string) list =
  let without_hash, hash = match String.index_opt href '#' with Some i -> (String.sub href 0 i, String.sub href i (String.length href - i)) | None -> (href, "") in
  let without_query, search =
    match String.index_opt without_hash '?' with Some i -> (String.sub without_hash 0 i, String.sub without_hash i (String.length without_hash - i)) | None -> (without_hash, "")
  in
  let protocol, rest = match String.index_opt without_query ':' with Some i -> (String.sub without_query 0 (i + 1), String.sub without_query (i + 1) (String.length without_query - i - 1)) | None -> ("", without_query) in
  let host, pathname =
    if String.starts_with ~prefix:"//" rest then
      let r = String.sub rest 2 (String.length rest - 2) in
      match String.index_opt r '/' with Some i -> (String.sub r 0 i, String.sub r i (String.length r - i)) | None -> (r, "/")
    else ("", rest)
  in
  let hostname = match String.index_opt host ':' with Some i -> String.sub host 0 i | None -> host in
  [ ("href", href); ("protocol", protocol); ("host", host); ("hostname", hostname); ("pathname", pathname); ("search", search); ("hash", hash);
    ("origin", if host = "" then "null" else protocol ^ "//" ^ host) ]

(* an object of a URL's parts; URL's searchParams, and toString *)
let url_object (href : string) : value =
  let parts = url_parts href in
  let o = new_object () in
  List.iter (fun (k, v) -> set_own o k (String v)) parts;
  let query = let s = List.assoc "search" parts in if s = "" then "" else String.sub s 1 (String.length s - 1) in
  let params = Urlencoded.decode query in
  let sp = new_object () in
  set_own sp "get" (host_function "get" (fun ~this:_ args -> match List.assoc_opt (str (arg args 0)) params with Some v -> String v | None -> Null));
  set_own sp "has" (host_function "has" (fun ~this:_ args -> Bool (List.mem_assoc (str (arg args 0)) params)));
  set_own o "searchParams" (Object sp);
  set_own o "toString" (host_function "toString" (fun ~this:_ _ -> String href));
  Object o

let location (t : t) : value = url_object t.base

let document (t : t) : value =
  let root = t.root in
  let title () = find root "title" in
  host_object
    {
      class_name = "HTMLDocument";
      get =
        (fun k ->
          match k with
          | "body" -> ( match find root "body" with Some b -> wrap t b | None -> Null)
          | "head" -> ( match find root "head" with Some h -> wrap t h | None -> Null)
          | "documentElement" -> wrap t root
          | "title" -> String (match title () with Some n -> String.trim (text_content n) | None -> "")
          | "getElementById" ->
              method_ k (fun args ->
                  let id = str (arg args 0) in
                  match List.find_opt (fun e -> attribute e "id" = Some id) (elements root) with Some e -> wrap t e | None -> Null)
          | "querySelector" -> method_ k (fun args -> match select t (str (arg args 0)) ~within:root with e :: _ -> wrap t e | [] -> Null)
          | "querySelectorAll" -> method_ k (fun args -> nodes_array t (select t (str (arg args 0)) ~within:root))
          | "createElement" -> method_ k (fun args -> wrap t (make (String.lowercase_ascii (str (arg args 0)))))
          | "getElementsByClassName" | "getElementsByTagName" -> get t root k
          | "location" -> location t
          | "URL" -> String t.base
          | "cookie" | "referrer" -> String ""
          | "readyState" -> String "complete"
          | "defaultView" -> Option.value (Js_eval.global t.engine "window") ~default:Undefined
          | "createTextNode" -> method_ k (fun args -> wrap t (make text_name ~text:(str (arg args 0))))
          | "addEventListener" ->
              method_ k (fun args ->
                  t.document_listeners <- t.document_listeners @ [ (str (arg args 0), arg args 1) ];
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

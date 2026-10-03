(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See LocalStorage.mli *)
open Js_value
open Script_host

let fn (name : string) (f : value list -> value) : value = host_function name (fun ~this:_ args -> f args)

(* a storage of its own: names and values, in the order they were set *)
let make () : value =
  let items : (string * string) list ref = ref [] in
  let set k v = items := if List.mem_assoc k !items then List.map (fun (k', v') -> if k' = k then (k, v) else (k', v')) !items else !items @ [ (k, v) ] in
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
          (* storage.name: an item, as getItem but undefined for none *)
          | k -> ( match List.assoc_opt k !items with Some v -> String v | None -> Undefined));
      set = (fun k v -> set k (str v));
      show = (fun () -> "Storage");
    }

let install (define : string -> value -> unit) : unit =
  define "localStorage" (make ());
  define "sessionStorage" (make ())

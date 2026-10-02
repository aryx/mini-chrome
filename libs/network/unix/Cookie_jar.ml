(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Cookie_jar.mli *)

type t = { mutable jar : Cookie.jar; mutable changes : int; lock : Mutex.t }

let create ?(cookies = []) () : t = { jar = cookies; changes = 0; lock = Mutex.create () }

let locked (t : t) (f : unit -> 'a) : 'a =
  Mutex.lock t.lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.lock) f

let now = Unix.gettimeofday
let cookies (t : t) : Cookie.jar = locked t (fun () -> Cookie.alive ~now:(now ()) t.jar)
let header (t : t) (url : Url.t) : string option = locked t (fun () -> Cookie.header ~now:(now ()) url t.jar)

(* the jar after [f], counted if it is another *)
let write (t : t) (f : Cookie.jar -> Cookie.jar) : unit =
  locked t (fun () ->
      let jar = f t.jar in
      if jar <> t.jar then begin
        t.jar <- jar;
        t.changes <- t.changes + 1
      end)

let received (t : t) (url : Url.t) (headers : Http.header list) : unit =
  match Http.values "Set-Cookie" headers with
  | [] -> ()
  | values ->
      List.iter (fun v -> Logs.debug (fun m -> m "cookie from %s: %s" (Url.to_string url) v)) values;
      write t (fun jar -> List.fold_left (fun jar v -> Cookie.store ~now:(now ()) url v jar) jar values)

let script_cookies (t : t) (url : Url.t) : string =
  locked t (fun () -> Option.value (Cookie.header ~now:(now ()) ~script:true url t.jar) ~default:"")

let set_from_script (t : t) (url : Url.t) (value : string) : unit = write t (Cookie.store ~now:(now ()) ~script:true url value)
let changes (t : t) : int = locked t (fun () -> t.changes)
let clear (t : t) : unit = write t (fun _ -> [])

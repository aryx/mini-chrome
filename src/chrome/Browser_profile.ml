(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_profile.mli *)

type t = { window : (int * int) option; scale : float option; zooms : Browser_zoom.t; helpers : Browser_helpers.t }

let empty : t = { window = None; scale = None; zooms = Browser_zoom.empty; helpers = [] }

(*****************************************************************************)
(* The Preferences file's text *)
(*****************************************************************************)

let to_string (p : t) : string =
  let window = match p.window with Some (w, h) -> [ ("window", Json.Object [ ("width", Number (float_of_int w)); ("height", Number (float_of_int h)) ]) ] | None -> [] in
  let scale = match p.scale with Some s -> [ ("scale", Json.Number s) ] | None -> [] in
  let helpers = if p.helpers = [] then [] else [ ("helpers", Browser_helpers.to_json p.helpers) ] in
  Json.to_string (Json.Object (window @ scale @ [ ("zoom", Json.Object (List.map (fun (host, z) -> (host, Json.Number z)) p.zooms)) ] @ helpers)) ^ "\n"

let of_string (s : string) : (t, string) result =
  let first = List.hd Browser_zoom.levels and last = List.nth Browser_zoom.levels (List.length Browser_zoom.levels - 1) in
  let level (z : Json.t option) = match z with Some (Number z) when z >= first && z <= last -> Some z | _ -> None in
  let zoom ((host, z) : string * Json.t) = match level (Some z) with Some z when z <> 1. -> Some (host, z) | _ -> None in
  let side (name : string) (window : Json.t option) : int option =
    match Option.bind window (Json.member name) with Some (Number n) when n >= 100. && n <= 10000. -> Some (int_of_float n) | _ -> None
  in
  Result.map
    (fun json ->
      let window = Json.member "window" json in
      { window = (match (side "width" window, side "height" window) with Some w, Some h -> Some (w, h) | _ -> None);
        scale = level (Json.member "scale" json);
        zooms = (match Json.member "zoom" json with Some (Object fields) -> List.filter_map zoom fields | _ -> []);
        helpers = (match Json.member "helpers" json with Some h -> Browser_helpers.of_json h | None -> []) })
    (Json.parse s)

(*****************************************************************************)
(* The profile's directory *)
(*****************************************************************************)

let default_dir (caps : < Cap.env ; .. >) : string option =
  let env name = match CapSys.getenv caps name with "" -> None | v -> Some v | exception Not_found -> None in
  match (env "XDG_CONFIG_HOME", env "HOME") with
  | Some config, _ -> Some (Filename.concat config "mini-chrome")
  | None, Some home -> Some (Filename.concat (Filename.concat home ".config") "mini-chrome")
  | None, None -> None

let preferences (dir : string) : string = Filename.concat dir "Preferences"

let load (caps : < Cap.open_in ; .. >) ~(dir : string) : (t, string) result =
  let path = preferences dir in
  (* the authority to read [path], asked for before it is opened *)
  let (_ : Cap.FS_.open_in) = caps#open_in path in
  if not (Sys.file_exists path) then (
    Logs.info (fun m -> m "profile: no %s yet" path);
    Ok empty)
  else (
    Logs.info (fun m -> m "profile: reading %s" path);
    Result.map_error
      (fun why -> path ^ ": " ^ why)
      (match In_channel.with_open_bin path In_channel.input_all with s -> of_string s | exception Sys_error why -> Error why))

let save (caps : < Cap.open_out ; .. >) ~(dir : string) (p : t) : (unit, string) result =
  let path = preferences dir in
  let (_ : Cap.FS_.open_out) = caps#open_out path in
  let rec make (dir : string) = if not (Sys.file_exists dir) then (make (Filename.dirname dir); Sys.mkdir dir 0o700) in
  Logs.info (fun m -> m "profile: writing %s" path);
  try
    make dir;
    Out_channel.with_open_bin (path ^ ".tmp") (fun oc -> Out_channel.output_string oc (to_string p));
    Sys.rename (path ^ ".tmp") path;
    Ok ()
  with Sys_error why -> Error why

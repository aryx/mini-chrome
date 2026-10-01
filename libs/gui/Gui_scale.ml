(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_scale.mli *)

let of_xrdb (text : string) : float option =
  String.split_on_char '\n' text
  |> List.find_map (fun line ->
         match String.split_on_char ':' line with
         | [ "Xft.dpi"; dpi ] -> (
             match float_of_string_opt (String.trim dpi) with
             | Some dpi when dpi >= 48. && dpi <= 480. -> Some (dpi /. 96.)
             | _ -> None)
         | _ -> None)

let desktop (caps : < Cap.forkew ; Cap.env ; .. >) : float =
  let env name = match CapSys.getenv caps name with v -> Some v | exception Not_found -> None in
  if env "SDL_VIDEODRIVER" = Some "dummy" || env "DISPLAY" = None then 1.
  else
    (* the authority to run xrdb -- a process forked, the program
     * executed in it, its end waited for -- asked for before it is run *)
    let (_ : Cap.Process.fork) = caps#fork and (_ : Cap.Exec.t) = caps#exec "xrdb" and (_ : Cap.Process.wait) = caps#wait in
    Logs.info (fun m -> m "running xrdb -query");
    match Unix.open_process_args_in "xrdb" [| "xrdb"; "-query" |] with
    | exception Unix.Unix_error _ -> 1.
    | ic ->
        let text = In_channel.input_all ic in
        ignore (Unix.close_process_in ic);
        let scale = Option.value (of_xrdb text) ~default:1. in
        Logs.info (fun m -> m "the desktop's scale: %g (Xft.dpi)" scale);
        scale

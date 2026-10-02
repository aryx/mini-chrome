(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Webm.mli *)

type track = { number : int; video : bool; codec : string; width : int; height : int; rate : float; channels : int; setup : string }
type t = { tracks : track list; frames : (int * float * string) list; duration : float }

(*****************************************************************************)
(* EBML: elements in elements *)
(*****************************************************************************)

(* a number of 1 to 8 bytes whose first byte says, by its leading
 * zeros, how many: with that mark kept (an element's name) or taken
 * out (a size, a track's number). Where it ends *)
let vint (s : string) (at : int) ~(keep_mark : bool) : int * int =
  if at >= String.length s then failwith "Webm: cut short";
  let first = Char.code s.[at] in
  let rec length n mask = if n > 8 then failwith "Webm: not a number" else if first land mask <> 0 then n else length (n + 1) (mask lsr 1) in
  let n = length 1 0x80 in
  if at + n > String.length s then failwith "Webm: cut short";
  let v = ref (if keep_mark then first else first land ((0x100 lsr n) - 1)) in
  for i = 1 to n - 1 do v := (!v lsl 8) lor Char.code s.[at + i] done;
  (!v, at + n)

(* the elements between two places: each its name, where its content
 * starts and how long it is. A size of all ones is "to the end" (a
 * file written as it was recorded) *)
let rec elements (s : string) (from : int) (until : int) : (int * int * int) list =
  if from >= until then []
  else
    let id, at = vint s from ~keep_mark:true in
    let size, at = vint s at ~keep_mark:false in
    let unknown = (at - from > 1) && size + 1 = 1 lsl (7 * (at - from - (if id < 0x100 then 1 else if id < 0x10000 then 2 else if id < 0x1000000 then 3 else 4))) in
    let size = if unknown then until - at else min size (until - at) in
    (id, at, size) :: elements s (at + size) until

let number (s : string) (at : int) (size : int) : int =
  let v = ref 0 in
  for i = 0 to size - 1 do v := (!v lsl 8) lor Char.code s.[at + i] done;
  !v

let real (s : string) (at : int) (size : int) : float =
  if size = 4 then Int32.float_of_bits (Int32.of_int (number s at 4)) else if size = 8 then Int64.float_of_bits (String.get_int64_be s at) else 0.

(*****************************************************************************)
(* Matroska: what the elements are *)
(*****************************************************************************)

let sniff (s : string) : bool = String.length s >= 4 && String.sub s 0 4 = "\x1a\x45\xdf\xa3"

let parse (s : string) : t =
  if not (sniff s) then failwith "Webm: not a WebM file";
  let tracks = ref [] and frames = ref [] and scale = ref 1_000_000. and duration = ref 0. in
  let children (_, at, size) = elements s at (at + size) in
  let find id es = List.filter (fun (i, _, _) -> i = id) es in
  (* a block: its track, its time after the cluster's, a byte of flags, a frame *)
  let block cluster_time (_, at, size) =
    let track, data = vint s at ~keep_mark:false in
    let time = (Char.code s.[data] lsl 8) lor Char.code s.[data + 1] in
    let time = if time >= 0x8000 then time - 0x10000 else time in
    if Char.code s.[data + 2] land 0x06 <> 0 then failwith "Webm: several frames laced in a block";
    frames := (track, float_of_int (cluster_time + time) *. !scale /. 1e9, String.sub s (data + 3) (at + size - data - 3)) :: !frames
  in
  List.iter
    (fun segment ->
      List.iter
        (fun ((id, at, size) as e) ->
          match id with
          (* Info: the unit of every time, in nanoseconds (a millisecond unless said); how long *)
          | 0x1549A966 ->
              List.iter
                (fun (id, at, size) -> if id = 0x2AD7B1 then scale := float_of_int (number s at size) else if id = 0x4489 then duration := real s at size)
                (children e)
          (* Tracks *)
          | 0x1654AE6B ->
              List.iter
                (fun entry ->
                  let fields = children entry in
                  let get id = match find id fields with (_, at, size) :: _ -> Some (at, size) | [] -> None in
                  let int id = match get id with Some (at, size) -> number s at size | None -> 0 in
                  let width, height =
                    match find 0xE0 fields with
                    | video :: _ ->
                        let v = children video in
                        let dim id = match find id v with (_, at, size) :: _ -> number s at size | [] -> 0 in
                        (dim 0xB0, dim 0xBA)
                    | [] -> (0, 0)
                  in
                  (* a sound's: samples a second (8,000 unless said), channels (1) *)
                  let rate, channels =
                    match find 0xE1 fields with
                    | audio :: _ ->
                        let a = children audio in
                        let field id = match find id a with (_, at, size) :: _ -> Some (at, size) | [] -> None in
                        ( (match field 0xB5 with Some (at, size) -> real s at size | None -> 8000.),
                          match field 0x9F with Some (at, size) -> number s at size | None -> 1 )
                    | [] -> (0., 0)
                  in
                  let text id = match get id with Some (at, size) -> String.sub s at size | None -> "" in
                  tracks := { number = int 0xD7; video = int 0x83 = 1; codec = text 0x86; width; height; rate; channels; setup = text 0x63A2 } :: !tracks)
                (find 0xAE (children e))
          (* a Cluster: its time, then its blocks, bare or in a group *)
          | 0x1F43B675 ->
              let inside = children e in
              let time = match find 0xE7 inside with (_, at, size) :: _ -> number s at size | [] -> 0 in
              List.iter
                (fun ((id, _, _) as b) -> if id = 0xA3 then block time b else if id = 0xA0 then List.iter (block time) (find 0xA1 (children b)))
                inside
          | _ -> ignore (at, size))
        (children segment))
    (find 0x18538067 (elements s 0 (String.length s)));
  { tracks = List.rev !tracks; frames = List.rev !frames; duration = !duration *. !scale /. 1e9 }

let first (t : t) (wanted : track -> bool) : (track * (float * string) list) option =
  match List.find_opt wanted t.tracks with
  | Some tr -> Some (tr, List.filter_map (fun (n, time, data) -> if n = tr.number then Some (time, data) else None) t.frames)
  | None -> None

let video (t : t) = first t (fun tr -> tr.video)
let audio (t : t) = first t (fun tr -> tr.channels > 0)

(* Xiph's lacing: a count less one, each packet's size but the last's
 * as bytes added up to one under 255, then the packets end to end *)
let laced (s : string) : string list =
  if s = "" then []
  else
    let count = Char.code s.[0] + 1 in
    let rec sizes at n acc =
      if n = 0 then (at, List.rev acc)
      else
        let rec size at sum = let b = Char.code s.[at] in if b = 255 then size (at + 1) (sum + 255) else (at + 1, sum + b) in
        let at, v = size at 0 in
        sizes at (n - 1) (v :: acc)
    in
    let at, sizes = sizes 1 (count - 1) [] in
    let at, packets = List.fold_left (fun (at, acc) size -> (at + size, String.sub s at size :: acc)) (at, []) sizes in
    List.rev (String.sub s at (String.length s - at) :: packets)

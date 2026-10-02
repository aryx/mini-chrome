(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Vp8_video.mli *)

(* the boolean decoder, the tokens, the transforms, the guesses from
 * neighbours and the loop filter are the still picture's (libs/images) *)
open Vp8

type planes = { y : Bytes.t; u : Bytes.t; v : Bytes.t }

type t = {
  mutable width : int;
  mutable height : int;
  mutable mbw : int; (* in macroblocks *)
  mutable mbh : int;
  (* the three frames a frame may be predicted from, and the one shown *)
  mutable last : planes option;
  mutable golden : planes option;
  mutable altref : planes option;
  mutable shown : planes option;
  (* the probabilities, kept from a frame to the next *)
  mutable coeff_probs : int array;
  mutable mv_probs : int array array; (* a vector's rows, then its columns: 19 each *)
  mutable ymode_probs : int array;
  mutable uv_probs : int array;
  (* the segments, and the loop filter's changes by reference and mode *)
  mutable segmented : bool;
  mutable seg_abs : bool;
  seg_quant : int array;
  seg_filter : int array;
  segment_probs : int array;
  ref_delta : int array;
  mode_delta : int array;
  (* each macroblock's record, with a row above the first and a column
   * on the left of the first, of nothing: its mode, the frame it is
   * predicted from (0: this one), its vector, its sixteen blocks'
   * when it is split, its segment *)
  mutable ymodes : int array;
  mutable refs : int array;
  mutable mvx : int array;
  mutable mvy : int array;
  mutable sub_x : int array;
  mutable sub_y : int array;
  mutable segments : int array;
}

let create () : t =
  { width = 0; height = 0; mbw = 0; mbh = 0; last = None; golden = None; altref = None; shown = None;
    coeff_probs = [||]; mv_probs = [||]; ymode_probs = [||]; uv_probs = [||];
    segmented = false; seg_abs = false; seg_quant = Array.make 4 0; seg_filter = Array.make 4 0; segment_probs = Array.make 3 255;
    ref_delta = Array.make 4 0; mode_delta = Array.make 4 0;
    ymodes = [||]; refs = [||]; mvx = [||]; mvy = [||]; sub_x = [||]; sub_y = [||]; segments = [||] }

let clip (lo : int) (hi : int) (v : int) : int = if v < lo then lo else if v > hi then hi else v

(*****************************************************************************)
(* The modes of a frame predicted from another, and their tables *)
(*****************************************************************************)

(* after the four ways to guess a whole block from its neighbours *)
let b_pred = 4 (* its sixteen 4 x 4 blocks each guessed their way *)
let nearest_mv = 5 and near_mv = 6 and zero_mv = 7 and new_mv = 8 and split_mv = 9

let ymode_tree = [| -dc_pred; 2; 4; 6; -v_pred; -h_pred; -tm_pred; -b_pred |]
let uv_mode_tree = [| -dc_pred; 2; -v_pred; 4; -h_pred; -tm_pred |]
let mv_ref_tree = [| -zero_mv; 2; -nearest_mv; 4; -near_mv; 6; -new_mv; -split_mv |]
let default_ymode_probs = [| 112; 86; 140; 37 |]
let default_uv_probs = [| 162; 101; 204 |]
let default_bmode_probs = [| 120; 90; 79; 133; 87; 85; 80; 111; 151 |]

(* a mode's probabilities, by how many of the neighbours agree *)
let mv_counts_to_probs = [| [| 7; 1; 1; 143 |]; [| 14; 18; 14; 107 |]; [| 135; 64; 57; 68 |]; [| 60; 56; 128; 65 |]; [| 159; 134; 128; 34 |]; [| 234; 188; 128; 28 |] |]

(* a split macroblock: in two halves, top and bottom or left and
 * right, in quarters, or its sixteen blocks; which part each block is of *)
let split_tree = [| -3; 2; -2; 4; 0; -1 |]
let split_probs = [| 110; 111; 150 |]
let partitions =
  [| [| 0; 0; 0; 0; 0; 0; 0; 0; 1; 1; 1; 1; 1; 1; 1; 1 |]; [| 0; 0; 1; 1; 0; 0; 1; 1; 0; 0; 1; 1; 0; 0; 1; 1 |];
     [| 0; 0; 1; 1; 0; 0; 1; 1; 2; 2; 3; 3; 2; 2; 3; 3 |]; Array.init 16 Fun.id |]

(* a part's vector: its left neighbour's, the one above's, none, or a
 * new one; the probabilities by what those two are *)
let sub_tree = [| 0; 2; -1; 4; -2; -3 |]
let sub_probs = [| [| 147; 136; 18 |]; [| 106; 145; 1 |]; [| 179; 121; 1 |]; [| 223; 1; 34 |]; [| 208; 1; 1 |] |]

(* a vector's component: short or long, its sign, a short one's tree,
 * a long one's bits *)
let small_mv_tree = [| 2; 8; 4; 6; 0; -1; -2; -3; 10; 12; -4; -5; -6; -7 |]
let default_mv_probs =
  [| [| 162; 128; 225; 146; 172; 147; 214; 39; 156; 128; 129; 132; 75; 145; 178; 206; 239; 254; 254 |];
     [| 164; 128; 204; 170; 119; 235; 140; 230; 228; 128; 130; 130; 74; 148; 180; 203; 236; 254; 254 |] |]
let mv_update_probs =
  [| [| 237; 246; 253; 253; 254; 254; 254; 254; 254; 254; 254; 254; 254; 254; 250; 250; 252; 254; 254 |];
     [| 231; 243; 245; 253; 254; 254; 254; 254; 254; 254; 254; 254; 254; 254; 251; 251; 254; 254; 254 |] |]

(* between two pixels: the six neighbours' weights for each eighth (a
 * luma vector is in quarters, a chroma one in eighths), in 128ths; and
 * the two neighbours' of the format's simpler versions *)
let sixtap =
  [| [| 0; 0; 128; 0; 0; 0 |]; [| 0; -6; 123; 12; -1; 0 |]; [| 2; -11; 108; 36; -8; 1 |]; [| 0; -9; 93; 50; -6; 0 |];
     [| 3; -16; 77; 77; -16; 3 |]; [| 0; -6; 50; 93; -9; 0 |]; [| 1; -8; 36; 108; -11; 2 |]; [| 0; -1; 12; 123; -6; 0 |] |]
let bilinear = Array.init 8 (fun i -> [| 0; 0; 128 - (16 * i); 16 * i; 0; 0 |])

(*****************************************************************************)
(* Motion vectors *)
(*****************************************************************************)

(* a component, in quarter pixels, doubled *)
let read_component (b : bools) (p : int array) : int =
  let x =
    if bool b p.(0) then (
      let x = ref 0 in
      for i = 0 to 2 do x := !x + (bit b p.(9 + i) lsl i) done;
      for i = 9 downto 4 do x := !x + (bit b p.(9 + i) lsl i) done;
      (* bit 3 is not sent when it must be set: a long one is 8 at least *)
      if !x land 0xfff0 = 0 || bool b p.(12) then x := !x + 8;
      !x)
    else tree b small_mv_tree (fun k -> p.(2 + k))
  in
  (if x <> 0 && bool b p.(1) then -x else x) * 2

(* a vector: down, then across *)
let read_mv (b : bools) (probs : int array array) : int * int =
  let y = read_component b probs.(0) in
  let x = read_component b probs.(1) in
  (x, y)

(*****************************************************************************)
(* A block predicted from another frame *)
(*****************************************************************************)

(* the 4 x 4 block at (x, y) of [dst]: the block of [src] that the
 * vector points at -- its whole part a place, its fraction a filter
 * across then down. Past the frame's edge, the edge's pixel *)
let inter_block (dst : Bytes.t) (src : Bytes.t) ~(stride : int) ~(w : int) ~(h : int) (x : int) (y : int) ((mvx, mvy) : int * int) (filters : int array array) : unit =
  let get xx yy = Char.code (Bytes.unsafe_get src ((clip 0 (h - 1) yy * stride) + clip 0 (w - 1) xx)) in
  let put i j v = Bytes.unsafe_set dst (((y + j) * stride) + x + i) (Char.unsafe_chr v) in
  let sx = x + (mvx asr 3) and sy = y + (mvy asr 3) and fx = mvx land 7 and fy = mvy land 7 in
  if fx lor fy = 0 then
    for j = 0 to 3 do for i = 0 to 3 do put i j (get (sx + i) (sy + j)) done done
  else (
    let f = filters.(fx) and g = filters.(fy) in
    (* nine rows filtered across: the four, two above and three below *)
    let across = Array.make 36 0 in
    for r = 0 to 8 do
      for i = 0 to 3 do
        let sum = ref 64 in
        for k = 0 to 5 do sum := !sum + (get (sx + i + k - 2) (sy + r - 2) * f.(k)) done;
        across.((r * 4) + i) <- clip 0 255 (!sum asr 7)
      done
    done;
    for j = 0 to 3 do
      for i = 0 to 3 do
        let sum = ref 64 in
        for k = 0 to 5 do sum := !sum + (across.(((j + k) * 4) + i) * g.(k)) done;
        put i j (clip 0 255 (!sum asr 7))
      done
    done)

(*****************************************************************************)
(* A frame *)
(*****************************************************************************)

let decode (t : t) (s : string) : bool =
  if String.length s < 3 then failwith "Vp8_video: a frame too short";
  let tag = Char.code s.[0] lor (Char.code s.[1] lsl 8) lor (Char.code s.[2] lsl 16) in
  let key = tag land 1 = 0 and version = (tag lsr 1) land 3 and show = (tag lsr 4) land 1 = 1 and first_size = tag lsr 5 in
  let start = if key then 10 else 3 in
  if String.length s < start + first_size then failwith "Vp8_video: a frame cut short";
  if key then (
    if s.[3] <> '\x9d' || s.[4] <> '\x01' || s.[5] <> '\x2a' then failwith "Vp8_video: no start code";
    let width = (Char.code s.[6] lor (Char.code s.[7] lsl 8)) land 0x3fff and height = (Char.code s.[8] lor (Char.code s.[9] lsl 8)) land 0x3fff in
    if width = 0 || height = 0 then failwith "Vp8_video: a picture of no size";
    if width <> t.width || height <> t.height then (
      t.width <- width;
      t.height <- height;
      t.mbw <- (width + 15) / 16;
      t.mbh <- (height + 15) / 16;
      let n = (t.mbw + 1) * (t.mbh + 1) in
      t.ymodes <- Array.make n 0;
      t.refs <- Array.make n 0;
      t.mvx <- Array.make n 0;
      t.mvy <- Array.make n 0;
      t.sub_x <- Array.make (16 * n) 0;
      t.sub_y <- Array.make (16 * n) 0;
      t.segments <- Array.make n 0);
    (* a key frame starts again: the probabilities, the segments, the filter's changes *)
    t.coeff_probs <- Array.copy Vp8_tables.default_coeff_probs;
    t.mv_probs <- Array.map Array.copy default_mv_probs;
    t.ymode_probs <- Array.copy default_ymode_probs;
    t.uv_probs <- Array.copy default_uv_probs;
    t.segmented <- false;
    t.seg_abs <- false;
    Array.fill t.seg_quant 0 4 0;
    Array.fill t.seg_filter 0 4 0;
    Array.fill t.ref_delta 0 4 0;
    Array.fill t.mode_delta 0 4 0)
  else if t.last = None then failwith "Vp8_video: a frame predicted from one that is not there";
  let mbw = t.mbw and mbh = t.mbh in
  let ys = mbw * 16 and cs = mbw * 8 in
  let b = bools s start first_size in
  (* the colour space and whether to clamp: one of each exists *)
  if key then ignore (literal b 2);
  let maybe n = if flag b then signed b n else 0 in
  (* segments *)
  t.segmented <- flag b;
  let update_map = t.segmented && flag b in
  if t.segmented && flag b then (
    t.seg_abs <- flag b;
    for i = 0 to 3 do t.seg_quant.(i) <- maybe 7 done;
    for i = 0 to 3 do t.seg_filter.(i) <- maybe 6 done);
  if update_map then for i = 0 to 2 do t.segment_probs.(i) <- (if flag b then literal b 8 else 255) done;
  (* the loop filter *)
  let simple = flag b in
  let level = literal b 6 in
  let sharpness = literal b 3 in
  let delta_enabled = flag b in
  if delta_enabled && flag b then (
    for i = 0 to 3 do if flag b then t.ref_delta.(i) <- signed b 6 done;
    for i = 0 to 3 do if flag b then t.mode_delta.(i) <- signed b 6 done);
  (* the coefficients' partitions: after the first, their sizes (but
   * the last's, which is what is left), then they *)
  let count = 1 lsl literal b 2 in
  let sizes_at = start + first_size in
  let data_at = sizes_at + (3 * (count - 1)) in
  if data_at > String.length s then failwith "Vp8_video: cut short";
  let at = ref data_at in
  let tokens =
    Array.init count (fun i ->
        let from = !at in
        let size =
          if i < count - 1 then Char.code s.[sizes_at + (3 * i)] lor (Char.code s.[sizes_at + (3 * i) + 1] lsl 8) lor (Char.code s.[sizes_at + (3 * i) + 2] lsl 16)
          else String.length s - from
        in
        if from + size > String.length s then failwith "Vp8_video: a partition cut short";
        at := from + size;
        bools s from size)
  in
  (* the quantizers, a segment's: y dc, y ac, y2 dc, y2 ac, uv dc, uv ac *)
  let base = literal b 7 in
  let y_dc = maybe 4 in
  let y2_dc = maybe 4 in
  let y2_ac = maybe 4 in
  let uv_dc = maybe 4 in
  let uv_ac = maybe 4 in
  let quantizers =
    Array.init 4 (fun i ->
        let q = if not t.segmented then base else if t.seg_abs then t.seg_quant.(i) else base + t.seg_quant.(i) in
        let dc d = Vp8_tables.dc_q.(clip 0 127 (q + d)) and ac d = Vp8_tables.ac_q.(clip 0 127 (q + d)) in
        (dc y_dc, ac 0, 2 * dc y2_dc, max 8 (ac y2_ac * 155 / 100), min 132 (dc uv_dc), ac uv_ac))
  in
  (* which frames this one becomes, or is copied to, once decoded *)
  let refresh_golden = key || flag b in
  let refresh_altref = key || flag b in
  let copy_golden = if key || refresh_golden then 0 else literal b 2 in
  let copy_altref = if key || refresh_altref then 0 else literal b 2 in
  let sign_bias = [| false; false; (not key) && flag b; (not key) && flag b |] in
  let refresh_entropy = flag b in
  let refresh_last = key || flag b in
  (* the probabilities this frame changes: for the frames after it too,
   * unless it says they are its own *)
  let saved = if refresh_entropy then None else Some (Array.copy t.coeff_probs, Array.map Array.copy t.mv_probs, Array.copy t.ymode_probs, Array.copy t.uv_probs) in
  Array.iteri (fun i update -> if bool b update then t.coeff_probs.(i) <- literal b 8) Vp8_tables.coeff_update_probs;
  let skip_prob = if flag b then Some (literal b 8) else None in
  let prob_inter = if key then 0 else literal b 8 in
  let prob_last = if key then 0 else literal b 8 in
  let prob_golden = if key then 0 else literal b 8 in
  if not key then (
    if flag b then for i = 0 to 3 do t.ymode_probs.(i) <- literal b 8 done;
    if flag b then for i = 0 to 2 do t.uv_probs.(i) <- literal b 8 done;
    for i = 0 to 1 do
      for j = 0 to 18 do
        if bool b mv_update_probs.(i).(j) then (
          let x = literal b 7 in
          t.mv_probs.(i).(j) <- (if x <> 0 then x lsl 1 else 1))
      done
    done);
  (* the frame being made, and where its predicted blocks come from *)
  let cur = { y = Bytes.make (ys * mbh * 16) '\000'; u = Bytes.make (cs * mbh * 8) '\000'; v = Bytes.make (cs * mbh * 8) '\000' } in
  let reference (r : int) : planes = Option.get (match r with 1 -> t.last | 2 -> t.golden | _ -> t.altref) in
  let filters = if version = 0 then sixtap else bilinear and full_pixel = version = 3 in
  let stride = mbw + 1 in
  let above_modes = Array.make (mbw * 4) b_dc and left_modes = Array.make 4 b_dc in
  let above_nz = Array.make (mbw * 9) 0 and left_nz = Array.make 9 0 in
  let inner = Array.make (mbw * mbh) false in
  let c = Array.make (25 * 16) 0 in
  let modes = Array.make 16 b_dc in
  for my = 0 to mbh - 1 do
    let tk = tokens.(my land (count - 1)) in
    Array.fill left_modes 0 4 b_dc;
    Array.fill left_nz 0 9 0;
    for mx = 0 to mbw - 1 do
      let i = ((my + 1) * stride) + mx + 1 in
      let above = i - stride and left = i - 1 in
      (* its segment, kept from the frame before unless this one says *)
      if update_map then t.segments.(i) <- (if not (bool b t.segment_probs.(0)) then bit b t.segment_probs.(1) else 2 + bit b t.segment_probs.(2))
      else if key then t.segments.(i) <- 0;
      let segment = t.segments.(i) in
      let skipped = match skip_prob with Some p -> bool b p | None -> false in
      let uvmode = ref dc_pred in
      t.refs.(i) <- 0;
      t.mvx.(i) <- 0;
      t.mvy.(i) <- 0;
      (* guessed from its neighbours in this frame: its mode, as a still's *)
      let intra ~(contexts : bool) : unit =
        let ymode =
          if contexts then if not (bool b 145) then b_pred else if bool b 156 then if bool b 128 then tm_pred else h_pred else if bool b 163 then v_pred else dc_pred
          else tree b ymode_tree (fun k -> t.ymode_probs.(k))
        in
        t.ymodes.(i) <- ymode;
        if ymode = b_pred then
          for k = 0 to 15 do
            modes.(k) <-
              (if contexts then (
                 let a = if k < 4 then above_modes.((mx * 4) + k) else modes.(k - 4) and l = if k land 3 = 0 then left_modes.(k / 4) else modes.(k - 1) in
                 tree b bmode_tree (fun n -> Vp8_tables.kf_bmode_probs.((((a * 10) + l) * 9) + n)))
               else tree b bmode_tree (fun n -> default_bmode_probs.(n)))
          done
        else Array.fill modes 0 16 (if ymode = dc_pred then b_dc else if ymode = v_pred then b_ve else if ymode = h_pred then b_he else b_tm);
        for k = 0 to 3 do
          above_modes.((mx * 4) + k) <- modes.(12 + k);
          left_modes.(k) <- modes.((4 * k) + 3)
        done;
        uvmode :=
          if contexts then if not (bool b 142) then dc_pred else if not (bool b 114) then v_pred else if bool b 183 then tm_pred else h_pred
          else tree b uv_mode_tree (fun k -> t.uv_probs.(k))
      in
      (* predicted from another frame: which, and by what vector *)
      let inter () : unit =
        let r = if bool b prob_last then 2 + bit b prob_golden else 1 in
        t.refs.(i) <- r;
        (* the neighbours' vectors, the most used first: above, left,
         * above left; counted 2, 2 and 1; one of a frame of the other
         * sign turned round *)
        let near = Array.make 4 (0, 0) and cnt = Array.make 4 0 and n = ref 0 in
        let vector j = if sign_bias.(t.refs.(j)) <> sign_bias.(r) then (-t.mvx.(j), -t.mvy.(j)) else (t.mvx.(j), t.mvy.(j)) in
        let neighbour j weight ~first =
          if t.refs.(j) <> 0 then
            if t.mvx.(j) <> 0 || t.mvy.(j) <> 0 then (
              let v = vector j in
              if first || v <> near.(!n) then (incr n; near.(!n) <- v);
              cnt.(!n) <- cnt.(!n) + weight)
            else cnt.(0) <- cnt.(0) + weight
        in
        neighbour above 2 ~first:true;
        neighbour left 2 ~first:false;
        neighbour (above - 1) 1 ~first:false;
        (* three different ones: the last may be the first again *)
        if cnt.(3) > 0 && near.(!n) = near.(1) then cnt.(1) <- cnt.(1) + 1;
        let is_split j = if t.ymodes.(j) = split_mv then 1 else 0 in
        cnt.(3) <- ((is_split above + is_split left) * 2) + is_split (above - 1);
        if cnt.(2) > cnt.(1) then (
          let k = cnt.(1) and v = near.(1) in
          cnt.(1) <- cnt.(2);
          near.(1) <- near.(2);
          cnt.(2) <- k;
          near.(2) <- v);
        if cnt.(1) >= cnt.(0) then near.(0) <- near.(1);
        (* a vector kept from pointing more than a macroblock outside the frame *)
        let clamp (x, y) = (clip (-((mx + 1) lsl 7)) ((mbw - mx) lsl 7) x, clip (-((my + 1) lsl 7)) ((mbh - my) lsl 7) y) in
        let mode = tree b mv_ref_tree (fun k -> mv_counts_to_probs.(cnt.(k)).(k)) in
        t.ymodes.(i) <- mode;
        let set (x, y) = t.mvx.(i) <- x; t.mvy.(i) <- y in
        if mode = nearest_mv then set (clamp near.(1))
        else if mode = near_mv then set (clamp near.(2))
        else if mode = new_mv then (
          let bx, by = clamp near.(0) in
          let dx, dy = read_mv b t.mv_probs in
          set (bx + dx, by + dy))
        else if mode = split_mv then (
          let bx, by = clamp near.(0) in
          let part = partitions.(tree b split_tree (fun k -> split_probs.(k))) in
          let parts = 1 + Array.fold_left max 0 part in
          let sub j k = (t.sub_x.((16 * j) + k), t.sub_y.((16 * j) + k)) in
          let whole j = (t.mvx.(j), t.mvy.(j)) in
          for p = 0 to parts - 1 do
            (* its first block: the vectors on its left and above it *)
            let k = ref 0 in
            while part.(!k) <> p do incr k done;
            let k = !k in
            let l = if k land 3 = 0 then if t.ymodes.(left) = split_mv then sub left (k + 3) else whole left else sub i (k - 1) in
            let a = if k < 4 then if t.ymodes.(above) = split_mv then sub above (k + 12) else whole above else sub i (k - 4) in
            let context = if l = a then if l = (0, 0) then 4 else 3 else if a = (0, 0) then 2 else if l = (0, 0) then 1 else 0 in
            let x, y =
              match tree b sub_tree (fun n -> sub_probs.(context).(n)) with
              | 0 -> l
              | 1 -> a
              | 2 -> (0, 0)
              | _ ->
                  let dx, dy = read_mv b t.mv_probs in
                  (bx + dx, by + dy)
            in
            Array.iteri (fun k q -> if q = p then (t.sub_x.((16 * i) + k) <- x; t.sub_y.((16 * i) + k) <- y)) part
          done;
          set (sub i 15))
      in
      if key then intra ~contexts:true else if bool b prob_inter then inter () else intra ~contexts:false;
      let ymode = t.ymodes.(i) in
      let whole = ymode <> b_pred && ymode <> split_mv in
      (* its coefficients *)
      Array.fill c 0 400 0;
      let q_y_dc, q_y_ac, q_y2_dc, q_y2_ac, q_uv_dc, q_uv_ac = quantizers.(segment) in
      let any = ref false in
      let an = mx * 9 in
      if skipped then (
        for k = 0 to 7 do above_nz.(an + k) <- 0; left_nz.(k) <- 0 done;
        if whole then (above_nz.(an + 8) <- 0; left_nz.(8) <- 0))
      else (
        let first =
          if not whole then 0
          else (
            let y2 = Array.make 16 0 in
            let n = coefficients tk t.coeff_probs ~kind:1 ~ctx:(above_nz.(an + 8) + left_nz.(8)) ~dc:q_y2_dc ~ac:q_y2_ac ~first:0 y2 0 in
            above_nz.(an + 8) <- (if n > 0 then 1 else 0);
            left_nz.(8) <- above_nz.(an + 8);
            inverse_wht y2 c;
            1)
        in
        for k = 0 to 15 do
          let bx = k land 3 and by = k lsr 2 in
          let n = coefficients tk t.coeff_probs ~kind:(if whole then 0 else 3) ~ctx:(above_nz.(an + bx) + left_nz.(by)) ~dc:q_y_dc ~ac:q_y_ac ~first c (16 * k) in
          let nz = if n > first then 1 else 0 in
          above_nz.(an + bx) <- nz;
          left_nz.(by) <- nz;
          if nz = 1 || c.(16 * k) <> 0 then any := true
        done;
        for k = 0 to 7 do
          let plane = k / 4 and bx = k land 1 and by = (k lsr 1) land 1 in
          let n = coefficients tk t.coeff_probs ~kind:2 ~ctx:(above_nz.(an + 4 + (2 * plane) + bx) + left_nz.(4 + (2 * plane) + by)) ~dc:q_uv_dc ~ac:q_uv_ac ~first:0 c (16 * (16 + k)) in
          let nz = if n > 0 then 1 else 0 in
          above_nz.(an + 4 + (2 * plane) + bx) <- nz;
          left_nz.(4 + (2 * plane) + by) <- nz;
          if nz = 1 then any := true
        done);
      inner.((my * mbw) + mx) <- (not whole) || !any;
      (* the picture: what is guessed or predicted, and the differences added *)
      let x0 = mx * 16 and y0 = my * 16 in
      if t.refs.(i) = 0 then (
        if ymode = b_pred then
          for k = 0 to 15 do
            let bx = k land 3 and by = k lsr 2 in
            predict_4x4 cur.y ys (x0 + (4 * bx)) (y0 + (4 * by)) ~right_y:(if bx = 3 then y0 - 1 else y0 + (4 * by) - 1) modes.(k);
            add_residue c (16 * k) cur.y ys (x0 + (4 * bx)) (y0 + (4 * by))
          done
        else (
          predict_block cur.y ys x0 y0 16 ymode;
          for k = 0 to 15 do add_residue c (16 * k) cur.y ys (x0 + (4 * (k land 3))) (y0 + (4 * (k lsr 2))) done);
        predict_block cur.u cs (mx * 8) (my * 8) 8 !uvmode;
        predict_block cur.v cs (mx * 8) (my * 8) 8 !uvmode;
        for k = 0 to 7 do
          add_residue c (16 * (16 + k)) (if k < 4 then cur.u else cur.v) cs ((mx * 8) + (4 * (k land 1))) ((my * 8) + (4 * ((k lsr 1) land 1)))
        done)
      else (
        let from = reference t.refs.(i) in
        let luma k = if ymode = split_mv then (t.sub_x.((16 * i) + k), t.sub_y.((16 * i) + k)) else (t.mvx.(i), t.mvy.(i)) in
        for k = 0 to 15 do
          let x = x0 + (4 * (k land 3)) and y = y0 + (4 * (k lsr 2)) in
          inter_block cur.y from.y ~stride:ys ~w:ys ~h:(mbh * 16) x y (luma k) filters;
          add_residue c (16 * k) cur.y ys x y
        done;
        (* a chroma block is four luma blocks: their vectors' mean, in
         * eighths of the half-size plane, rounded away from zero *)
        let chroma k =
          let x, y =
            if ymode = split_mv then (
              let first = (2 * (k land 1)) + (8 * (k lsr 1)) in
              let mean (a : int array) =
                let sum = a.((16 * i) + first) + a.((16 * i) + first + 1) + a.((16 * i) + first + 4) + a.((16 * i) + first + 5) in
                (if sum < 0 then sum - 4 else sum + 4) / 8
              in
              (mean t.sub_x, mean t.sub_y))
            else
              let half v = (v + (if v < 0 then -1 else 1)) / 2 in
              (half t.mvx.(i), half t.mvy.(i))
          in
          if full_pixel then (x land lnot 7, y land lnot 7) else (x, y)
        in
        for k = 0 to 3 do
          let x = (mx * 8) + (4 * (k land 1)) and y = (my * 8) + (4 * (k lsr 1)) and mv = chroma k in
          inter_block cur.u from.u ~stride:cs ~w:cs ~h:(mbh * 8) x y mv filters;
          add_residue c (16 * (16 + k)) cur.u cs x y;
          inter_block cur.v from.v ~stride:cs ~w:cs ~h:(mbh * 8) x y mv filters;
          add_residue c (16 * (20 + k)) cur.v cs x y
        done)
    done
  done;
  (* the edges between blocks smoothed, each macroblock by its own
   * strength: the frame's, its segment's, and what its reference and
   * its mode add *)
  for my = 0 to mbh - 1 do
    for mx = 0 to mbw - 1 do
      let i = ((my + 1) * stride) + mx + 1 in
      let l = if not t.segmented then level else if t.seg_abs then t.seg_filter.(t.segments.(i)) else level + t.seg_filter.(t.segments.(i)) in
      let l = clip 0 63 l in
      let l =
        if not delta_enabled then l
        else
          let m = t.ymodes.(i) in
          l + t.ref_delta.(t.refs.(i))
          + (if t.refs.(i) = 0 then if m = b_pred then t.mode_delta.(0) else 0 else if m = zero_mv then t.mode_delta.(1) else if m = split_mv then t.mode_delta.(3) else t.mode_delta.(2))
      in
      let l = clip 0 63 l in
      (* a frame of level 0 is not filtered at all, whatever is added *)
      if level > 0 && l > 0 then (
        let limit = if sharpness > 4 then l lsr 2 else if sharpness > 0 then l lsr 1 else l in
        let limit = max 1 (if sharpness > 0 then min limit (9 - sharpness) else limit) in
        let hev = (if l >= 15 then 1 else 0) + (if l >= 40 then 1 else 0) + if l >= 20 && not key then 1 else 0 in
        filter_macroblock ~simple cur.y cur.u cur.v ~ys ~cs ~mx ~my ((2 * l) + limit, limit, hev) ~inner_edges:inner.((my * mbw) + mx))
    done
  done;
  (* its probabilities were its own *)
  Option.iter
    (fun (coeff, mv, ymode, uv) ->
      t.coeff_probs <- coeff;
      t.mv_probs <- mv;
      t.ymode_probs <- ymode;
      t.uv_probs <- uv)
    saved;
  (* the frames it becomes: copies between the old ones first *)
  (match copy_altref with 1 -> t.altref <- t.last | 2 -> t.altref <- t.golden | _ -> ());
  (match copy_golden with 1 -> t.golden <- t.last | 2 -> t.golden <- t.altref | _ -> ());
  if refresh_golden then t.golden <- Some cur;
  if refresh_altref then t.altref <- Some cur;
  if refresh_last then t.last <- Some cur;
  if show then t.shown <- Some cur;
  show

(*****************************************************************************)
(* What was decoded *)
(*****************************************************************************)

let size (t : t) : int * int = (t.width, t.height)

let picture (t : t) : Rgba_image.t =
  match t.shown with
  | Some f -> image ~width:t.width ~height:t.height ~ys:(t.mbw * 16) ~cs:(t.mbw * 8) f.y f.u f.v
  | None -> failwith "Vp8_video: no frame decoded"

(* the frame shown as raw video is written: its luma, row by row, then
 * each chroma, the size's own (what was decoded past it left out) *)
let yuv (t : t) : string =
  match t.shown with
  | None -> failwith "Vp8_video: no frame decoded"
  | Some f ->
      let out = Buffer.create (t.width * t.height * 3 / 2) in
      let plane (p : Bytes.t) (stride : int) (w : int) (h : int) = for y = 0 to h - 1 do Buffer.add_subbytes out p (y * stride) w done in
      plane f.y (t.mbw * 16) t.width t.height;
      plane f.u (t.mbw * 8) ((t.width + 1) / 2) ((t.height + 1) / 2);
      plane f.v (t.mbw * 8) ((t.width + 1) / 2) ((t.height + 1) / 2);
      Buffer.contents out

(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Vp8.mli *)

(*****************************************************************************)
(* The boolean decoder *)
(*****************************************************************************)

(* an arithmetic decoder of yes and no: [value] is where the number
 * coded falls in the current interval, [range] the interval's width
 * (RFC 6386, section 7.3) *)
type bools = { data : string; mutable pos : int; limit : int; mutable range : int; mutable value : int; mutable count : int }

let byte (b : bools) : int =
  let v = if b.pos < b.limit then Char.code (String.unsafe_get b.data b.pos) else 0 in
  b.pos <- b.pos + 1;
  v

let bools (data : string) (from : int) (size : int) : bools =
  let b = { data; pos = from; limit = min (String.length data) (from + size); range = 255; value = 0; count = 0 } in
  let hi = byte b in
  b.value <- (hi lsl 8) lor byte b;
  b

(* a yes or a no whose chance of being no is [prob] out of 256 *)
let bool (b : bools) (prob : int) : bool =
  let split = 1 + (((b.range - 1) * prob) lsr 8) in
  let big = split lsl 8 in
  let yes = b.value >= big in
  if yes then (
    b.range <- b.range - split;
    b.value <- b.value - big)
  else b.range <- split;
  while b.range < 128 do
    b.value <- b.value lsl 1;
    b.range <- b.range lsl 1;
    b.count <- b.count + 1;
    if b.count = 8 then (
      b.count <- 0;
      b.value <- b.value lor byte b)
  done;
  yes

let bit (b : bools) (prob : int) : int = if bool b prob then 1 else 0
let flag (b : bools) : bool = bool b 128

(* a number of [n] bits, the highest first, each as likely 0 as 1 *)
let literal (b : bools) (n : int) : int =
  let v = ref 0 in
  for _ = 1 to n do v := (!v lsl 1) lor bit b 128 done;
  !v

let signed (b : bools) (n : int) : int = let v = literal b n in if flag b then -v else v

(* a leaf of a tree of choices: at each node the next bool, by that
 * node's probability, picks a branch; a leaf is written -value *)
let tree (b : bools) (t : int array) (probs : int -> int) : int =
  let rec go i = let next = t.(i + bit b (probs (i lsr 1))) in if next > 0 then go next else -next in
  go 0

(*****************************************************************************)
(* The frame's header *)
(*****************************************************************************)

type header = {
  width : int;
  height : int;
  update_map : bool; (* each macroblock says its segment *)
  segment_probs : int array;
  quantizers : (int * int * int * int * int * int) array; (* a segment's: y dc, y ac, y2 dc, y2 ac, uv dc, uv ac *)
  simple_filter : bool;
  filters : (int * int * int) array; (* a segment's and (16 x 16, or 4 x 4) a mode's: limit, inner limit, high edge variance threshold; limit 0: none *)
  partitions : (int * int) array; (* where each of the coefficients' partitions is, and its size *)
  coeff_probs : int array; (* [4] [8] [3] [11] *)
  skip_prob : int option;
  first : bools; (* the first partition, at the macroblocks' modes *)
}

let clip (lo : int) (hi : int) (v : int) : int = if v < lo then lo else if v > hi then hi else v

let header (s : string) : header =
  if String.length s < 10 then failwith "Vp8: too short";
  let tag = Char.code s.[0] lor (Char.code s.[1] lsl 8) lor (Char.code s.[2] lsl 16) in
  if tag land 1 <> 0 then failwith "Vp8: not a key frame";
  if s.[3] <> '\x9d' || s.[4] <> '\x01' || s.[5] <> '\x2a' then failwith "Vp8: no start code";
  let width = (Char.code s.[6] lor (Char.code s.[7] lsl 8)) land 0x3fff and height = (Char.code s.[8] lor (Char.code s.[9] lsl 8)) land 0x3fff in
  if width = 0 || height = 0 then failwith "Vp8: a picture of no size";
  let first_size = tag lsr 5 in
  let b = bools s 10 first_size in
  let (_ : int) = literal b 2 in
  (* the colour space and whether to clamp: one of each exists *)
  let segmented = flag b in
  let update_map = segmented && flag b in
  let absolute, seg_quant, seg_filter =
    if segmented && flag b then
      let absolute = flag b in
      let q = Array.init 4 (fun _ -> if flag b then signed b 7 else 0) in
      (absolute, q, Array.init 4 (fun _ -> if flag b then signed b 6 else 0))
    else (false, Array.make 4 0, Array.make 4 0)
  in
  let segment_probs = if update_map then Array.init 3 (fun _ -> if flag b then literal b 8 else 255) else [| 255; 255; 255 |] in
  let simple_filter = flag b in
  let level = literal b 6 in
  let sharpness = literal b 3 in
  (* a filter's level may be changed by the macroblock's mode: the two
   * that count in a key frame are "intra" and "4 x 4" *)
  let ref_delta = ref 0 and mode_delta = ref 0 in
  if flag b && flag b then (
    for i = 0 to 3 do if flag b then (let d = signed b 6 in if i = 0 then ref_delta := d) done;
    for i = 0 to 3 do if flag b then (let d = signed b 6 in if i = 0 then mode_delta := d) done);
  let use_deltas = !ref_delta <> 0 || !mode_delta <> 0 in
  let count = 1 lsl literal b 2 in
  let base = literal b 7 in
  let delta () = if flag b then signed b 4 else 0 in
  let y_dc = delta () in
  let y2_dc = delta () in
  let y2_ac = delta () in
  let uv_dc = delta () in
  let uv_ac = delta () in
  let (_ : bool) = flag b in
  let quantizers =
    Array.init 4 (fun i ->
        let q = if not segmented then base else if absolute then seg_quant.(i) else base + seg_quant.(i) in
        let dc d = Vp8_tables.dc_q.(clip 0 127 (q + d)) and ac d = Vp8_tables.ac_q.(clip 0 127 (q + d)) in
        (dc y_dc, ac 0, 2 * dc y2_dc, max 8 ((ac y2_ac * 101581) lsr 16), Vp8_tables.dc_q.(clip 0 117 (q + uv_dc)), ac uv_ac))
  in
  let filters =
    Array.init 8 (fun k ->
        let seg = k / 2 and small = k land 1 = 1 in
        let l = if not segmented then level else if absolute then seg_filter.(seg) else level + seg_filter.(seg) in
        let l = if use_deltas then l + !ref_delta + (if small then !mode_delta else 0) else l in
        let l = clip 0 63 l in
        (* a frame of level 0 is not filtered at all, whatever is added *)
        if l = 0 || level = 0 then (0, 0, 0)
        else
          let inner = if sharpness > 4 then l lsr 2 else if sharpness > 0 then l lsr 1 else l in
          let inner = max 1 (if sharpness > 0 then min inner (9 - sharpness) else inner) in
          ((2 * l) + inner, inner, if l >= 40 then 2 else if l >= 15 then 1 else 0))
  in
  let coeff_probs = Array.copy Vp8_tables.default_coeff_probs in
  Array.iteri (fun i update -> if bool b update then coeff_probs.(i) <- literal b 8) Vp8_tables.coeff_update_probs;
  let skip_prob = if flag b then Some (literal b 8) else None in
  (* the partitions of coefficients: after the first, their sizes (but
   * the last's, which is what is left), then they *)
  let sizes_at = 10 + first_size in
  let data_at = sizes_at + (3 * (count - 1)) in
  if data_at > String.length s then failwith "Vp8: cut short";
  let at = ref data_at in
  let partitions =
    Array.init count (fun i ->
        let from = !at in
        let size =
          if i < count - 1 then Char.code s.[sizes_at + (3 * i)] lor (Char.code s.[sizes_at + (3 * i) + 1] lsl 8) lor (Char.code s.[sizes_at + (3 * i) + 2] lsl 16)
          else String.length s - from
        in
        at := from + size;
        (from, size))
  in
  { width; height; update_map; segment_probs; quantizers; simple_filter; filters; partitions; coeff_probs; skip_prob; first = b }

(*****************************************************************************)
(* A macroblock's modes, and its coefficients *)
(*****************************************************************************)

(* the 16 x 16 and chroma modes, and the ten of a 4 x 4 block: the
 * RFC's numbers *)
let dc_pred = 0 and v_pred = 1 and h_pred = 2 and tm_pred = 3
let b_dc = 0 and b_tm = 1 and b_ve = 2 and b_he = 3 and b_ld = 4 and b_rd = 5 and b_vr = 6 and b_vl = 7 and b_hd = 8 and b_hu = 9
let bmode_tree = [| -b_dc; 2; -b_tm; 4; -b_ve; 6; 8; 12; -b_he; 10; -b_rd; -b_vr; -b_ld; 14; -b_vl; 16; -b_hd; -b_hu |]

(* where the coefficients of a block go, read along its diagonals *)
let zigzag = [| 0; 1; 4; 8; 5; 2; 3; 6; 9; 12; 13; 10; 7; 11; 14; 15 |]

(* a coefficient's place gives its band of probabilities *)
let bands = [| 0; 1; 2; 3; 6; 4; 5; 6; 6; 6; 6; 6; 6; 6; 6; 7; 0 |]

(* the extra bits of the large values, each with its probability *)
let categories = [| [| 173; 148; 140 |]; [| 176; 155; 140; 135 |]; [| 180; 157; 141; 134; 130 |]; [| 254; 254; 243; 230; 196; 177; 153; 140; 133; 130; 129 |] |]

(* a block's coefficients read into [out] at [at], from the [first]:
 * each a token (end, zero, one, or larger: a value and maybe extra
 * bits), its probabilities chosen by the plane's [kind], the place's
 * band and what came before ([ctx]: nothing, a one, larger). How many
 * were read: more than [first] if the block has any *)
let coefficients (b : bools) (probs : int array) ~(kind : int) ~(ctx : int) ~(dc : int) ~(ac : int) ~(first : int) (out : int array) (at : int) : int =
  let p n ctx i = probs.((((((kind * 8) + bands.(n)) * 3) + ctx) * 11) + i) in
  let rec go n ctx =
    if n >= 16 then 16
    else if not (bool b (p n ctx 0)) then n
    else
      (* zeros, each read in the context "after a zero" *)
      let rec zeros n ctx = if n < 16 && not (bool b (p n ctx 1)) then zeros (n + 1) 0 else (n, ctx) in
      let n, ctx = zeros n ctx in
      if n >= 16 then 16
      else
        let v =
          if not (bool b (p n ctx 2)) then 1
          else if not (bool b (p n ctx 3)) then if not (bool b (p n ctx 4)) then 2 else 3 + bit b (p n ctx 5)
          else if not (bool b (p n ctx 6)) then
            if not (bool b (p n ctx 7)) then 5 + bit b 159
            else
              let hi = bit b 165 in
              7 + (2 * hi) + bit b 145
          else
            let b1 = bit b (p n ctx 8) in
            let b0 = bit b (p n ctx (9 + b1)) in
            let cat = (2 * b1) + b0 in
            3 + (8 lsl cat) + Array.fold_left (fun v prob -> (2 * v) + bit b prob) 0 categories.(cat)
        in
        let v = if flag b then -v else v in
        out.(at + zigzag.(n)) <- v * (if n = 0 then dc else ac);
        go (n + 1) (if abs v = 1 then 1 else 2)
  in
  go first ctx

(*****************************************************************************)
(* The inverse transforms *)
(*****************************************************************************)

(* the Y2 block's sixteen numbers are the sixteen luma blocks' first
 * coefficients, mixed by a Walsh-Hadamard transform: unmixed *)
let inverse_wht (y2 : int array) (out : int array) : unit =
  let t = Array.make 16 0 in
  for i = 0 to 3 do
    let a0 = y2.(i) + y2.(12 + i) and a1 = y2.(4 + i) + y2.(8 + i) and a2 = y2.(4 + i) - y2.(8 + i) and a3 = y2.(i) - y2.(12 + i) in
    t.(i) <- a0 + a1;
    t.(8 + i) <- a0 - a1;
    t.(4 + i) <- a3 + a2;
    t.(12 + i) <- a3 - a2
  done;
  for i = 0 to 3 do
    let dc = t.(4 * i) + 3 in
    let a0 = dc + t.((4 * i) + 3) and a1 = t.((4 * i) + 1) + t.((4 * i) + 2) and a2 = t.((4 * i) + 1) - t.((4 * i) + 2) and a3 = dc - t.((4 * i) + 3) in
    out.(16 * (4 * i)) <- (a0 + a1) asr 3;
    out.(16 * ((4 * i) + 1)) <- (a3 + a2) asr 3;
    out.(16 * ((4 * i) + 2)) <- (a0 - a1) asr 3;
    out.(16 * ((4 * i) + 3)) <- (a3 - a2) asr 3
  done

(* a block's coefficients back to sixteen differences, added to what
 * was predicted at (x, y) of a plane: the inverse of a 4 x 4 cosine
 * transform, in integers (RFC 6386, section 14.4) *)
let add_residue (c : int array) (at : int) (plane : Bytes.t) (stride : int) (x : int) (y : int) : unit =
  let mul1 a = ((a * 20091) asr 16) + a and mul2 a = (a * 35468) asr 16 in
  let t = Array.make 16 0 in
  for i = 0 to 3 do
    let i0 = c.(at + i) and i4 = c.(at + 4 + i) and i8 = c.(at + 8 + i) and i12 = c.(at + 12 + i) in
    let a = i0 + i8 and b = i0 - i8 and cc = mul2 i4 - mul1 i12 and d = mul1 i4 + mul2 i12 in
    t.(4 * i) <- a + d;
    t.((4 * i) + 1) <- b + cc;
    t.((4 * i) + 2) <- b - cc;
    t.((4 * i) + 3) <- a - d
  done;
  for i = 0 to 3 do
    let dc = t.(i) + 4 in
    let a = dc + t.(8 + i) and b = dc - t.(8 + i) and cc = mul2 t.(4 + i) - mul1 t.(12 + i) and d = mul1 t.(4 + i) + mul2 t.(12 + i) in
    let put dx v =
      let o = ((y + i) * stride) + x + dx in
      Bytes.unsafe_set plane o (Char.unsafe_chr (clip 0 255 (Char.code (Bytes.unsafe_get plane o) + (v asr 3))))
    in
    put 0 (a + d);
    put 1 (b + cc);
    put 2 (b - cc);
    put 3 (a - d)
  done

(*****************************************************************************)
(* Prediction *)
(*****************************************************************************)

(* a pixel of a plane; outside it, what the format says is there: 127
 * above the picture, 129 on its left *)
let px (plane : Bytes.t) (stride : int) (x : int) (y : int) : int =
  if y < 0 then 127 else if x < 0 then 129 else Char.code (Bytes.unsafe_get plane ((y * stride) + x))

let set (plane : Bytes.t) (stride : int) (x : int) (y : int) (v : int) : unit = Bytes.unsafe_set plane ((y * stride) + x) (Char.unsafe_chr v)

(* a square block of [size] at (x0, y0) guessed from the row above it
 * and the column on its left: their mean (DC), the row repeated down
 * (V), the column repeated across (H), or both less their corner (TM) *)
let predict_block (plane : Bytes.t) (stride : int) (x0 : int) (y0 : int) (size : int) (mode : int) : unit =
  let get = px plane stride in
  let fill f = for j = 0 to size - 1 do for i = 0 to size - 1 do set plane stride (x0 + i) (y0 + j) (f i j) done done in
  if mode = dc_pred then (
    (* the mean of the neighbours that exist; none: grey *)
    let top = y0 > 0 and left = x0 > 0 in
    let sum f = let s = ref 0 in for i = 0 to size - 1 do s := !s + f i done; !s in
    let shift = if size = 16 then 4 else 3 in
    let v =
      match (top, left) with
      | true, true -> (sum (fun i -> get (x0 + i) (y0 - 1)) + sum (fun j -> get (x0 - 1) (y0 + j)) + size) asr (shift + 1)
      | true, false -> (sum (fun i -> get (x0 + i) (y0 - 1)) + (size / 2)) asr shift
      | false, true -> (sum (fun j -> get (x0 - 1) (y0 + j)) + (size / 2)) asr shift
      | false, false -> 128
    in
    fill (fun _ _ -> v))
  else if mode = v_pred then fill (fun i _ -> get (x0 + i) (y0 - 1))
  else if mode = h_pred then fill (fun _ j -> get (x0 - 1) (y0 + j))
  else
    let corner = get (x0 - 1) (y0 - 1) in
    fill (fun i j -> clip 0 255 (get (x0 - 1) (y0 + j) + get (x0 + i) (y0 - 1) - corner))

(* a 4 x 4 luma block guessed, by one of ten ways, from the 4 pixels on
 * its left (i to l), its corner (x), the 4 above (a to d) and the 4
 * above on its right (e to h, at [right_y]: the row above the
 * macroblock for its last column of blocks) *)
let predict_4x4 (plane : Bytes.t) (stride : int) (x0 : int) (y0 : int) ~(right_y : int) (mode : int) : unit =
  let get = px plane stride in
  let width = stride in
  let a = get x0 (y0 - 1) and b = get (x0 + 1) (y0 - 1) and c = get (x0 + 2) (y0 - 1) and d = get (x0 + 3) (y0 - 1) in
  (* past the picture's right edge: the last pixel above, again *)
  let right k = if x0 + 4 + k < width then get (x0 + 4 + k) right_y else get (width - 1) right_y in
  let e = right 0 and f = right 1 and g = right 2 and h = right 3 in
  let i = get (x0 - 1) y0 and j = get (x0 - 1) (y0 + 1) and k = get (x0 - 1) (y0 + 2) and l = get (x0 - 1) (y0 + 3) in
  let x = get (x0 - 1) (y0 - 1) in
  let avg2 p q = (p + q + 1) asr 1 and avg3 p q r = (p + (2 * q) + r + 2) asr 2 in
  let put dx dy v = set plane stride (x0 + dx) (y0 + dy) v in
  let fill f = for dy = 0 to 3 do for dx = 0 to 3 do put dx dy (f dx dy) done done in
  if mode = b_dc then (let v = (a + b + c + d + i + j + k + l + 4) asr 3 in fill (fun _ _ -> v))
  else if mode = b_tm then (
    let top = [| a; b; c; d |] and left = [| i; j; k; l |] in
    fill (fun dx dy -> clip 0 255 (left.(dy) + top.(dx) - x)))
  else if mode = b_ve then (
    let row = [| avg3 x a b; avg3 a b c; avg3 b c d; avg3 c d e |] in
    fill (fun dx _ -> row.(dx)))
  else if mode = b_he then (
    let col = [| avg3 x i j; avg3 i j k; avg3 j k l; avg3 k l l |] in
    fill (fun _ dy -> col.(dy)))
  else if mode = b_ld then (
    (* down and to the left: each diagonal one value, from the row above *)
    let v = [| avg3 a b c; avg3 b c d; avg3 c d e; avg3 d e f; avg3 e f g; avg3 f g h; avg3 g h h |] in
    fill (fun dx dy -> v.(dx + dy)))
  else if mode = b_rd then (
    (* down and to the right: from the left column, the corner, the row *)
    let v = [| avg3 j k l; avg3 i j k; avg3 x i j; avg3 a x i; avg3 b a x; avg3 c b a; avg3 d c b |] in
    fill (fun dx dy -> v.(3 - dy + dx)))
  else if mode = b_vr then (
    put 0 0 (avg2 x a); put 1 2 (avg2 x a);
    put 1 0 (avg2 a b); put 2 2 (avg2 a b);
    put 2 0 (avg2 b c); put 3 2 (avg2 b c);
    put 3 0 (avg2 c d);
    put 0 3 (avg3 k j i);
    put 0 2 (avg3 j i x);
    put 0 1 (avg3 i x a); put 1 3 (avg3 i x a);
    put 1 1 (avg3 x a b); put 2 3 (avg3 x a b);
    put 2 1 (avg3 a b c); put 3 3 (avg3 a b c);
    put 3 1 (avg3 b c d))
  else if mode = b_vl then (
    put 0 0 (avg2 a b);
    put 1 0 (avg2 b c); put 0 2 (avg2 b c);
    put 2 0 (avg2 c d); put 1 2 (avg2 c d);
    put 3 0 (avg2 d e); put 2 2 (avg2 d e);
    put 0 1 (avg3 a b c);
    put 1 1 (avg3 b c d); put 0 3 (avg3 b c d);
    put 2 1 (avg3 c d e); put 1 3 (avg3 c d e);
    put 3 1 (avg3 d e f); put 2 3 (avg3 d e f);
    put 3 2 (avg3 e f g);
    put 3 3 (avg3 f g h))
  else if mode = b_hd then (
    put 0 0 (avg2 i x); put 2 1 (avg2 i x);
    put 0 1 (avg2 j i); put 2 2 (avg2 j i);
    put 0 2 (avg2 k j); put 2 3 (avg2 k j);
    put 0 3 (avg2 l k);
    put 3 0 (avg3 a b c);
    put 2 0 (avg3 x a b);
    put 1 0 (avg3 i x a); put 3 1 (avg3 i x a);
    put 1 1 (avg3 j i x); put 3 2 (avg3 j i x);
    put 1 2 (avg3 k j i); put 3 3 (avg3 k j i);
    put 1 3 (avg3 l k j))
  else (
    (* b_hu *)
    put 0 0 (avg2 i j);
    put 2 0 (avg2 j k); put 0 1 (avg2 j k);
    put 2 1 (avg2 k l); put 0 2 (avg2 k l);
    put 1 0 (avg3 i j k);
    put 3 0 (avg3 j k l); put 1 1 (avg3 j k l);
    put 3 1 (avg3 k l l); put 1 2 (avg3 k l l);
    put 3 2 l; put 2 2 l; put 0 3 l; put 1 3 l; put 2 3 l; put 3 3 l)

(*****************************************************************************)
(* The loop filter *)
(*****************************************************************************)

(* the edge between two blocks, smoothed: [o] is the first pixel after
 * the edge, [step] the way across it. The pixels p3 p2 p1 p0 | q0 q1
 * q2 q3 are changed only where the edge is not a true one of the
 * picture (RFC 6386, section 15) *)
let sclip1 v = clip (-128) 127 v
let sclip2 v = clip (-16) 15 v

let filter_edge (plane : Bytes.t) (o : int) (step : int) ~(simple : bool) ~(macroblock : bool) ~(limit : int) ~(inner : int) ~(hev : int) : unit =
  let get k = Char.code (Bytes.unsafe_get plane (o + (k * step))) in
  let put k v = Bytes.unsafe_set plane (o + (k * step)) (Char.unsafe_chr (clip 0 255 v)) in
  let p1 = get (-2) and p0 = get (-1) and q0 = get 0 and q1 = get 1 in
  let strong = (4 * abs (p0 - q0)) + abs (p1 - q1) <= (2 * limit) + 1 in
  (* two pixels changed, the edge's own *)
  let two () =
    let a = (3 * (q0 - p0)) + sclip1 (p1 - q1) in
    put (-1) (p0 + sclip2 ((a + 3) asr 3));
    put 0 (q0 - sclip2 ((a + 4) asr 3))
  in
  if simple then (if strong then two ())
  else if strong then
    let p3 = get (-4) and p2 = get (-3) and q2 = get 2 and q3 = get 3 in
    if abs (p3 - p2) <= inner && abs (p2 - p1) <= inner && abs (p1 - p0) <= inner && abs (q3 - q2) <= inner && abs (q2 - q1) <= inner && abs (q1 - q0) <= inner then
      (* a sharp step beside the edge: only the edge's two pixels *)
      if abs (p1 - p0) > hev || abs (q1 - q0) > hev then two ()
      else if macroblock then (
        (* between two macroblocks: three pixels each side *)
        let a = sclip1 ((3 * (q0 - p0)) + sclip1 (p1 - q1)) in
        let a1 = ((27 * a) + 63) asr 7 and a2 = ((18 * a) + 63) asr 7 and a3 = ((9 * a) + 63) asr 7 in
        put (-3) (p2 + a3);
        put (-2) (p1 + a2);
        put (-1) (p0 + a1);
        put 0 (q0 - a1);
        put 1 (q1 - a2);
        put 2 (q2 - a3))
      else
        (* between two blocks of a macroblock: two each side *)
        let a = 3 * (q0 - p0) in
        let a1 = sclip2 ((a + 4) asr 3) and a2 = sclip2 ((a + 3) asr 3) in
        let a3 = (a1 + 1) asr 1 in
        put (-2) (p1 + a3);
        put (-1) (p0 + a2);
        put 0 (q0 - a1);
        put 1 (q1 - a3)

(*****************************************************************************)
(* From YUV to RGB *)
(*****************************************************************************)

(* a pixel's colour from its luma and its two chromas (ITU-R BT.601),
 * in integers *)
let rgb (y : int) (u : int) (v : int) : int * int * int =
  let hi a c = (a * c) asr 8 in
  let c8 v = if v < 0 then 0 else if v > 16383 then 255 else v asr 6 in
  (c8 (hi y 19077 + hi v 26149 - 14234), c8 (hi y 19077 - hi u 6419 - hi v 13320 + 8708), c8 (hi y 19077 + hi u 33050 - 17685))

(* a macroblock's edges smoothed, in a frame whose blocks are all
 * there: its left edge, its inner vertical ones, its top edge, its
 * inner horizontal ones. [filter]: the limit, the inner limit and the
 * threshold of a sharp step; a limit of 0: not filtered. The inner
 * edges only if [inner_edges] (the macroblock had coefficients, or was
 * predicted block by block) *)
let filter_macroblock ~(simple : bool) (yp : Bytes.t) (up : Bytes.t) (vp : Bytes.t) ~(ys : int) ~(cs : int) ~(mx : int) ~(my : int) ((limit, inner, hev) : int * int * int)
    ~(inner_edges : bool) : unit =
  if limit > 0 then (
    let edges plane stride x y size ~inner_at =
      let run ~across o step ~macroblock ~limit =
        for k = 0 to size - 1 do filter_edge plane (o + (k * across)) step ~simple ~macroblock ~limit ~inner ~hev done
      in
      let o = (y * stride) + x in
      if mx > 0 then run ~across:stride o 1 ~macroblock:true ~limit:(limit + 4);
      if inner_edges then List.iter (fun d -> run ~across:stride (o + d) 1 ~macroblock:false ~limit) inner_at;
      if my > 0 then run ~across:1 o stride ~macroblock:true ~limit:(limit + 4);
      if inner_edges then List.iter (fun d -> run ~across:1 (o + (d * stride)) stride ~macroblock:false ~limit) inner_at
    in
    edges yp ys (mx * 16) (my * 16) 16 ~inner_at:[ 4; 8; 12 ];
    if not simple then (
      edges up cs (mx * 8) (my * 8) 8 ~inner_at:[ 4 ];
      edges vp cs (mx * 8) (my * 8) 8 ~inner_at:[ 4 ]))

(* the three planes as a picture: each pixel's luma with the chroma of
 * its place between the four chroma samples round it (9, 3, 3 and 1
 * sixteenths) *)
let image ~(width : int) ~(height : int) ~(ys : int) ~(cs : int) (yp : Bytes.t) (up : Bytes.t) (vp : Bytes.t) : Rgba_image.t =
  let img = Rgba_image.create ~width ~height in
  let cw = (width + 1) / 2 and ch = (height + 1) / 2 in
  let chroma plane cx cy = Char.code (Bytes.unsafe_get plane ((clip 0 (ch - 1) cy * cs) + clip 0 (cw - 1) cx)) in
  for y = 0 to height - 1 do
    (* the chroma row nearer, and the other one *)
    let near = y / 2 and far = if y land 1 = 0 then (y / 2) - 1 else (y / 2) + 1 in
    for x = 0 to width - 1 do
      let cnear = x / 2 and cfar = if x land 1 = 0 then (x / 2) - 1 else (x / 2) + 1 in
      let mix plane =
        ((9 * chroma plane cnear near) + (3 * chroma plane cfar near) + (3 * chroma plane cnear far) + chroma plane cfar far + 8) asr 4
      in
      let r, g, bl = rgb (Char.code (Bytes.unsafe_get yp ((y * ys) + x))) (mix up) (mix vp) in
      let o = 4 * ((y * width) + x) in
      img.rgba.{o} <- r;
      img.rgba.{o + 1} <- g;
      img.rgba.{o + 2} <- bl;
      img.rgba.{o + 3} <- 255
    done
  done;
  img

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let decode (s : string) : Rgba_image.t =
  let h = header s in
  let mbw = (h.width + 15) / 16 and mbh = (h.height + 15) / 16 in
  let ys = mbw * 16 and cs = mbw * 8 in
  let yp = Bytes.make (ys * mbh * 16) '\000' and up = Bytes.make (cs * mbh * 8) '\000' and vp = Bytes.make (cs * mbh * 8) '\000' in
  (* what the blocks above and on the left were: their 4 x 4 modes (for
   * the next modes' probabilities), and whether they had coefficients
   * (for the next coefficients'): 4 luma, 2 and 2 chroma, 1 Y2 *)
  let above_modes = Array.make (mbw * 4) b_dc and left_modes = Array.make 4 b_dc in
  let above_nz = Array.make (mbw * 9) 0 and left_nz = Array.make 9 0 in
  (* each macroblock's filter (the header's, by its segment and kind),
   * and whether its inner edges are filtered *)
  let mb_filter = Array.make (mbw * mbh) (0, 0, 0) and mb_inner = Array.make (mbw * mbh) false in
  let c = Array.make (25 * 16) 0 in
  let modes = Array.make 16 b_dc in
  let b = h.first in
  let tokens = Array.map (fun (from, size) -> bools s from size) h.partitions in
  for my = 0 to mbh - 1 do
    let t = tokens.(my land (Array.length tokens - 1)) in
    Array.fill left_modes 0 4 b_dc;
    Array.fill left_nz 0 9 0;
    for mx = 0 to mbw - 1 do
      (* its modes *)
      let segment = if h.update_map then (if not (bool b h.segment_probs.(0)) then bit b h.segment_probs.(1) else 2 + bit b h.segment_probs.(2)) else 0 in
      let skipped = match h.skip_prob with Some p -> bool b p | None -> false in
      let small = not (bool b 145) in
      let ymode =
        if small then (
          for i = 0 to 15 do
            let above = if i < 4 then above_modes.((mx * 4) + i) else modes.(i - 4) and left = if i land 3 = 0 then left_modes.(i / 4) else modes.(i - 1) in
            modes.(i) <- tree b bmode_tree (fun k -> Vp8_tables.kf_bmode_probs.((((above * 10) + left) * 9) + k))
          done;
          dc_pred)
        else
          let m = if bool b 156 then if bool b 128 then tm_pred else h_pred else if bool b 163 then v_pred else dc_pred in
          (* for its neighbours' probabilities, a 16 x 16 mode counts as the 4 x 4 one like it *)
          Array.fill modes 0 16 (if m = dc_pred then b_dc else if m = v_pred then b_ve else if m = h_pred then b_he else b_tm);
          m
      in
      for i = 0 to 3 do
        above_modes.((mx * 4) + i) <- modes.(12 + i);
        left_modes.(i) <- modes.((4 * i) + 3)
      done;
      let uvmode = if not (bool b 142) then dc_pred else if not (bool b 114) then v_pred else if bool b 183 then tm_pred else h_pred in
      (* its coefficients *)
      Array.fill c 0 400 0;
      let y_dc, y_ac, y2_dc, y2_ac, uv_dc, uv_ac = h.quantizers.(segment) in
      let any = ref false in
      let an = mx * 9 in
      if skipped then (
        for i = 0 to 7 do above_nz.(an + i) <- 0; left_nz.(i) <- 0 done;
        if not small then (above_nz.(an + 8) <- 0; left_nz.(8) <- 0))
      else (
        let first =
          if small then 0
          else (
            let y2 = Array.make 16 0 in
            let n = coefficients t h.coeff_probs ~kind:1 ~ctx:(above_nz.(an + 8) + left_nz.(8)) ~dc:y2_dc ~ac:y2_ac ~first:0 y2 0 in
            above_nz.(an + 8) <- (if n > 0 then 1 else 0);
            left_nz.(8) <- above_nz.(an + 8);
            inverse_wht y2 c;
            1)
        in
        for i = 0 to 15 do
          let bx = i land 3 and by = i lsr 2 in
          let n = coefficients t h.coeff_probs ~kind:(if small then 3 else 0) ~ctx:(above_nz.(an + bx) + left_nz.(by)) ~dc:y_dc ~ac:y_ac ~first c (16 * i) in
          let nz = if n > first then 1 else 0 in
          above_nz.(an + bx) <- nz;
          left_nz.(by) <- nz;
          if nz = 1 || c.(16 * i) <> 0 then any := true
        done;
        (* U's four blocks, then V's *)
        for i = 0 to 7 do
          let plane = i / 4 and bx = i land 1 and by = (i lsr 1) land 1 in
          let n = coefficients t h.coeff_probs ~kind:2 ~ctx:(above_nz.(an + 4 + (2 * plane) + bx) + left_nz.(4 + (2 * plane) + by)) ~dc:uv_dc ~ac:uv_ac ~first:0 c (16 * (16 + i)) in
          let nz = if n > 0 then 1 else 0 in
          above_nz.(an + 4 + (2 * plane) + bx) <- nz;
          left_nz.(4 + (2 * plane) + by) <- nz;
          if nz = 1 then any := true
        done);
      mb_filter.((my * mbw) + mx) <- h.filters.((2 * segment) + if small then 1 else 0);
      mb_inner.((my * mbw) + mx) <- small || !any;
      (* the picture: what is guessed, and the differences added *)
      let x0 = mx * 16 and y0 = my * 16 in
      if small then
        for i = 0 to 15 do
          let bx = i land 3 and by = i lsr 2 in
          predict_4x4 yp ys (x0 + (4 * bx)) (y0 + (4 * by)) ~right_y:(if bx = 3 then y0 - 1 else y0 + (4 * by) - 1) modes.(i);
          add_residue c (16 * i) yp ys (x0 + (4 * bx)) (y0 + (4 * by))
        done
      else (
        predict_block yp ys x0 y0 16 ymode;
        for i = 0 to 15 do add_residue c (16 * i) yp ys (x0 + (4 * (i land 3))) (y0 + (4 * (i lsr 2))) done);
      predict_block up cs (mx * 8) (my * 8) 8 uvmode;
      predict_block vp cs (mx * 8) (my * 8) 8 uvmode;
      for i = 0 to 7 do
        add_residue c (16 * (16 + i)) (if i < 4 then up else vp) cs ((mx * 8) + (4 * (i land 1))) ((my * 8) + (4 * ((i lsr 1) land 1)))
      done
    done
  done;
  (* the edges between blocks smoothed, once the whole frame is there *)
  for my = 0 to mbh - 1 do
    for mx = 0 to mbw - 1 do
      filter_macroblock ~simple:h.simple_filter yp up vp ~ys ~cs ~mx ~my mb_filter.((my * mbw) + mx) ~inner_edges:mb_inner.((my * mbw) + mx)
    done
  done;
  image ~width:h.width ~height:h.height ~ys ~cs yp up vp

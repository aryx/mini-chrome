(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Celt_bands.mli *)

open Celt_tables

(*****************************************************************************)
(* Pulses: a band's shape as k steps shared between its n numbers *)
(*****************************************************************************)

(* U(n, 0..k+1): the vectors of n numbers whose first is not negative
 * and whose sizes add up to less than k, counted. U(n,k) = U(n-1,k) +
 * U(n,k-1) + U(n-1,k-1); there are V(n,k) = U(n,k) + U(n,k+1) vectors
 * of k pulses *)
let counts (n : int) (k : int) : int array =
  let row = ref (Array.init (k + 2) (fun j -> if j = 0 then 1 else 0)) in
  for _ = 1 to n do
    let before = !row and next = Array.make (k + 2) 0 in
    for j = 1 to k + 1 do next.(j) <- before.(j) + next.(j - 1) + before.(j - 1) done;
    row := next
  done;
  !row

(* the vector a number stands for, among the V(n,k) *)
let vector_of_index ?(u : int array option) (n : int) (k : int) (index : int) : int array =
  let u = match u with Some u -> u | None -> counts n k in
  let k = ref k and i = ref index in
  Array.init n (fun _ ->
      let negative = !i >= u.(!k + 1) in
      if negative then i := !i - u.(!k + 1);
      let before = !k in
      while u.(!k) > !i do decr k done;
      i := !i - u.(!k);
      (* the row of n - 1, from the row of n *)
      let carry = ref 0 in
      for j = 1 to !k + 1 do
        let next = u.(j) - u.(j - 1) - !carry in
        u.(j - 1) <- !carry;
        carry := next
      done;
      u.(!k + 1) <- !carry;
      if negative then !k - before else before - !k)

let pulses (dec : Range_decoder.t) (n : int) (k : int) : int array =
  let u = counts n k in
  vector_of_index ~u n k (Range_decoder.uint dec (u.(k) + u.(k + 1)))

(*****************************************************************************)
(* A band's numbers, turned *)
(*****************************************************************************)

(* a sum and a difference of neighbours, [stride] apart: two short
 * blocks made a longer one, or back *)
let haar (a : float array) (o : int) (n : int) (stride : int) : unit =
  let s = 0.70710678 in
  for i = 0 to stride - 1 do
    for j = 0 to (n / 2) - 1 do
      let p = o + (stride * 2 * j) + i and q = o + (stride * ((2 * j) + 1)) + i in
      let t1 = s *. a.(p) and t2 = s *. a.(q) in
      a.(p) <- t1 +. t2;
      a.(q) <- t1 -. t2
    done
  done

(* the order of Hadamard's frequencies, for 2, 4, 8 and 16 blocks *)
let order (stride : int) (hadamard : bool) (i : int) : int =
  if not hadamard then i
  else
    (match stride with
     | 2 -> [| 1; 0 |]
     | 4 -> [| 3; 0; 2; 1 |]
     | 8 -> [| 7; 0; 4; 3; 6; 1; 5; 2 |]
     | _ -> [| 15; 0; 8; 7; 12; 3; 11; 4; 14; 1; 9; 6; 13; 2; 10; 5 |]).(i)

(* the blocks' numbers one after the other (each block whole), from
 * their numbers in turn; and back *)
let deinterleave (a : float array) (o : int) (n0 : int) (stride : int) (hadamard : bool) : unit =
  let tmp = Array.make (n0 * stride) 0. in
  for i = 0 to stride - 1 do for j = 0 to n0 - 1 do tmp.((order stride hadamard i * n0) + j) <- a.(o + (j * stride) + i) done done;
  Array.blit tmp 0 a o (n0 * stride)

let interleave (a : float array) (o : int) (n0 : int) (stride : int) (hadamard : bool) : unit =
  let tmp = Array.make (n0 * stride) 0. in
  for i = 0 to stride - 1 do for j = 0 to n0 - 1 do tmp.((j * stride) + i) <- a.(o + (order stride hadamard i * n0) + j) done done;
  Array.blit tmp 0 a o (n0 * stride)

(* a vector made of length [gain] *)
let renormalise (a : float array) (o : int) (n : int) (gain : float) : unit =
  let e = ref 1e-15 in
  for j = o to o + n - 1 do e := !e +. (a.(j) *. a.(j)) done;
  let g = gain /. Float.sqrt !e in
  for j = o to o + n - 1 do a.(j) <- g *. a.(j) done

(* the pulses spread over their neighbours, so that a band of few
 * pulses is not a few lone tones: rotations of neighbours, undone *)
let rotation (a : float array) (o : int) (len : int) (stride : int) (k : int) (spread : int) : unit =
  if 2 * k < len && spread <> 0 then (
    let factor = [| 15; 10; 5 |].(spread - 1) in
    let gain = float_of_int len /. float_of_int (len + (factor * k)) in
    let theta = 0.5 *. gain *. gain in
    let c = Float.cos (0.5 *. Float.pi *. theta) and s = Float.cos (0.5 *. Float.pi *. (1. -. theta)) in
    let stride2 = ref 0 in
    if len >= 8 * stride then (
      stride2 := 1;
      while ((!stride2 * !stride2) + !stride2) * stride + (stride asr 2) < len do incr stride2 done);
    let len = len / stride in
    let turn o stride c s =
      let step i =
        let x1 = a.(o + i) and x2 = a.(o + i + stride) in
        a.(o + i + stride) <- (c *. x2) +. (s *. x1);
        a.(o + i) <- (c *. x1) -. (s *. x2)
      in
      for i = 0 to len - stride - 1 do step i done;
      for i = len - (2 * stride) - 1 downto 0 do step i done
    in
    for i = 0 to stride - 1 do
      if !stride2 > 0 then turn (o + (i * len)) !stride2 s c;
      turn (o + (i * len)) 1 c s
    done)

(* a band's shape from its pulses; which of its blocks have any *)
let shape (dec : Range_decoder.t) (a : float array) (o : int) (n : int) (k : int) (spread : int) (blocks : int) (gain : float) : int =
  let iy = pulses dec n k in
  let g = gain /. Float.sqrt (float_of_int (Array.fold_left (fun s v -> s + (v * v)) 0 iy)) in
  Array.iteri (fun j v -> a.(o + j) <- g *. float_of_int v) iy;
  rotation a o n blocks k spread;
  if blocks <= 1 then 1
  else (
    let n0 = n / blocks and mask = ref 0 in
    for i = 0 to blocks - 1 do for j = 0 to n0 - 1 do if iy.((i * n0) + j) <> 0 then mask := !mask lor (1 lsl i) done done;
    !mask)

(*****************************************************************************)
(* Arithmetic the encoder and the decoder must do alike, to the bit *)
(*****************************************************************************)

let frac_mul (a : int) (b : int) : int = (16384 + (a * b)) asr 15

let cos_ (x : int) : int =
  let x2 = (4096 + (x * x)) asr 13 in
  1 + (32767 - x2) + frac_mul x2 (-7651 + frac_mul x2 (8277 + frac_mul (-626) x2))

let log2tan (isin : int) (icos : int) : int =
  let lc = Range_decoder.ilog icos and ls = Range_decoder.ilog isin in
  let icos = icos lsl (15 - lc) and isin = isin lsl (15 - ls) in
  ((ls - lc) * 2048) + frac_mul isin (frac_mul isin (-2597) + 7932) - frac_mul icos (frac_mul icos (-2597) + 7932)

let isqrt (x : int) : int =
  let r = ref (int_of_float (Float.sqrt (float_of_int x))) in
  while !r * !r > x do decr r done;
  while (!r + 1) * (!r + 1) <= x do incr r done;
  !r

(* how many angles a split's bits allow *)
let angles (n : int) (b : int) (offset : int) (pulse_cap : int) (stereo : bool) : int =
  let n2 = (2 * n) - 1 - if stereo && n = 2 then 1 else 0 in
  let qb = min 64 (min (b - pulse_cap - 32) ((b + (n2 * offset)) / n2)) in
  if qb < 4 then 1 else ((([| 16384; 17866; 19483; 21247; 23170; 25267; 27554; 30048 |].(qb land 7) asr (14 - (qb asr 3))) + 1) asr 1) lsl 1

(*****************************************************************************)
(* A band *)
(*****************************************************************************)

type vector = float array * int (* numbers, from an offset *)

type state = {
  dec : Range_decoder.t;
  mutable remaining : int; (* the frame's bits not yet used, in eighths *)
  mutable seed : int; (* of the noise *)
  spread : int;
  intensity : int;
  scratch : float array;
}

let noise (s : state) : int =
  s.seed <- ((1664525 * s.seed) + 1013904223) land 0xffffffff;
  s.seed

(* two channels from their sum and difference: the mid of length
 * [mid], the side already scaled *)
let stereo_merge ((xa, xo) : vector) ((ya, yo) : vector) (mid : float) (n : int) : unit =
  let xp = ref 0. and side = ref 0. in
  for j = 0 to n - 1 do
    xp := !xp +. (xa.(xo + j) *. ya.(yo + j));
    side := !side +. (ya.(yo + j) *. ya.(yo + j))
  done;
  let xp = mid *. !xp in
  let el = (mid *. mid) +. !side -. (2. *. xp) and er = (mid *. mid) +. !side +. (2. *. xp) in
  if er < 6e-4 || el < 6e-4 then Array.blit xa xo ya yo n
  else (
    let lgain = 1. /. Float.sqrt el and rgain = 1. /. Float.sqrt er in
    for j = 0 to n - 1 do
      let l = mid *. xa.(xo + j) and r = ya.(yo + j) in
      xa.(xo + j) <- lgain *. (l -. r);
      ya.(yo + j) <- rgain *. (l +. r)
    done)

(* [band s ~i x y ~n ~b ...]: band i's n numbers decoded into x (and y,
 * a second channel) with b eighths of a bit; which blocks got
 * something. Too many bits for one vector of pulses: the band cut in
 * two halves, and an angle saying how the energy is shared; the same
 * for two channels. No bit: the band filled from a lower one
 * ([lowband]) or with noise *)
let rec band (s : state) ~(i : int) ((xa, xo) : vector) (y : vector option) ~(n : int) ~(b : int) ~(blocks : int) ~(tf : int)
    ~(lowband : vector option) ~(lm : int) ~(out : vector option) ~(level : int) ~(gain : float) ~(fill : int) : int =
  let stereo = y <> None in
  if n = 1 then (
    let sign ((a, o) : vector) =
      let negative = s.remaining >= 8 && (s.remaining <- s.remaining - 8; Range_decoder.bits s.dec 1 = 1) in
      a.(o) <- (if negative then -1. else 1.)
    in
    sign (xa, xo);
    Option.iter sign y;
    Option.iter (fun ((a, o) : vector) -> a.(o) <- xa.(xo)) out;
    1)
  else (
    let n0 = n and long_blocks = blocks = 1 in
    let n = ref n and b = ref b and blocks = ref blocks and tf = ref tf and lowband = ref lowband and lm = ref lm and fill = ref fill and y = ref y in
    let blocks0 = ref !blocks and per_block = ref (n0 / !blocks) and recombine = ref 0 and time_divide = ref 0 in
    if (not stereo) && level = 0 then (
      if !tf > 0 then recombine := !tf;
      (match !lowband with
       | Some (la, lo) when !recombine > 0 || (!per_block land 1 = 0 && !tf < 0) || !blocks0 > 1 ->
           Array.blit la lo s.scratch 0 n0;
           lowband := Some (s.scratch, 0)
       | _ -> ());
      let on_lowband f = Option.iter (fun ((a, o) : vector) -> f a o) !lowband in
      (* fewer, longer blocks: finer in frequency *)
      for k = 0 to !recombine - 1 do
        on_lowband (fun a o -> haar a o (n0 asr k) (1 lsl k));
        let table = [| 0; 1; 1; 1; 2; 3; 3; 3; 2; 3; 3; 3; 2; 3; 3; 3 |] in
        fill := table.(!fill land 15) lor (table.(!fill asr 4) lsl 2)
      done;
      blocks := !blocks asr !recombine;
      per_block := !per_block lsl !recombine;
      (* more, shorter blocks: finer in time *)
      while !per_block land 1 = 0 && !tf < 0 do
        on_lowband (fun a o -> haar a o !per_block !blocks);
        fill := !fill lor (!fill lsl !blocks);
        blocks := !blocks lsl 1;
        per_block := !per_block asr 1;
        incr time_divide;
        incr tf
      done;
      blocks0 := !blocks;
      if !blocks0 > 1 then on_lowband (fun a o -> deinterleave a o (!per_block asr !recombine) (!blocks0 lsl !recombine) long_blocks));
    let per_block0 = !per_block in
    let split = ref stereo in
    (* more bits than a vector of pulses can take: two halves *)
    if (not stereo) && !lm <> -1 && !n > 2 && (let at = Celt_rate.cache i !lm in !b > cache_bits.(at + cache_bits.(at)) + 12) then (
      n := !n asr 1;
      y := Some (xa, xo + !n);
      split := true;
      decr lm;
      if !blocks = 1 then fill := (!fill land 1) lor (!fill lsl 1);
      blocks := (!blocks + 1) asr 1);
    let n = !n and lm = !lm and blocks = !blocks and tf = !tf and lowband = !lowband in
    let cm = ref 0 and inverted = ref false and mid = ref 0. in
    (match !y with
     | Some ((ya, yo) as yv) when !split ->
         let pulse_cap = log_n.(i) + (lm * 8) in
         let offset = (pulse_cap asr 1) - if stereo && n = 2 then 16 else 4 in
         let qn = if stereo && i >= s.intensity then 1 else angles n !b offset pulse_cap stereo in
         let tell = Range_decoder.tell_frac s.dec in
         let itheta = ref 0 in
         if qn <> 1 then (
           (if stereo && n > 2 then (
              (* a step: the low angles three times as likely *)
              let x0 = qn / 2 in
              let ft = (3 * (x0 + 1)) + x0 in
              let fs = Range_decoder.decode s.dec ft in
              let x = if fs < (x0 + 1) * 3 then fs / 3 else x0 + 1 + (fs - ((x0 + 1) * 3)) in
              Range_decoder.update s.dec (if x <= x0 then 3 * x else x - 1 - x0 + ((x0 + 1) * 3)) (if x <= x0 then 3 * (x + 1) else x - x0 + ((x0 + 1) * 3)) ft;
              itheta := x)
            else if !blocks0 > 1 || stereo then itheta := Range_decoder.uint s.dec (qn + 1)
            else (
              (* a triangle: the middle angles likelier *)
              let half = qn asr 1 in
              let ft = (half + 1) * (half + 1) in
              let fm = Range_decoder.decode s.dec ft in
              let fl, fs =
                if fm < (half * (half + 1)) asr 1 then (
                  itheta := (isqrt ((8 * fm) + 1) - 1) asr 1;
                  ((!itheta * (!itheta + 1)) asr 1, !itheta + 1))
                else (
                  itheta := ((2 * (qn + 1)) - isqrt ((8 * (ft - fm - 1)) + 1)) asr 1;
                  (ft - (((qn + 1 - !itheta) * (qn + 2 - !itheta)) asr 1), qn + 1 - !itheta))
              in
              Range_decoder.update s.dec fl (fl + fs) ft));
           itheta := !itheta * 16384 / qn)
         else if stereo then inverted := !b > 16 && s.remaining > 16 && Range_decoder.bit s.dec 2;
         let itheta = !itheta in
         let qalloc = Range_decoder.tell_frac s.dec - tell in
         b := !b - qalloc;
         let b = !b and orig_fill = !fill in
         let imid, iside, delta =
           if itheta = 0 then (
             fill := !fill land ((1 lsl blocks) - 1);
             (32767, 0, -16384))
           else if itheta = 16384 then (
             fill := !fill land (((1 lsl blocks) - 1) lsl blocks);
             (0, 32767, 16384))
           else
             let imid = cos_ itheta and iside = cos_ (16384 - itheta) in
             (imid, iside, frac_mul ((n - 1) lsl 7) (log2tan iside imid))
         in
         let fill = !fill in
         mid := float_of_int imid /. 32768.;
         let side = float_of_int iside /. 32768. in
         if n = 2 && stereo then (
           (* two numbers a channel: the side is the mid turned a quarter, and a sign *)
           let sbits = if itheta <> 0 && itheta <> 16384 then 8 else 0 in
           s.remaining <- s.remaining - (qalloc + sbits);
           let (x2a, x2o), (y2a, y2o) = if itheta > 8192 then (yv, (xa, xo)) else ((xa, xo), yv) in
           let sign = if sbits > 0 && Range_decoder.bits s.dec 1 = 1 then -1. else 1. in
           cm := band s ~i (x2a, x2o) None ~n ~b:(b - sbits) ~blocks ~tf ~lowband ~lm ~out ~level ~gain ~fill:orig_fill;
           y2a.(y2o) <- -.sign *. x2a.(x2o + 1);
           y2a.(y2o + 1) <- sign *. x2a.(x2o);
           for j = 0 to 1 do
             let m = !mid *. xa.(xo + j) and sd = side *. ya.(yo + j) in
             xa.(xo + j) <- m -. sd;
             ya.(yo + j) <- m +. sd
           done)
         else (
           let delta =
             if !blocks0 > 1 && (not stereo) && itheta land 0x3fff <> 0 then
               if itheta > 8192 then delta - (delta asr (4 - lm)) else min 0 (delta + ((n lsl 3) asr (5 - lm)))
             else delta
           in
           let mbits = max 0 (min b ((b - delta) / 2)) in
           let sbits = b - mbits in
           s.remaining <- s.remaining - qalloc;
           let lowband2 = if stereo then None else Option.map (fun ((a, o) : vector) -> (a, o + n)) lowband in
           let out1 = if stereo then out else None and level = if stereo then 0 else level + 1 in
           let before = s.remaining in
           let side_shift = if stereo then 0 else !blocks0 asr 1 in
           let mid_part b = band s ~i (xa, xo) None ~n ~b ~blocks ~tf ~lowband ~lm ~out:out1 ~level ~gain:(if stereo then 1. else gain *. !mid) ~fill in
           let side_part b = band s ~i yv None ~n ~b ~blocks ~tf ~lowband:lowband2 ~lm ~out:None ~level ~gain:(gain *. side) ~fill:(fill asr blocks) lsl side_shift in
           (* the bits one half did not use go to the other *)
           if mbits >= sbits then (
             cm := mid_part mbits;
             let rebalance = mbits - (before - s.remaining) in
             cm := !cm lor side_part (if rebalance > 24 && itheta <> 0 then sbits + rebalance - 24 else sbits))
           else (
             cm := side_part sbits;
             let rebalance = sbits - (before - s.remaining) in
             cm := !cm lor mid_part (if rebalance > 24 && itheta <> 16384 then mbits + rebalance - 24 else mbits)))
     | _ ->
         let b = !b in
         let q = ref (Celt_rate.bits_to_pulses i lm b) in
         let cost = ref (Celt_rate.pulses_to_bits i lm !q) in
         s.remaining <- s.remaining - !cost;
         while s.remaining < 0 && !q > 0 do
           s.remaining <- s.remaining + !cost;
           decr q;
           cost := Celt_rate.pulses_to_bits i lm !q;
           s.remaining <- s.remaining - !cost
         done;
         if !q <> 0 then cm := shape s.dec xa xo n (Celt_rate.pulses_of !q) s.spread blocks gain
         else (
           let mask = (1 lsl blocks) - 1 in
           let fill = !fill land mask in
           if fill = 0 then Array.fill xa xo n 0.
           else (
             (match lowband with
              | None ->
                  for j = 0 to n - 1 do
                    let r = noise s in
                    xa.(xo + j) <- float_of_int ((if r >= 0x80000000 then r - 0x100000000 else r) asr 20)
                  done;
                  cm := mask
              | Some (la, lo) ->
                  (* the lower band's shape, and a little noise *)
                  for j = 0 to n - 1 do xa.(xo + j) <- la.(lo + j) +. if noise s land 0x8000 <> 0 then 1. /. 256. else -1. /. 256. done;
                  cm := fill);
             renormalise xa xo n gain)));
    (match !y with
     | Some ((ya, yo) as yv) when stereo ->
         if n <> 2 then stereo_merge (xa, xo) yv !mid n;
         if !inverted then for j = yo to yo + n - 1 do ya.(j) <- -.ya.(j) done
     | _ when level = 0 ->
         if !blocks0 > 1 then interleave xa xo (per_block0 asr !recombine) (!blocks0 lsl !recombine) long_blocks;
         let per_block = ref per_block0 and blocks = ref !blocks0 in
         for _ = 1 to !time_divide do
           blocks := !blocks asr 1;
           per_block := !per_block lsl 1;
           cm := !cm lor (!cm asr !blocks);
           haar xa xo !per_block !blocks
         done;
         for k = 0 to !recombine - 1 do
           cm := [| 0x00; 0x03; 0x0C; 0x0F; 0x30; 0x33; 0x3C; 0x3F; 0xC0; 0xC3; 0xCC; 0xCF; 0xF0; 0xF3; 0xFC; 0xFF |].(!cm);
           haar xa xo (n0 asr k) (1 lsl k)
         done;
         blocks := !blocks lsl !recombine;
         (* kept at its full size, for a higher band to fold from *)
         Option.iter (fun ((oa, oo) : vector) -> for j = 0 to n0 - 1 do oa.(oo + j) <- Float.sqrt (float_of_int n0) *. xa.(xo + j) done) out;
         cm := !cm land ((1 lsl !blocks) - 1)
     | _ -> ());
    !cm)

(*****************************************************************************)
(* All the bands of a frame *)
(*****************************************************************************)

(* [all dec ~x ~y ...]: every band's shape decoded into x (and y), each
 * of unit length; which blocks of each band (and channel) got
 * something, and the noise's seed after *)
let all (dec : Range_decoder.t) ~(start : int) ~(stop : int) ~(x : float array) ~(y : float array option) ~(alloc : Celt_rate.t) ~(short : bool)
    ~(spread : int) ~(tf : int array) ~(total_bits : int) ~(lm : int) ~(seed : int) : int array * int =
  let m = 1 lsl lm and channels = if y = None then 1 else 2 in
  let blocks = if short then m else 1 in
  let edge i = m * band_edges.(i) in
  (* the bands decoded so far, at full size: what a band with no bit is folded from *)
  let norm = Array.make (edge bands) 0. and norm2 = Array.make (edge bands) 0. in
  let s = { dec; remaining = 0; seed; spread; intensity = alloc.intensity; scratch = Array.make (edge bands - edge (bands - 1)) 0. } in
  let masks = Array.make (channels * bands) 0 in
  let balance = ref alloc.balance and dual = ref alloc.dual and lowband_offset = ref 0 and update_lowband = ref true in
  for i = start to stop - 1 do
    let n = edge (i + 1) - edge i in
    let tell = Range_decoder.tell_frac dec in
    if i <> start then balance := !balance - tell;
    s.remaining <- total_bits - tell - 1;
    let b = if i <= alloc.coded - 1 then max 0 (min 16383 (min (s.remaining + 1) (alloc.pulses.(i) + (!balance / min 3 (alloc.coded - i))))) else 0 in
    if edge i - n >= edge start && (!update_lowband || !lowband_offset = 0) then lowband_offset := i;
    let x_mask, y_mask, lowband =
      if !lowband_offset <> 0 && (spread <> 3 || blocks > 1 || tf.(i) < 0) then (
        (* never the same numbers twice in a band *)
        let from = max (edge start) (edge !lowband_offset - n) in
        let first = ref (!lowband_offset - 1) in
        while edge !first > from do decr first done;
        let last = ref !lowband_offset in
        while edge !last < from + n do incr last done;
        let xm = ref 0 and ym = ref 0 in
        for f = !first to !last - 1 do
          xm := !xm lor masks.(f * channels);
          ym := !ym lor masks.((f * channels) + channels - 1)
        done;
        (!xm, !ym, Some from))
      else ((1 lsl blocks) - 1, (1 lsl blocks) - 1, None)
    in
    if !dual && i = alloc.intensity then (
      dual := false;
      for j = edge start to edge i - 1 do norm.(j) <- 0.5 *. (norm.(j) +. norm2.(j)) done);
    let one a xv yv b fill = band s ~i xv yv ~n ~b ~blocks ~tf:tf.(i) ~lowband:(Option.map (fun o -> (a, o)) lowband) ~lm ~out:(Some (a, edge i)) ~level:0 ~gain:1. ~fill in
    let x_mask, y_mask =
      match y with
      | Some y when !dual ->
          let xm = one norm (x, edge i) None (b / 2) x_mask in
          (xm, one norm2 (y, edge i) None (b / 2) y_mask)
      | _ ->
          let cm = one norm (x, edge i) (Option.map (fun y -> (y, edge i)) y) b (x_mask lor y_mask) in
          (cm, cm)
    in
    masks.(i * channels) <- x_mask land 255;
    masks.((i * channels) + channels - 1) <- y_mask land 255;
    balance := !balance + alloc.pulses.(i) + tell;
    update_lowband := b > n lsl 3
  done;
  (masks, s.seed)

(* a transient's short blocks that got nothing in a band, when the
 * band was loud just before: noise at the level of the two frames
 * before, so that it does not sound as a hole *)
let anti_collapse ~(x : float array array) ~(masks : int array) ~(lm : int) ~(start : int) ~(stop : int) ~(energy : float array) ~(before1 : float array)
    ~(before2 : float array) ~(pulses : int array) ~(seed : int) : unit =
  let channels = Array.length x and seed = ref seed in
  for i = start to stop - 1 do
    let n0 = band_edges.(i + 1) - band_edges.(i) in
    let depth = (1 + pulses.(i)) / (n0 lsl lm) in
    let thresh = 0.5 *. Float.pow 2. (-0.125 *. float_of_int depth) and norm = 1. /. Float.sqrt (float_of_int (n0 lsl lm)) in
    for c = 0 to channels - 1 do
      let prev (e : float array) = if channels = 1 then Float.max e.(i) e.(bands + i) else e.((c * bands) + i) in
      let diff = Float.max 0. (energy.((c * bands) + i) -. Float.min (prev before1) (prev before2)) in
      let r = 2. *. Float.pow 2. (-.diff) in
      let r = Float.min thresh (if lm = 3 then r *. 1.41421356 else r) *. norm in
      let at = band_edges.(i) lsl lm and filled = ref false in
      for k = 0 to (1 lsl lm) - 1 do
        if masks.((i * channels) + c) land (1 lsl k) = 0 then (
          for j = 0 to n0 - 1 do
            seed := ((1664525 * !seed) + 1013904223) land 0xffffffff;
            x.(c).(at + (j lsl lm) + k) <- (if !seed land 0x8000 <> 0 then r else -.r)
          done;
          filled := true)
      done;
      if !filled then renormalise x.(c) at (n0 lsl lm) 1.
    done
  done

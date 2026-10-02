(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Celt_rate.mli *)

open Celt_tables

type t = {
  coded : int; (* the bands with pulses are those below it *)
  intensity : int; (* from this band on, two channels are one and a sign *)
  dual : bool; (* two channels coded apart *)
  balance : int; (* bits the first bands may borrow, in eighths *)
  pulses : int array; (* each band's bits for its shape, in eighths *)
  fine : int array; (* each band's bits to refine its energy, a channel *)
  priority : int array; (* 0: among the first to get a bit left over *)
}

let fine_offset = 21
let max_fine = 8
let width (j : int) : int = band_edges.(j + 1) - band_edges.(j)

(* the most a band can use, in eighths of a bit *)
let caps ~(lm : int) ~(channels : int) : int array =
  Array.init bands (fun i -> ((cache_caps.((bands * ((2 * lm) + channels - 1)) + i) + 64) * channels * (width i lsl lm)) asr 2)

(* the bits of a frame shared between its bands, as the encoder shared
 * them: nothing of it is sent but what the decoder cannot find by
 * itself ([boosts], [trim], bands given up, the stereo's two numbers) *)
let allocation (dec : Range_decoder.t) ~(start : int) ~(stop : int) ~(boosts : int array) ~(cap : int array) ~(trim : int) ~(total : int)
    ~(channels : int) ~(lm : int) : t =
  let c = channels and stereo = if channels > 1 then 1 else 0 in
  let total = ref (max total 0) in
  let skip_reserve = if !total >= 8 then 8 else 0 in
  total := !total - skip_reserve;
  let intensity_reserve = ref 0 and dual_reserve = ref 0 in
  if c = 2 then (
    intensity_reserve := log2_frac.(stop - start);
    if !intensity_reserve > !total then intensity_reserve := 0
    else (
      total := !total - !intensity_reserve;
      dual_reserve := if !total >= 8 then 8 else 0;
      total := !total - !dual_reserve));
  (* under this, a band surely has no pulse *)
  let thresh = Array.init bands (fun j -> max (c lsl 3) ((((3 * width j) lsl lm) lsl 3) asr 4)) in
  (* the curve tilted: more to the low bands, or to the high *)
  let tilt =
    Array.init bands (fun j ->
        let t = (c * width j * (trim - 5 - lm) * (stop - j - 1) * (1 lsl (lm + 3))) asr 6 in
        if width j lsl lm = 1 then t - (c lsl 3) else t)
  in
  let tilted (bits : int) (j : int) : int = if bits > 0 then max 0 (bits + tilt.(j)) else bits in
  let curve (row : int) (j : int) : int = tilted (((c * width j * Celt_tables.allocation.((row * bands) + j)) lsl lm) asr 2) j in
  (* what a guess of every band's bits adds up to *)
  let sum (guess : int -> int) : int =
    let psum = ref 0 and fixed = ref false in
    for j = stop - 1 downto start do
      let bits = guess j in
      if bits >= thresh.(j) || !fixed then (
        fixed := true;
        psum := !psum + min bits cap.(j))
      else if bits >= c lsl 3 then psum := !psum + (c lsl 3)
    done;
    !psum
  in
  (* the two curves the budget falls between *)
  let lo = ref 1 and hi = ref 10 in
  while !lo <= !hi do
    let mid = (!lo + !hi) asr 1 in
    if sum (fun j -> curve mid j + boosts.(j)) > !total then hi := mid - 1 else lo := mid + 1
  done;
  let hi = !lo and lo = !lo - 1 in
  let skip_start = ref start in
  let bits1 = Array.make bands 0 and bits2 = Array.make bands 0 in
  for j = start to stop - 1 do
    let low = curve lo j and high = if hi >= 11 then tilted cap.(j) j else curve hi j in
    let low = if lo > 0 then low + boosts.(j) else low in
    if boosts.(j) > 0 then skip_start := j;
    bits1.(j) <- low;
    bits2.(j) <- max 0 (high + boosts.(j) - low)
  done;
  (* and how far between them, in 64ths *)
  let lo = ref 0 and hi = ref 64 in
  for _ = 1 to 6 do
    let mid = (!lo + !hi) asr 1 in
    if sum (fun j -> bits1.(j) + ((mid * bits2.(j)) asr 6)) > !total then hi := mid else lo := mid
  done;
  let bits = Array.make bands 0 in
  let psum = ref 0 and fixed = ref false in
  for j = stop - 1 downto start do
    let b = bits1.(j) + ((!lo * bits2.(j)) asr 6) in
    let b = if b < thresh.(j) && not !fixed then if b >= c lsl 3 then c lsl 3 else 0 else (fixed := true; b) in
    let b = min b cap.(j) in
    bits.(j) <- b;
    psum := !psum + b
  done;
  (* the bands given up, from the top: the encoder says where it stops *)
  let coded = ref stop and stopped = ref false in
  while not !stopped do
    let j = !coded - 1 in
    if j <= !skip_start then (
      total := !total + skip_reserve;
      stopped := true)
    else (
      let left = !total - !psum in
      let span = band_edges.(!coded) - band_edges.(start) in
      let per = left / span in
      let left = left - (span * per) in
      let rem = max (left - (band_edges.(j) - band_edges.(start))) 0 in
      let band_bits = ref (bits.(j) + (per * width j) + rem) in
      if !band_bits >= max thresh.(j) ((c lsl 3) + 8) && Range_decoder.bit dec 1 then stopped := true
      else (
        if !band_bits >= max thresh.(j) ((c lsl 3) + 8) then (
          psum := !psum + 8;
          band_bits := !band_bits - 8);
        psum := !psum - (bits.(j) + !intensity_reserve);
        if !intensity_reserve > 0 then intensity_reserve := log2_frac.(j - start);
        psum := !psum + !intensity_reserve;
        if !band_bits >= c lsl 3 then (
          psum := !psum + (c lsl 3);
          bits.(j) <- c lsl 3)
        else bits.(j) <- 0;
        decr coded))
  done;
  let coded = !coded in
  let intensity = if !intensity_reserve > 0 then start + Range_decoder.uint dec (coded + 1 - start) else 0 in
  if intensity <= start then (
    total := !total + !dual_reserve;
    dual_reserve := 0);
  let dual = !dual_reserve > 0 && Range_decoder.bit dec 1 in
  (* what is left, shared by width *)
  let left = !total - !psum in
  let span = band_edges.(coded) - band_edges.(start) in
  let per = left / span in
  let left = ref (left - (span * per)) in
  for j = start to coded - 1 do bits.(j) <- bits.(j) + (per * width j) done;
  for j = start to coded - 1 do
    let more = min !left (width j) in
    bits.(j) <- bits.(j) + more;
    left := !left - more
  done;
  (* each band's bits cut in two: its energy made finer, its shape *)
  let fine = Array.make bands 0 and priority = Array.make bands 0 in
  let balance = ref 0 in
  for j = start to coded - 1 do
    let n = width j lsl lm in
    bits.(j) <- bits.(j) + !balance;
    let excess = ref 0 in
    if n > 1 then (
      excess := max (bits.(j) - cap.(j)) 0;
      bits.(j) <- bits.(j) - !excess;
      let den = (c * n) + if c = 2 && n > 2 && (not dual) && j < intensity then 1 else 0 in
      let nc_log_n = den * (log_n.(j) + (lm lsl 3)) in
      let offset = ref ((nc_log_n asr 1) - (den * fine_offset)) in
      if n = 2 then offset := !offset + ((den lsl 3) asr 2);
      if bits.(j) + !offset < (den * 2) lsl 3 then offset := !offset + (nc_log_n asr 2)
      else if bits.(j) + !offset < (den * 3) lsl 3 then offset := !offset + (nc_log_n asr 3);
      fine.(j) <- max 0 ((bits.(j) + !offset + (den lsl 2)) / (den lsl 3));
      if c * fine.(j) > bits.(j) asr 3 then fine.(j) <- (bits.(j) asr stereo) asr 3;
      fine.(j) <- min fine.(j) max_fine;
      priority.(j) <- (if fine.(j) * (den lsl 3) >= bits.(j) + !offset then 1 else 0);
      bits.(j) <- bits.(j) - ((c * fine.(j)) lsl 3))
    else (
      excess := max 0 (bits.(j) - (c lsl 3));
      bits.(j) <- bits.(j) - !excess;
      fine.(j) <- 0;
      priority.(j) <- 1);
    if !excess > 0 then (
      let extra = min (!excess asr (stereo + 3)) (max_fine - fine.(j)) in
      fine.(j) <- fine.(j) + extra;
      let extra_bits = (extra * c) lsl 3 in
      priority.(j) <- (if extra_bits >= !excess - !balance then 1 else 0);
      excess := !excess - extra_bits);
    balance := !excess
  done;
  (* a band given up keeps its bits for its energy *)
  for j = coded to stop - 1 do
    fine.(j) <- (bits.(j) asr stereo) asr 3;
    bits.(j) <- 0;
    priority.(j) <- (if fine.(j) < 1 then 1 else 0)
  done;
  { coded; intensity; dual; balance = !balance; pulses = bits; fine; priority }

(* how many pulses a number of the cache's list stands for *)
let pulses_of (q : int) : int = if q < 8 then q else (8 + (q land 7)) lsl ((q lsr 3) - 1)

(* a band's list in the cache, for blocks of 2^lm *)
let cache (band : int) (lm : int) : int = cache_index.(((lm + 1) * bands) + band)

(* the number of pulses whose cost is nearest to [bits] *)
let bits_to_pulses (band : int) (lm : int) (bits : int) : int =
  let at = cache band lm in
  let lo = ref 0 and hi = ref cache_bits.(at) and bits = bits - 1 in
  for _ = 1 to 6 do
    let mid = (!lo + !hi + 1) asr 1 in
    if cache_bits.(at + mid) >= bits then hi := mid else lo := mid
  done;
  if bits - (if !lo = 0 then -1 else cache_bits.(at + !lo)) <= cache_bits.(at + !hi) - bits then !lo else !hi

let pulses_to_bits (band : int) (lm : int) (q : int) : int = if q = 0 then 0 else cache_bits.(cache band lm + q) + 1

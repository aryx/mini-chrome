(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Celt.mli *)

open Celt_tables

let overlap = 120
let history = 2048

type postfilter = { period : int; gain : float; tapset : int }

type t = {
  channels : int;
  (* each band's energy, in log2, as last decoded; and of the two frames before (two channels of [bands]) *)
  energy : float array;
  before1 : float array;
  before2 : float array;
  mutable seed : int; (* of the noise: where the range decoder ended *)
  past : float array array; (* each channel's last samples, before the de-emphasis *)
  tail : float array array; (* the half window the next frame is added to *)
  mutable filter : postfilter;
  mutable filter_before : postfilter;
  emphasis : float array;
}

let create ~(channels : int) : t =
  { channels; energy = Array.make (2 * bands) 0.; before1 = Array.make (2 * bands) (-28.); before2 = Array.make (2 * bands) (-28.); seed = 0;
    past = Array.init channels (fun _ -> Array.make history 0.); tail = Array.init channels (fun _ -> Array.make overlap 0.);
    filter = { period = 0; gain = 0.; tapset = 0 }; filter_before = { period = 0; gain = 0.; tapset = 0 }; emphasis = Array.make channels 0. }

(* the window's slope: its square and its mirror's add to one *)
let window : float array =
  Array.init overlap (fun i ->
      let s = Float.sin (0.5 *. Float.pi *. (float_of_int i +. 0.5) /. float_of_int overlap) in
      Float.sin (0.5 *. Float.pi *. s *. s))

(*****************************************************************************)
(* The bands' energies *)
(*****************************************************************************)

(* each band's energy to 6 dB: what it was (unless [intra]) and what
 * the band below is, corrected by a small number *)
let coarse_energy (dec : Range_decoder.t) (t : t) ~(stop : int) ~(intra : bool) ~(channels : int) ~(lm : int) : unit =
  let model = ((2 * lm) + if intra then 1 else 0) * 42 in
  let coef = if intra then 0. else [| 29440.; 26112.; 21248.; 16384. |].(lm) /. 32768.
  and beta = (if intra then 4915. else [| 30147.; 22282.; 12124.; 6554. |].(lm)) /. 32768. in
  let budget = Range_decoder.size dec * 8 and below = [| 0.; 0. |] in
  for i = 0 to stop - 1 do
    for c = 0 to channels - 1 do
      let room = budget - Range_decoder.tell dec in
      let q =
        if room >= 15 then
          let pi = 2 * min i 20 in
          Range_decoder.laplace dec ~zero:(energy_model.(model + pi) lsl 7) ~decay:(energy_model.(model + pi + 1) lsl 6)
        else if room >= 2 then
          let q = Range_decoder.icdf dec small_energy_icdf 2 in
          (q asr 1) lxor (-(q land 1))
        else if room >= 1 then if Range_decoder.bit dec 1 then -1 else 0
        else -1
      in
      let q = float_of_int q and at = i + (c * bands) in
      t.energy.(at) <- (coef *. Float.max (-9.) t.energy.(at)) +. below.(c) +. q;
      below.(c) <- below.(c) +. q -. (beta *. q)
    done
  done

(* then finer, with the bits the allocation gave each band *)
let fine_energy (dec : Range_decoder.t) (t : t) ~(stop : int) ~(fine : int array) ~(channels : int) : unit =
  for i = 0 to stop - 1 do
    if fine.(i) > 0 then
      for c = 0 to channels - 1 do
        let q = Range_decoder.bits dec fine.(i) in
        t.energy.(i + (c * bands)) <- t.energy.(i + (c * bands)) +. ((float_of_int q +. 0.5) *. float_of_int (1 lsl (14 - fine.(i))) /. 16384.) -. 0.5
      done
  done

(* and with the bits nobody used, at the frame's end *)
let final_energy (dec : Range_decoder.t) (t : t) ~(stop : int) ~(fine : int array) ~(priority : int array) ~(left : int) ~(channels : int) : unit =
  let left = ref left in
  for wanted = 0 to 1 do
    for i = 0 to stop - 1 do
      if !left >= channels && fine.(i) < 8 && priority.(i) = wanted then
        for c = 0 to channels - 1 do
          let q = Range_decoder.bits dec 1 in
          t.energy.(i + (c * bands)) <- t.energy.(i + (c * bands)) +. ((float_of_int q -. 0.5) *. float_of_int (1 lsl (14 - fine.(i) - 1)) /. 16384.);
          decr left
        done
    done
  done

(* each band's blocks: as the frame's (long, or short for a
 * transient), or one step the other way *)
let time_frequency (dec : Range_decoder.t) ~(stop : int) ~(transient : bool) ~(lm : int) : int array =
  let table = [| [| 0; -1; 0; -1; 0; -1; 0; -1 |]; [| 0; -1; 0; -2; 1; 0; 1; -1 |]; [| 0; -2; 0; -3; 2; 0; 1; -1 |]; [| 0; -2; 0; -3; 3; 0; 1; -1 |] |].(lm) in
  let budget = ref (Range_decoder.size dec * 8) and tell = ref (Range_decoder.tell dec) in
  let logp = ref (if transient then 2 else 4) in
  let select_reserved = lm > 0 && !tell + !logp + 1 <= !budget in
  if select_reserved then decr budget;
  let changed = ref 0 and current = ref 0 in
  let res =
    Array.init stop (fun _ ->
        if !tell + !logp <= !budget then (
          if Range_decoder.bit dec !logp then current := !current lxor 1;
          tell := Range_decoder.tell dec;
          changed := !changed lor !current);
        logp := if transient then 4 else 5;
        !current)
  in
  let base = if transient then 4 else 0 in
  let select = if select_reserved && table.(base + !changed) <> table.(base + 2 + !changed) && Range_decoder.bit dec 1 then 2 else 0 in
  Array.map (fun r -> table.(base + select + r)) res

(*****************************************************************************)
(* Frequencies to samples *)
(*****************************************************************************)

(* a channel's frequencies as its samples: one long block, or
 * [blocks] short ones whose numbers come in turn; each windowed on
 * 120 samples a side and added to its neighbour, the last one's end
 * kept for the next frame *)
let synthesis (t : t) (c : int) (freq : float array) ~(blocks : int) (into : float array) (at : int) : unit =
  let n = Array.length freq in
  let size = n / blocks in
  let x = Array.make (n + overlap) 0. and skip = (size - overlap) / 2 in
  for b = 0 to blocks - 1 do
    let y = Mdct.imdct (Array.init size (fun k -> freq.(b + (k * blocks)))) in
    for j = 0 to size + overlap - 1 do
      let w = if j < overlap then window.(j) else if j >= size then window.(overlap - 1 - (j - size)) else 1. in
      x.((size * b) + j) <- x.((size * b) + j) +. (w *. y.(skip + j))
    done
  done;
  for j = 0 to n - 1 do into.(at + j) <- (if j < overlap then x.(j) +. t.tail.(c).(j) else x.(j)) done;
  Array.blit x n t.tail.(c) 0 overlap

(* the pitch made sharper: each sample plus a little of those one
 * period before (the encoder took as much out). From one setting to
 * the next over the window's 120 samples *)
let comb (x : float array) (at : int) (count : int) (f0 : postfilter) (f1 : postfilter) : unit =
  let gains = [| [| 0.3066406250; 0.2170410156; 0.1296386719 |]; [| 0.4638671875; 0.2680664062; 0. |]; [| 0.7998046875; 0.1000976562; 0. |] |] in
  let taps (f : postfilter) (i : int) : float =
    if f.gain = 0. then 0.
    else
      let g = gains.(f.tapset) and p = at + i - f.period in
      f.gain *. ((g.(0) *. x.(p)) +. (g.(1) *. (x.(p - 1) +. x.(p + 1))) +. (g.(2) *. (x.(p - 2) +. x.(p + 2))))
  in
  for i = 0 to count - 1 do
    if i < overlap then (
      let f = window.(i) *. window.(i) in
      x.(at + i) <- x.(at + i) +. ((1. -. f) *. taps f0 i) +. (f *. taps f1 i))
    else x.(at + i) <- x.(at + i) +. taps f1 i
  done

(*****************************************************************************)
(* A frame *)
(*****************************************************************************)

let decode (t : t) ~(stream_channels : int) ~(lm : int) ~(stop : int) (packet : string) : float array array =
  let c = stream_channels and m = 1 lsl lm in
  let n = m * overlap and len = String.length packet in
  if len <= 1 then Array.init t.channels (fun _ -> Array.make n 0.)
  else (
    let dec = Range_decoder.create packet in
    if c = 1 then for i = 0 to bands - 1 do t.energy.(i) <- Float.max t.energy.(i) t.energy.(bands + i) done;
    let total = len * 8 in
    let tell = Range_decoder.tell dec in
    let silence = tell >= total || (tell = 1 && Range_decoder.bit dec 15) in
    if silence then Range_decoder.skip dec (total - Range_decoder.tell dec);
    let room bits = (if silence then total else Range_decoder.tell dec) + bits <= total in
    let filter =
      if room 16 && Range_decoder.bit dec 1 then (
        let octave = Range_decoder.uint dec 6 in
        let period = (16 lsl octave) + Range_decoder.bits dec (4 + octave) - 1 in
        let gain = 0.09375 *. float_of_int (Range_decoder.bits dec 3 + 1) in
        { period; gain; tapset = (if room 2 then Range_decoder.icdf dec tapset_icdf 2 else 0) })
      else { period = 0; gain = 0.; tapset = 0 }
    in
    let transient = lm > 0 && room 3 && Range_decoder.bit dec 3 in
    let intra = room 3 && Range_decoder.bit dec 3 in
    coarse_energy dec t ~stop ~intra ~channels:c ~lm;
    let tf = time_frequency dec ~stop ~transient ~lm in
    let spread = if Range_decoder.tell dec + 4 <= total then Range_decoder.icdf dec spread_icdf 5 else 2 in
    (* bands the encoder chose to give more: a boost each *)
    let cap = Celt_rate.caps ~lm ~channels:c in
    let logp = ref 6 and total8 = ref (total lsl 3) and tell = ref (Range_decoder.tell_frac dec) in
    let boosts =
      Array.init bands (fun i ->
          if i >= stop then 0
          else (
            let width = (c * (band_edges.(i + 1) - band_edges.(i))) lsl lm in
            let quanta = min (width lsl 3) (max 48 width) in
            let boost = ref 0 and loop_logp = ref !logp and go = ref true in
            while !go && !tell + (!loop_logp lsl 3) < !total8 && !boost < cap.(i) do
              let flag = Range_decoder.bit dec !loop_logp in
              tell := Range_decoder.tell_frac dec;
              if flag then (
                boost := !boost + quanta;
                total8 := !total8 - quanta;
                loop_logp := 1)
              else go := false
            done;
            if !boost > 0 then logp := max 2 (!logp - 1);
            !boost))
    in
    let trim = if !tell + 48 <= !total8 then Range_decoder.icdf dec trim_icdf 7 else 5 in
    let bits = (total lsl 3) - Range_decoder.tell_frac dec - 1 in
    let anti_collapse_reserve = if transient && lm >= 2 && bits >= (lm + 2) lsl 3 then 8 else 0 in
    let alloc = Celt_rate.allocation dec ~start:0 ~stop ~boosts ~cap ~trim ~total:(bits - anti_collapse_reserve) ~channels:c ~lm in
    fine_energy dec t ~stop ~fine:alloc.fine ~channels:c;
    let x = Array.init c (fun _ -> Array.make n 0.) in
    let masks, seed =
      Celt_bands.all dec ~start:0 ~stop ~x:x.(0) ~y:(if c = 2 then Some x.(1) else None) ~alloc ~short:transient ~spread ~tf
        ~total_bits:((total lsl 3) - anti_collapse_reserve) ~lm ~seed:t.seed
    in
    let anti_collapse = anti_collapse_reserve > 0 && Range_decoder.bits dec 1 = 1 in
    final_energy dec t ~stop ~fine:alloc.fine ~priority:alloc.priority ~left:(total - Range_decoder.tell dec) ~channels:c;
    if anti_collapse then
      Celt_bands.anti_collapse ~x ~masks ~lm ~start:0 ~stop ~energy:t.energy ~before1:t.before1 ~before2:t.before2 ~pulses:alloc.pulses ~seed;
    (* each band's shape at its energy *)
    let freq =
      Array.init c (fun ch ->
          let f = Array.make n 0. in
          if not silence then
            for i = 0 to stop - 1 do
              let e = Float.pow 2. (t.energy.(i + (ch * bands)) +. means.(i)) in
              for j = m * band_edges.(i) to (m * band_edges.(i + 1)) - 1 do f.(j) <- x.(ch).(j) *. e done
            done;
          f)
    in
    if silence then Array.fill t.energy 0 (2 * bands) (-28.);
    let freq =
      if t.channels = c then freq
      else if c = 1 then [| freq.(0); freq.(0) |]
      else [| Array.mapi (fun j v -> 0.5 *. (v +. freq.(1).(j))) freq.(0) |]
    in
    let before = { t.filter_before with period = max t.filter_before.period 15 } and current = { t.filter with period = max t.filter.period 15 } in
    let out =
      Array.mapi
        (fun ch f ->
          let past = t.past.(ch) in
          Array.blit past n past 0 (history - n);
          synthesis t ch f ~blocks:(if transient then m else 1) past (history - n);
          comb past (history - n) overlap before current;
          if lm <> 0 then comb past (history - n + overlap) (n - overlap) current filter;
          (* the high frequencies the encoder raised, lowered again *)
          Array.init n (fun j ->
              let v = past.(history - n + j) +. t.emphasis.(ch) in
              t.emphasis.(ch) <- 0.8500061035 *. v;
              v /. 32768.))
        freq
    in
    t.filter_before <- (if lm <> 0 then filter else current);
    t.filter <- filter;
    if c = 1 then Array.blit t.energy 0 t.energy bands bands;
    if not transient then (
      Array.blit t.before1 0 t.before2 0 (2 * bands);
      Array.blit t.energy 0 t.before1 0 (2 * bands))
    else Array.iteri (fun i e -> t.before1.(i) <- Float.min t.before1.(i) e) t.energy;
    for ch = 0 to 1 do
      for i = stop to bands - 1 do
        t.energy.((ch * bands) + i) <- 0.;
        t.before1.((ch * bands) + i) <- -28.;
        t.before2.((ch * bands) + i) <- -28.
      done
    done;
    t.seed <- Range_decoder.range dec;
    out)

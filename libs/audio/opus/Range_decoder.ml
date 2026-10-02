(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Range_decoder.mli *)

type t = {
  data : string;
  mutable at : int; (* the next byte, from the front *)
  mutable range : int; (* 32 bits *)
  mutable value : int; (* the top of the range less the code, less than [range] *)
  mutable left : int; (* the last byte read: its low bit is not used yet *)
  mutable divided : int; (* [range] over the total, between [decode] and [update] *)
  mutable total_bits : int; (* bits taken from both ends so far *)
  (* the raw bits, read from the end backwards *)
  mutable back : int; (* bytes taken from the end *)
  mutable window : int;
  mutable window_bits : int;
}

let rec ilog (x : int) : int = if x <= 0 then 0 else 1 + ilog (x lsr 1)
let byte (t : t) : int = if t.at < String.length t.data then (t.at <- t.at + 1; Char.code t.data.[t.at - 1]) else 0

(* the range kept above 2^23: a byte in at a time *)
let normalize (t : t) : unit =
  while t.range <= 0x800000 do
    t.total_bits <- t.total_bits + 8;
    t.range <- t.range lsl 8;
    let before = t.left in
    t.left <- byte t;
    let symbol = ((before lsl 8) lor t.left) lsr 1 in
    t.value <- ((t.value lsl 8) + (255 land lnot symbol)) land 0x7fffffff
  done

let create (data : string) : t =
  let t = { data; at = 0; range = 128; value = 0; left = 0; divided = 0; total_bits = 9; back = 0; window = 0; window_bits = 0 } in
  t.left <- byte t;
  t.value <- t.range - 1 - (t.left lsr 1);
  normalize t;
  t

let size (t : t) : int = String.length t.data
let range (t : t) : int = t.range
let tell (t : t) : int = t.total_bits - ilog t.range
let skip (t : t) (bits : int) : unit = t.total_bits <- t.total_bits + bits

(* the same in eighths of a bit: three more bits of the range's logarithm, by squaring *)
let tell_frac (t : t) : int =
  let l = ref (ilog t.range) in
  let r = ref (t.range lsr (!l - 16)) in
  for _ = 1 to 3 do
    r := (!r * !r) lsr 15;
    let b = !r lsr 16 in
    l := (!l lsl 1) lor b;
    r := !r lsr b
  done;
  (t.total_bits * 8) - !l

let decode (t : t) (total : int) : int =
  t.divided <- t.range / total;
  total - min ((t.value / t.divided) + 1) total

let update (t : t) (low : int) (high : int) (total : int) : unit =
  let s = t.divided * (total - high) in
  t.value <- t.value - s;
  t.range <- (if low > 0 then t.divided * (high - low) else t.range - s);
  normalize t

let bit (t : t) (logp : int) : bool =
  let s = t.range lsr logp in
  let one = t.value < s in
  if not one then t.value <- t.value - s;
  t.range <- (if one then s else t.range - s);
  normalize t;
  one

let icdf (t : t) (table : int array) (bits : int) : int =
  let r = t.range lsr bits in
  let rec find k above =
    let s = r * table.(k) in
    if t.value < s then find (k + 1) s
    else (
      t.value <- t.value - s;
      t.range <- above - s;
      normalize t;
      k)
  in
  find 0 t.range

let bits (t : t) (n : int) : int =
  if n = 0 then 0
  else (
    while t.window_bits < n do
      let b = if t.back < String.length t.data then (t.back <- t.back + 1; Char.code t.data.[String.length t.data - t.back]) else 0 in
      t.window <- t.window lor (b lsl t.window_bits);
      t.window_bits <- t.window_bits + 8
    done;
    let v = t.window land ((1 lsl n) - 1) in
    t.window <- t.window lsr n;
    t.window_bits <- t.window_bits - n;
    t.total_bits <- t.total_bits + n;
    v)

let uint (t : t) (count : int) : int =
  let last = count - 1 in
  let high_bits = ilog last in
  if high_bits > 8 then (
    let low_bits = high_bits - 8 in
    let total = (last lsr low_bits) + 1 in
    let s = decode t total in
    update t s (s + 1) total;
    min last ((s lsl low_bits) lor bits t low_bits))
  else (
    let s = decode t count in
    update t s (s + 1) count;
    s)

let laplace (t : t) ~(zero : int) ~(decay : int) : int =
  let fm =
    t.divided <- t.range lsr 15;
    32768 - min ((t.value / t.divided) + 1) 32768
  in
  let value = ref 0 and low = ref 0 and fs = ref zero in
  if fm >= !fs then (
    incr value;
    low := !fs;
    fs := (((32768 - 32 - !fs) * (16384 - decay)) lsr 15) + 1;
    while !fs > 1 && fm >= !low + (2 * !fs) do
      fs := !fs * 2;
      low := !low + !fs;
      fs := (((!fs - 2) * decay) lsr 15) + 1;
      incr value
    done;
    if !fs <= 1 then (
      let more = (fm - !low) lsr 1 in
      value := !value + more;
      low := !low + (2 * more));
    if fm < !low + !fs then value := - !value else low := !low + !fs);
  update t !low (min (!low + !fs) 32768) 32768;
  !value

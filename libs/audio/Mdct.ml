(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Mdct.mli *)

(* a Fourier transform of n complex numbers, n of any size: cut by its
 * smallest factor p into p transforms of n/p (the numbers taken one
 * in p), put together with the n-th roots of one. n log n for a
 * product of small factors (a power of two, Vorbis's; 15 times one,
 * Opus's); n^2 for a prime *)
let fft (re : float array) (im : float array) : float array * float array =
  let size = Array.length re in
  let angle k = -2. *. Float.pi *. float_of_int k /. float_of_int size in
  let cos_ = Array.init size (fun k -> Float.cos (angle k)) and sin_ = Array.init size (fun k -> Float.sin (angle k)) in
  (* [step]: size / n, a root of the n-th order in the table *)
  let rec go (re : float array) (im : float array) (step : int) : float array * float array =
    let n = Array.length re in
    if n = 1 then (re, im)
    else
      let p = if n mod 2 = 0 then 2 else if n mod 3 = 0 then 3 else if n mod 5 = 0 then 5 else n in
      let m = n / p in
      let parts = Array.init p (fun r -> go (Array.init m (fun j -> re.((j * p) + r))) (Array.init m (fun j -> im.((j * p) + r))) (step * p)) in
      let out_re = Array.make n 0. and out_im = Array.make n 0. in
      for k = 0 to n - 1 do
        let sr = ref 0. and si = ref 0. and j = k mod m in
        for r = 0 to p - 1 do
          let pr, pi = parts.(r) in
          let w = r * k mod n * step in
          sr := !sr +. (pr.(j) *. cos_.(w)) -. (pi.(j) *. sin_.(w));
          si := !si +. (pr.(j) *. sin_.(w)) +. (pi.(j) *. cos_.(w))
        done;
        out_re.(k) <- !sr;
        out_im.(k) <- !si
      done;
      (out_re, out_im)
  in
  go re im 1

(* u.(n) = the sum over k of x.(k) cos (pi / m (n + 1/2) (k + 1/2)):
 * the cosine transform the MDCT is made of, by its definition *)
let dct4_simple (x : float array) : float array =
  let m = Array.length x in
  Array.init m (fun n ->
      let sum = ref 0. in
      for k = 0 to m - 1 do sum := !sum +. (x.(k) *. Float.cos (Float.pi /. float_of_int m *. (float_of_int n +. 0.5) *. (float_of_int k +. 0.5))) done;
      !sum)

(* opti: the same by a Fourier transform of half the size: the pairs
 * (x.(2j), x.(m-1-2j)) as complex numbers, turned before (by
 * (4j+1) pi / 4m) and after (by k pi / m): with the transform's own
 * 2 pi jk / (m/2), that is (4j+1)(4k+1) pi / 4m, the cosine's angle.
 * A Vorbis block of 2048 samples: 1024 x 1024 cosines, or 512 log 512
 * (measured: a second of sound decoded in 1.2 s, then in 0.06) *)
let dct4_opti (x : float array) : float array =
  let m = Array.length x in
  if m < 4 || m mod 2 = 1 then dct4_simple x
  else (
    let h = m / 2 in
    let re = Array.make h 0. and im = Array.make h 0. in
    let turn j = -.Float.pi *. float_of_int ((4 * j) + 1) /. float_of_int (4 * m) in
    for j = 0 to h - 1 do
      let a = x.(2 * j) and b = x.(m - 1 - (2 * j)) and c = Float.cos (turn j) and s = Float.sin (turn j) in
      re.(j) <- (a *. c) -. (b *. s);
      im.(j) <- (a *. s) +. (b *. c)
    done;
    let re, im = fft re im in
    let u = Array.make m 0. in
    for k = 0 to h - 1 do
      let after = -.Float.pi *. float_of_int k /. float_of_int m in
      let c = Float.cos after and s = Float.sin after in
      u.(2 * k) <- (re.(k) *. c) -. (im.(k) *. s);
      u.(m - 1 - (2 * k)) <- -.((re.(k) *. s) +. (im.(k) *. c))
    done;
    u)

let dct4 (x : float array) : float array = if !Mini_opti.enabled then dct4_opti x else dct4_simple x

(* the cosine transform's values, unfolded by its symmetries *)
let imdct (x : float array) : float array =
  let m = Array.length x in
  let u = dct4 x in
  Array.init (2 * m) (fun n -> if n < m / 2 then u.(n + (m / 2)) else if n < 3 * m / 2 then -.u.((3 * m / 2) - 1 - n) else -.u.(n - (3 * m / 2)))

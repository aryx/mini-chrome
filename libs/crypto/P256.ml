(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See P256.mli *)

let p = Bignum.modulus (Bignum.of_hex "FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF")
let order = Bignum.of_hex "FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551"
let b = Bignum.of_hex "5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B"
let gx = Bignum.of_hex "6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296"
let gy = Bignum.of_hex "4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5"
let ( *% ) = Bignum.mul_mod p
let ( +% ) = Bignum.add_mod p
let ( -% ) = Bignum.sub_mod p
let times (k : int) (x : Bignum.t) : Bignum.t = Bignum.of_int k *% x

(* (X, Y, Z) for (X/Z^2, Y/Z^3); Z = 0 is the point at infinity *)
type point = Bignum.t * Bignum.t * Bignum.t

let infinity : point = (Bignum.one, Bignum.one, Bignum.zero)

let double ((x, y, z) : point) : point =
  if Bignum.is_zero z || Bignum.is_zero y then infinity
  else
    let delta = z *% z and gamma = y *% y in
    let beta = x *% gamma in
    let alpha = times 3 ((x -% delta) *% (x +% delta)) in
    let x3 = (alpha *% alpha) -% times 8 beta in
    (x3, (alpha *% (times 4 beta -% x3)) -% times 8 (gamma *% gamma), ((y +% z) *% (y +% z)) -% gamma -% delta)

let add ((x1, y1, z1) as a : point) ((x2, y2, z2) as c : point) : point =
  if Bignum.is_zero z1 then c
  else if Bignum.is_zero z2 then a
  else
    let z1z1 = z1 *% z1 and z2z2 = z2 *% z2 in
    let u1 = x1 *% z2z2 and u2 = x2 *% z1z1 in
    let s1 = y1 *% z2 *% z2z2 and s2 = y2 *% z1 *% z1z1 in
    if Bignum.equal u1 u2 then if Bignum.equal s1 s2 then double a else infinity
    else
      let h = u2 -% u1 and r = s2 -% s1 in
      let hh = h *% h in
      let hhh = h *% hh and v = u1 *% hh in
      let x3 = (r *% r) -% hhh -% times 2 v in
      (x3, (r *% (v -% x3)) -% (s1 *% hhh), h *% z1 *% z2)

(* k.P: the bits of k from the top, doubling at each, adding P at a 1 *)
let multiply (k : Bignum.t) (pt : point) : point =
  let rec go i acc = if i < 0 then acc else let acc = double acc in go (i - 1) (if Bignum.bit k i then add acc pt else acc) in
  go (Bignum.bits k - 1) infinity

let affine ((x, y, z) : point) : (Bignum.t * Bignum.t) option =
  if Bignum.is_zero z then None
  else
    let zi = Bignum.inverse_prime p z in
    let zi2 = zi *% zi in
    Some (x *% zi2, y *% zi2 *% zi)

(* a secret as a number of the curve's order, never 0 *)
let scalar (secret : string) : Bignum.t = let k = Bignum.rem (Bignum.of_bytes secret) order in if Bignum.is_zero k then Bignum.one else k

let public_key (secret : string) : string =
  match affine (multiply (scalar secret) (gx, gy, Bignum.one)) with
  | Some (x, y) -> "\004" ^ Bignum.to_bytes ~len:32 x ^ Bignum.to_bytes ~len:32 y
  | None -> invalid_arg "P256.public_key"

let shared (secret : string) (point : string) : string option =
  if String.length point <> 65 || point.[0] <> '\004' then None
  else
    let x = Bignum.of_bytes (String.sub point 1 32) and y = Bignum.of_bytes (String.sub point 33 32) in
    let modulus = Bignum.modulus_value p in
    (* a point of the curve, not any pair of numbers: y^2 = x^3 - 3x + b *)
    if Bignum.compare x modulus >= 0 || Bignum.compare y modulus >= 0 || not (Bignum.equal (y *% y) (((x *% x *% x) -% times 3 x) +% b)) then None
    else Option.map (fun (x, _) -> Bignum.to_bytes ~len:32 x) (affine (multiply (scalar secret) (x, y, Bignum.one)))

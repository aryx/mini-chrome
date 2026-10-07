(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_tls12.mli *)

let of_hex (h : string) : string =
  let h = String.concat "" (String.split_on_char ' ' h) in
  String.init (String.length h / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

let hex (s : string) : string = String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

let tests =
  Testo.categorize "Tls12"
    [
      Testo.create "P256: two sides arrive at the same secret; what is not a point is refused" (fun () ->
          let a = of_hex "c88f01f510d9ac3f70a292daa2316de544e9aab8afe84049c62a9c57862d1433"
          and b = of_hex "c6ef9c5d78ae012a011164acb397ce2088685d8f06bf9be0b283ab46476bee53" in
          let pa = P256.public_key a and pb = P256.public_key b in
          Alcotest.(check int) "a point: 65 bytes, the first 4" 0x41 (String.length pa + Char.code pa.[0] - 4);
          (* RFC 5903, section 8.1: this secret's point *)
          Alcotest.(check string) "the generator multiplied" "dad0b65394221cf9b051e1feca5787d098dfe637fc90b9ef945d0c3772581180" (hex (String.sub pa 1 32));
          Alcotest.(check bool) "the same from both sides" true (P256.shared a pb <> None && P256.shared a pb = P256.shared b pa);
          Alcotest.(check string) "and RFC 5903's" "d6840f6b42f6edafd13116e0e12565202fef8e9ece7dce03812464d04b9442de" (hex (Option.get (P256.shared a pb)));
          let off = Bytes.of_string pb in
          Bytes.set off 64 (Char.chr (Char.code pb.[64] lxor 1));
          Alcotest.(check bool) "a y changed: not on the curve" true (P256.shared a (Bytes.to_string off) = None);
          Alcotest.(check bool) "too short" true (P256.shared a "\004abc" = None));
      Testo.create "the PRF: a chain of HMAC-SHA256, as long as asked" (fun () ->
          (* the test vector passed around for TLS 1.2's PRF with SHA-256 *)
          let secret = of_hex "9bbe436ba940f017b17652849a71db35" and seed = of_hex "a0ba9f936cda311827a6f796ffd5198c" in
          let out = Tls12.prf secret "test label" seed 100 in
          Alcotest.(check string) "its first bytes" "e3f229ba727be17b8d122620557cd453" (hex (String.sub out 0 16));
          Alcotest.(check int) "100 bytes" 100 (String.length out);
          Alcotest.(check string) "a shorter one is its start" (hex (String.sub out 0 12)) (hex (Tls12.prf secret "test label" seed 12)));
      Testo.create "a record sealed is opened by the same keys, in order; changed, it is refused" (fun () ->
          List.iter
            (fun chacha ->
              let k : Tls12.keys = { chacha; key = String.make (if chacha then 32 else 16) 'k'; iv = String.make (if chacha then 12 else 4) 'i'; seq = 0 } in
              let r1, k1 = Tls12.seal k 23 "hello" in
              let r2, _ = Tls12.seal k1 23 "world" in
              let body r = String.sub r 5 (String.length r - 5) in
              Alcotest.(check string) "its header: the type, 1.2, the length" (hex ("\023\003\003\000" ^ String.make 1 (Char.chr (String.length (body r1))))) (hex (String.sub r1 0 5));
              let opened = Tls12.open_ k 23 (body r1) in
              Alcotest.(check (option string)) "the first" (Some "hello") (Option.map fst opened);
              Alcotest.(check (option string)) "the second, with the keys after the first" (Some "world") (Option.map fst (Tls12.open_ (snd (Option.get opened)) 23 (body r2)));
              Alcotest.(check bool) "out of order" true (Tls12.open_ k 23 (body r2) = None);
              Alcotest.(check bool) "as another type" true (Tls12.open_ k 22 (body r1) = None))
            [ false; true ]);
    ]

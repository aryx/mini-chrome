(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_crypto.mli *)

let unhex (h : string) : string = String.init (String.length h / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))
let hex (s : string) : string = String.concat "" (List.init (String.length s) (fun i -> Printf.sprintf "%02x" (Char.code s.[i])))

let tests =
  Testo.categorize "Crypto"
    [
      Testo.create "Hmac: RFC 4231's test case 2" (fun () ->
          Alcotest.(check string) "Jefe" "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" (hex (Hmac.sha256 "Jefe" "what do ya want for nothing?")));
      Testo.create "Hkdf: RFC 5869's test case 1" (fun () ->
          let prk = Hkdf.extract ~hmac:Hmac.sha256 ~salt:(String.init 13 Char.chr) (String.make 22 '\x0b') in
          Alcotest.(check string) "extract" "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5" (hex prk);
          Alcotest.(check string) "expand, 42 bytes" "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
            (hex (Hkdf.expand ~hmac:Hmac.sha256 prk ~info:(String.init 10 (fun i -> Char.chr (0xf0 + i))) 42)));
      Testo.create "Chacha20_poly1305: RFC 8439's section 2.8.2; a byte changed, nothing" (fun () ->
          let text = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it." in
          let key = String.init 32 (fun i -> Char.chr (0x80 + i)) and nonce = unhex "070000004041424344454647" and aad = unhex "50515253c0c1c2c3c4c5c6c7" in
          let sealed = Chacha20_poly1305.seal ~key ~nonce ~aad text in
          Alcotest.(check string) "its first bytes" "d31a8d34648e60db" (hex (String.sub sealed 0 8));
          Alcotest.(check string) "its tag" "1ae10b594f09e26a7e902ecbd0600691" (hex (String.sub sealed (String.length sealed - 16) 16));
          Alcotest.(check (option string)) "opened" (Some text) (Chacha20_poly1305.open_ ~key ~nonce ~aad sealed);
          let bad = String.mapi (fun i c -> if i = 3 then Char.chr (Char.code c lxor 1) else c) sealed in
          Alcotest.(check (option string)) "refused" None (Chacha20_poly1305.open_ ~key ~nonce ~aad bad));
      Testo.create "X25519: RFC 7748's Alice and Bob" (fun () ->
          let alice = unhex "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a" and bob = unhex "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb" in
          let shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742" in
          Alcotest.(check string) "hers with his key" shared (hex (X25519.scalar_mult alice (X25519.public_key bob)));
          Alcotest.(check string) "his with hers" shared (hex (X25519.scalar_mult bob (X25519.public_key alice))));
    ]

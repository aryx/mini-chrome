(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Tls12.mli *)

let u8 (n : int) : string = String.make 1 (Char.chr (n land 0xff))
let u16 (n : int) : string = u8 (n lsr 8) ^ u8 n
let u24 (n : int) : string = u8 (n lsr 16) ^ u16 n
let u64 (n : int) : string = String.init 8 (fun i -> Char.chr ((n lsr (8 * (7 - i))) land 0xff))
let get8 (s : string) (i : int) : int = Char.code s.[i]
let get16 (s : string) (i : int) : int = (get8 s i lsl 8) lor get8 s (i + 1)
let get24 (s : string) (i : int) : int = (get8 s i lsl 16) lor get16 s (i + 1)
let vec8 (s : string) : string = u8 (String.length s) ^ s
let vec16 (s : string) : string = u16 (String.length s) ^ s

(* ECDHE with the server's key signed by RSA or ECDSA; AES-128-GCM or
 * ChaCha20-Poly1305; SHA-256 *)
let suites = [ 0xc02f; 0xc02b; 0xcca8; 0xcca9 ]
let chacha_suite (suite : int) : bool = suite = 0xcca8 || suite = 0xcca9

let hello_extensions : string =
  let ext typ data = u16 typ ^ vec16 data in
  ext 0x0017 "" (* extended_master_secret *) ^ ext 0xff01 (vec8 "") (* renegotiation_info: none *) ^ ext 0x000b (vec8 "\000") (* ec_point_formats: uncompressed *)

(*****************************************************************************)
(* The keys *)
(*****************************************************************************)

let hash = Sha256.digest
let hmac = Hmac.sha256

(* P_hash: A(0) = the seed, A(i) = HMAC(secret, A(i-1)); the output is
 * HMAC(secret, A(1) + seed), HMAC(secret, A(2) + seed), ... *)
let prf (secret : string) (label : string) (seed : string) (n : int) : string =
  let seed = label ^ seed in
  let rec go a out = if String.length out >= n then String.sub out 0 n else let a = hmac secret a in go a (out ^ hmac secret (a ^ seed)) in
  go seed ""

type keys = { chacha : bool; key : string; iv : string; seq : int }

(*****************************************************************************)
(* The records *)
(*****************************************************************************)

(* what is authenticated beside a record: its number, type, version, length *)
let aad (k : keys) (typ : int) (length : int) : string = u64 k.seq ^ u8 typ ^ u16 0x0303 ^ u16 length

(* ChaCha20: the IV xored with the record's number (RFC 7905), as 1.3 does *)
let xored (k : keys) : string = String.mapi (fun i c -> if i < 4 then c else Char.chr (Char.code c lxor ((k.seq lsr (8 * (11 - i))) land 0xff))) k.iv

let seal (k : keys) (typ : int) (data : string) : string * keys =
  let body =
    if k.chacha then Chacha20_poly1305.seal ~key:k.key ~nonce:(xored k) ~aad:(aad k typ (String.length data)) data
    else
      (* AES-GCM: 4 bytes of the key block, then 8 sent with the record (RFC 5288) *)
      let explicit = u64 k.seq in
      explicit ^ Gcm.seal ~key:k.key ~nonce:(k.iv ^ explicit) ~aad:(aad k typ (String.length data)) data
  in
  (u8 typ ^ u16 0x0303 ^ vec16 body, { k with seq = k.seq + 1 })

let open_ (k : keys) (typ : int) (body : string) : (string * keys) option =
  let n = String.length body in
  let plain =
    if k.chacha then if n < 16 then None else Chacha20_poly1305.open_ ~key:k.key ~nonce:(xored k) ~aad:(aad k typ (n - 16)) body
    else if n < 24 then None
    else Gcm.open_ ~key:k.key ~nonce:(k.iv ^ String.sub body 0 8) ~aad:(aad k typ (n - 24)) (String.sub body 8 (n - 8))
  in
  Option.map (fun p -> (p, { k with seq = k.seq + 1 })) plain

(*****************************************************************************)
(* The handshake *)
(*****************************************************************************)

type waiting = Certificate | Key_exchange | Hello_done | Finished | Done

type t = {
  secret : string; (* our X25519 secret *)
  verify : X509.t list -> (unit, string) result;
  randoms : string * string; (* ours, the server's *)
  chacha : bool;
  extended : bool;
  waiting : waiting;
  transcript : string;
  chain : X509.t list;
  server_key : string;
  p256 : bool; (* the exchange is over P-256, not X25519 *)
  asked : bool; (* the server asked for our certificate *)
  master : string;
  write : keys option;
  read : keys option; (* the server's, once it said ChangeCipherSpec *)
  reading : bool;
}

let start ~secret ~verify ~client_random ~server_random ~(suite : int) ~(extended : bool) ~(transcript : string) : (t, string) result =
  if not (List.mem suite suites) then Error "TLS 1.2: a cipher suite we did not offer"
  else
    Ok
      { secret; verify; randoms = (client_random, server_random); chacha = chacha_suite suite; extended; waiting = Certificate; transcript; chain = [];
        server_key = ""; p256 = false; asked = false; master = ""; write = None; read = None; reading = false }

(* a Certificate message's chain: three bytes of length, then each certificate after its own three *)
let chain_of (body : string) : (X509.t list, string) result =
  let stop = 3 + get24 body 0 in
  let rec go i acc =
    if i + 3 > stop then Ok (List.rev acc)
    else
      let len = get24 body i in
      match X509.parse (String.sub body (i + 3) len) with Ok c -> go (i + 3 + len) (c :: acc) | Error e -> Error e
  in
  go 3 []

(* ServerHelloDone: our key, the keys made, and our Finished under them *)
let answer (t : t) : t * string =
  let client_random, server_random = t.randoms in
  (* asked for a certificate: an empty list of them *)
  let none = if t.asked then u8 11 ^ u24 3 ^ u24 0 else "" in
  let exchange = let b = vec8 (if t.p256 then P256.public_key t.secret else X25519.public_key t.secret) in u8 16 ^ u24 (String.length b) ^ b in
  let transcript = t.transcript ^ none ^ exchange in
  (* (a point not of the curve was refused when it came) *)
  let pre_master = if t.p256 then Option.get (P256.shared t.secret t.server_key) else X25519.scalar_mult t.secret t.server_key in
  let master =
    if t.extended then prf pre_master "extended master secret" (hash transcript) 48 else prf pre_master "master secret" (client_random ^ server_random) 48
  in
  let key_len, iv_len = if t.chacha then (32, 12) else (16, 4) in
  let block = prf master "key expansion" (server_random ^ client_random) ((2 * key_len) + (2 * iv_len)) in
  let part at len = String.sub block at len in
  let write = { chacha = t.chacha; key = part 0 key_len; iv = part (2 * key_len) iv_len; seq = 0 } in
  let read = { chacha = t.chacha; key = part key_len key_len; iv = part ((2 * key_len) + iv_len) iv_len; seq = 0 } in
  let finished = u8 20 ^ u24 12 ^ prf master "client finished" (hash transcript) 12 in
  let record, write = seal write 22 finished in
  ( { t with transcript = transcript ^ finished; master; write = Some write; read = Some read; waiting = Finished },
    u8 22 ^ u16 0x0303 ^ vec16 (none ^ exchange) ^ "\x14\x03\x03\x00\x01\x01" ^ record )

let handshake (t : t) (typ : int) (msg : string) : (t * string * bool, string) result =
  let body = String.sub msg 4 (String.length msg - 4) in
  let after = { t with transcript = t.transcript ^ msg } in
  match (t.waiting, typ) with
  | Certificate, 11 -> (
      match chain_of body with
      | Error e -> Error e
      | Ok [] -> Error "no certificate"
      | Ok chain -> Result.map (fun () -> ({ after with chain; waiting = Key_exchange }, "", false)) (t.verify chain))
  | Key_exchange, 12 ->
      (* a named curve (3), X25519 (0x001d) or P-256 (0x0017), its key;
       * then the signature's scheme and bytes *)
      let curve = if String.length body < 8 || get8 body 0 <> 3 then 0 else get16 body 1 in
      let len = if curve = 0 then 0 else get8 body 3 in
      if not ((curve = 0x001d && len = 32) || (curve = 0x0017 && len = 65)) || String.length body < 8 + len then Error "TLS 1.2: a key exchange that is neither X25519 nor P-256"
      else
        let params = String.sub body 0 (4 + len) and scheme = get16 body (4 + len) in
        let signature = String.sub body (8 + len) (get16 body (6 + len)) in
        let client_random, server_random = t.randoms in
        let server_key = String.sub body 4 len in
        if not (X509.verify_scheme (List.hd t.chain) ~scheme ~message:(client_random ^ server_random ^ params) ~signature) then
          Error (Printf.sprintf "the server's key exchange is not signed by its certificate (scheme %04x)" scheme)
        else if curve = 0x0017 && P256.shared t.secret server_key = None then Error "TLS 1.2: the server's key is not a point of the curve"
        else Ok ({ after with server_key; p256 = curve = 0x0017; waiting = Hello_done }, "", false)
  | Hello_done, 13 -> Ok ({ after with asked = true }, "", false)
  | Hello_done, 14 ->
      let t, out = answer after in
      Ok (t, out, false)
  | Finished, 20 ->
      if t.reading && body = prf t.master "server finished" (hash t.transcript) 12 then Ok ({ after with waiting = Done }, "", true)
      else Error "the server's Finished does not check"
  (* a HelloRequest, later: no renegotiation, not answered *)
  | Done, 0 -> Ok (t, "", true)
  | _ -> Error (Printf.sprintf "TLS 1.2: an unexpected handshake message (%d)" typ)

let change_cipher (t : t) : t = { t with reading = true }

let received (t : t) (typ : int) (body : string) : (string * t) option =
  match (t.reading, t.read) with
  | true, Some k -> Option.map (fun (plain, k) -> (plain, { t with read = Some k })) (open_ k typ body)
  | _ -> Some (body, t)

let sealed (t : t) (typ : int) (data : string) : string * t =
  match t.write with Some k -> let record, k = seal k typ data in (record, { t with write = Some k }) | None -> ("", t)

let certificates (t : t) : X509.t list = t.chain

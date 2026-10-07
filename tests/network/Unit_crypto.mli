(* Tests of libs/crypto's copies (Hmac, Hkdf, Chacha20_poly1305,
   X25519): each interface's worked example, the RFCs' vectors. P256's
   are with Tls12's (Unit_tls12) *)
val tests : Testo.t list

(* Chacha20_poly1305: encryption that also proves the message was not
   changed -- an AEAD, "authenticated encryption with associated data"
   (RFC 8439, section 2.8): what protects each record of TLS.

       key, nonce --Chacha20 block 0--> the first 32 bytes: Poly1305's
                                        one-time key (never reused: a
                                        new nonce per record)
       plaintext  --Chacha20 from block 1--> ciphertext
       tag = Poly1305(aad | pad | ciphertext | pad | len aad | len ct)

   The *associated data* is authenticated but not encrypted -- in TLS,
   the record's header, which the network must read. Opening checks the
   tag before giving anything back: a changed byte, and nothing.

   Worked example (RFC 8439 section 2.8.2, checked by the tests): the
   sunscreen text again, with its key, nonce and AAD 50515253 c0c1c2c3
   c4c5c6c7, gives a ciphertext starting d31a8d34 648e60db and the tag
   1ae10b59 4f09e26a 7e902ecb d0600691.

   cs-history:
   The two parts are Daniel J. Bernstein's: Poly1305 (2005), ChaCha20
   (2008, a variant of his Salsa20). That they are one cipher of TLS is
   Chrome's doing. In 2013 TLS had two families of ciphers and both
   were in trouble: the CBC ones broken in practice (BEAST, Lucky
   Thirteen), RC4 failing; what remained was AES-GCM, fast on a
   desktop's processor with its AES instructions and slow -- and hard
   to write safely -- on a phone's without them. Adam Langley and his
   colleagues at Google put Bernstein's two together as an AEAD, three
   times faster than AES-GCM on those phones, shipped it in Chrome for
   Android and on Google's servers that year, and wrote it up for the
   IETF (RFC 7539, 2015; RFC 7905 for TLS 1.2). TLS 1.3 kept it as one
   of its three ciphers, and WireGuard and OpenSSH use nothing else.

   References: RFC 8439 (2018), sections 2.6-2.8; RFC 7905 (2016), its
   suites in TLS 1.2; Adam Langley, "Speeding up and strengthening
   HTTPS connections for Chrome on Android" (Google's security blog,
   April 2014). *)

(* ciphertext followed by the 16-byte tag *)
val seal : key:string -> nonce:string -> aad:string -> string -> string

(* the plaintext, or None if the tag does not check *)
val open_ : key:string -> nonce:string -> aad:string -> string -> string option

(* two tags compared in time that does not depend on where they differ *)
val same : string -> string -> bool

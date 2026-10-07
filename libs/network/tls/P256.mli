(* P256: the key exchange over NIST's curve P-256 (secp256r1), for the
   TLS 1.2 servers that offer no other.

   Elliptic-curve Diffie-Hellman: each side has a secret number d and
   sends the point d.G, G being the curve's fixed point; each then
   multiplies the other's point by its own secret, and both arrive at
   the same point, whose x is the shared secret:

     ours  d,  sends  d.G          theirs  e,  sends  e.G
     shared = d.(e.G) = e.(d.G), its x coordinate (32 bytes)

   The curve is y^2 = x^3 - 3x + b over the integers modulo a prime p
   of 256 bits. A point is kept as three numbers (X, Y, Z) standing
   for (X/Z^2, Y/Z^3) -- Jacobian coordinates, which add and double
   points without a division each time; the multiplication is by
   doubling and adding along the secret's bits. A point is sent as 65
   bytes: 4, then x, then y.

   Not constant-time: how long a multiplication takes depends on the
   secret's bits, as everything of this browser's cryptography; a
   secret is used for one handshake.

   cs-history:
   Elliptic curves for cryptography are Neal Koblitz's and Victor
   Miller's, independently, in 1985: the security of RSA's 3072 bits
   in 256. P-256 is one of the curves NIST published in 1999 (FIPS
   186-2), its constant b made from a seed nobody explained -- the
   doubt that, after 2013, sent new designs to Daniel Bernstein's
   Curve25519 (2005), which TLS 1.3 and this browser prefer (X25519).
   A server set up before that still offers P-256 alone.

   References: SEC 1 and SEC 2 (the curve's numbers); RFC 8422 (its
   use in TLS); the Explicit-Formulas Database (the formulas here:
   dbl-2001-b, add-2007-bl). *)

(* our point for a secret of 32 bytes: 65 bytes *)
val public_key : string -> string

(* the shared secret with the other side's point (65 bytes), 32 bytes;
   None if it is not a point of the curve *)
val shared : string -> string -> string option

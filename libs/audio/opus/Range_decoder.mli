(* Range_decoder: symbols out of a number -- the arithmetic coding
   Opus is written in.

   Huffman's codes (Vorbis's, JPEG's, Deflate's) give each symbol a
   whole number of bits: a symbol nine times in ten still costs one
   bit, where it carries a seventh of one. An arithmetic coder has no
   such floor: the whole message is one number in [0, 1), and each
   symbol narrows the interval where that number lies, by its
   probability --

     symbols a (3/4) and b (1/4); the message "aab":

     [0 ........................... 1)
     a: [0 ............... 3/4)
     a: [0 ...... 9/16)
     b:      [27/64 .. 9/16)        any number in there says "aab":
                                    0.5 does, in one bit

   and a likely symbol narrows it little: costs little. The decoder
   has the number and does the same narrowing, seeing at each step
   which symbol's part the number is in.

   A *range* coder is that with whole numbers and bytes: the interval
   is a range of 32 bits, and when it gets under 2^23 a byte comes in
   and it is widened by 256 ([normalize]). Probabilities are whole
   counts out of a total: a symbol is the counts below it and its own
   ([decode] says where the number falls, [update] narrows).

   What Opus adds:

     [bit]       a flag likely one way: 1 in 2^logp
     [icdf]      a symbol by a small table of counts (cumulative,
                 from the top, out of a power of two)
     [uint]      a number of 0 to n-1, every one as likely
     [laplace]   a small number near 0, either sign: the energy's
     [bits]      plain bits, read from the *end* of the packet
                 backwards: what would gain nothing by being coded
                 (signs, the last bits of a number). The two meet in
                 the middle, and nothing says where

   and [tell]: how many bits have been used so far, to an eighth
   ([tell_frac]) -- which the format asks for all the time, since what
   is decoded next depends on the bits left (Celt_rate.mli). A new
   decoder has used 1.

   cs-history:
   Arithmetic coding is Jorma Rissanen's and Richard Pasco's (IBM and
   Stanford, 1976); the range coder, its form in bytes, G. N. N.
   Martin's (Range encoding: an algorithm for removing redundancy
   from a digitised message, 1979). IBM's patents kept it out of
   formats for twenty years -- JPEG has an arithmetic mode nobody
   used -- and every codec since they ran out has one: H.264's CABAC,
   AV1, Opus.

   Reference: RFC 6716, section 4.1. *)

type t

val create : string -> t

(* the packet's size in bytes *)
val size : t -> int

(* bits used so far, whole (rounded up) and in eighths *)
val tell : t -> int

val tell_frac : t -> int

(* [bit t logp]: a flag that is true 1 time in 2^logp *)
val bit : t -> int -> bool

(* [icdf t table bits]: a symbol; table.(k) is, out of 2^bits, the
 * chance of a symbol after k *)
val icdf : t -> int array -> int -> int

(* [uint t n]: a number of 0 to n - 1 *)
val uint : t -> int -> int

(* [bits t n]: n plain bits, from the packet's end *)
val bits : t -> int -> int

(* a number near 0: [zero], the chance of 0 out of 32768; [decay], how
 * fast the others fall off, out of 16384 *)
val laplace : t -> zero:int -> decay:int -> int

(* [decode t total]: where the number falls, 0 to total - 1; then
 * [update t low high total] for the symbol whose counts are from low
 * to high *)
val decode : t -> int -> int

val update : t -> int -> int -> int -> unit

(* the rest of the packet counted as used (a frame of silence) *)
val skip : t -> int -> unit

(* the range itself, at the end: the next frame's noise starts from it *)
val range : t -> int

(* how many bits a number takes: 0 for 0, 3 for 4 to 7 *)
val ilog : int -> int

(* Celt_rate: who gets how many bits -- computed, not sent.

   A codec must say how the bits of a frame are shared between its
   bands. MP3 and AAC send it (scale factors, a table per frame);
   Vorbis sends the floor. CELT sends almost nothing: the encoder and
   the decoder both compute the share from what they both know -- the
   frame's size and how many bits it has -- and the stream only
   corrects it:

     eleven curves   bits a band at eleven qualities (Celt_tables),
                     made by ear once and for all: the budget falls
                     between two of them, found by bisection, and how
                     far between, in 64ths
     a tilt          more to the low bands or to the high ("trim")
     boosts          a band the encoder wants more for
     bands given up  from the top: a bit each says where it stops
     two channels    where intensity stereo starts, and whether the
                     two are coded apart

   Then each band's bits are cut in two: some make its energy finer,
   the rest are for its shape (Celt_bands.mli), in the proportion
   that makes the two errors alike. Bits are counted in eighths: the
   range decoder knows how much of a bit a symbol took.

   Since nothing of this is sent, it must come out the same on every
   machine: whole numbers only, shifts and tables.

   The last step is a table too: how many pulses a number of bits
   buys in a band of a size ([bits_to_pulses], from the cost of 1, 2,
   3... pulses, which is the logarithm of how many vectors there are).

   Reference: RFC 6716, section 4.3.3. *)

type t = {
  coded : int; (* the bands with a shape are those below it *)
  intensity : int; (* from this band on, two channels are one and a sign *)
  dual : bool; (* two channels coded apart *)
  balance : int; (* bits the first bands may borrow, in eighths *)
  pulses : int array; (* each band's bits for its shape, in eighths *)
  fine : int array; (* each band's bits to make its energy finer, a channel *)
  priority : int array; (* 0: among the first to get a bit left at the end *)
}

(* the most each band can use, in eighths of a bit *)
val caps : lm:int -> channels:int -> int array

(* [allocation dec ~start ~stop ~boosts ~cap ~trim ~total ~channels
 * ~lm]: the share of [total] eighths of a bit; reads the bands given
 * up and the two numbers of stereo *)
val allocation :
  Range_decoder.t -> start:int -> stop:int -> boosts:int array -> cap:int array -> trim:int -> total:int -> channels:int -> lm:int -> t

(* how many pulses a step of the table stands for: 0 to 7 as they
 * are, then by eighths of an octave (8, 9... 15, 16, 18, 20...) *)
val pulses_of : int -> int

(* where a band's costs are in Celt_tables.cache_bits, for blocks of 2^lm (-1: half a short block) *)
val cache : int -> int -> int

(* [bits_to_pulses band lm bits]: the step whose cost is nearest; and its cost, in eighths *)
val bits_to_pulses : int -> int -> int -> int

val pulses_to_bits : int -> int -> int -> int

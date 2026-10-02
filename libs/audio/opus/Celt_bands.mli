(* Celt_bands: the shape of each band of a frame -- pulses, splits,
   folding.

   A band's shape is n numbers of length one (Celt.mli: its energy is
   sent apart). It is coded as k *pulses*: n whole numbers whose sizes
   add up to k, then scaled to length one. With n = 2 and k = 2 there
   are 8:

     (2,0) (1,1) (1,-1) (0,2) (0,-2) (-2,0) (-1,1) (-1,-1)

   numbered 0 to 7 in that order: points spread on the diamond
   |a| + |b| = 2, pushed out to the circle. More pulses, more points, a finer shape. Nothing is coded
   pulse by pulse: all the vectors of (n, k) are counted -- V(n,k), by
   a recurrence ([counts]: V(3,2) is 18) -- and the one meant is sent
   as its number among them, every one as likely, by the range
   decoder ([vector_of_index]). No table and no code to design: a
   quantizer by arithmetic.

   Around that:

     a rotation    a band of few pulses would be a few lone tones;
                   its numbers are mixed with their neighbours' by
                   small rotations, as much as the frame says (its
                   "spread")
     a split       more bits than one vector's number can hold (32
                   bits): the band is cut in two halves, with an
                   angle saying how the energy is shared, and so on
                   down
     two channels  the same split: a mid and a side and the angle
                   between, or, from a band on, one channel and a
                   sign (intensity), or each by itself (dual)
     folding       a band with no bit is not left empty: it takes the
                   shape of a lower band already decoded, or noise;
                   its energy is right either way
     blocks        a band's numbers reordered and summed in pairs
                   (Hadamard, Haar) when the frame is short blocks,
                   so that each block gets its pulses

   and, for a transient, a last repair ([anti_collapse]): a short
   block left with nothing in a band that was loud just before is
   given noise, so that it does not sound as a hole.

   The arithmetic that decides anything -- how many angles, how the
   bits of a split are shared -- is in whole numbers, with a cosine
   and a logarithm of their own, for the encoder and every decoder to
   agree to the bit.

   cs-history:
   Thomas Fischer, A Pyramid Vector Quantizer, IEEE Transactions on
   Information Theory, 1986: the points of the pyramid |x1| + ... +
   |xn| = k as a codebook, for sources whose numbers follow Laplace's
   law. Counting them and numbering them fast enough for n = 176 is
   CELT's (Timothy Terriberry's "cwrs", combinations with replacement
   and signs).

   References: RFC 6716, sections 4.3.4 (shapes) and 4.3.5
   (anti-collapse). *)

(* U(n, 0..k+1), from which V(n,k) = U(n,k) + U(n,k+1), the number of
 * vectors of n whole numbers whose sizes add up to k *)
val counts : int -> int -> int array

(* the vector of (n, k) with that number, 0 to V(n,k) - 1 *)
val vector_of_index : ?u:int array -> int -> int -> int -> int array

(* [all dec ~start ~stop ~x ~y ~alloc ~short ~spread ~tf ~total_bits
 * ~lm ~seed]: the bands from [start] to [stop] decoded into x (and y,
 * a second channel), each of length one; [tf], each band's turn in
 * time or frequency; [total_bits] in eighths. Which blocks of each
 * band and channel got something (a bit a block), and the noise's
 * seed after *)
val all :
  Range_decoder.t ->
  start:int ->
  stop:int ->
  x:float array ->
  y:float array option ->
  alloc:Celt_rate.t ->
  short:bool ->
  spread:int ->
  tf:int array ->
  total_bits:int ->
  lm:int ->
  seed:int ->
  int array * int

(* noise in the short blocks that got nothing ([masks], from [all]),
 * at the level of the two frames before ([before1], [before2], and
 * now [energy]: each band's, in log2, two channels) *)
val anti_collapse :
  x:float array array ->
  masks:int array ->
  lm:int ->
  start:int ->
  stop:int ->
  energy:float array ->
  before1:float array ->
  before2:float array ->
  pulses:int array ->
  seed:int ->
  unit

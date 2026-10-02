(* Vp8_tables: the numbers of VP8 that are not computed but given.

   An arithmetic coder is as good as its probabilities (Vp8.mli), and
   VP8's were counted on many videos by its makers and written in the
   standard: of a block's ten modes after each pair of modes above
   and on its left, of each token of a coefficient by plane, band and
   neighbours. A frame can change the second; the first are the
   format. The quantizers' steps are here too. All are RFC 6386's,
   taken from its text by a program and not typed: 3,268 numbers, one
   of which wrong would give a picture nearly right.

   Each table is flat; its comment says the dimensions. *)

(* the probabilities of a 4 x 4 block's mode in a key frame:
 * [10 above] [10 left] [9 branches of the modes' tree]  (section 11.5) *)
val kf_bmode_probs : int array

(* the probability that the frame's header changes each of the
 * coefficients' probabilities: [4] [8] [3] [11]  (section 13.4) *)
val coeff_update_probs : int array

(* the coefficients' probabilities until changed:
 * [4 kinds of block] [8 bands] [3 contexts] [11 branches of the
 * tokens' tree]  (section 13.5) *)
val default_coeff_probs : int array

(* a quantizer's index, 0 to 127, to its step, for a block's first
 * coefficient and for the others  (section 14.1) *)
val dc_q : int array
val ac_q : int array

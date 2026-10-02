(* Celt_tables: CELT's numbers -- the bands, the allocation's curves,
   the costs of pulses, the energies' laws.

   The 21 bands, in steps of 200 Hz (a short block's 100 numbers at
   48,000 Hz): one step wide up to 1.6 kHz, then wider, to 20 kHz --

     0 200 400 ... 1600 2000 2400 2800 3200 4000 4800 5600 6800 8000
     9600 12000 15600 20000

   near the ear's critical bands (Zwicker's Bark scale), on which a
   codec's bands have been cut since MP3.

   The tables are the standard's, taken from its decoder (RFC 6716's
   appendix) by a program: nothing here was chosen. Two could be
   computed instead of kept -- what k pulses cost in a band is the
   logarithm of the count of vectors (Celt_bands.counts) -- and are
   kept so that they are surely the reference's, to the bit. *)

(* 21 *)
val bands : int

(* where each band starts, in a short block's numbers; 22 of them *)
val band_edges : int array

(* log2 of each band's width, in eighths *)
val log_n : int array

(* the allocation's eleven curves, a row of 21 each: 1/32 bit a number *)
val allocation : int array

(* the first step of each band's energy: the chance of 0 and the decay,
 * two a band, a row of 42 for each frame size (four) and each of
 * "from the frame before" and "by itself" *)
val energy_model : int array

(* each band's usual energy, in log2 *)
val means : float array

(* 8 log2 n, rounded up *)
val log2_frac : int array

(* the costs of pulses: for a block size (five rows of 21 bands, from
 * half a short block) where a band's list is in [cache_bits], or -1;
 * a list is its length, then the cost less one, in eighths of a bit,
 * of each step (Celt_rate.pulses_of) *)
val cache_index : int array

val cache_bits : int array

(* the most a band can use, by block size and channels: rows of 21 *)
val cache_caps : int array

(* the range decoder's tables (Range_decoder.icdf) *)
val spread_icdf : int array

val trim_icdf : int array
val tapset_icdf : int array
val small_energy_icdf : int array

(* Celt: a frame of Opus's transform codec decoded -- the energy of
   each band kept exact, its shape a point on a sphere.

   A transform codec (Vorbis.mli, Mdct.mli) sends a block's
   frequencies coarsely. Where the others lose: a band given few bits
   comes back quieter than it was, or silent, and music at a low rate
   sounds muffled, with holes that come and go. CELT (Constrained
   Energy Lapped Transform) starts from what the ear will not forgive
   and makes it impossible: each band's *energy* is sent by itself,
   first and exactly enough; what is left of the band -- its numbers
   divided by that energy, a vector of length one -- is its *shape*,
   sent with whatever bits remain. Few bits make a shape that is
   wrong, never a band that is quiet.

     packet --> flags --> energies, coarse --> who gets how many bits
            --> energies, finer --> shapes --> energies, last bits
            --> shape x energy --> inverse MDCT --> window, overlap
            --> post-filter --> de-emphasis

   The spectrum (to 20 kHz) is cut in 21 bands, narrow at the bottom
   (200 Hz) and wide at the top, as the ear's own (Celt_tables).

   The energies ([coarse_energy]): each to 6 dB, as a difference from
   what the same band was a frame before and from the band below, a
   small number that is mostly 0 (a Laplace law, the range decoder's);
   then finer, with bits the allocation gives.

   The bits are not said. How many bits each band's shape gets is
   computed, the same by the encoder and the decoder, from what both
   know (the frame's size, the bits it has; Celt_rate.mli): a codec
   whose side information is almost nothing, which is what frames of
   2.5 ms need.

   The shapes (Celt_bands.mli): k pulses shared between a band's n
   numbers, all such vectors counted and the one meant sent as its
   number.

   A frame is one long block (to 20 ms), or, where the sound has an
   attack (a transient), eight short ones whose numbers come in turn:
   fine in time, so that the noise of coding does not come before the
   stroke. A band can also be turned one way or the other by itself
   ([time_frequency], a sum and a difference of neighbours).

   The window is flat for most of a block and slopes over 2.5 ms only
   (120 samples): the codec's delay is that overlap, not half a block.
   The price is leakage between frequencies, and a pitched sound (a
   voice, a string) coded less well; so the encoder takes the pitch
   out before, and the decoder puts it back after ([comb]: each sample
   plus a little of those one period earlier), which also pushes the
   coding noise under the harmonics.

   Not done: a lost frame concealed.

   cs-history:
   Jean-Marc Valin (Xiph.Org), from 2007: a codec for playing music
   together over a network, where 20 ms of delay is too much -- and
   where MP3 and Vorbis, with blocks of 46 ms and more, could not go.
   Its two ideas are older than it: the energy kept apart is what a
   speech codec does with its gain; the shape on a sphere of pulses is
   Thomas Fischer's pyramid vector quantizer (1986). What was new was
   to build a whole codec of music on them, and to compute the
   allocation instead of sending it.

   References: RFC 6716, section 4.3; J.-M. Valin, T. Terriberry,
   C. Montgomery and G. Maxwell, A High-Quality Speech and Audio Codec
   With Less Than 10 ms Delay, IEEE Transactions on Audio, Speech and
   Language Processing, 2010. *)

(* a decoder: each band's energy in the frames before, the samples
 * past (the post-filter looks back a period), the half window the
 * next frame is added to *)
type t

(* for a stream played in one or two channels *)
val create : channels:int -> t

(* [decode t ~stream_channels ~lm ~stop frame]: a frame of 120 * 2^lm
 * samples (2.5 to 20 ms at 48,000 Hz), coded in one or two channels,
 * its bands under [stop] (13, 17, 19 or 21: 4, 8, 12 or 20 kHz). Each
 * of the decoder's channels, from -1 to 1. A frame of one byte or
 * none is silence *)
val decode : t -> stream_channels:int -> lm:int -> stop:int -> string -> float array array

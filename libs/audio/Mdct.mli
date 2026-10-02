(* Mdct: the transform of the sound codecs -- m frequencies made the 2m
   samples of a block that overlaps its neighbours by half.

   A codec of sound cuts it in blocks and sends each block's
   frequencies, coarsely. Blocks that only touch would click where
   they meet, each rounded its own way; blocks that overlap by half
   would cost twice the numbers. The modified discrete cosine
   transform does both: a block of 2m samples is folded onto m
   frequencies,

     X.(k) = the sum over n < 2m of
               x.(n) cos (pi / m (n + 1/2 + m/2) (k + 1/2))

   which cannot be undone -- m numbers do not say 2m. Going back
   ([imdct]: the same sum, over k) gives the block plus itself
   mirrored: an alias. But the next block's alias, over the half they
   share, is the same with the other sign; with a window on each block
   whose two slopes' squares add to one, the halves added give the
   sound back. Time-domain aliasing cancellation: half-overlapping
   blocks at the price of blocks that touch.

     block 1   /~~~~~~\
     block 2       /~~~~~~\          each sent as m numbers,
     block 3           /~~~~~~\      m new samples a block

   Worked example, m = 2: the frequencies (1, 0) are the four samples
   cos (pi/8 (2n + 3)), n = 0..3: 0.383, -0.383, -0.924, -0.924 -- odd
   around the middle of its first half, even around that of its
   second: the two mirrors.

   cs-history:
   John Princen and Alan Bradley (University of Surrey) gave the
   cancellation in 1986, and with A. Johnson the transform in this
   form in 1987. Every codec of sound since stands on it: MP3 (1993:
   after its filterbank), AAC, Dolby's AC-3, Vorbis, and Opus's CELT.
   What differs between them is the window, the sizes of the blocks,
   and how the m numbers are written.

   By its definition the sum costs m cosines for each of 2m samples.
   It is a cosine transform of size m (the DCT-IV, [dct4_simple])
   unfolded, and that one is a Fourier transform of m/2 complex
   numbers between two rotations ([dct4_opti]). The Fourier transform
   here ([fft]) takes any size, cutting it by its small factors:
   Vorbis's blocks are powers of two, Opus's are 15 times one (120,
   240, 480, 960: 2.5 ms and its doubles, at 48,000 Hz).

   References: J. Princen and A. Bradley, Analysis/synthesis filter
   bank design based on time domain aliasing cancellation, IEEE
   Transactions on Acoustics, Speech, and Signal Processing, 1986;
   J. Princen, A. Johnson and A. Bradley, Subband/transform coding
   using filter bank designs based on time domain aliasing
   cancellation, ICASSP 1987. *)

(* m frequencies as the 2m samples of their block (not windowed, not
 * scaled: each codec's own) *)
val imdct : float array -> float array

(* u.(n) = the sum over k of x.(k) cos (pi / m (n + 1/2) (k + 1/2)), by
 * the definition; and by a Fourier transform *)
val dct4_simple : float array -> float array

val dct4_opti : float array -> float array

(* one or the other, on Mini_opti.enabled *)
val dct4 : float array -> float array

(* the discrete Fourier transform of complex numbers, their real and
 * imaginary parts: X.(k) = the sum over n of x.(n) e^(-2 i pi n k / size) *)
val fft : float array -> float array -> float array * float array

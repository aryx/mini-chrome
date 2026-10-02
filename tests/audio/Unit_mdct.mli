(* Tests of Mdct: the worked example, the samples against the
 * definition's sum, the fast cosine transform against the simple one
 * at Vorbis's sizes and Opus's, the Fourier transform at a size that
 * is no power of two. *)

val tests : Testo.t list

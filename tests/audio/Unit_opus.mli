(* Tests of Opus and what it stands on (Range_decoder, Celt_bands'
 * pulses, Celt_rate's table): the interfaces' worked examples, a
 * packet's frames by each of its four codes, and five files of
 * libopus's encoder (data/, made by data/make.sh) decoded to
 * libopus's samples, a rounding apart; SILK and a lost frame are
 * silence. *)

val tests : Testo.t list

(* Tests of Vorbis and Ogg: the specification's example of codes from
 * their lengths, the fast transform against its definition, Ogg's
 * packets across pages, and four files of others' encoders (data/,
 * made by data/make.sh) decoded to libvorbis's sound, a rounding
 * apart. *)

val tests : Testo.t list

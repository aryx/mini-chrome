(* Brotli's static dictionary, the bytes themselves: 13,504 words and
   fragments of six languages, of HTML and of JavaScript, 122,784 bytes
   that every Brotli decoder carries (Brotli_dictionary.mli says how
   they are laid out and used; RFC 7932's Appendix A prints them).
   Brotli.decompress takes its words from here.

   Generated from dictionary.bin (Google's file, MIT license) by the
   dune rule, so the browser's binary has them and reads no file. *)

val bytes : string

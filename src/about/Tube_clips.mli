(* The files about:tube plays (Tube.mli), each a file's name and bytes:
 * every kind of media the browser reads. One clip -- a ball bouncing
 * and a square turning, filmed by our own 2D rasterizer -- in the
 * containers and codecs of video (VP8 and Vorbis in a WebM, MPEG-1
 * with its MP2 in an .mpg, both made once by ffmpeg; MPEG-1 alone,
 * Motion JPEG with PCM in an AVI, FLC, raw Y4M, made here by
 * tiny_libs' writers) and an animated GIF written by hand. Two chirps
 * in the codecs of sound (Opus in its file and in a WebM, Vorbis, MP3,
 * MP2: others' encoders, once) and blips as a WAV. A tune in the
 * formats that hold notes: ABC and solfege (text), a MIDI file and a
 * tracker's module (made here). Each item's bytes made when first
 * forced: encoding the clip takes a second. *)
val playlist : (string * string Lazy.t) list

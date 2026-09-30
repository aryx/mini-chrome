(* The files about:tube plays (Tube.mli), each a file's name and bytes:
 * one clip -- a ball bouncing and a square turning, filmed by our own
 * 2D rasterizer -- in the containers and codecs the browser reads
 * (MPEG-1 video with its MP2 in an .mpg, made once by ffmpeg; Motion
 * JPEG with PCM in an AVI; FLC; raw Y4M, made here by tiny_libs'
 * writers), an animated GIF written by hand, and two chirps as an MP3
 * (LAME's). Each item's bytes made when first forced: encoding the
 * clip takes a second. *)
val playlist : (string * string Lazy.t) list

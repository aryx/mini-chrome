(* Tube: a video site of our own in the browser's built-in site -- what
 * a video site asks of a browser, without the real one (YouTube's
 * streams are H.264 and AV1, its pages megabytes of script).
 *
 *   about:tube         the index: a thumbnail per clip (a <video> paused
 *                      on its first frame) in a grid of flexbox, then
 *                      every kind of sound the browser plays, an
 *                      <audio> each
 *   about:tube-N       a clip's page: its player (<video controls
 *                      autoplay>), its title and description, the next
 *                      ones beside it
 *   about:clip/NAME    the files (Tube_clips): one clip -- a ball and a
 *                      square, filmed by our own 2D rasterizer -- in the
 *                      containers and codecs the browser reads (VP8
 *                      with Vorbis in a WebM, MPEG-1 with its MP2 in an
 *                      .mpg and alone, Motion JPEG with PCM in an AVI,
 *                      FLC, raw Y4M, an animated GIF); two chirps as
 *                      Opus (in its file, in a WebM), Vorbis, MP3 and
 *                      MP2, blips as a WAV; a tune as a MIDI file, a
 *                      module, ABC and solfege
 *
 * so the page fetches nothing and changes for no one else. *)

(* about:NAME's bytes and type, for the names above *)
val about : string -> (string * string) option

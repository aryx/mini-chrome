(* Vp8_video: VP8 as a video -- the frames predicted from other frames.

   A still picture is one key frame (libs/images' Vp8.mli: the guesses
   from neighbours, the transform, the tokens, the loop filter). A
   video is a key frame now and then, and between them frames that
   say, block by block, "as that frame, there, and this much
   different". Nearly everything in a moving picture was in the frame
   before, a little to one side: saying where costs a few bits, where
   saying what costs thousands.

     key frame      frame 2              frame 3
     +--------+     +--------+           +--------+
     | whole  | <-- | mostly | <-------- | mostly |
     +--------+     | vectors|           | vectors|
                    +--------+           +--------+

   What a frame that is not a key frame adds, a macroblock at a time:

   **Whose it is.** A macroblock is guessed from this frame, as in a
   still (it happens: something new came in), or predicted from one of
   three kept frames:

     last      the frame before
     golden    one kept from further back: the background a passing
               thing hid, there again when it has passed
     altref    another kept one, that may never have been shown: an
               encoder that reads ahead makes a frame that is the
               average of the next ones, sends it hidden, and predicts
               them from it

   Each frame's header says which of the three it becomes once
   decoded, or is copied to, and whether it is shown ([decode] gives
   that).

   **By what vector.** 16 x 16 pixels moved by (x, y) quarter pixels.
   A vector is rarely new: things move together, so a macroblock's is
   most often one of its neighbours'. The three already decoded
   (above, left, above left) are looked at, their vectors counted (2,
   2 and 1) and ranked, and the mode is one of

     nearest    the most used neighbour vector
     near       the second
     zero       none: as the reference, in place
     new        the best neighbour's plus a difference, read
     split      the macroblock in 2, 4 or 16 parts, each with its own
                (its left neighbour's, the one above's, zero, or new)

   read with probabilities that depend on how the neighbours agreed --
   where they all moved alike, "nearest" costs a fraction of a bit.

   **From between pixels.** A vector's fraction is a place between
   pixels, whose value is made from the six pixels round it, across
   then down, with weights for each eighth (the .ml's sixtap): a
   quarter pixel to the right is 108 parts of a pixel and 36 of the
   next, less 11 and 8 of those beside, plus 2 and 1 of the ones
   beyond (out of 128). Chroma, half the size, has the mean
   of its luma blocks' vectors, in eighths. A vector may point past
   the frame's edge: the edge's pixels go on for ever.

   Then the residue is read and added, as in a still, and the frame's
   edges are filtered -- which is why it is called the loop filter:
   the filtered frame is the one the next is predicted from, so that
   the encoder and every decoder must filter alike, to the bit. A
   macroblock's filter is as strong as its frame's, its segment's,
   and what its reference and mode add (a still's "added" is here
   used whole).

   What lasts from frame to frame, and is the decoder's state: the
   three frames, the probabilities (of coefficients, of modes, of
   vectors, each changed a little by a frame's header), the segment
   each macroblock is in. A key frame starts all of it again: which
   is why a player can only begin, or jump to, a key frame.

   Checked to the byte: seven clips made by libvpx, every frame the
   same as ffmpeg's decoder gives (tests/video). VP8 is specified so:
   a decoder is right when its frames are identical, not close.

   cs-history:
   Predicting a block from where it was is as old as digital video:
   H.261 (1988, for video calls), then MPEG-1 (1993: elm-playground's
   Mpeg1.mli, whose vectors are half pixels and whose in-between is
   the mean of two). Each generation spent more on the same idea:
   quarter pixels and a six-tap filter, blocks split down to 4 x 4,
   several frames to choose from (H.264, 2003). VP8 has those, in its
   own forms. The golden frame is On2's, from its earlier codecs, and
   the hidden alternate reference VP8's own: a frame made to be
   predicted from, never to be seen.

   evolution:
   VP9 (2013) and AV1 (2018) are this, grown: blocks up to 64 then
   128 pixels and down to 4, more frames to predict from and two at
   once, vectors of eighths, far more work to encode for about half
   the bytes each time. YouTube took up VP9, then AV1. H.264 remains
   what every device decodes in hardware.

   modern:
   A real browser does not decode on its main thread, nor to RGB: the
   frames go from a decoder (often the graphics card's) to the
   compositor as YUV planes, and are converted when drawn. Here a
   frame is decoded when it is asked for, to a picture; a clip of 176
   by 144 takes about 3 ms a frame.

   Reference: RFC 6386, sections 9.7 to 9.10 (the header), 16 (modes),
   17 (vectors), 18 (prediction between frames), and its decoder's
   source (dixie's modemv.c and predict.c), which this follows. *)

(* a decoder, between frames: the frames kept, the probabilities *)
type t

val create : unit -> t

(* [decode t frame]: a frame's bytes decoded (a key frame, or one
 * predicted from those before it); whether it is to be shown (a
 * hidden one is kept to predict from). Raises [Failure] or
 * [Invalid_argument] on bytes that are not a frame, or on a predicted
 * frame when no key frame came first *)
val decode : t -> string -> bool

(* the frames' size, once a key frame was decoded *)
val size : t -> int * int

(* the last frame shown, as a picture *)
val picture : t -> Rgba_image.t

(* the same as raw video: its luma, row by row, then each chroma at
 * half the size (I420): what the tests compare *)
val yuv : t -> string

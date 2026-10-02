(* Vp8: WebP's lossy format -- one key frame of the VP8 video codec,
   decoded to a picture.

   A video codec sends most frames as what changed since another one.
   But the first frame, and one every few seconds after (to start from
   after a seek, or a loss), has no other to lean on: a key frame,
   coded from itself alone. That is a compressed picture, and WebP is
   that part of VP8 put to work alone. It is JPEG's scheme (elm-
   playground's Jpeg.mli) with what video coding learned in the twenty
   years after:

                       JPEG (1992)            VP8 (2008)
     colours           YCbCr, chroma halved   the same (4:2:0)
     blocks            8 x 8                  16 x 16 macroblocks, of
                                              4 x 4 blocks
     a block is sent   as it is               as its difference from a
                                              guess made of its
                                              neighbours
     transform         DCT, 8 x 8             DCT, 4 x 4, in integers
     numbers coded by  Huffman codes          an arithmetic coder,
                                              with probabilities that
                                              depend on the neighbours
     blocks' edges     show                   smoothed (the loop filter)

   The frame. Three bytes of tag (Webp.mli's example: 10 05 00, the
   bytes turned round 0x000510: bit 0 clear, a key frame; bit 4, to be
   shown; the rest, 0x510 lsr 5 = 40, the first part's size), the
   start code 9d 01 2a, the sizes; then the parts:

     the first partition   the frame's header (segments, the filter,
                           the quantizers, the probabilities changed),
                           then each macroblock's modes
     1, 2, 4 or 8 others   the coefficients, a row of macroblocks in
                           one, the next row in the next: rows that an
                           encoder or a decoder with as many
                           processors can work on at once

   Every one of them is read through the boolean decoder.

   The boolean decoder. An arithmetic coder writes a whole message as
   one number, a fraction, each symbol narrowing the interval the
   number is in by that symbol's share of it; a likely symbol narrows
   it little and costs less than a bit, which no Huffman code can do.
   VP8's symbols are all booleans. The decoder keeps a [range] (128 to
   255) and a [value] read from the bytes; to read a boolean that is
   false with a probability of p in 256:

     split = 1 + (((range - 1) * p) lsr 8)
     value < split:  false; range becomes split
     otherwise:      true;  range and value are lessened by split
     then both are doubled, a new bit let in, until range >= 128

   With range 255 and p 128 the split is 128, the middle: a coin. With
   p 250 it is 249: false keeps the range nearly whole and costs
   almost nothing, true leaves 6 and five doublings. Anything larger
   than a boolean is read as a walk down a small tree, a boolean a
   branch, each with its probability ([tree]).

   A macroblock. 16 by 16 pixels of luma, and 8 by 8 of each chroma.
   Its luma is guessed whole, in one of four ways, or as sixteen
   4 x 4 blocks, each in one of ten:

     whole:   DC (the mean of the pixels above and on the left), V
              (each column, the pixel above it), H (each row, the one
              on its left), TM (left + above - the corner)
     4 x 4:   those four, and six that carry the pixels above and on
              the left along a slant, down to the left, down to the
              right, and four between: an edge crossing the block

   Beyond the frame's edge the row above is 127 and the column on the
   left 129. Each 4 x 4 mode is read with probabilities chosen by the
   modes of the blocks above and on the left (an edge goes on): a
   table of 10 x 10 x 9 numbers (Vp8_tables). The chroma has the four
   whole modes.

   Then what the guess missed, the residue: for each 4 x 4 block, 16
   coefficients in zigzag order, read as tokens (zero, one, two...,
   ranges with extra bits, the end of the block) whose probabilities
   depend on the plane, on how far in the zigzag (a band), and on
   whether the neighbours had any: 4 x 8 x 3 x 11 numbers, which the
   frame's header may change. Each is multiplied by its quantizer and
   the block put through the inverse DCT, and added to the guess. A
   macroblock guessed whole has a 25th block, Y2: the sixteen blocks'
   first coefficients, their means, taken out and transformed once
   more together (a Walsh-Hadamard transform), since a flat area's
   means are alike.

   The loop filter. Blocks quantized apart do not meet: JPEG's
   squares. Once the frame is whole, each edge between blocks is
   looked at, and where the step across it is small (a seam and not
   an edge of the picture: the frame's thresholds say) the pixels on
   both sides are moved towards each other -- one on each side (the
   simple filter), or up to three (the normal one). In a video the
   filtered frame is the one the next frames are predicted from, the
   filter is inside the coding loop: hence its name.

   Last, the colours: the chroma, half the size, is enlarged (each
   pixel 9, 3, 3 and 1 sixteenths of the four samples round it), and
   YUV made RGB (ITU-R BT.601). That part is not VP8's but libwebp's,
   and done its way to the bit, so that the pictures are the same.

   cs-history:
   On2's eighth codec (Webp.mli says how it came to Google and out).
   Its ideas are those of H.264 (2003), the standard it competed with:
   the guess from neighbours along a direction, the 4 x 4 transform in
   integers that any decoder computes alike, the filter in the loop.
   TM, TrueMotion, the one mode H.264 has not, bears the name of On2's
   first codecs. Its entropy coder goes back further: arithmetic
   coding is Rissanen's and Pasco's (1976), and Witten, Neal and
   Cleary's Arithmetic Coding for Data Compression (CACM, 1987) is how
   programmers learnt it. JPEG has had one too since 1992, as an
   option nobody used: IBM's patents on it.

   cs-history:
   The format's definition is unusual: RFC 6386 (Bankoski, Koleszar,
   Quillio, Salonen, Wilkins and Xu, November 2011), VP8 Data Format
   and Decoding Guide, three hundred pages of which the larger part is
   a decoder's source in C, and which says that where the prose and
   the code differ the code is right. A format defined by its
   program: bought, then described, not designed in a committee.

   evolution:
   VP9 (2013) took the blocks to 64 x 64 and YouTube with it; AV1
   (2018), the Alliance for Open Media's, is its descendant. And WebRTC
   (a browser's calls) made VP8 one of its two required codecs in
   2014, so every browser decodes it yet.

   road-not-taken:
   The frames between key frames -- a macroblock guessed from where it
   was in an earlier frame, a motion vector saying where -- are the
   other half of RFC 6386 and of a video player; not read here, where
   a frame that is not a key frame is refused.

   Reference: RFC 6386; its sections 7 (the boolean decoder), 9 (the
   frame's header), 11 and 12 (the modes and the guesses), 13 and 14
   (the coefficients and the transforms), 15 (the loop filter). *)

(* a key frame's picture, opaque; the bytes are a WebP file's VP8
 * chunk. Raises [Failure] or [Invalid_argument] on bytes that are not
 * one. *)
val decode : string -> Rgba_image.t

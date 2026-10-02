(* Vp8l: WebP's lossless format -- every pixel given back as it was.

   The name is the lossy format's with an L; nothing else is shared.
   A picture is an array of pixels of 32 bits, ARGB, and the format is
   two layers. Under: the pixels written as a stream of symbols,
   compressed the way DEFLATE compresses bytes (elm-playground's
   Inflate.mli, PNG's compression). Over: transforms that change the
   pixels, before, into others that compress better; the decoder
   undoes them after, the last applied first.

     bytes -> bits -> transforms read (up to 4, each once)
                   -> the pixels read (prefix codes, copies, cache)
                   -> transforms undone, in reverse -> ARGB

   The bits are read from each byte's low end, as DEFLATE's.

   The pixels. A pixel is not one symbol but four, each with its own
   prefix code (a Huffman code, by its lengths: elm-playground's
   Huffman.mli): green, red, blue, alpha. The green's alphabet is
   larger than 256, and its other symbols say what DEFLATE's say and
   one thing more:

     0..255         a green; red, blue and alpha follow, a symbol each
     256..279       a copy: this many pixels (a length code and its
                    extra bits), from that far back (a distance code,
                    of a fifth prefix code)
     280 and above  a colour seen lately: the cache's entry of this
                    number

   A copy's distance counts pixels in reading order, but the 120
   smallest codes are places near in two dimensions: 1 is the pixel
   above, 2 the one on the left, 3 above and right... (a table,
   [near]): what is alike in a picture is above as often as behind.
   The cache is an array of 2 to 2048 colours where each pixel
   decoded is put at the place (colour * 0x1e35a7bd) lsr (32 - bits):
   a hash, with no search, kept the same on both sides; a colour that
   comes back costs one short symbol instead of four.

   One set of five codes does not fit a whole picture -- sky above,
   grass below. So the picture may come with a smaller one, the
   entropy image, a pixel of which says which set of codes the block
   of pixels under it uses. That smaller picture is itself in this
   format (without transforms or an entropy image of its own): the
   decoder calls itself, [image ~main:false].

   The transforms.

     predictor       each pixel is sent as its difference from a
                     guess made of its neighbours already decoded:
                     left, above, their average, one of 14 ways, the
                     way chosen for each block by a pixel of a smaller
                     picture. PNG's five filters, grown: by block and
                     not by line, and with one that chooses left or
                     above by which is nearer to left + above - corner
                     (as PNG's Paeth, in all four channels at once).
     colour          red and blue are sent less a multiple of green
                     (and blue less a multiple of red), the three
                     multiples a block's: what the channels share is
                     sent once.
     subtract green  the same with the multiple 1 and no table: red
                     and blue as their difference from green. A grey
                     picture becomes green alone.
     colour indexing a picture of 256 colours or fewer is sent as the
                     table and the numbers (in the green); with 16 or
                     fewer, 2, 4 or 8 numbers are packed in a pixel,
                     and the picture is that much narrower.

   A worked example, the picture of Webp.mli's first one: after the
   signature and the sizes come

     07   = 0000 0111, read from the right:
            1          a transform follows
            11         its kind, 3: colour indexing
            0 0000 ... the table's size - 1, 8 bits (three more are
                       the next byte's): 0, a table of one colour

   then the table, a picture 1 wide; a 0 bit, no other transform; and
   the picture, of numbers into the table -- all 0, each of its codes
   a single symbol that takes no bit to read.

   cs-history:
   Announced by Google in November 2011, a year after the lossy
   format, and designed by Jyrki Alakuijala in its Zurich office --
   who went on to Brotli (elm-playground's Brotli.mli; a browser's
   Content-Encoding: br) and to JPEG XL. Google's measure was files a
   quarter smaller than PNG's. Its parts were not new: Huffman's codes
   (1952), Lempel's and Ziv's copies (1977), the guess from neighbours
   that lossless JPEG (1993) and PNG (1996) made. What it added is
   what a format for pictures alone can know and DEFLATE cannot: that
   a symbol is a pixel of four channels, that near is above as well
   as behind, that one part of a picture is not like another.

   others:
   PNG, the format it meant to replace: one filter a line, chosen
   among five; then DEFLATE over the bytes, which does not know where
   a pixel starts. Simpler by far (elm-playground's Png.mli is a third
   of this), read by everything, and still what a screenshot is saved
   as.

   Reference: RFC 9649, section 3, the WebP Lossless Bitstream. *)

(* a stream's picture; the stream is a VP8L chunk's bytes, from its
 * signature 0x2f. Raises [Failure] or [Invalid_argument] on a stream
 * that is not one. *)
val decode : string -> Rgba_image.t

(* its width and height, from its first five bytes *)
val size : string -> (int * int) option

(* [plane s ~width ~height]: a stream with no header (the sizes are
 * given), decoded, and its green alone, a number a pixel: a lossy
 * picture's alpha (Webp.mli's ALPH) *)
val plane : string -> width:int -> height:int -> int array

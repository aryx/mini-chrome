(* Browser_picture: a page's picture, as a browser keeps it -- waiting
 * for its turn, arrived and decoded, or not to be had -- and its bytes
 * decoded by what they say they are.
 *
 * The first bytes of a file say its format better than a server's
 * Content-Type does (a .gif served as text/plain still starts with
 * GIF8): the formats' magic numbers, as TinyMediaPlayer's Media.sniff
 * reads them for every format.
 *
 * cs-history:
 * Pictures in the page were Mosaic's doing: Marc Andreessen proposed
 * <img> on the www-talk list in February 1993 and shipped it, while
 * the list was still discussing something more general. Mosaic
 * read GIF (CompuServe, 1987) and X bitmaps. GIF's compression, LZW,
 * turned out to be patented, and when Unisys asked for royalties at
 * the end of 1994 a group on Usenet designed a free replacement in a
 * few weeks: PNG ("PNG's Not GIF"; a W3C Recommendation, 1996). JPEG
 * (1992) was for photographs from the start. SVG (2001) is the one
 * that is not pixels; it waited ten years for Internet Explorer.
 * Since: WebP (Google, 2010) and AVIF (2019), each a video codec's
 * still frame; the first is read (libs/images' Webp.mli tells it),
 * the second is not.
 *
 *   GIF8      GIF (1987)
 *   \x89PNG   PNG (1996)
 *   \xFF\xD8  JPEG (1992)
 *   RIFF....WEBP   WebP (2010): the four bytes between are the
 *             file's length
 *   <svg      SVG (2001), text (after <?xml ...?> perhaps): drawn at its
 *             own size into pixels (libs/images' Svg)
 *
 * Decoded by our own readers (elm-playground's graphics/images/: Gif,
 * Jpeg; libs/images here, those born of the web: Png, Webp, Svg),
 * pure OCaml, so a browser running in a browser decodes them too. *)

type t = Waiting | Arrived of Rgba_image.t | Broken

(* the bytes decoded: Arrived, or Broken for what is none of these
 * or does not decode *)
val decode : string -> t

(* the same picture decoded ahead, to be had by the next [decode] of
 * these very bytes without the work: what a thread that fetched them
 * calls, so that no frame waits for a picture's decoding *)
val warm : string -> unit

(* the size a picture that could not be had takes: the broken image's *)
(* the bytes of decoded pictures a tab keeps besides those of the page
   it shows (four a dot): past it, the oldest are let go, and decoded
   again if their page is shown again (Browser_tab.with_pictures) *)
val kept_bytes : int

val broken_size : float

(* its size, for the layout, once known: its pixels', or the broken
 * image's *)
val size : t -> (float * float) option

(* [drawn w h img]: the pixels stretched to [w] by [h], centred
 * on the origin; nothing when there is no area to fill -- Hacker News
 * indents a comment with <img src="s.gif" width=0>, a narrow window
 * squeezes a box to nothing -- which Cairo cannot scale to (it raises
 * INVALID_MATRIX, and the program ends) *)
val drawn : float -> float -> Rgba_image.t -> Playground.shape list

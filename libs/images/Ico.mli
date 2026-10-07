(* Ico: a site's small picture, the favicon -- several pictures in one
   file, of which one is taken.

     6 bytes    0, 0; 1 (icons; 2: cursors); how many pictures
     16 bytes   each picture's entry: width, height (0 means 256),
                colours, 0, planes, bits a dot, its size in bytes,
                where it starts in the file
     ...        each picture: a PNG file as it is, or a Windows bitmap
                without its file header

   A bitmap in an icon is two pictures one above the other, so its
   header says twice the height: the colours ("XOR"), rows from the
   bottom up, 1, 4 or 8 bits through a palette, 24 bits, or 32 with an
   alpha; then one bit a dot of mask ("AND": 1, the dot is not drawn),
   what made an icon's outline before there was an alpha to say it.

   [decode] takes the picture nearest to the size asked (32 dots: a
   tab's 16 on a screen of two dots a point), the larger of two as near.

   cs-history:
   The format is Windows 1.0's, of 1985: a program's icon in several
   sizes and depths, the system picking the one its screen could show.
   It came to the web by an accident of Internet Explorer 5 (March
   1999): to draw a picture beside a favourite ("favori" in French:
   the bookmark of Microsoft's browser), it asked each site for
   /favicon.ico, a file of the format it had at hand -- and site owners
   found in their logs requests for a file they had never heard of,
   which told them how many readers had bookmarked them. The other
   browsers followed, with a tag to say where the file is (<link
   rel="icon">, in HTML5 since) and any format a browser draws: most
   icons are PNG now, in a .ico file or not, and SVG.

   modern:
   A site gives many sizes today (rel="icon" with sizes=, Apple's
   apple-touch-icon, a web app's manifest): the tab, the home screen
   of a phone, the task bar each want theirs. The request for
   /favicon.ico with no tag asking for it is still made by every
   browser. *)

(* whether the bytes are an icon file's *)
val sniff : string -> bool

(* its picture nearest to [size] dots wide (32); Failure if none can be read *)
val decode : ?size:int -> string -> Rgba_image.t

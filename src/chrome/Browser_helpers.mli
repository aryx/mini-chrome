(* Browser_helpers: the programs the browser hands to what it does not
 * show itself -- its "helper applications", or "external viewers".
 *
 * cs-history:
 * The first graphical browsers showed text and a few kinds of
 * pictures, and gave the rest away: NCSA Mosaic (1993) ran xv for a
 * picture it could not draw, ghostview for PostScript, mpeg_play for
 * a film, each in a window of its own, by a table from the content's
 * type to a command -- the mailcap file mail readers already had
 * (RFC 1524), where "%s" stands for the file:
 *
 *   application/postscript; ghostview %s
 *   video/mpeg; mpeg_play %s
 *
 * Plug-ins (Netscape 2, 1996) then put the helper's picture inside
 * the page, and the browsers since have taken nearly every kind in:
 * what is left of the table is the dialog "open with".
 *
 * Here the table has one rule of its own -- a video of YouTube's to
 * mpv, if mpv is there ([defaults]) -- and before it the person's, in
 * the profile's Preferences:
 *
 *   "helpers": [
 *     { "site": "youtube.com/watch", "run": ["mpv", "%u"] },
 *     { "type": "application/postscript", "run": ["gv", "%f"] }
 *   ]
 *
 * A rule is for a site -- a host, and what the path begins with --
 * or for a content type; "run" is the program and its arguments, %u
 * the address, %f a file the content was written to. The first rule
 * that matches is the one.
 *
 *   by an address   the right click's menu has "Open with mpv" (on a
 *                   link: "Open link with mpv"), and the program is
 *                   given the address: a video's page of a site whose
 *                   player we cannot be (the films are refused to us,
 *                   and are of codecs we have not) plays beside the
 *                   browser, in the player's own window
 *   by a type       a page that comes of that type is written to a
 *                   file, the program run on it, and the tab says so
 *
 * A worked example:
 *
 *   for_url rules "https://www.youtube.com/watch?v=abc"  the first rule above
 *   for_url rules "https://www.youtube.com/results"      None
 *   for_type rules "application/postscript; x=1"         the second
 *   command rule ~url:"U" ~file:None                     ["mpv"; "U"]
 *
 * design:
 * Only a program the person named is ever run, with the address or
 * the file as one argument each (no shell reads them): a page cannot
 * choose a command, nor add to one. Running a program is an authority
 * handed down (Cap.exec), asked for with the program's name before it
 * is started. The program is not waited for -- it lives beside the
 * browser -- and one that has ended is collected at the next launch.
 * It is started without a fork of ours (Unix.create_process), since
 * under OCaml 5 a program with several domains cannot fork.
 *
 * https://www.rfc-editor.org/rfc/rfc1524 (A User Agent Configuration
 *   Mechanism For Multimedia Mail Format Information: mailcap) *)

type rule = {
  site : string option; (* "youtube.com/watch": the host, and the path's beginning *)
  kind : string option; (* a content type: "application/postscript" *)
  run : string list; (* the program and its arguments; %u the address, %f a file of the content *)
}

type t = rule list

(* the "helpers" of a Preferences, and back; what is not a rule is skipped *)
val of_json : Json.t -> t
val to_json : t -> Json.t

(* the rules that need no writing: a YouTube video's address to mpv.
 * By an address only -- those run when the menu's item is chosen; a
 * rule by a type runs with no click, and is the person's to write *)
val defaults : t

(* [table caps own]: the person's rules, then [defaults], less those
 * whose program is not on this machine (a path, or a name in PATH's
 * directories; looked for once) *)
val table : < Cap.env ; .. > -> t -> t

(* the first rule for this address; for this content type (its
 * parameters, "; charset=...", not looked at) *)
val for_url : t -> string -> rule option
val for_type : t -> string -> rule option

(* the program's name, for a menu: "mpv" *)
val name : rule -> string

(* the command, %u and %f replaced (%f with no file: the address) *)
val command : rule -> url:string -> file:string option -> string list

(* [launch caps argv]: the program started, not waited for *)
val launch : < Cap.exec ; .. > -> string list -> (unit, string) result

(* [opened caps rule ~url body]: a content of the rule's type written
 * to a file and the program run on it; the page to show in its place,
 * which says what was done, or why not *)
val opened : < Cap.exec ; Cap.open_out ; .. > -> rule -> url:string -> string -> string

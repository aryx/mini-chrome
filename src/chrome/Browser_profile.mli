(* Browser_profile: what the browser remembers from one run to the
 * next, as Chrome's profile (its "user data directory",
 * ~/.config/google-chrome): for now the window's size and each site's
 * zoom (Browser_zoom).
 *
 * One file, Preferences, in the profile's directory, JSON as Chrome's
 * (which keeps its zooms under partition.per_host_zoom_levels):
 *
 *   {
 *     "window": {
 *       "width": 1280,
 *       "height": 900
 *     },
 *     "zoom": {
 *       "news.ycombinator.com": 1.5,
 *       "en.wikipedia.org": 0.9,
 *       "": 1.25
 *     }
 *   }
 *
 * the window as it was last (1280 by 900 the first time), and each
 * site's zoom by its host; the last, without a host, is the built-in
 * pages' (about:chrome has none). What is not understood is skipped (a
 * newer version's field, a zoom out of Browser_zoom's levels, a window
 * smaller than 100 or larger than 10000) -- and not written back: the file is the program's, written
 * whole at each change. But a file that is not JSON (a brace lost
 * fixing it by hand) is an error, so that the program can leave it
 * alone rather than write over it.
 *
 * The directory is $XDG_CONFIG_HOME/mini-chrome, else
 * $HOME/.config/mini-chrome, made when first saved to. Saving writes
 * Preferences.tmp and renames it, so a reader (another MiniChrome
 * running) never sees half a file; of two browsers saving, the last
 * wins.
 *
 * Reading and writing files is an authority the program hands down
 * (Cap.open_in, Cap.open_out, and Cap.env for the directory's place),
 * as Cap.network is for sockets (libs/network's Tcp.mli).
 *
 * https://chromium.googlesource.com/chromium/src/+/main/docs/user_data_dir.md
 * https://specifications.freedesktop.org/basedir-spec/latest/ *)

type t = {
  window : int * int; (* the window's width and height *)
  zooms : Browser_zoom.t;
}

(* a first run's: a window of 1280 by 900, no site zoomed *)
val empty : t

(* the Preferences file's text, the example above; and back, or what is
 * wrong with the text and on which line *)
val to_string : t -> string
val of_string : string -> (t, string) result

(* the profile's directory, from the environment; None without a HOME *)
val default_dir : < Cap.env ; .. > -> string option

(* the profile in [dir]: [empty] when it has no Preferences; Error (the
 * file, and why) for one that cannot be read or is not JSON *)
val load : < Cap.open_in ; .. > -> dir:string -> (t, string) result

(* [dir]'s Preferences written (and [dir] made, with its parents);
 * Error with the system's words when it could not be *)
val save : < Cap.open_out ; .. > -> dir:string -> t -> (unit, string) result

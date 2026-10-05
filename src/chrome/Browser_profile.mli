(* Browser_profile: what the browser remembers from one run to the
 * next, as Chrome's profile (its "user data directory",
 * ~/.config/google-chrome): for now the window's size, its scale and
 * each site's zoom (Browser_zoom).
 *
 * One file, Preferences, in the profile's directory, JSON as Chrome's
 * (which keeps its zooms under partition.per_host_zoom_levels):
 *
 *   {
 *     "window": {
 *       "width": 1280,
 *       "height": 900
 *     },
 *     "scale": 1.5,
 *     "zoom": {
 *       "news.ycombinator.com": 1.5,
 *       "en.wikipedia.org": 0.9,
 *       "": 1.25
 *     }
 *   }
 *
 * the window as it was last, in the screen's dots; the scale
 * everything is drawn at, if the person chose one (without, the
 * desktop's: Gui_scale); and each site's zoom by its host, the last,
 * without a host, the built-in pages' (about:chrome has none). A
 * window never resized and a scale never chosen are not written. What
 * is not understood is skipped (a newer version's field, a zoom or a
 * scale out of Browser_zoom's levels, a window smaller than 100 or
 * larger than 10000) -- and not written back: the file is the
 * program's, written whole at each change. But a file that is not JSON (a brace lost
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
  window : (int * int) option; (* the window's width and height, once it was resized *)
  scale : float option; (* the scale chosen; None, the desktop's *)
  zooms : Browser_zoom.t;
  helpers : Browser_helpers.t; (* the programs given what the browser does not show: written by hand, kept as read *)
}

(* a first run's: nothing chosen yet *)
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

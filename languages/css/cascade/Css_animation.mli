(* Css_animation: where an animation ends -- the one moment of it this
   browser shows.

   An animation is a rule that names its own steps (@keyframes, CSS
   Animations Level 1) and a property that plays them on an element:

     @keyframes fade-in { from { opacity: 0 } to { opacity: 1 } }
     .logo { opacity: 0; animation: fade-in .25s 1.25s 1 forwards }

   the logo is not there, then after a second and a quarter it is, in a
   quarter of a second. "forwards" (animation-fill-mode) is the word
   that matters once the film is over: the element keeps the last
   step's values instead of going back to its own. A page that is
   revealed so -- its content at opacity 0 or moved off the screen, an
   animation to bring it in -- shows nothing at all in a browser that
   knows no animation: Gmail's loading screen was a blank page with one
   line of help.

   So the film is not played here, but its end is shown: an element
   whose animation fills forwards (or both ways) is given the
   declarations of the last keyframe ("to", or "100%"), on top of
   whatever the cascade chose for it.

     ends     the sheets' @keyframes, each by its name: its last step's
              declarations (those in @media that holds, @supports and
              @layer too; of two of one name the later)
     ended    an element's winning declarations, with them

   A worked example, with the two rules above:

     ended ends [ opacity: 0; animation: fade-in .25s 1.25s 1 forwards ]
       = [ animation: ...; opacity: 1 ]
     ended ends [ opacity: 0; animation: fade-in 1s infinite ]
       = unchanged: it never ends, and its own values are one of its moments

   cs-history:
   Animation on the web was first a script's: a timer changing a style
   a few pixels at a time (DHTML, 1997), then jQuery's animate (2006).
   Apple's WebKit team proposed doing it in the style sheet itself in
   2007 -- transitions, then keyframe animations, for the iPhone, whose
   processor could not afford a script at every frame but whose
   graphics chip could move a layer -- and Safari 4 shipped
   @-webkit-keyframes in 2009; the W3C's working draft is of the same
   year, and the unprefixed @keyframes is in every browser since about
   2013.

   modern:
   A browser runs these on its compositor thread, off the main one:
   opacity and transform change a layer already painted, so the film
   goes on while a script is busy.

   Not done: the film (delays, durations, the steps between, the
   timing functions), several animations on one element beyond the
   first that fills forwards, transitions, the events (animationend).

   Reference: W3C, "CSS Animations Level 1", sections 3 (keyframes) and
   4.9 (animation-fill-mode). *)

(* the last step of each @keyframes, by its name *)
type ends

(* [ends ~media sheets]: of the rules of each sheet; [media] says
 * whether an @media's query holds *)
val ends : media:(Css_syntax.component list -> bool) -> Css_syntax.rule list list -> ends

(* [ended ends winning]: an element's declarations (a name, its
 * value), those of its animation's last step put over them when it
 * fills forwards. [ends] is asked for only then *)
val ended : ends Lazy.t -> (string * Css_syntax.component list) list -> (string * Css_syntax.component list) list

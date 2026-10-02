(* Browser_details: <details> opened and closed by a click on its
   <summary> -- a part of a page folded, with no script.

     <details>
       <summary>System requirements</summary>
       <p>A computer made after 2010.</p>
     </details>

   shows its summary alone; a click on the summary shows the rest, and
   another folds it again. What is open is said by an attribute, open,
   that the browser sets and removes: so the look is a style sheet's
   (data/css/ua.css: details:not([open]) > :not(summary) { display:
   none }), a page's own rules can match details[open], and a script
   reads and sets el.open.

   Here: [clicked] finds the <details> whose summary a click was in,
   [toggled] gives the page's tree with its open attribute turned
   over. The tree is a value (Dom.mli): a new one is made, the path
   from the root to the element new, the rest shared; the page is then
   laid out again (Browser_tab does it, or, when the page has
   scripts, sets the attribute in their copy of the tree, where a
   script's listener sees it).

   cs-history:
   The disclosure triangle is the Macintosh's (the Finder's list
   views, System 7, 1991). On the web it was a script's work for
   fifteen years -- a click handler toggling display: none, written
   again on every site, each with its own idea of the keyboard and of
   what a screen reader was told. HTML5 made it an element (Chrome
   12, 2011; Firefox 49, 2016), one of the few things the web took
   back from scripts into markup; <dialog> and the popover attribute
   are the same move.

   Not done: the toggle event, name= (details that close each other,
   an accordion), the keyboard (Enter or Space on a summary in
   focus), ::marker's triangle. *)

(* [clicked root target]: the <details> of the page, the innermost,
 * whose <summary> the element clicked is, or is in *)
val clicked : Dom.element -> Dom.element -> Dom.element option

val is_open : Dom.element -> bool

(* [toggled root details]: the tree with that <details> opened if it
 * was closed, closed if open *)
val toggled : Dom.element -> Dom.element -> Dom.element

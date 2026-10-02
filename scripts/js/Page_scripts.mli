(* A saved page's scripts run, with no window: what they say on the
   console, what they ask of the network, what timers they leave.

     Page_scripts.exe page.html [http://its/address [expression]]

   The page's inline scripts run in order (a <script src> is said and
   skipped: its file is not there), then its timers for five seconds
   of the page's clock. Each request a script makes is printed and
   answered by a failure; the expression, if one is given, is asked of
   the page at the end ("typeof jQuery"). To find what a real site's script stops on,
   without the browser around it: save the page (mini-curl -o), run
   this, read the first error. *)

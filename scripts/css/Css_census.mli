(* What a page's style sheets ask that the CSS engine does not do: a
   census, to know what to add next for a site that looks wrong.

     Css_census.exe page.html sheet.css ... [WIDTHxHEIGHT]   (1200x800)
     Css_census.exe page.html sheet.css ... at=SELECTOR      one element's rules

   The page and its sheets are saved first (mini-curl -o), the sheets
   in the order the page links them. They are read by the engine's own
   parser and cascade (Css_syntax, Selectors, Cascade, Computed), and
   three things are said, the most frequent first:

     at-rules      each kind and how many; "skipped" those the cascade
                   does not open (it opens @media, @supports, @layer)
     selectors     the style rules whose selector Selectors does not
                   read (the rule is dropped whole), by the
                   pseudo-class or the sign that it stopped on
     properties    for this page's elements: each property a rule
                   gives one of them that changes nothing in its
                   computed style on any element -- one the engine
                   does not know, or knows but not that value -- with
                   how many elements are given it, and a value seen

   The first two are about the sheets, whatever the page; the third
   about this page: a sheet of two megabytes has thousands of rules
   for components that are not in it.

   With at=SELECTOR (.header, #readme h1), no census: the first
   elements the selector matches, each with the declarations that
   win for it and the rule each comes from (the sheet's number, its
   selector) -- a developer tools' Styles pane in a terminal, for the
   one thing that looks wrong.

   A property listed is not a bug by that alone: cursor, transition
   and outline change nothing a dump shows. The list is where to look,
   read with the page's picture beside it. *)

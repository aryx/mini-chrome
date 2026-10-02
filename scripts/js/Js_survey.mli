(* What real scripts ask of the JavaScript engine: each file given is
   parsed, and if it parses, run in an empty page; the first mistake of
   each is said, with the source round it.

     Js_survey.exe FILE.js ...

     jquery.js          285,314 bytes  PARSE line 147: expected ...
         |   var arr = [];
     hn.js                5,217 bytes  ok (parsed, and run: no error)
     example.js           2,153 bytes  RUN  TypeError: ...

   and at the end, the mistakes counted by their message: what to add
   to the engine next is the one most scripts stop at. A script stops
   at its first mistake, so the survey is run again after each
   addition: the next mistake shows.

   A library that loads is then used ([uses] in the .ml: for a file
   whose name starts with "jquery", "vue", "preact"... a small page, a
   script asking the library for something, and the answer it must
   give): "ok, and used: works", or USE and where it stopped. Loading
   only says the library is defined.

   A parse error's line is the engine's; for a script of one long line
   (a minified one) the columns round the mistake cannot be shown, and
   the message alone says what token stopped it.

   The page a script is run in is empty (<html><head></head><body>
   </body></html>), at http://survey.test/: enough for a library that
   defines its functions, not for one that expects its page. *)

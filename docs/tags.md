# Tags in the interfaces' comments

An `.mli`'s opening comment is the module's documentation, and it
teaches (CLAUDE.md, "Conventions"). Some of its paragraphs are the
module itself: what it is, how it works, a worked example. Nobody
skips those. Others are around it: where the idea came from, how the
real browsers do it today, a word explained. A reader who wants only
the code skips them; one who wants the web's history looks for them.

A tag says which kind such a paragraph is. The vocabulary is
principia-softwarica's (`~/principia/docs/latex/Tags.tex`), where the
same tags are `%`-comments in the `.nw` sources and are to become
boxes in the books; here they are words in an OCaml comment.

## How a tag is written

On a line of its own, before the paragraph it is about, with the
comment's indentation and a colon:

```ocaml
(* XMLHttpRequest: a script asking its server, the first way.

   cs-history:
   Where it came from. Until 1999 a page got something new from its
   server in one way: by being replaced. ...

   How it is used:

     const x = new XMLHttpRequest()
```

(In a comment whose lines each start with " * ", the tag's line
does too.) The tag holds for that paragraph, to the next blank line. A history
of several paragraphs has the tag before each. A paragraph has one
tag at most, its main kind. A fact in passing ("Lou Montulli's
cookies (Netscape, 1994)") inside a paragraph that explains the
module is not tagged: a tagged paragraph is one that could be put in
a box, or left out, whole.

There is no tag for who wrote a paragraph (principia's `%claude:`):
all of mini-chrome is written by Claude.

## The tags

The test, as in principia: without the paragraph, would the reader
still understand the module? If yes, it can be tagged; if no, it is
the module's own, and has no tag.

| Tag | What the paragraph is | Example here |
|---|---|---|
| `cs-history:` | where it came from: who made it, when, where, and why it mattered then | Outlook Web Access and XMLHTTP (`XMLHttpRequest.mli`); the ten days of May 1995 (`Js_eval.mli`) |
| `modern:` | how the real browsers do it today, where we do the simple thing | V8 compiles to machine code, we walk the tree (`Js_eval.mli`); fetch beside XMLHttpRequest |
| `others:` | how other systems do the same thing: another browser, another language, another way | effects, continuation-passing style or a thread, for a coroutine (`Js_coroutine.mli`) |
| `evolution:` | how a thing changed over the years, from its invention to now | selectors from CSS1 to Level 3 and out of style sheets (`Selectors.mli`); promises from 1976 to `await` (`Js_promise.mli`) |
| `design:` | a principle of design the module shows, true beyond it | CSS's syntax made to be skipped (`Css_syntax.mli`) |
| `terminology:` | words that are confused, told apart | URL, URI and URN (`Url.mli`); a property's specified, computed, used and actual values (`Computed.mli`) |
| `why-win:` | why this one prevailed over its rivals | |
| `comeback:` | an idea invented, set aside, and back in another form | Pratt's parser (`Js_parse.mli`); coroutines (`Js_coroutine.mli`) |
| `road-not-taken:` | an idea of merit that history passed by | a browser that reads the DTD; XHTML (`Dtd.mli`) |
| `reframe:` | the thing seen as another ("a browser is an operating system for pages") | |
| `wib:` | worse is better: a deliberate simplification of ours, and what it costs | |
| `why-study:` | why this old or small thing is worth reading | |

## Counting them

The budget of 30,000 lines does not count an interface's opening
comment at all, tagged or not: it is where the module teaches.
`make loc` says how many lines those comments are, and of those how
many are under a tag, by tag.

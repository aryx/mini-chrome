(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_shadow_tree.mli *)

(* a page's body composed, blank text left out, as indented lines *)
let composed (html : string) : string list =
  let root = Shadow_tree.composed (Html_tree.of_string html) in
  match Dom.find_all "body" (Dom.without_blank_text root) with [ b ] -> List.concat_map (fun (n : Dom.node) -> match n with Element e -> Dom.to_lines e | Text t -> [ t ]) b.children | _ -> Alcotest.fail "no body"

let check what html expected = Alcotest.(check (list string)) what expected (composed html)

let card = {|<template shadowrootmode="open"><div class="card"><b><slot name="name">?</slot></b><p><slot></slot></p></div></template>|}

let tests =
  Testo.categorize "Shadow_tree"
    [
      Testo.create "the worked example: the shadow tree drawn, the children where its slots are" (fun () ->
          check "a named slot, and the one with no name" ("<user-card>" ^ card ^ {|<span slot="name">Ada</span>born in 1815</user-card>|})
            [ "user-card"; {|  div class="card"|}; "    b"; {|      span slot="name"|}; {|        "Ada"|}; "    p"; {|      "born in 1815"|} ]);
      Testo.create "a slot given nothing shows its own content; a child no slot takes is not drawn" (fun () ->
          check "no name given: the slot's ?" ("<user-card>" ^ card ^ "born in 1815</user-card>") [ "user-card"; {|  div class="card"|}; "    b"; {|      "?"|}; "    p"; {|      "born in 1815"|} ];
          check "a shadow tree with no slot: the children are not shown" {|<x-box><template shadowrootmode="open"><i>only this</i></template><p>hidden</p></x-box>|}
            [ "x-box"; "  i"; {|    "only this"|} ];
          check "a child asking for a slot there is not" {|<x-box><template shadowrootmode="open"><slot></slot></template><b slot="none">lost</b>kept</x-box>|} [ "x-box"; {|  "kept"|} ]);
      Testo.create "a host in a host's shadow tree, and in its children" (fun () ->
          check "both composed" {|<x-a><template shadowrootmode="open">[<slot></slot>]<x-b><template shadowrootmode="open">inner</template></x-b></template><x-b><template shadowrootmode="open">light</template></x-b></x-a>|}
            [ "x-a"; {|  "["|}; "  x-b"; {|    "light"|}; {|  "]"|}; "  x-b"; {|    "inner"|} ]);
      Testo.create "a tree with no shadow root is the very tree; a template alone is not one" (fun () ->
          let tree = Html_tree.of_string "<p>a <b>page</b></p><template><i>kept for a script</i></template>" in
          Alcotest.(check bool) "==" true (Shadow_tree.composed tree == tree));
    ]

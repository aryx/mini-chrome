(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_xml.mli *)

(* a tree as a string, to compare: (name k=v ... children) and "text" *)
let rec show (node : Dom.node) : string =
  match node with
  | Text s -> Printf.sprintf "%S" s
  | Element e ->
      "(" ^ String.concat " " ((e.name :: List.map (fun (k, v) -> k ^ "=" ^ v) e.attributes) @ List.map show e.children) ^ ")"

let read (s : string) : string = String.concat " " (List.map show (Xml.parse s))
let same = Alcotest.(check string)

let feed =
  {|<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>News &amp; notes</title>
  <entry id="1"><title>First</title></entry>
  <link href="/"/>
</feed>|}

let tests =
  Testo.categorize "Xml"
    [
      Testo.create "the worked example: a feed" (fun () ->
          same "its tree" {|(feed xmlns=http://www.w3.org/2005/Atom (title "News & notes") (entry id=1 (title "First")) (link href=/))|} (read feed);
          (match Xml.parse feed with
          | [ Element root ] ->
              Alcotest.(check (list string)) "as Dom.to_lines shows it"
                [ {|feed xmlns="http://www.w3.org/2005/Atom"|}; "  title"; {|    "News & notes"|}; {|  entry id="1"|}; "    title"; {|      "First"|}; {|  link href="/"|} ]
                (Dom.to_lines root)
          | _ -> Alcotest.fail "one element");
          match Xml.find "entry" (Xml.parse feed) with
          | Some e -> Alcotest.(check string) "an element's text" "First" (Dom.text_content e)
          | None -> Alcotest.fail "no entry");
      Testo.create "what there is to read" (fun () ->
          same "quotes of either kind, an empty element" "(a x=1 y=2 (b))" (read {|<a x="1" y='2'><b/></a>|});
          same "references, by name and by number" {|(a t=<> "\195\169 \195\169 & <")|} (read {|<a t="&lt;&gt;">&#233; &#xe9; &amp; &lt;</a>|});
          same "CDATA: as it is" {|(a " a < b &amp; ")|} (read "<a><![CDATA[ a < b &amp; ]]></a>");
          same "comments and instructions skipped" "(a (b))" (read "<!-- one --><?xml-stylesheet href='x'?><a><!-- two --><b/></a>");
          same "a DOCTYPE, with its own declarations" "(a)" (read {|<!DOCTYPE a [ <!ENTITY e "x"> <!ELEMENT a EMPTY> ]><a/>|});
          same "a DOCTYPE without" "(svg)" (read {|<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"><svg/>|}));
      Testo.create "no element is special: names as written" (fun () ->
          same "the case kept, and the prefix" "(svg:linearGradient gradientUnits=userSpaceOnUse xlink:href=#a)"
            (read {|<svg:linearGradient gradientUnits="userSpaceOnUse" xlink:href="#a"/>|});
          Alcotest.(check string) "a name without its prefix" "rect" (Xml.local "svg:rect");
          Alcotest.(check string) "or with none" "rect" (Xml.local "rect");
          same "the spaces between elements dropped, those in text kept" {|(p "a " (b "b") " c")|} (read "<p>a <b>b</b> c</p>\n");
          same "br is an element like another: it holds what follows" {|(p (br "after"))|} (read "<p><br>after</p>"));
      Testo.create "forgiving, where XML is not" (fun () ->
          same "cut short: everything open is closed" {|(a (b "text"))|} (read "<a><b>text");
          same "an end tag closes what is open, whatever its name" {|(a (b) (c))|} (read "<a><b></x><c/></a>");
          same "an attribute with no quotes, or no value" "(a x=1 hidden=)" (read "<a x=1 hidden>");
          same "an entity not known stays" {|(a "&nbsp; & co")|} (read "<a>&nbsp; & co</a>");
          same "nothing" "" (read "");
          same "not XML at all" {|"just text"|} (read "just text"));
    ]

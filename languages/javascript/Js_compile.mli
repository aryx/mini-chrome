(* A function's body compiled to closures: the tree read once, not at
   each call.

   Js_eval walks the tree: to add two numbers a million times it asks
   a million times what kind of node this is, which operator "+" names,
   whether the statement is the last of its block. None of the answers
   change. Here those questions are asked once, when a function is
   first called, and what is left is kept as an OCaml function that
   does the rest:

     s = s + i          Assign ("=", Local s, Binary ("+", Local s, Local i))

     walked             eval_expr matches Assign, then "=", then Local;
                        calls itself on the Binary, matches it, calls
                        Js_operators.arithmetic, which looks "+" up
                        among thirty names...  each time

     compiled           let a = expr s and b = expr i and add = binary "+" in
                        fun scope this -> ... add (a scope this) (b scope this)
                        made once; called each time

   An expression becomes a [scope -> this -> value], a statement a
   [scope -> this -> outcome], each made from those of its parts: the
   tree's shape is in how the closures hold one another, and running
   the program is calling the outermost.

   **What is compiled** is what a program spends its time in: numbers,
   strings and names, the operators, a property and an item read and
   set, a call, an array, a function made; if, the loops, a block,
   switch, try, return, throw. **What is not** is left to the
   evaluator, node by node, by a closure that calls it on that part of
   the tree ([walk]): a class, a template, a spread, a pattern, with, a
   generator's yield, a loop with a label... So nothing of the language
   is written twice that did not have to be, and what the evaluator
   does for a node is the definition: where the two could differ, the
   compiled case is the evaluator's lines again, in the same order (who
   is evaluated first, which step of the budget is taken where, which
   scope a block makes).

   Clearly apart: the evaluator knows nothing of this module but one
   reference it calls if it is set ([Js_eval.compiler], set here when
   the program starts: the library is linked whole for that), at a
   function's first call, and the place where the result is kept, the
   function's [frame] in the quickened tree (Js_ast.code). With
   Mini_opti.compiled off, or Mini_opti.enabled off, no line of this
   file runs.

   What it bought, 2026-10-04 (scripts/perf/Js_bench.exe; compile=off
   is the evaluator, with Js_scope's places and the rest):

                                   compile=off   compiled
     a loop, 3M turns                1,040 ms      640 ms
     calls, 1M                         610         450
     properties, 1M                    430         320
     arrays, 1M                        390         240
     the Playground's menu, a frame    190         167

   A quarter on a real program, not the several times hoped for: what
   a call costs now is the frame it makes, the list of its arguments,
   each number a new value, each name some scopes up -- the things a
   tree and its closures share. The next step is not here: variables in
   registers and not in scopes, which is a compiler with its own idea
   of a function (others, below).

   cs-history:
   SICP's fourth chapter does it to its Scheme evaluator in a section
   named for it, "Separating Syntactic Analysis from Execution"
   (Abelson and Sussman, 1985): analyze gives a procedure of the
   environment. Feeley and Lapalme made it a way to write compilers
   (Using Closures for Code Generation, Computer Languages, 1987): the
   target is closures of the language the compiler is written in, and
   the host's own compiler does the code generation.

   modern:
   No engine of a browser stops there. V8 compiles a function to
   bytecode for a register machine (Ignition), where a local name is a
   register's number, and the functions that run often to machine code
   that assumes what it has seen (their types, their shapes) and goes
   back to the bytecode when it was wrong. *)

(* [body t f]: f's body compiled for the engine t: given a call's
 * frame and its this, what the call returns. Js_eval calls it by its
 * [compiler] reference, set to this function when the program starts *)
val body : Js_eval.t -> Js_ast.func -> Js_value.scope -> Js_value.value -> Js_value.value

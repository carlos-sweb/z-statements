# Z-Statements

[![Zig Version](https://img.shields.io/badge/zig-0.16-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

ECMAScript **statements and declarations parser** (ECMA-262 §14) in Zig 0.16 — the third repo of the JS engine, wrapping [z-parser](https://github.com/carlos-sweb/z-parser)'s expression parser. Part of the [z-*](https://github.com/carlos-sweb) micro-library family.

## Scope: statements/declarations that don't need function bodies

The full ECMA-262 grammar is split across repos the same way it's split in the spec itself (§13 Expressions in `z-parser` vs. §14 Statements/Declarations here vs. §15 Functions/Classes in a future repo). This repo covers §14, with the same deliberate omission `z-parser` already carried forward: anything whose grammar reaches into function/class bodies (`function`/`class` declarations, and — as a consequence — the eventual early-SyntaxError check for top-level `return`) is left for the phase that depends on this one. See [Known gaps](#known-gaps-deferred-to-future-phases).

No new AST vocabulary duplicates `z-parser`'s: every expression-valued position in a statement (an `if`'s test, a `for`'s update, a `return`'s argument, ...) holds a `*zparser.Node` straight from `z-parser`'s own parser, unwrapped.

## Design

- **Wraps `zparser.Parser`, doesn't reimplement it**: `Parser` holds a `expr_parser: zparser.Parser` field and drives it directly (`advance`/`expect`/`parseExpression`/`parseAssignmentExpression` are all `pub` on `zparser.Parser` specifically for this). No second token buffer, no duplicated lexer-cooperation logic.
- **Arena-allocated AST**, same rationale as `z-parser`'s own `Node` tree — built once, walked/discarded as a unit, no `Rc(T)` needed.
- **Regex-vs-division after a closing `}`**: resolved upstream in `z-parser` (its `parseObjectLiteral` now explicitly requests division context on its own closing `}`), so every `}` this repo produces (block/switch/try-catch-finally) correctly falls into `regexAllowedAfter`'s default (regex allowed) with no extra work here.
- **ASI (Automatic Semicolon Insertion)** uses `Token.had_line_terminator_before` at a fixed set of semicolon slots — no backtracking machine, same approach V8/Acorn/Babel use. See `consumeSemicolon` in `src/parser.zig` for the three termination rules (`;`, `}`, EOF/LT) and the restricted-production rule applied to `continue`/`break`/`return`/`throw`. `throw` has no argument-less form, so a LineTerminator right after it is a hard `IllegalNewlineAfterThrow`, not an ASI save. ASI never applies inside a `for (init; test; update)` header.
- **for-in/for-of/C-style disambiguation** avoids threading a `NoIn` parameter through `z-parser`'s ~7-function precedence chain. With a declaration keyword, only one `BindingIdentifier` is parsed before branching on `in`/`of`/anything else. Without one, the init clause is parsed eagerly as a full `Expression` and then reinterpreted: a top-level `a in b` becomes for-in (the `b` side is already correctly parsed), and a bare identifier followed by contextual `of` becomes for-of (`of` isn't a valid expression continuation, so `parseExpression` already stops right after the identifier for free). See the known trade-off below.
- **Labelled statements**: `is_loop` (needed so labelled `continue` can reject non-loop targets) is resolved via a lexer-position rewind peek (`peekStartsLoop`, same idiom `z-parser`'s own `parseTemplateLiteral` uses) *before* recursing into the body, so nested `continue label;` checks inside that body see the right answer immediately — including through chains of nested labels (`a: b: for (...) ...`).
- **Loop/switch context** for `break`/`continue` legality is tracked as plain counters (`loop_depth`, `switch_depth`) incremented/decremented with `defer` around each construct's body, plus a stack of active labels.
- **Function-declaration hooks**: `Parser.statement_hooks: ?StatementHooks` (default `null`, zero behavior change when unset) lets [z-functions](https://github.com/carlos-sweb/z-functions) produce a proper `.function_declaration: *anyopaque` `StatementData` variant (instead of an `ExpressionStatement` wrapping a function expression) when `function` appears at statement position. `parseBlockStatement`/`parseBindingName`/`parseBindingPattern` are `pub` specifically so z-functions can reuse them verbatim for function bodies (`{ StatementList }`) and parameters.
- **Destructuring binding patterns** (`[a, b]`/`{x, y}` in binding positions): every binding site — `var`/`let`/`const` declarators, `catch` parameters, `for-in`/`for-of` declared bindings, and (via z-functions) function parameters — goes through one recursive `parseBindingPattern` (`BindingPattern = identifier | array | object` in the AST). Array patterns support elision holes (`[, x]` — `null` elements), per-element defaults (`[a = 1]`), nesting, and a recursive rest (`[...pat]`, must be last); object patterns support shorthand (`{x}`), rename (`{x: y}`), defaults on both forms, nesting (`{a: {b}}`), keyword keys with rename (`{if: x}` — same criterion as z-parser's object literals; keyword *shorthand* is rejected), and an identifier-only rest (`{...r}`, must be last — the real spec grammar's own restriction). A destructuring declarator without an initializer (`let [a];`) is the spec's early error, `MissingDestructuringInitializer`.

## Known gaps (deferred to future phases)

- **Class declarations as statements**: need class-body grammar no repo in this family has yet.
- **Destructuring as an assignment target** (`[a, b] = arr;` without a declaration keyword, `for ([a, b] of x)` over existing bindings): different machinery entirely — it requires reinterpreting already-parsed array/object *literals* as patterns in z-parser, not binding-position grammar. Deferred to its own phase. Also still out of pattern scope: string/number/computed keys in object patterns.
- **Modules** (`import`/`export` statement grammar): the keywords are already tokenized by `z-lexer`, but their statement-level grammar is entirely out of scope here.
- **Generators/async functions/`await`-as-statement**: N/A while functions overall are deferred.
- **Strict-mode-only early errors** (e.g. rejecting `with` in strict mode): no strict-mode tracking exists anywhere in this ecosystem yet, same documented gap `z-lexer` already carries for legacy octal literals.
- **`return` outside a function body**: parsed permissively everywhere, with no context-validity check — this repo has no notion of "inside a function body" at all; the real ECMA-262 §14.10.1 early SyntaxError is deferred to whatever future phase assembles function bodies out of `parseProgram()`'s `StatementList` output.
- **The `[lookahead ∉ {'let','['}]` two-token lookahead** that lets real ECMA-262 tell `let[0] = 1` (an expression statement assigning into a variable literally named `let`) apart from `let [x] = arr` (a destructuring declaration): not implemented. Any statement-start `let` commits to declaration parsing here; `let [x] = arr` now parses as the destructuring declaration it looks like, and `let[0] = 1` fails inside the array pattern (`0` isn't a valid binding) with `UnexpectedToken`. Verified against real Node.js — this happens to reject the same input real JS does (`let[0] = 1;` is a `SyntaxError` there too, for an unrelated reason: `let` is a reserved binding name in that position), so the observable behavior matches even though the reasoning differs. The lexer-rewind idiom used elsewhere in this repo (`peekIsColon`/`peekStartsLoop`) is the documented escape hatch if full spec fidelity is ever needed here.
- **The `for (a in obj; ...)` NoIn restriction**: real ECMA-262 requires parentheses (`for ((a in obj); ...)`) around an `in` expression used as a bare C-style for-init; this repo accepts the unparenthesized form permissively instead of rejecting it (confirmed via real Node.js: it *does* reject `for (a in obj; i<10; i++) {}` with a `SyntaxError`, and does accept the parenthesized form, which this repo also accepts correctly since parens turn the outer node into `.paren`, not a bare `.binary`, and the reinterpretation check no longer fires).
- **Legacy Annex-B `for (var x = init in obj)` initializer-in-for-in-head form**: rejected outright as a hard parse error. Confirmed via real Node.js that this form *is* accepted there (a sloppy-mode-only legacy allowance) — a deliberate, documented deviation from real-world engines, not an oversight.

## Usage

```zig
const zstatements = @import("zstatements");

var arena_state = std.heap.ArenaAllocator.init(allocator);
defer arena_state.deinit();

var parser = try zstatements.Parser.init(arena_state.allocator(), "if (a) { b; } else c;");
const program = try parser.parseProgram();
// program[0].data == .if_stmt, ...
```

## Testing

```bash
zig build test
```

## License

MIT

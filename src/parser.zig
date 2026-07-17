const std = @import("std");
const Allocator = std.mem.Allocator;
const zlexer = @import("zlexer");
const zparser = @import("zparser");
const ast = @import("ast.zig");
const Statement = ast.Statement;

pub const ParseError = error{
    /// ASI's "offending token" rule couldn't save the input -- an explicit
    /// `;` was required and neither a line terminator, `}`, nor EOF followed.
    MissingSemicolon,
    /// `throw` followed by a LineTerminator before its argument -- unlike
    /// return/break/continue, ThrowStatement has no argument-less form, so
    /// this is a hard SyntaxError, not an ASI save.
    IllegalNewlineAfterThrow,
    /// `const x;` -- const declarators require an initializer.
    MissingConstInitializer,
    /// `let [a];` / `var {x};` -- a destructuring declarator requires an
    /// initializer (real ECMA-262 early error; for-in/of heads, function
    /// params, and catch bindings are different productions and exempt).
    MissingDestructuringInitializer,
    /// A `...rest` element inside a destructuring pattern was not the last
    /// thing before the closing `]`/`}` (`[...a, b]`, `{...r, x}`), or an
    /// array-pattern rest carried a default (`[...a = []]`).
    RestElementMustBeLast,
    /// `for (expr in expr)` reinterpretation found a top-level `in`
    /// expression whose left side isn't a plain identifier, e.g.
    /// `for (a.b in obj)` or `for (a + b in obj)`.
    InvalidForInTarget,
    /// break/continue with no enclosing loop (continue) or loop/switch
    /// (break), and no valid label reference either.
    IllegalBreak,
    IllegalContinue,
    /// break/continue referencing a label not currently active, or continue
    /// referencing a label that doesn't label an IterationStatement.
    UndefinedLabel,
    /// `foo: foo: ...` -- the same label name nested within itself.
    DuplicateLabel,
    /// More than one `default:` clause in the same switch.
    DuplicateSwitchDefault,
} || zparser.ParseError;

const LabelInfo = struct { name: []const u8, is_loop: bool };

/// Result of a `StatementHooks` callback: an opaque, arena-allocated node
/// plus its precise end position (this repo can't read `.end` off the
/// opaque node itself without dereferencing it, which it must never do).
pub const StatementHookResult = struct { node: *anyopaque, end: usize };

/// Hooks a dependent repo (z-functions) installs so this parser can produce
/// a proper FunctionDeclaration statement (instead of an ExpressionStatement
/// wrapping a function expression) when `function` appears at statement
/// position. Null by default -- every existing call site's behavior is
/// unchanged when no hooks are installed.
pub const StatementHooks = struct {
    ctx: *anyopaque,
    parseFunctionDeclaration: *const fn (ctx: *anyopaque, parser: *zparser.Parser) ParseError!StatementHookResult,
};

pub const Parser = struct {
    expr_parser: zparser.Parser,
    arena: Allocator,
    loop_depth: u32 = 0,
    switch_depth: u32 = 0,
    labels: std.ArrayList(LabelInfo) = .empty,
    statement_hooks: ?StatementHooks = null,

    pub fn init(arena: Allocator, source: []const u8) ParseError!Parser {
        return .{
            .expr_parser = try zparser.Parser.init(arena, source),
            .arena = arena,
        };
    }

    // ===== Entry points =====

    pub fn parseProgram(self: *Parser) ParseError![]const *Statement {
        var stmts: std.ArrayList(*Statement) = .empty;
        while (self.expr_parser.current.type != .eof) {
            try stmts.append(self.arena, try self.parseStatement());
        }
        return stmts.toOwnedSlice(self.arena);
    }

    pub fn parseStatement(self: *Parser) ParseError!*Statement {
        switch (self.expr_parser.current.type) {
            .punct_semi => return self.parseEmptyStatement(),
            .punct_lbrace => return self.parseBlockStatement(),
            .keyword_var, .keyword_const => return self.parseVariableStatement(),
            .keyword_if => return self.parseIfStatement(),
            .keyword_while => return self.parseWhileStatement(),
            .keyword_do => return self.parseDoWhileStatement(),
            .keyword_for => return self.parseForStatement(),
            .keyword_continue => return self.parseContinueStatement(),
            .keyword_break => return self.parseBreakStatement(),
            .keyword_return => return self.parseReturnStatement(),
            .keyword_throw => return self.parseThrowStatement(),
            .keyword_try => return self.parseTryStatement(),
            .keyword_switch => return self.parseSwitchStatement(),
            .keyword_debugger => return self.parseDebuggerStatement(),
            .keyword_with => return self.parseWithStatement(),
            .keyword_function => if (self.statement_hooks) |h| {
                const start = self.expr_parser.current.start;
                const result = try h.parseFunctionDeclaration(h.ctx, &self.expr_parser);
                return self.newStmt(start, result.end, .{ .function_declaration = result.node });
            } else return ParseError.UnexpectedToken,
            .identifier => {
                if (self.isLetKeyword()) return self.parseVariableStatement();
                if (try self.peekIsColon()) return self.parseLabelledStatement();
                return self.parseExpressionStatement();
            },
            else => return self.parseExpressionStatement(),
        }
    }

    // ===== Small helpers =====

    fn newStmt(self: *Parser, start: usize, end: usize, data: ast.StatementData) ParseError!*Statement {
        const stmt = try self.arena.create(Statement);
        stmt.* = .{ .start = start, .end = end, .data = data };
        return stmt;
    }

    fn isLetKeyword(self: *Parser) bool {
        const tok = self.expr_parser.current;
        if (tok.type != .identifier) return false;
        return std.mem.eql(u8, tok.owned_value orelse tok.lexeme, "let");
    }

    fn isOfKeyword(self: *Parser) bool {
        const tok = self.expr_parser.current;
        if (tok.type != .identifier) return false;
        return std.mem.eql(u8, tok.owned_value orelse tok.lexeme, "of");
    }

    fn currentStartsDeclaration(self: *Parser) bool {
        return switch (self.expr_parser.current.type) {
            .keyword_var, .keyword_const => true,
            .identifier => self.isLetKeyword(),
            else => false,
        };
    }

    fn currentVariableKind(self: *Parser) ast.VariableKind {
        return switch (self.expr_parser.current.type) {
            .keyword_var => .@"var",
            .keyword_const => .@"const",
            else => .let,
        };
    }

    fn canStartExpression(self: *Parser) bool {
        return switch (self.expr_parser.current.type) {
            .punct_semi, .punct_rbrace, .eof => false,
            else => true,
        };
    }

    /// Implicit-semicolon handling (ECMA-262 12.10 Automatic Semicolon
    /// Insertion): a literal `;`, a `}` closing the enclosing block, or EOF
    /// all terminate a statement; otherwise a LineTerminator before the
    /// offending token saves the input. No general backtracking machine is
    /// needed -- ASI only ever matters at this fixed set of syntactic slots.
    fn consumeSemicolon(self: *Parser) ParseError!void {
        if (self.expr_parser.current.type == .punct_semi) {
            try self.expr_parser.advance();
            return;
        }
        if (self.expr_parser.current.type == .punct_rbrace) return;
        if (self.expr_parser.current.type == .eof) return;
        if (self.expr_parser.current.had_line_terminator_before) return;
        return ParseError.MissingSemicolon;
    }

    fn findLabel(self: *Parser, name: []const u8) ?LabelInfo {
        var i = self.labels.items.len;
        while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, self.labels.items[i].name, name)) return self.labels.items[i];
        }
        return null;
    }

    /// Peeks one token past `self.expr_parser.current` without consuming it,
    /// using the same lexer-position rewind idiom z-parser's own
    /// `parseTemplateLiteral` uses: save `lexer.{pos,line,column}` + the
    /// current `Token`, advance once to inspect what follows, then restore
    /// both exactly. Used to tell a labelled statement (`foo: ...`) apart
    /// from an expression statement starting with a bare identifier.
    fn peekIsColon(self: *Parser) ParseError!bool {
        const saved_pos = self.expr_parser.lexer.pos;
        const saved_line = self.expr_parser.lexer.line;
        const saved_column = self.expr_parser.lexer.column;
        const saved_current = self.expr_parser.current;
        try self.expr_parser.advance();
        const is_colon = self.expr_parser.current.type == .punct_colon;
        self.expr_parser.lexer.pos = saved_pos;
        self.expr_parser.lexer.line = saved_line;
        self.expr_parser.lexer.column = saved_column;
        self.expr_parser.current = saved_current;
        return is_colon;
    }

    /// Same rewind idiom as `peekIsColon`, generalized to walk forward
    /// through an entire chain of labels (`a: b: c: while (...) ...`) to
    /// determine whether the statement a label chain eventually reaches is
    /// an IterationStatement -- needed before recursing into the body so
    /// nested `continue label;` validity checks see the right answer.
    fn peekStartsLoop(self: *Parser) ParseError!bool {
        const saved_pos = self.expr_parser.lexer.pos;
        const saved_line = self.expr_parser.lexer.line;
        const saved_column = self.expr_parser.lexer.column;
        const saved_current = self.expr_parser.current;
        defer {
            self.expr_parser.lexer.pos = saved_pos;
            self.expr_parser.lexer.line = saved_line;
            self.expr_parser.lexer.column = saved_column;
            self.expr_parser.current = saved_current;
        }
        while (self.expr_parser.current.type == .identifier) {
            try self.expr_parser.advance();
            if (self.expr_parser.current.type != .punct_colon) return false;
            try self.expr_parser.advance();
        }
        return switch (self.expr_parser.current.type) {
            .keyword_while, .keyword_do, .keyword_for => true,
            else => false,
        };
    }

    /// A plain BindingIdentifier only. Still the right call for positions
    /// where the real grammar takes an identifier, not a pattern (function
    /// names, object-pattern rest, z-functions' rest parameter).
    pub fn parseBindingName(self: *Parser) ParseError!ast.BindingName {
        const tok = self.expr_parser.current;
        if (tok.type != .identifier) return ParseError.UnexpectedToken;
        const name = tok.owned_value orelse tok.lexeme;
        try self.expr_parser.advance();
        return .{ .name = name, .start = tok.start, .end = tok.end };
    }

    /// BindingIdentifier | ArrayBindingPattern | ObjectBindingPattern.
    /// The single entry point every binding position (declarators, catch
    /// params, for-in/of declared bindings, z-functions' params) goes
    /// through -- adding pattern support here covered all of them at once.
    pub fn parseBindingPattern(self: *Parser) ParseError!*ast.BindingPattern {
        const pat = try self.arena.create(ast.BindingPattern);
        pat.* = switch (self.expr_parser.current.type) {
            .punct_lbracket => .{ .array = try self.parseArrayPattern() },
            .punct_lbrace => .{ .object = try self.parseObjectPattern() },
            else => .{ .identifier = try self.parseBindingName() },
        };
        return pat;
    }

    fn parseArrayPattern(self: *Parser) ParseError!ast.ArrayPattern {
        _ = try self.expr_parser.expect(.punct_lbracket);
        var elements: std.ArrayList(?ast.ArrayPatternElement) = .empty;
        var rest: ?*ast.BindingPattern = null;
        while (self.expr_parser.current.type != .punct_rbracket) {
            if (self.expr_parser.current.type == .punct_comma) {
                // Elision hole (`[, x]`). A comma right after an element was
                // already consumed as the separator below, so any comma seen
                // at element position is a genuine hole.
                try elements.append(self.arena, null);
                try self.expr_parser.advance();
                continue;
            }
            if (self.expr_parser.current.type == .punct_ellipsis) {
                try self.expr_parser.advance();
                rest = try self.parseBindingPattern();
                if (self.expr_parser.current.type != .punct_rbracket) return ParseError.RestElementMustBeLast;
                break;
            }
            const elem_pat = try self.parseBindingPattern();
            var default: ?*zparser.Node = null;
            if (self.expr_parser.current.type == .punct_assign) {
                try self.expr_parser.advance();
                default = try self.expr_parser.parseAssignmentExpression();
            }
            try elements.append(self.arena, .{ .pattern = elem_pat, .default = default });
            if (self.expr_parser.current.type != .punct_rbracket) _ = try self.expr_parser.expect(.punct_comma);
        }
        _ = try self.expr_parser.expect(.punct_rbracket);
        return .{ .elements = try elements.toOwnedSlice(self.arena), .rest = rest };
    }

    /// Keys follow z-parser's `parseObjectProperty` criterion for the
    /// identifier/keyword cases (`{ if: x }` is legal); string, number, and
    /// computed keys in patterns are out of scope for this phase. Shorthand
    /// (`{x}`) requires a real identifier -- `{if}` would otherwise bind a
    /// reserved word.
    fn parseObjectPattern(self: *Parser) ParseError!ast.ObjectPattern {
        _ = try self.expr_parser.expect(.punct_lbrace);
        var properties: std.ArrayList(ast.ObjectPatternProperty) = .empty;
        var rest: ?ast.BindingName = null;
        while (self.expr_parser.current.type != .punct_rbrace) {
            if (self.expr_parser.current.type == .punct_ellipsis) {
                try self.expr_parser.advance();
                rest = try self.parseBindingName();
                if (self.expr_parser.current.type != .punct_rbrace) return ParseError.RestElementMustBeLast;
                break;
            }
            const key_tok = self.expr_parser.current;
            const is_identifier = key_tok.type == .identifier;
            if (!is_identifier and zlexer.keywordFromLexeme(key_tok.lexeme) == null) {
                return ParseError.UnexpectedToken;
            }
            const key = key_tok.owned_value orelse key_tok.lexeme;
            try self.expr_parser.advance();
            var value: *ast.BindingPattern = undefined;
            if (self.expr_parser.current.type == .punct_colon) {
                try self.expr_parser.advance();
                value = try self.parseBindingPattern();
            } else {
                if (!is_identifier) return ParseError.UnexpectedToken;
                const id = try self.arena.create(ast.BindingPattern);
                id.* = .{ .identifier = .{ .name = key, .start = key_tok.start, .end = key_tok.end } };
                value = id;
            }
            var default: ?*zparser.Node = null;
            if (self.expr_parser.current.type == .punct_assign) {
                try self.expr_parser.advance();
                default = try self.expr_parser.parseAssignmentExpression();
            }
            try properties.append(self.arena, .{ .key = key, .value = value, .default = default });
            if (self.expr_parser.current.type != .punct_rbrace) _ = try self.expr_parser.expect(.punct_comma);
        }
        _ = try self.expr_parser.expect(.punct_rbrace);
        return .{ .properties = try properties.toOwnedSlice(self.arena), .rest = rest };
    }

    fn parseDeclaratorListFrom(self: *Parser, kind: ast.VariableKind, first_pattern: *ast.BindingPattern) ParseError![]const ast.Declarator {
        var declarators: std.ArrayList(ast.Declarator) = .empty;
        var pattern = first_pattern;
        while (true) {
            var init_expr: ?*zparser.Node = null;
            if (self.expr_parser.current.type == .punct_assign) {
                try self.expr_parser.advance();
                init_expr = try self.expr_parser.parseAssignmentExpression();
            } else if (kind == .@"const") {
                return ParseError.MissingConstInitializer;
            } else if (pattern.* != .identifier) {
                return ParseError.MissingDestructuringInitializer;
            }
            try declarators.append(self.arena, .{ .pattern = pattern, .init = init_expr });
            if (self.expr_parser.current.type != .punct_comma) break;
            try self.expr_parser.advance();
            pattern = try self.parseBindingPattern();
        }
        return declarators.toOwnedSlice(self.arena);
    }

    fn parseDeclaratorList(self: *Parser, kind: ast.VariableKind) ParseError![]const ast.Declarator {
        const first_pattern = try self.parseBindingPattern();
        return self.parseDeclaratorListFrom(kind, first_pattern);
    }

    /// Parses `test? ; update?` given that the `;` separating init from
    /// test has already been consumed by the caller.
    fn parseForTestUpdate(self: *Parser) ParseError!struct { test_expr: ?*zparser.Node, update: ?*zparser.Node } {
        const test_expr = if (self.expr_parser.current.type != .punct_semi) try self.expr_parser.parseExpression() else null;
        _ = try self.expr_parser.expect(.punct_semi);
        const update = if (self.expr_parser.current.type != .punct_rparen) try self.expr_parser.parseExpression() else null;
        return .{ .test_expr = test_expr, .update = update };
    }

    // ===== Statement forms =====

    fn parseEmptyStatement(self: *Parser) ParseError!*Statement {
        const tok = self.expr_parser.current;
        try self.expr_parser.advance();
        return self.newStmt(tok.start, tok.end, .{ .empty = {} });
    }

    fn parseDebuggerStatement(self: *Parser) ParseError!*Statement {
        const tok = self.expr_parser.current;
        try self.expr_parser.advance();
        try self.consumeSemicolon();
        return self.newStmt(tok.start, tok.end, .{ .debugger = {} });
    }

    fn parseExpressionStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        const expr = try self.expr_parser.parseExpression();
        try self.consumeSemicolon();
        return self.newStmt(start, expr.end, .{ .expr_stmt = expr });
    }

    /// Relies on the z-parser Step 0 fix (`parseObjectLiteral`'s closing
    /// `}` now explicitly requests division context) for the `regex vs.
    /// division` context to be correct on whatever follows this block's own
    /// closing `}` -- `regexAllowedAfter`'s default (regex allowed) is
    /// correct here since a fresh statement position follows.
    pub fn parseBlockStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        _ = try self.expr_parser.expect(.punct_lbrace);
        var stmts: std.ArrayList(*Statement) = .empty;
        while (self.expr_parser.current.type != .punct_rbrace) {
            try stmts.append(self.arena, try self.parseStatement());
        }
        const end = self.expr_parser.current.end;
        try self.expr_parser.advance();
        return self.newStmt(start, end, .{ .block = try stmts.toOwnedSlice(self.arena) });
    }

    fn parseVariableStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        const kind = self.currentVariableKind();
        try self.expr_parser.advance(); // consume var/const/let
        const declarators = try self.parseDeclaratorList(kind);
        const last = declarators[declarators.len - 1];
        // No-init declarators are guaranteed identifiers here: a pattern
        // without an initializer is rejected in parseDeclaratorListFrom.
        const end = if (last.init) |e| e.end else last.pattern.identifier.end;
        try self.consumeSemicolon();
        return self.newStmt(start, end, .{ .variable = .{ .kind = kind, .declarators = declarators } });
    }

    /// Dangling-else needs no special handling: ordinary recursive descent
    /// (parse the consequent, then just check whether `else` follows)
    /// naturally binds `else` to the nearest open `if`.
    fn parseIfStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        try self.expr_parser.advance(); // 'if'
        _ = try self.expr_parser.expect(.punct_lparen);
        const test_expr = try self.expr_parser.parseExpression();
        _ = try self.expr_parser.expect(.punct_rparen);
        const consequent = try self.parseStatement();
        var alternate: ?*Statement = null;
        var end = consequent.end;
        if (self.expr_parser.current.type == .keyword_else) {
            try self.expr_parser.advance();
            const alt = try self.parseStatement();
            alternate = alt;
            end = alt.end;
        }
        return self.newStmt(start, end, .{ .if_stmt = .{ .test_expr = test_expr, .consequent = consequent, .alternate = alternate } });
    }

    fn parseWhileStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        try self.expr_parser.advance(); // 'while'
        _ = try self.expr_parser.expect(.punct_lparen);
        const test_expr = try self.expr_parser.parseExpression();
        _ = try self.expr_parser.expect(.punct_rparen);
        self.loop_depth += 1;
        defer self.loop_depth -= 1;
        const body = try self.parseStatement();
        return self.newStmt(start, body.end, .{ .while_stmt = .{ .test_expr = test_expr, .body = body } });
    }

    fn parseDoWhileStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        try self.expr_parser.advance(); // 'do'
        self.loop_depth += 1;
        const body = blk: {
            defer self.loop_depth -= 1;
            break :blk try self.parseStatement();
        };
        _ = try self.expr_parser.expect(.keyword_while);
        _ = try self.expr_parser.expect(.punct_lparen);
        const test_expr = try self.expr_parser.parseExpression();
        const rparen = try self.expr_parser.expect(.punct_rparen);
        // The trailing ';' after do-while is one of the few ASI-eligible
        // slots outside expression-statement-shaped forms.
        try self.consumeSemicolon();
        return self.newStmt(start, rparen.end, .{ .do_while = .{ .body = body, .test_expr = test_expr } });
    }

    /// for-in/for-of/C-style disambiguation. With a declaration keyword,
    /// only one BindingIdentifier is parsed before branching on `in`/`of`/
    /// anything else -- no ambiguity risk since nothing expression-shaped
    /// has been parsed yet. Without one, the init clause is parsed eagerly
    /// as a full Expression (exactly as a C-style init would be) and then
    /// reinterpreted: a top-level `a in b` becomes for-in (the `b` side is
    /// already correctly parsed, no re-parsing needed), and a bare
    /// identifier followed by contextual `of` becomes for-of (`of` isn't a
    /// valid expression continuation, so parseExpression already stops
    /// right after the identifier for free). This avoids threading a NoIn
    /// parameter through z-parser's entire precedence chain. Known,
    /// documented trade-off: unparenthesized `for (a in obj; ...)` is
    /// accepted permissively here instead of being rejected as real
    /// ECMA-262 requires (`for ((a in obj); ...)`).
    fn parseForStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        try self.expr_parser.advance(); // 'for'
        _ = try self.expr_parser.expect(.punct_lparen);

        const head: ast.ForHead = blk: {
            if (self.currentStartsDeclaration()) {
                const kind = self.currentVariableKind();
                try self.expr_parser.advance(); // consume var/const/let
                const pattern = try self.parseBindingPattern();
                if (self.expr_parser.current.type == .keyword_in) {
                    try self.expr_parser.advance();
                    const object = try self.expr_parser.parseExpression();
                    break :blk .{ .for_in = .{ .binding = .{ .declared = .{ .kind = kind, .pattern = pattern } }, .object = object } };
                }
                if (self.isOfKeyword()) {
                    try self.expr_parser.advance();
                    const iterable = try self.expr_parser.parseAssignmentExpression();
                    break :blk .{ .for_of = .{ .binding = .{ .declared = .{ .kind = kind, .pattern = pattern } }, .iterable = iterable } };
                }
                // C-style: continue the declarator list from this binding.
                // (The legacy Annex-B `for (var x = 0 in obj)` form is
                // rejected here, not supported -- once `=` is consumed by
                // parseDeclaratorListFrom, `in`/`of` are no longer checked,
                // so that input falls through to expecting ';' and errors.)
                const declarators = try self.parseDeclaratorListFrom(kind, pattern);
                _ = try self.expr_parser.expect(.punct_semi);
                const tu = try self.parseForTestUpdate();
                break :blk .{ .c_style = .{ .init = .{ .decl = .{ .kind = kind, .declarators = declarators } }, .test_expr = tu.test_expr, .update = tu.update } };
            }

            if (self.expr_parser.current.type == .punct_semi) {
                try self.expr_parser.advance();
                const tu = try self.parseForTestUpdate();
                break :blk .{ .c_style = .{ .init = null, .test_expr = tu.test_expr, .update = tu.update } };
            }

            const expr = try self.expr_parser.parseExpression();
            if (self.expr_parser.current.type == .punct_rparen and expr.data == .binary and expr.data.binary.op == .in) {
                const bin = expr.data.binary;
                if (bin.left.data != .identifier) return ParseError.InvalidForInTarget;
                const name: ast.BindingName = .{ .name = bin.left.data.identifier, .start = bin.left.start, .end = bin.left.end };
                break :blk .{ .for_in = .{ .binding = .{ .existing = name }, .object = bin.right } };
            }
            if (expr.data == .identifier and self.isOfKeyword()) {
                const name: ast.BindingName = .{ .name = expr.data.identifier, .start = expr.start, .end = expr.end };
                try self.expr_parser.advance(); // consume 'of'
                const iterable = try self.expr_parser.parseAssignmentExpression();
                break :blk .{ .for_of = .{ .binding = .{ .existing = name }, .iterable = iterable } };
            }
            _ = try self.expr_parser.expect(.punct_semi);
            const tu = try self.parseForTestUpdate();
            break :blk .{ .c_style = .{ .init = .{ .expr = expr }, .test_expr = tu.test_expr, .update = tu.update } };
        };

        _ = try self.expr_parser.expect(.punct_rparen);
        self.loop_depth += 1;
        defer self.loop_depth -= 1;
        const body = try self.parseStatement();
        return self.newStmt(start, body.end, .{ .for_stmt = .{ .head = head, .body = body } });
    }

    fn parseContinueStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        var end = self.expr_parser.current.end;
        try self.expr_parser.advance(); // 'continue'
        var label: ?[]const u8 = null;
        if (!self.expr_parser.current.had_line_terminator_before and self.expr_parser.current.type == .identifier) {
            const tok = self.expr_parser.current;
            label = tok.owned_value orelse tok.lexeme;
            end = tok.end;
            try self.expr_parser.advance();
        }
        if (label) |l| {
            const info = self.findLabel(l) orelse return ParseError.UndefinedLabel;
            if (!info.is_loop) return ParseError.IllegalContinue;
        } else if (self.loop_depth == 0) {
            return ParseError.IllegalContinue;
        }
        try self.consumeSemicolon();
        return self.newStmt(start, end, .{ .continue_stmt = label });
    }

    fn parseBreakStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        var end = self.expr_parser.current.end;
        try self.expr_parser.advance(); // 'break'
        var label: ?[]const u8 = null;
        if (!self.expr_parser.current.had_line_terminator_before and self.expr_parser.current.type == .identifier) {
            const tok = self.expr_parser.current;
            label = tok.owned_value orelse tok.lexeme;
            end = tok.end;
            try self.expr_parser.advance();
        }
        if (label) |l| {
            _ = self.findLabel(l) orelse return ParseError.UndefinedLabel;
        } else if (self.loop_depth == 0 and self.switch_depth == 0) {
            return ParseError.IllegalBreak;
        }
        try self.consumeSemicolon();
        return self.newStmt(start, end, .{ .break_stmt = label });
    }

    /// This repo has no concept of "am I inside a function body" -- that's
    /// introduced by whatever future phase assembles function bodies out of
    /// `parseProgram`'s StatementList output. `return` is therefore parsed
    /// permissively here, unconditionally; the ECMA-262 14.10.1 early
    /// SyntaxError for top-level `return` is deferred to that future phase.
    fn parseReturnStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        var end = self.expr_parser.current.end;
        try self.expr_parser.advance(); // 'return'
        var arg: ?*zparser.Node = null;
        if (!self.expr_parser.current.had_line_terminator_before and self.canStartExpression()) {
            const e = try self.expr_parser.parseExpression();
            end = e.end;
            arg = e;
        }
        try self.consumeSemicolon();
        return self.newStmt(start, end, .{ .return_stmt = arg });
    }

    /// `throw` has no argument-less form -- a LineTerminator right after
    /// the keyword is a hard SyntaxError, not an ASI save.
    fn parseThrowStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        try self.expr_parser.advance(); // 'throw'
        if (self.expr_parser.current.had_line_terminator_before) return ParseError.IllegalNewlineAfterThrow;
        const arg = try self.expr_parser.parseExpression();
        try self.consumeSemicolon();
        return self.newStmt(start, arg.end, .{ .throw_stmt = arg });
    }

    fn parseTryStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        try self.expr_parser.advance(); // 'try'
        const block = try self.parseBlockStatement();
        var handler: ?ast.CatchClause = null;
        var finalizer: ?*Statement = null;
        var end = block.end;
        if (self.expr_parser.current.type == .keyword_catch) {
            try self.expr_parser.advance();
            var param: ?*ast.BindingPattern = null;
            if (self.expr_parser.current.type == .punct_lparen) {
                try self.expr_parser.advance();
                param = try self.parseBindingPattern();
                _ = try self.expr_parser.expect(.punct_rparen);
            }
            const catch_body = try self.parseBlockStatement();
            end = catch_body.end;
            handler = .{ .param = param, .body = catch_body };
        }
        if (self.expr_parser.current.type == .keyword_finally) {
            try self.expr_parser.advance();
            const fin = try self.parseBlockStatement();
            end = fin.end;
            finalizer = fin;
        }
        if (handler == null and finalizer == null) return ParseError.UnexpectedToken;
        return self.newStmt(start, end, .{ .try_stmt = .{ .block = block, .handler = handler, .finalizer = finalizer } });
    }

    fn parseSwitchStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        try self.expr_parser.advance(); // 'switch'
        _ = try self.expr_parser.expect(.punct_lparen);
        const discriminant = try self.expr_parser.parseExpression();
        _ = try self.expr_parser.expect(.punct_rparen);
        _ = try self.expr_parser.expect(.punct_lbrace);
        self.switch_depth += 1;
        defer self.switch_depth -= 1;
        var cases: std.ArrayList(ast.SwitchCase) = .empty;
        var seen_default = false;
        while (self.expr_parser.current.type != .punct_rbrace) {
            var test_expr: ?*zparser.Node = null;
            switch (self.expr_parser.current.type) {
                .keyword_case => {
                    try self.expr_parser.advance();
                    test_expr = try self.expr_parser.parseExpression();
                },
                .keyword_default => {
                    if (seen_default) return ParseError.DuplicateSwitchDefault;
                    seen_default = true;
                    try self.expr_parser.advance();
                },
                else => return ParseError.UnexpectedToken,
            }
            _ = try self.expr_parser.expect(.punct_colon);
            var consequent: std.ArrayList(*Statement) = .empty;
            while (self.expr_parser.current.type != .keyword_case and
                self.expr_parser.current.type != .keyword_default and
                self.expr_parser.current.type != .punct_rbrace)
            {
                try consequent.append(self.arena, try self.parseStatement());
            }
            try cases.append(self.arena, .{ .test_expr = test_expr, .consequent = try consequent.toOwnedSlice(self.arena) });
        }
        const end = self.expr_parser.current.end;
        try self.expr_parser.advance(); // consume '}'
        return self.newStmt(start, end, .{ .switch_stmt = .{ .discriminant = discriminant, .cases = try cases.toOwnedSlice(self.arena) } });
    }

    /// Grammar identical to `while` (`with (Expression) Statement`); the
    /// keyword is already tokenized and this needs no function/class-body
    /// grammar, so the usual "needs grammar this phase doesn't have"
    /// deferral reason doesn't apply. Strict-mode rejection of `with` is
    /// not enforced -- no strict-mode tracking exists anywhere in this
    /// ecosystem yet (same documented gap as z-lexer's legacy octal
    /// literals).
    fn parseWithStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        try self.expr_parser.advance(); // 'with'
        _ = try self.expr_parser.expect(.punct_lparen);
        const object = try self.expr_parser.parseExpression();
        _ = try self.expr_parser.expect(.punct_rparen);
        const body = try self.parseStatement();
        return self.newStmt(start, body.end, .{ .with_stmt = .{ .object = object, .body = body } });
    }

    /// `DuplicateLabel` if the name is already active. `is_loop` is
    /// resolved via `peekStartsLoop` before recursing into the body so
    /// nested `continue label;` checks (which run *during* that recursion)
    /// see the correct answer immediately, including through further
    /// nested label chains (`a: b: for (...) ...`).
    fn parseLabelledStatement(self: *Parser) ParseError!*Statement {
        const start = self.expr_parser.current.start;
        const tok = self.expr_parser.current;
        const label = tok.owned_value orelse tok.lexeme;
        if (self.findLabel(label) != null) return ParseError.DuplicateLabel;
        try self.expr_parser.advance(); // identifier
        _ = try self.expr_parser.expect(.punct_colon);
        const is_loop = try self.peekStartsLoop();
        try self.labels.append(self.arena, .{ .name = label, .is_loop = is_loop });
        defer _ = self.labels.pop();
        const body = try self.parseStatement();
        return self.newStmt(start, body.end, .{ .labelled = .{ .label = label, .body = body } });
    }
};

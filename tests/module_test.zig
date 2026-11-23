//! Module grammar (import/export declarations). Accepted at any
//! statement position (permissive); the interpreter enforces placement.
const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "import forms produce the right ImportDecl shapes" {
    try helpers.parseAndCheck("import './efectos.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const imp = stmt.data.import_decl;
            try testing.expect(imp.default_local == null);
            try testing.expect(imp.namespace_local == null);
            try testing.expectEqual(@as(usize, 0), imp.named.len);
            try testing.expectEqualStrings("./efectos.js", imp.source);
        }
    }.check);
    try helpers.parseAndCheck("import def from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqualStrings("def", stmt.data.import_decl.default_local.?);
        }
    }.check);
    try helpers.parseAndCheck("import * as ns from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqualStrings("ns", stmt.data.import_decl.namespace_local.?);
        }
    }.check);
    try helpers.parseAndCheck("import { a, b as c } from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const named = stmt.data.import_decl.named;
            try testing.expectEqual(@as(usize, 2), named.len);
            try testing.expectEqualStrings("a", named[0].imported);
            try testing.expectEqualStrings("a", named[0].local);
            try testing.expectEqualStrings("b", named[1].imported);
            try testing.expectEqualStrings("c", named[1].local);
        }
    }.check);
    try helpers.parseAndCheck("import def, { a } from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const imp = stmt.data.import_decl;
            try testing.expectEqualStrings("def", imp.default_local.?);
            try testing.expectEqual(@as(usize, 1), imp.named.len);
        }
    }.check);
    try testing.expect(true);
}

test "export forms produce the right ExportDecl shapes" {
    try helpers.parseAndCheck("export const x = 1;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const inner = stmt.data.export_decl.declaration;
            try testing.expect(inner.data == .variable);
        }
    }.check);
    try helpers.parseAndCheck("export { a, b as c };", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const named = stmt.data.export_decl.named;
            try testing.expect(named.source == null);
            try testing.expectEqualStrings("b", named.specifiers[1].local);
            try testing.expectEqualStrings("c", named.specifiers[1].exported);
        }
    }.check);
    try helpers.parseAndCheck("export { a } from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqualStrings("./m.js", stmt.data.export_decl.named.source.?);
        }
    }.check);
    try helpers.parseAndCheck("export default 40 + 2;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.export_decl.default.data == .binary);
        }
    }.check);
    try helpers.parseAndCheck("export * from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqualStrings("./m.js", stmt.data.export_decl.all.source);
        }
    }.check);
}

test "import errors: missing source / missing from" {
    try helpers.expectParseError("import { a };", zstatements.ParseError.UnexpectedToken);
    try helpers.expectParseError("import from './m.js';", zstatements.ParseError.UnexpectedToken);
    try helpers.expectParseError("import * as ns './m.js';", zstatements.ParseError.UnexpectedToken);
}

test "export default class/function does not require a trailing semicolon" {
    const zparser = @import("zparser");
    var dummy: u8 = 0;
    const Stub = struct {
        fn skipBalanced(parser: *zparser.Parser) zparser.ParseError!usize {
            while (parser.current.type != .punct_lbrace and parser.current.type != .eof) {
                try parser.advance();
            }
            _ = try parser.expect(.punct_lbrace);
            const end = parser.current.end;
            _ = try parser.expect(.punct_rbrace);
            return end;
        }
        fn parseFn(ctx: *anyopaque, parser: *zparser.Parser) zparser.ParseError!zparser.FunctionHookResult {
            const end = try skipBalanced(parser);
            return .{ .node = ctx, .end = end };
        }
        fn parseMethod(ctx: *anyopaque, parser: *zparser.Parser, _: zparser.MethodKind, _: []const u8, _: bool, _: bool) zparser.ParseError!zparser.FunctionHookResult {
            const end = try skipBalanced(parser);
            return .{ .node = ctx, .end = end };
        }
    };
    const hooks: zparser.FunctionHooks = .{
        .ctx = @ptrCast(&dummy),
        .parseArrowFunction = Stub.parseFn,
        .parseFunctionExpression = Stub.parseFn,
        .parseMethod = Stub.parseMethod,
        .parseClassExpression = Stub.parseFn,
    };
    const cases = [_]struct { src: []const u8, second_tag: std.meta.Tag(zstatements.StatementData) }{
        .{ .src = "export default class {}\nconst x = 1;", .second_tag = .variable },
        .{ .src = "export default function() {} if (true) {}", .second_tag = .if_stmt },
    };
    for (cases) |c| {
        var arena = std.heap.ArenaAllocator.init(testing.allocator);
        defer arena.deinit();
        var parser = try zstatements.Parser.init(arena.allocator(), c.src);
        parser.expr_parser.function_hooks = hooks;
        const stmts = try parser.parseProgram();
        try testing.expectEqual(@as(usize, 2), stmts.len);
        try testing.expect(stmts[0].data == .export_decl);
        try testing.expectEqual(c.second_tag, std.meta.activeTag(stmts[1].data));
    }
}

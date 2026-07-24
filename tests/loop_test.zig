const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "while statement" {
    try helpers.parseAndCheck("while (a) b;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .while_stmt);
        }
    }.check);
}

test "do-while statement" {
    try helpers.parseAndCheck("do a; while (b);", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .do_while);
        }
    }.check);
}

test "C-style for with all clauses empty" {
    try helpers.parseAndCheck("for (;;) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .for_stmt);
            try testing.expect(stmt.data.for_stmt.head == .c_style);
            try testing.expect(stmt.data.for_stmt.head.c_style.init == null);
            try testing.expect(stmt.data.for_stmt.head.c_style.test_expr == null);
            try testing.expect(stmt.data.for_stmt.head.c_style.update == null);
        }
    }.check);
}

test "C-style for with a declaration init" {
    try helpers.parseAndCheck("for (var i = 0; i < 10; i++) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const head = stmt.data.for_stmt.head.c_style;
            try testing.expect(head.init.? == .decl);
            try testing.expectEqual(zstatements.VariableKind.@"var", head.init.?.decl.kind);
            try testing.expect(head.test_expr != null);
            try testing.expect(head.update != null);
        }
    }.check);
}

test "C-style for with a plain expression init (no declaration keyword)" {
    try helpers.parseAndCheck("for (i = 0; i < 10; i++) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const head = stmt.data.for_stmt.head.c_style;
            try testing.expect(head.init.? == .expr);
        }
    }.check);
}

test "for-of with a declaration" {
    try helpers.parseAndCheck("for (let x of arr) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.for_stmt.head == .for_of);
            const binding = stmt.data.for_stmt.head.for_of.binding;
            try testing.expect(binding == .declared);
            try testing.expectEqualStrings("x", binding.declared.pattern.identifier.name);
        }
    }.check);
}

test "for-of with an existing binding (no declaration keyword)" {
    try helpers.parseAndCheck("for (x of arr) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.for_stmt.head == .for_of);
            try testing.expect(stmt.data.for_stmt.head.for_of.binding == .existing);
        }
    }.check);
}

test "for await (...) requires await_allowed (contextual, only inside async bodies)" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parser = try zstatements.Parser.init(arena, "for await (const x of arr) a;");
    parser.expr_parser.await_allowed = true;
    const stmt = try parser.parseStatement();
    try testing.expect(stmt.data.for_stmt.head == .for_of);
    try testing.expect(stmt.data.for_stmt.head.for_of.is_await);
}

test "plain for-of has is_await = false" {
    try helpers.parseAndCheck("for (const x of arr) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.for_stmt.head == .for_of);
            try testing.expect(!stmt.data.for_stmt.head.for_of.is_await);
        }
    }.check);
}

test "`for (await of x)` outside an async body: `await` stays a plain identifier binding, not the contextual keyword" {
    try helpers.parseAndCheck("for (await of arr) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.for_stmt.head == .for_of);
            try testing.expect(!stmt.data.for_stmt.head.for_of.is_await);
            try testing.expect(stmt.data.for_stmt.head.for_of.binding == .existing);
            try testing.expectEqualStrings("await", stmt.data.for_stmt.head.for_of.binding.existing.name);
        }
    }.check);
}

test "for-in with a declaration" {
    try helpers.parseAndCheck("for (let x in obj) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.for_stmt.head == .for_in);
            try testing.expect(stmt.data.for_stmt.head.for_in.binding == .declared);
        }
    }.check);
}

test "for-in reinterpreted from a plain `a in b` expression (no declaration keyword)" {
    try helpers.parseAndCheck("for (x in obj) a;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.for_stmt.head == .for_in);
            const binding = stmt.data.for_stmt.head.for_in.binding;
            try testing.expect(binding == .existing);
            try testing.expectEqualStrings("x", binding.existing.name);
        }
    }.check);
}

test "legacy Annex-B `for (var x = 0 in obj)` initializer form is rejected" {
    try helpers.expectParseError("for (var x = 0 in obj) a;", zstatements.ParseError.UnexpectedToken);
}

test "for-of declared bindings accept destructuring patterns" {
    try helpers.parseAndCheck("for (const [k, v] of pairs) x;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const binding = stmt.data.for_stmt.head.for_of.binding;
            try testing.expect(binding == .declared);
            try testing.expect(binding.declared.pattern.* == .array);
            try testing.expectEqual(@as(usize, 2), binding.declared.pattern.array.elements.len);
        }
    }.check);
}

test "a member expression as an unparenthesized for-in target is rejected" {
    try helpers.expectParseError("for (a.b in obj) x;", zstatements.ParseError.InvalidForInTarget);
}

test "for(a;b) -- a missing second ';' is a hard error, not silently accepted" {
    try helpers.expectParseError("for(a;b) c;", zstatements.ParseError.UnexpectedToken);
}

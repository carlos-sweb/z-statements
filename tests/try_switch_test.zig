const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "try/catch with a bound parameter" {
    try helpers.parseAndCheck("try { a; } catch (e) { b; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .try_stmt);
            try testing.expect(stmt.data.try_stmt.handler != null);
            try testing.expectEqualStrings("e", stmt.data.try_stmt.handler.?.param.?.identifier.name);
            try testing.expect(stmt.data.try_stmt.finalizer == null);
        }
    }.check);
}

test "try/catch with an optional (unbound) catch parameter" {
    try helpers.parseAndCheck("try { a; } catch { b; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.try_stmt.handler != null);
            try testing.expect(stmt.data.try_stmt.handler.?.param == null);
        }
    }.check);
}

test "try/finally with no catch" {
    try helpers.parseAndCheck("try { a; } finally { b; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.try_stmt.handler == null);
            try testing.expect(stmt.data.try_stmt.finalizer != null);
        }
    }.check);
}

test "try/catch/finally all present" {
    try helpers.parseAndCheck("try { a; } catch (e) { b; } finally { c; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.try_stmt.handler != null);
            try testing.expect(stmt.data.try_stmt.finalizer != null);
        }
    }.check);
}

test "try with neither catch nor finally is a hard error" {
    try helpers.expectParseError("try { a; }", zstatements.ParseError.UnexpectedToken);
}

test "destructuring catch parameters parse as binding patterns" {
    try helpers.parseAndCheck("try { a; } catch ([e]) { b; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const param = stmt.data.try_stmt.handler.?.param.?;
            try testing.expect(param.* == .array);
            try testing.expectEqualStrings("e", param.array.elements[0].?.pattern.identifier.name);
        }
    }.check);
    try helpers.parseAndCheck("try { a; } catch ({message}) { b; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const param = stmt.data.try_stmt.handler.?.param.?;
            try testing.expect(param.* == .object);
            try testing.expectEqualStrings("message", param.object.properties[0].key);
        }
    }.check);
}

test "switch with case and default clauses" {
    try helpers.parseAndCheck("switch (a) { case 1: b; case 2: c; default: d; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .switch_stmt);
            try testing.expectEqual(@as(usize, 3), stmt.data.switch_stmt.cases.len);
            try testing.expect(stmt.data.switch_stmt.cases[0].test_expr != null);
            try testing.expect(stmt.data.switch_stmt.cases[2].test_expr == null);
        }
    }.check);
}

test "case fallthrough: consequent runs until the next case/default/}" {
    try helpers.parseAndCheck("switch (a) { case 1: b; c; case 2: d; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqual(@as(usize, 2), stmt.data.switch_stmt.cases[0].consequent.len);
        }
    }.check);
}

test "a second default clause is a hard error" {
    try helpers.expectParseError("switch (a) { default: b; default: c; }", zstatements.ParseError.DuplicateSwitchDefault);
}

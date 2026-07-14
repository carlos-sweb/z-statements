const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "if with no else" {
    try helpers.parseAndCheck("if (a) b;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .if_stmt);
            try testing.expect(stmt.data.if_stmt.alternate == null);
        }
    }.check);
}

test "if with else" {
    try helpers.parseAndCheck("if (a) b; else c;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .if_stmt);
            try testing.expect(stmt.data.if_stmt.alternate != null);
        }
    }.check);
}

test "dangling else binds to the nearest if" {
    try helpers.parseAndCheck("if (a) if (b) c; else d;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .if_stmt);
            try testing.expect(stmt.data.if_stmt.alternate == null); // outer if has no else
            const inner = stmt.data.if_stmt.consequent;
            try testing.expect(inner.data == .if_stmt);
            try testing.expect(inner.data.if_stmt.alternate != null); // else binds to inner if
        }
    }.check);
}

test "if body can be a block" {
    try helpers.parseAndCheck("if (a) { b; c; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.if_stmt.consequent.data == .block);
        }
    }.check);
}

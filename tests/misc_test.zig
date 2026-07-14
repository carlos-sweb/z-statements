const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "debugger statement" {
    try helpers.parseAndCheck("debugger;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .debugger);
        }
    }.check);
}

test "with statement" {
    try helpers.parseAndCheck("with (a) { b; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .with_stmt);
            try testing.expect(stmt.data.with_stmt.body.data == .block);
        }
    }.check);
}

test "top-level return is parsed permissively (no function-body context check exists yet)" {
    try helpers.parseAndCheck("return 1;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .return_stmt);
            try testing.expect(stmt.data.return_stmt != null);
        }
    }.check);
}

test "a '/' right after a block's closing '}' is a regex, not division (exercises the z-parser Step 0 fix)" {
    try helpers.parseProgramAndCheck("{}\n/x/.test(a);", {}, struct {
        fn check(_: void, program: []const *zstatements.Statement) !void {
            try testing.expectEqual(@as(usize, 2), program.len);
            try testing.expect(program[0].data == .block);
            try testing.expect(program[1].data == .expr_stmt);
            const expr = program[1].data.expr_stmt;
            try testing.expect(expr.data == .call);
            try testing.expect(expr.data.call.callee.data == .member);
            try testing.expect(expr.data.call.callee.data.member.object.data == .regex_literal);
        }
    }.check);
}

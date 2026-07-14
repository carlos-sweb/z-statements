const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "offending-token rule: a newline between two statements inserts the missing ';'" {
    try helpers.parseProgramAndCheck("a\nb", {}, struct {
        fn check(_: void, program: []const *zstatements.Statement) !void {
            try testing.expectEqual(@as(usize, 2), program.len);
            try testing.expect(program[0].data == .expr_stmt);
            try testing.expect(program[1].data == .expr_stmt);
        }
    }.check);
}

test "'}' rule: a block's closing brace terminates the last statement without a ';'" {
    try helpers.parseAndCheck("{ a }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .block);
            try testing.expectEqual(@as(usize, 1), stmt.data.block.len);
        }
    }.check);
}

test "EOF rule: end of input terminates the last statement without a ';'" {
    try helpers.parseProgramAndCheck("if (a) b", {}, struct {
        fn check(_: void, program: []const *zstatements.Statement) !void {
            try testing.expectEqual(@as(usize, 1), program.len);
            try testing.expect(program[0].data == .if_stmt);
        }
    }.check);
}

test "restricted production: a newline right after 'return' makes it argument-less" {
    try helpers.parseProgramAndCheck("return\na;", {}, struct {
        fn check(_: void, program: []const *zstatements.Statement) !void {
            try testing.expectEqual(@as(usize, 2), program.len);
            try testing.expect(program[0].data == .return_stmt);
            try testing.expect(program[0].data.return_stmt == null);
            try testing.expect(program[1].data == .expr_stmt);
        }
    }.check);
}

test "restricted production: a newline right after 'continue' drops the label" {
    try helpers.parseAndCheck("while (x) { continue\na; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const body = stmt.data.while_stmt.body.data.block;
            try testing.expectEqual(@as(usize, 2), body.len);
            try testing.expect(body[0].data == .continue_stmt);
            try testing.expect(body[0].data.continue_stmt == null);
            try testing.expect(body[1].data == .expr_stmt);
        }
    }.check);
}

test "'throw' has no ASI escape: a newline right after it is a hard SyntaxError" {
    try helpers.expectParseError("throw\na;", zstatements.ParseError.IllegalNewlineAfterThrow);
}

test "ASI does not apply inside a for-header: for(a;b) is a hard error, not silently accepted" {
    try helpers.expectParseError("for(a;b) c;", zstatements.ParseError.UnexpectedToken);
}

test "do-while's trailing ';' is itself ASI-eligible" {
    try helpers.parseAndCheck("do a; while (b)", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .do_while);
        }
    }.check);
}

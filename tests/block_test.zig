const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "empty block" {
    try helpers.parseAndCheck("{}", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .block);
            try testing.expectEqual(@as(usize, 0), stmt.data.block.len);
        }
    }.check);
}

test "block with multiple expression statements" {
    try helpers.parseAndCheck("{ 1; 2; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .block);
            try testing.expectEqual(@as(usize, 2), stmt.data.block.len);
            try testing.expect(stmt.data.block[0].data == .expr_stmt);
            try testing.expect(stmt.data.block[1].data == .expr_stmt);
        }
    }.check);
}

test "nested blocks" {
    try helpers.parseAndCheck("{ { a; } }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .block);
            try testing.expectEqual(@as(usize, 1), stmt.data.block.len);
            try testing.expect(stmt.data.block[0].data == .block);
        }
    }.check);
}

const std = @import("std");
const zstatements = @import("zstatements");

pub fn parseAndCheck(source: []const u8, context: anytype, comptime check: fn (@TypeOf(context), *zstatements.Statement) anyerror!void) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parser = try zstatements.Parser.init(arena, source);
    const stmt = try parser.parseStatement();
    try check(context, stmt);
}

pub fn parseProgramAndCheck(source: []const u8, context: anytype, comptime check: fn (@TypeOf(context), []const *zstatements.Statement) anyerror!void) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parser = try zstatements.Parser.init(arena, source);
    const program = try parser.parseProgram();
    try check(context, program);
}

pub fn expectParseError(source: []const u8, expected: zstatements.ParseError) !void {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var parser = try zstatements.Parser.init(arena, source);
    try std.testing.expectError(expected, parser.parseProgram());
}

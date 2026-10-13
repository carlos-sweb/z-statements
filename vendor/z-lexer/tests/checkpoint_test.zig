//! `Lexer.checkpoint()`/`.restore()` -- part of z-lexer-improve.md's
//! Point 1 (giving Lexer a real save/restore primitive instead of
//! consumers reaching into `pos`/`line`/`column` directly).
const std = @import("std");
const testing = std.testing;
const zlexer = @import("zlexer");
const Lexer = zlexer.Lexer;
const TT = zlexer.TokenType;

test "restore() rewinds nextToken() to reproduce the exact same token" {
    const allocator = testing.allocator;
    var lex = Lexer.init(allocator, "foo bar baz");

    const cp = lex.checkpoint();
    var first = try lex.nextToken(.div_allowed);
    defer first.deinit(allocator);
    try testing.expectEqual(TT.identifier, first.type);
    try testing.expectEqualStrings("foo", first.lexeme);

    lex.restore(cp);
    var replayed = try lex.nextToken(.div_allowed);
    defer replayed.deinit(allocator);
    try testing.expectEqual(TT.identifier, replayed.type);
    try testing.expectEqualStrings("foo", replayed.lexeme);

    // Lexing continues normally after a restore -- not stuck replaying.
    var second = try lex.nextToken(.div_allowed);
    defer second.deinit(allocator);
    try testing.expectEqualStrings("bar", second.lexeme);
}

test "restore() rewinds line/column tracking, not just pos" {
    const allocator = testing.allocator;
    var lex = Lexer.init(allocator, "a\nb\nc");

    var a = try lex.nextToken(.div_allowed);
    defer a.deinit(allocator);
    try testing.expectEqual(@as(u32, 1), a.line);

    const cp = lex.checkpoint();
    var b = try lex.nextToken(.div_allowed);
    defer b.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), b.line);

    lex.restore(cp);
    var b_again = try lex.nextToken(.div_allowed);
    defer b_again.deinit(allocator);
    try testing.expectEqual(@as(u32, 2), b_again.line);
    try testing.expectEqualStrings("b", b_again.lexeme);
}

test "checkpoint() taken mid-stream can be restored more than once" {
    const allocator = testing.allocator;
    var lex = Lexer.init(allocator, "1 + 2");

    var one = try lex.nextToken(.regex_allowed);
    defer one.deinit(allocator);
    const cp = lex.checkpoint();

    for (0..3) |_| {
        lex.restore(cp);
        var plus = try lex.nextToken(.div_allowed);
        defer plus.deinit(allocator);
        try testing.expectEqual(TT.punct_plus, plus.type);
    }
}

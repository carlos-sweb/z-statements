const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "break inside a loop" {
    try helpers.parseAndCheck("while (a) { break; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const body = stmt.data.while_stmt.body;
            try testing.expect(body.data.block[0].data == .break_stmt);
            try testing.expect(body.data.block[0].data.break_stmt == null);
        }
    }.check);
}

test "continue inside a loop" {
    try helpers.parseAndCheck("while (a) { continue; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const body = stmt.data.while_stmt.body;
            try testing.expect(body.data.block[0].data == .continue_stmt);
        }
    }.check);
}

test "top-level break/continue with no enclosing loop are illegal" {
    try helpers.expectParseError("break;", zstatements.ParseError.IllegalBreak);
    try helpers.expectParseError("continue;", zstatements.ParseError.IllegalContinue);
}

test "break is legal directly inside a switch with no enclosing loop" {
    try helpers.parseAndCheck("switch (a) { case 1: break; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .switch_stmt);
        }
    }.check);
}

test "continue inside a switch with no enclosing loop is illegal" {
    try helpers.expectParseError("switch (a) { case 1: continue; }", zstatements.ParseError.IllegalContinue);
}

test "labelled continue/break to an enclosing loop" {
    try helpers.parseAndCheck("loop1: while (a) { continue loop1; break loop1; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .labelled);
        }
    }.check);
}

test "labelled break to a non-loop statement is legal, labelled continue to it is not" {
    try helpers.parseAndCheck("label1: { break label1; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .labelled);
        }
    }.check);
    try helpers.expectParseError("label1: { continue label1; }", zstatements.ParseError.IllegalContinue);
}

test "break/continue referencing an undefined label" {
    try helpers.expectParseError("while (a) { break nope; }", zstatements.ParseError.UndefinedLabel);
    try helpers.expectParseError("while (a) { continue nope; }", zstatements.ParseError.UndefinedLabel);
}

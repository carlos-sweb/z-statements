const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "a simple label wrapping an empty statement" {
    try helpers.parseAndCheck("a: ;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .labelled);
            try testing.expectEqualStrings("a", stmt.data.labelled.label);
            try testing.expect(stmt.data.labelled.body.data == .empty);
        }
    }.check);
}

test "duplicate label nested within itself" {
    try helpers.expectParseError("a: a: ;", zstatements.ParseError.DuplicateLabel);
}

test "a chain of labels reaching a loop marks every label in the chain as a loop label" {
    try helpers.parseAndCheck("a: b: for (;;) { continue a; continue b; }", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .labelled);
            try testing.expectEqualStrings("a", stmt.data.labelled.label);
            try testing.expect(stmt.data.labelled.body.data == .labelled);
            try testing.expectEqualStrings("b", stmt.data.labelled.body.data.labelled.label);
        }
    }.check);
}

test "a label chain that doesn't reach a loop rejects continue by either label" {
    try helpers.expectParseError("a: b: { continue a; }", zstatements.ParseError.IllegalContinue);
    try helpers.expectParseError("a: b: { continue b; }", zstatements.ParseError.IllegalContinue);
}

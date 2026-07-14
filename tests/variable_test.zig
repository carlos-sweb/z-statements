const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

test "var with no initializer" {
    try helpers.parseAndCheck("var x;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .variable);
            try testing.expectEqual(zstatements.VariableKind.@"var", stmt.data.variable.kind);
            try testing.expectEqual(@as(usize, 1), stmt.data.variable.declarators.len);
            try testing.expectEqualStrings("x", stmt.data.variable.declarators[0].name.name);
            try testing.expect(stmt.data.variable.declarators[0].init == null);
        }
    }.check);
}

test "let with initializer" {
    try helpers.parseAndCheck("let x = 1;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .variable);
            try testing.expectEqual(zstatements.VariableKind.let, stmt.data.variable.kind);
            const decl = stmt.data.variable.declarators[0];
            try testing.expect(decl.init != null);
            try testing.expect(decl.init.?.data == .number_literal);
        }
    }.check);
}

test "const with multiple declarators" {
    try helpers.parseAndCheck("const x = 1, y = 2;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data == .variable);
            try testing.expectEqual(zstatements.VariableKind.@"const", stmt.data.variable.kind);
            try testing.expectEqual(@as(usize, 2), stmt.data.variable.declarators.len);
            try testing.expectEqualStrings("x", stmt.data.variable.declarators[0].name.name);
            try testing.expectEqualStrings("y", stmt.data.variable.declarators[1].name.name);
        }
    }.check);
}

test "const without an initializer is a hard error" {
    try helpers.expectParseError("const x;", zstatements.ParseError.MissingConstInitializer);
}

test "destructuring binding targets are rejected" {
    try helpers.expectParseError("var [a, b] = arr;", zstatements.ParseError.DestructuringBindingNotSupported);
    try helpers.expectParseError("let {x, y} = obj;", zstatements.ParseError.DestructuringBindingNotSupported);
}

test "let[0] = 1 is treated as a (rejected) destructuring declaration, not division into a variable named let -- documented simplification, not full 2-token lookahead" {
    try helpers.expectParseError("let[0] = 1;", zstatements.ParseError.DestructuringBindingNotSupported);
}

test "ASI still terminates a variable statement" {
    try helpers.parseProgramAndCheck("let x = 1\nlet y = 2", {}, struct {
        fn check(_: void, program: []const *zstatements.Statement) !void {
            try testing.expectEqual(@as(usize, 2), program.len);
            try testing.expect(program[0].data == .variable);
            try testing.expect(program[1].data == .variable);
        }
    }.check);
}

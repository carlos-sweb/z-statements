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
            try testing.expectEqualStrings("x", stmt.data.variable.declarators[0].pattern.identifier.name);
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
            try testing.expectEqualStrings("x", stmt.data.variable.declarators[0].pattern.identifier.name);
            try testing.expectEqualStrings("y", stmt.data.variable.declarators[1].pattern.identifier.name);
        }
    }.check);
}

test "const without an initializer is a hard error" {
    try helpers.expectParseError("const x;", zstatements.ParseError.MissingConstInitializer);
}

test "destructuring declarators parse as binding patterns" {
    try helpers.parseAndCheck("var [a, b] = arr;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const decl = stmt.data.variable.declarators[0];
            try testing.expect(decl.pattern.* == .array);
            try testing.expectEqual(@as(usize, 2), decl.pattern.array.elements.len);
            try testing.expectEqualStrings("a", decl.pattern.array.elements[0].?.pattern.identifier.name);
            try testing.expectEqualStrings("b", decl.pattern.array.elements[1].?.pattern.identifier.name);
            try testing.expect(decl.init != null);
        }
    }.check);
    try helpers.parseAndCheck("let {x, y} = obj;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const decl = stmt.data.variable.declarators[0];
            try testing.expect(decl.pattern.* == .object);
            try testing.expectEqual(@as(usize, 2), decl.pattern.object.properties.len);
            try testing.expectEqualStrings("x", decl.pattern.object.properties[0].key);
            try testing.expectEqualStrings("x", decl.pattern.object.properties[0].value.identifier.name);
            try testing.expectEqualStrings("y", decl.pattern.object.properties[1].key);
        }
    }.check);
}

test "a destructuring declarator without an initializer is a hard error" {
    try helpers.expectParseError("let [a];", zstatements.ParseError.MissingDestructuringInitializer);
    try helpers.expectParseError("var {x};", zstatements.ParseError.MissingDestructuringInitializer);
}

test "let[0] = 1 is treated as a destructuring declaration (0 is not a valid binding), not division into a variable named let -- documented simplification, not full 2-token lookahead" {
    try helpers.expectParseError("let[0] = 1;", zstatements.ParseError.UnexpectedToken);
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

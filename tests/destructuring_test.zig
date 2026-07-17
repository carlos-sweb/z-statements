const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const zparser = @import("zparser");
const helpers = @import("helpers.zig");

fn firstDeclPattern(stmt: *zstatements.Statement) *const zstatements.BindingPattern {
    return stmt.data.variable.declarators[0].pattern;
}

test "array pattern: elision holes are null elements" {
    try helpers.parseAndCheck("let [, x, , y] = arr;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const arr = firstDeclPattern(stmt).array;
            try testing.expectEqual(@as(usize, 4), arr.elements.len);
            try testing.expect(arr.elements[0] == null);
            try testing.expectEqualStrings("x", arr.elements[1].?.pattern.identifier.name);
            try testing.expect(arr.elements[2] == null);
            try testing.expectEqualStrings("y", arr.elements[3].?.pattern.identifier.name);
            try testing.expect(arr.rest == null);
        }
    }.check);
}

test "array pattern: trailing comma adds no hole" {
    try helpers.parseAndCheck("let [a,] = arr;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqual(@as(usize, 1), firstDeclPattern(stmt).array.elements.len);
        }
    }.check);
}

test "array pattern: defaults and rest" {
    try helpers.parseAndCheck("let [a = 1, ...rest] = arr;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const arr = firstDeclPattern(stmt).array;
            try testing.expectEqual(@as(usize, 1), arr.elements.len);
            try testing.expect(arr.elements[0].?.default != null);
            try testing.expect(arr.elements[0].?.default.?.data == .number_literal);
            try testing.expectEqualStrings("rest", arr.rest.?.identifier.name);
        }
    }.check);
}

test "array pattern: nested patterns recurse" {
    try helpers.parseAndCheck("let [[a], {b}] = arr;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const arr = firstDeclPattern(stmt).array;
            try testing.expect(arr.elements[0].?.pattern.* == .array);
            try testing.expect(arr.elements[1].?.pattern.* == .object);
        }
    }.check);
}

test "array pattern: rest must be last" {
    try helpers.expectParseError("let [...a, b] = arr;", zstatements.ParseError.RestElementMustBeLast);
    try helpers.expectParseError("let [...a = []] = arr;", zstatements.ParseError.RestElementMustBeLast);
}

test "object pattern: shorthand, rename, defaults" {
    try helpers.parseAndCheck("let {x, y: z, w = 3, v: u = 4} = obj;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const obj = firstDeclPattern(stmt).object;
            try testing.expectEqual(@as(usize, 4), obj.properties.len);
            // {x} shorthand
            try testing.expectEqualStrings("x", obj.properties[0].key);
            try testing.expectEqualStrings("x", obj.properties[0].value.identifier.name);
            try testing.expect(obj.properties[0].default == null);
            // {y: z} rename
            try testing.expectEqualStrings("y", obj.properties[1].key);
            try testing.expectEqualStrings("z", obj.properties[1].value.identifier.name);
            // {w = 3} shorthand default
            try testing.expectEqualStrings("w", obj.properties[2].key);
            try testing.expect(obj.properties[2].default != null);
            // {v: u = 4} rename + default
            try testing.expectEqualStrings("u", obj.properties[3].value.identifier.name);
            try testing.expect(obj.properties[3].default != null);
        }
    }.check);
}

test "object pattern: nested value patterns" {
    try helpers.parseAndCheck("let {a: {b}, c: [d]} = obj;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const obj = firstDeclPattern(stmt).object;
            try testing.expect(obj.properties[0].value.* == .object);
            try testing.expect(obj.properties[1].value.* == .array);
        }
    }.check);
}

test "object pattern: rest is identifier-only and must be last" {
    try helpers.parseAndCheck("let {a, ...r} = obj;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const obj = firstDeclPattern(stmt).object;
            try testing.expectEqual(@as(usize, 1), obj.properties.len);
            try testing.expectEqualStrings("r", obj.rest.?.name);
        }
    }.check);
    try helpers.expectParseError("let {...r, a} = obj;", zstatements.ParseError.RestElementMustBeLast);
    try helpers.expectParseError("let {...{a}} = obj;", zstatements.ParseError.UnexpectedToken);
}

test "object pattern: keyword keys with rename are legal, keyword shorthand is not" {
    try helpers.parseAndCheck("let {if: x} = obj;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const obj = firstDeclPattern(stmt).object;
            try testing.expectEqualStrings("if", obj.properties[0].key);
            try testing.expectEqualStrings("x", obj.properties[0].value.identifier.name);
        }
    }.check);
    try helpers.expectParseError("let {if} = obj;", zstatements.ParseError.UnexpectedToken);
}

test "patterns in a multi-declarator list" {
    try helpers.parseAndCheck("let a = 1, [b] = arr, {c} = obj;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const decls = stmt.data.variable.declarators;
            try testing.expectEqual(@as(usize, 3), decls.len);
            try testing.expect(decls[0].pattern.* == .identifier);
            try testing.expect(decls[1].pattern.* == .array);
            try testing.expect(decls[2].pattern.* == .object);
        }
    }.check);
}

test "const patterns still require an initializer" {
    try helpers.expectParseError("const [a];", zstatements.ParseError.MissingConstInitializer);
}

test "for-in declared object pattern" {
    try helpers.parseAndCheck("for (const {length} in obj) x;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const binding = stmt.data.for_stmt.head.for_in.binding;
            try testing.expect(binding.declared.pattern.* == .object);
        }
    }.check);
}

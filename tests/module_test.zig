//! Module grammar (import/export declarations). Accepted at any
//! statement position (permissive); the interpreter enforces placement.
const std = @import("std");
const testing = std.testing;
const zstatements = @import("zstatements");
const helpers = @import("helpers.zig");

test "import forms produce the right ImportDecl shapes" {
    try helpers.parseAndCheck("import './efectos.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const imp = stmt.data.import_decl;
            try testing.expect(imp.default_local == null);
            try testing.expect(imp.namespace_local == null);
            try testing.expectEqual(@as(usize, 0), imp.named.len);
            try testing.expectEqualStrings("./efectos.js", imp.source);
        }
    }.check);
    try helpers.parseAndCheck("import def from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqualStrings("def", stmt.data.import_decl.default_local.?);
        }
    }.check);
    try helpers.parseAndCheck("import * as ns from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqualStrings("ns", stmt.data.import_decl.namespace_local.?);
        }
    }.check);
    try helpers.parseAndCheck("import { a, b as c } from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const named = stmt.data.import_decl.named;
            try testing.expectEqual(@as(usize, 2), named.len);
            try testing.expectEqualStrings("a", named[0].imported);
            try testing.expectEqualStrings("a", named[0].local);
            try testing.expectEqualStrings("b", named[1].imported);
            try testing.expectEqualStrings("c", named[1].local);
        }
    }.check);
    try helpers.parseAndCheck("import def, { a } from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const imp = stmt.data.import_decl;
            try testing.expectEqualStrings("def", imp.default_local.?);
            try testing.expectEqual(@as(usize, 1), imp.named.len);
        }
    }.check);
    try testing.expect(true);
}

test "export forms produce the right ExportDecl shapes" {
    try helpers.parseAndCheck("export const x = 1;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const inner = stmt.data.export_decl.declaration;
            try testing.expect(inner.data == .variable);
        }
    }.check);
    try helpers.parseAndCheck("export { a, b as c };", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            const named = stmt.data.export_decl.named;
            try testing.expect(named.source == null);
            try testing.expectEqualStrings("b", named.specifiers[1].local);
            try testing.expectEqualStrings("c", named.specifiers[1].exported);
        }
    }.check);
    try helpers.parseAndCheck("export { a } from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqualStrings("./m.js", stmt.data.export_decl.named.source.?);
        }
    }.check);
    try helpers.parseAndCheck("export default 40 + 2;", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expect(stmt.data.export_decl.default.data == .binary);
        }
    }.check);
    try helpers.parseAndCheck("export * from './m.js';", {}, struct {
        fn check(_: void, stmt: *zstatements.Statement) !void {
            try testing.expectEqualStrings("./m.js", stmt.data.export_decl.all.source);
        }
    }.check);
}

test "import errors: missing source / missing from" {
    try helpers.expectParseError("import { a };", zstatements.ParseError.UnexpectedToken);
    try helpers.expectParseError("import from './m.js';", zstatements.ParseError.UnexpectedToken);
    try helpers.expectParseError("import * as ns './m.js';", zstatements.ParseError.UnexpectedToken);
}

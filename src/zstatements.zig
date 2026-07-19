const ast_mod = @import("ast.zig");
const parser_mod = @import("parser.zig");

pub const Statement = ast_mod.Statement;
pub const StatementData = ast_mod.StatementData;
pub const VariableKind = ast_mod.VariableKind;
pub const BindingName = ast_mod.BindingName;
pub const BindingPattern = ast_mod.BindingPattern;
pub const ArrayPattern = ast_mod.ArrayPattern;
pub const ArrayPatternElement = ast_mod.ArrayPatternElement;
pub const ObjectPattern = ast_mod.ObjectPattern;
pub const ObjectPatternProperty = ast_mod.ObjectPatternProperty;
pub const Declarator = ast_mod.Declarator;
pub const CatchClause = ast_mod.CatchClause;
pub const SwitchCase = ast_mod.SwitchCase;
pub const ForInit = ast_mod.ForInit;
pub const ForBinding = ast_mod.ForBinding;
pub const ForHead = ast_mod.ForHead;
pub const ImportSpecifier = ast_mod.ImportSpecifier;
pub const ImportDecl = ast_mod.ImportDecl;
pub const ExportSpecifier = ast_mod.ExportSpecifier;
pub const ExportDecl = ast_mod.ExportDecl;

pub const Parser = parser_mod.Parser;
pub const ParseError = parser_mod.ParseError;
pub const StatementHooks = parser_mod.StatementHooks;
pub const StatementHookResult = parser_mod.StatementHookResult;

test {
    _ = @import("ast.zig");
    _ = @import("parser.zig");
}

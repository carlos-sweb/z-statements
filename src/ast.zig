const zparser = @import("zparser");

pub const Statement = struct {
    start: usize,
    end: usize,
    data: StatementData,
};

pub const VariableKind = enum { @"var", let, @"const" };

/// A plain BindingIdentifier.
pub const BindingName = struct {
    name: []const u8,
    start: usize,
    end: usize,
};

/// A binding position: either a plain identifier or a destructuring
/// pattern. Every binding site (declarators, function params, catch,
/// for-in/of declared bindings) holds one of these.
pub const BindingPattern = union(enum) {
    identifier: BindingName,
    array: ArrayPattern,
    object: ObjectPattern,
};

pub const ArrayPatternElement = struct {
    pattern: *BindingPattern,
    /// `= AssignmentExpression` initializer, applied when the source
    /// element is undefined.
    default: ?*zparser.Node,
};

pub const ArrayPattern = struct {
    /// null = elision hole (`[, x]`).
    elements: []const ?ArrayPatternElement,
    /// `...pat` -- recursive per spec (`[...[a, b]]` is legal).
    rest: ?*BindingPattern,
};

pub const ObjectPatternProperty = struct {
    /// Property name as written in source. Computed keys are out of
    /// scope for this phase.
    key: []const u8,
    /// Shorthand `{x}` becomes an identifier pattern for `x`.
    value: *BindingPattern,
    default: ?*zparser.Node,
};

pub const ObjectPattern = struct {
    properties: []const ObjectPatternProperty,
    /// `...rest` -- identifier only, per the real spec grammar.
    rest: ?BindingName,
};

pub const Declarator = struct {
    pattern: *BindingPattern,
    init: ?*zparser.Node,
};

pub const CatchClause = struct {
    /// null = `catch { ... }` (optional catch binding, ES2019+).
    param: ?*BindingPattern,
    body: *Statement, // always .block
};

pub const SwitchCase = struct {
    /// null = the `default:` clause.
    test_expr: ?*zparser.Node,
    consequent: []const *Statement,
};

pub const ForInit = union(enum) {
    expr: *zparser.Node,
    decl: struct { kind: VariableKind, declarators: []const Declarator },
};

pub const ForBinding = union(enum) {
    /// `for (x in/of ...)` -- pre-existing binding, no declaration keyword.
    existing: BindingName,
    /// `for ([a, b] of ...)` / `for ({x} in ...)` -- a destructuring
    /// *assignment* over pre-existing bindings. The node is the array/
    /// object literal as parsed, already validated by z-parser's
    /// isValidAssignmentPattern (cover-grammar reinterpretation).
    existing_pattern: *zparser.Node,
    /// `for (var/let/const x in/of ...)`.
    declared: struct { kind: VariableKind, pattern: *BindingPattern },
};

pub const ForHead = union(enum) {
    c_style: struct { init: ?ForInit, test_expr: ?*zparser.Node, update: ?*zparser.Node },
    for_in: struct { binding: ForBinding, object: *zparser.Node },
    for_of: struct { binding: ForBinding, iterable: *zparser.Node },
};

pub const StatementData = union(enum) {
    empty: void,
    expr_stmt: *zparser.Node,
    block: []const *Statement,
    variable: struct { kind: VariableKind, declarators: []const Declarator },
    if_stmt: struct { test_expr: *zparser.Node, consequent: *Statement, alternate: ?*Statement },
    while_stmt: struct { test_expr: *zparser.Node, body: *Statement },
    do_while: struct { body: *Statement, test_expr: *zparser.Node },
    for_stmt: struct { head: ForHead, body: *Statement },
    continue_stmt: ?[]const u8, // label name, or null
    break_stmt: ?[]const u8,
    return_stmt: ?*zparser.Node,
    labelled: struct { label: []const u8, body: *Statement },
    throw_stmt: *zparser.Node,
    try_stmt: struct { block: *Statement, handler: ?CatchClause, finalizer: ?*Statement },
    switch_stmt: struct { discriminant: *zparser.Node, cases: []const SwitchCase },
    debugger: void,
    with_stmt: struct { object: *zparser.Node, body: *Statement },
    /// A function declaration, typed and owned solely by z-functions -- this
    /// repo never dereferences it. See z-functions' `asFunctionNode()`.
    function_declaration: *anyopaque,
};

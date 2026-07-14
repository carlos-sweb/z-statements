const zparser = @import("zparser");

pub const Statement = struct {
    start: usize,
    end: usize,
    data: StatementData,
};

pub const VariableKind = enum { @"var", let, @"const" };

/// A plain BindingIdentifier. Destructuring binding patterns (`[a,b]`,
/// `{x,y}`) are explicitly out of scope for this phase -- see README.
pub const BindingName = struct {
    name: []const u8,
    start: usize,
    end: usize,
};

pub const Declarator = struct {
    name: BindingName,
    init: ?*zparser.Node,
};

pub const CatchClause = struct {
    /// null = `catch { ... }` (optional catch binding, ES2019+).
    param: ?BindingName,
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
    /// `for (var/let/const x in/of ...)`.
    declared: struct { kind: VariableKind, name: BindingName },
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
};

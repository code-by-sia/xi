/**
 * Tree-sitter grammar for the X programming language.
 *
 * Covers the syntax accepted by the xc compiler: declarations (type,
 * interface, class, module, functions/creators/entry, extern, export, import,
 * namespace), dependency blocks, statements and expressions, and type
 * expressions (T?, T[], T!, &T, refined `where`, compound).
 */
const PREC = {
  or: 1, and: 2, not: 3, eq: 4, rel: 5, typecheck: 6,
  add: 7, mul: 8, unary: 9, postfix: 10,
};

module.exports = grammar({
  name: 'xi',

  word: $ => $.identifier,

  extras: $ => [/\s/, $.line_comment, $.block_comment],

  conflicts: $ => [
    [$._type, $._expression],
    [$.qualified_name, $.member_expr],
    [$.qualified_name, $._expression],
    [$.named_type, $._expression],
  ],

  rules: {
    source_file: $ => repeat($._top_decl),

    line_comment: _ => token(seq('//', /[^\n]*/)),
    block_comment: _ => token(seq('/*', /[^*]*\*+([^/*][^*]*\*+)*/, '/')),

    _top_decl: $ => choice(
      $.import_decl,
      $.namespace_decl,
      $.type_decl,
      $.interface_decl,
      $.class_decl,
      $.module_decl,
      $.extern_block,
      $.export_decl,
      $.entry_decl,
      $.function_decl,
      $.creator_decl,
    ),

    // ── imports / namespaces ────────────────────────────────────
    import_decl: $ => seq('import', $.string),
    namespace_decl: $ => seq('namespace', $.qualified_name),

    qualified_name: $ => prec.left(seq($.identifier, repeat(seq('.', $.identifier)))),

    // ── types ───────────────────────────────────────────────────
    type_decl: $ => seq(
      'type', field('name', $.identifier), '=',
      field('value', $._type),
      optional(seq('where', field('constraint', $._expression))),
    ),

    _type: $ => choice(
      $.primitive_type,
      $.generic_type,
      $.named_type,
      $.compound_type,
      $.optional_type,
      $.array_type,
      $.result_type,
      $.ref_type,
      $.own_type,
    ),

    // generic instantiation:  List<Item>, Map<String, Integer>, Future<T>, …
    generic_type: $ => prec(PREC.postfix, seq(
      field('name', $.qualified_name), '<', commaSep1($._type), '>',
    )),

    primitive_type: _ => choice(
      'Number', 'Integer', 'Bool', 'String', 'Char',
      'Timestamp', 'Void', 'Size', 'cstring',
    ),
    named_type: $ => $.qualified_name,
    optional_type: $ => prec(PREC.postfix, seq($._type, '?')),
    array_type: $ => prec(PREC.postfix, seq($._type, '[', ']')),
    result_type: $ => prec(PREC.postfix, seq($._type, '!')),
    ref_type: $ => prec.right(seq(choice('&', '&mut'), $._type)),
    own_type: $ => prec.right(seq('own', $._type)),
    compound_type: $ => seq('{', commaSep($.field_def), '}'),
    field_def: $ => seq(field('name', $.identifier), ':', field('type', $._type)),

    // ── interfaces ──────────────────────────────────────────────
    interface_decl: $ => seq(
      'interface', field('name', $.identifier),
      optional($.type_params),
      optional(seq('extends', commaSep1(choice($.generic_type, $.qualified_name)))),
      '{', repeat($.method_sig), '}',
    ),
    // generic type parameters on a declaration:  <TKey, TEntity, TModel>
    type_params: $ => seq('<', commaSep1(field('param', $.identifier)), '>'),
    method_sig: $ => seq(
      optional('async'), $.function_kind, field('name', $.identifier),
      $.params, optional(seq('->', field('return', $._type))),
      // interface methods may carry a default body (`{ … }` or `=> expr`)
      optional(field('body', choice($.block, seq('=>', $._expression)))),
    ),

    // ── classes ─────────────────────────────────────────────────
    class_decl: $ => seq(
      'class', field('name', $.identifier),
      optional(seq('extends', field('base', choice($.generic_type, $.qualified_name)))),
      'implements', optional(commaSep1(choice($.generic_type, $.qualified_name))),
      '{', optional($.deps_block), optional($.state_block), repeat($._class_member), '}',
    ),
    deps_block: $ => seq('deps', '{', repeat($.dep), '}'),
    dep: $ => seq(
      field('name', $.identifier), ':', field('type', $._type),
      optional(seq('as', field('scope', $.scope_kind))),
      optional(choice(
        seq('where', field('guard', $._expression)),
        seq('or', field('fallback', $.qualified_name)),
        $.when_clause,
      )),
      optional(','),
    ),
    // mutable instance state:  state { name: Type = expr, ... }
    state_block: $ => seq('state', '{', commaSep($.state_field), '}'),
    state_field: $ => seq(
      field('name', $.identifier), ':', field('type', $._type),
      optional(seq('=', field('value', $._expression))),
    ),
    when_clause: $ => seq('when', '{', commaSep($.when_arm), '}'),
    when_arm: $ => seq(choice($._expression, 'otherwise'), '->', choice($.qualified_name, $.array_literal, 'none')),
    _class_member: $ => choice($.function_decl, $.creator_decl),

    // ── functions / creators / entry ────────────────────────────
    function_kind: _ => choice(
      'mapper', 'projector', 'predicate', 'consumer', 'producer', 'reducer', 'action', 'decision', 'listener',
    ),
    function_decl: $ => seq(
      optional('async'), $.function_kind,
      optional($.fn_deps_block),
      field('name', $.identifier), $.params,
      optional(seq('->', field('return', $._type))),
      optional(seq('where', field('guard', $._expression))),
      field('body', choice($.block, seq('=>', $._expression))),
    ),
    fn_deps_block: $ => seq('{', repeat($.dep), '}'),
    creator_decl: $ => seq(
      optional('async'), 'creator',
      field('name', $.identifier), $.params,
      optional(seq('->', field('return', $._type))),
      $.block,
    ),
    entry_decl: $ => seq(
      optional('async'), 'entry',
      field('name', $.identifier), $.params,
      optional(seq('->', field('return', $._type))),
      $.block,
    ),
    params: $ => seq('(', commaSep($.param), ')'),
    param: $ => seq(field('name', $.identifier), ':', field('type', $._type),
                    optional(seq('=', $._expression))),

    // ── modules ─────────────────────────────────────────────────
    module_decl: $ => seq('module', optional($.qualified_name), '{',
      repeat(choice($.import_decl, $.binding, $.const_decl, $.module_field)), '}'),
    // module-scoped constant:  const NAME: Type = expr
    const_decl: $ => seq('const', field('name', $.identifier), ':', field('type', $._type),
                         '=', field('value', $._expression)),
    // module metadata field:  id = "…", version = "…", includes = [ … ], …
    module_field: $ => prec(-1, seq(field('name', $.identifier), '=', field('value', $._expression))),
    binding: $ => seq(
      'bind', field('interface', $._type), '->',
      field('target', choice($.qualified_name, $.array_literal, 'none')),
      optional(seq('as', $.scope_kind)),
    ),
    scope_kind: _ => choice('singleton', 'transient', 'scoped'),

    // ── extern / export ─────────────────────────────────────────
    extern_block: $ => seq('extern', $.string, '{', repeat($.method_sig), '}'),
    export_decl: $ => seq('export', $.string, $.function_decl),

    // ── statements ──────────────────────────────────────────────
    block: $ => seq('{', repeat($._statement), '}'),
    _statement: $ => choice(
      $.let_stmt, $.return_stmt, $.if_stmt, $.match_stmt,
      $.while_stmt, $.for_stmt, $.loop_stmt, $.scope_stmt, $.unsafe_stmt,
      $.break_stmt, $.continue_stmt, $.assign_stmt, $.expr_stmt,
    ),
    let_stmt: $ => seq('let', field('name', $.identifier),
                       optional(seq(':', field('type', $._type))),
                       '=', field('value', $._expression)),
    return_stmt: $ => prec.right(seq('return', optional($._expression))),
    assign_stmt: $ => seq($._expression, choice('=', '+=', '-=', '*=', '/=', '%='), $._expression),
    expr_stmt: $ => $._expression,
    if_stmt: $ => prec.right(seq(
      'if', $._condition, $.block,
      repeat(seq('else', 'if', $._condition, $.block)),
      optional(seq('else', $.block)),
    )),
    _condition: $ => choice($._expression, $.if_let),
    if_let: $ => seq('let', field('name', $.identifier), '=', $._expression),
    while_stmt: $ => seq('while', $._expression, $.block),
    for_stmt: $ => seq('for', field('name', $.identifier), 'in', $._expression, $.block),
    loop_stmt: $ => seq('loop', $.block),
    scope_stmt: $ => seq('scope', field('name', $.identifier), $.block),
    unsafe_stmt: $ => seq('unsafe', $.block),
    break_stmt: _ => 'break',
    continue_stmt: _ => 'continue',
    match_stmt: $ => seq('match', $._expression, '{', repeat($.match_arm), '}'),
    match_arm: $ => seq(field('pattern', $._pattern), optional(seq('if', $._expression)),
                        '->', choice($.block, $._expression), optional(',')),
    _pattern: $ => choice($.identifier, $.number, $.string, $.boolean, 'none', '_'),

    // ── expressions ─────────────────────────────────────────────
    _expression: $ => choice(
      $.binary_expr, $.unary_expr, $.cast_expr, $.try_expr, $.call_expr, $.member_expr,
      $.index_expr, $.type_literal, $.array_literal, $.paren_expr, $.empty_expr,
      $.identifier, $.self, $.input, $.value,
      $.number, $.string, $.char, $.boolean, 'none', $.regex,
    ),

    // `x as T` — cross-type view / codec cast (e.g. `e as Json`, `j as User`).
    cast_expr: $ => prec.left(PREC.typecheck, seq(
      field('value', $._expression), 'as', field('type', $._type),
    )),

    // empty collection literal:  empty List<Item>, empty Map<String, Integer>, …
    empty_expr: $ => prec.right(seq('empty', field('type', $._type))),

    // postfix `?` — Result/Optional error-propagation
    try_expr: $ => prec(PREC.postfix, seq($._expression, '?')),
    paren_expr: $ => seq('(', $._expression, ')'),
    self: _ => 'this',
    input: _ => 'input',
    value: _ => 'value',

    binary_expr: $ => choice(
      ...[
        ['or', PREC.or], ['and', PREC.and],
        ['==', PREC.eq], ['!=', PREC.eq],
        ['<', PREC.rel], ['>', PREC.rel], ['<=', PREC.rel], ['>=', PREC.rel],
        ['is', PREC.typecheck], ['in', PREC.typecheck], ['matches', PREC.typecheck],
        ['+', PREC.add], ['-', PREC.add],
        ['*', PREC.mul], ['/', PREC.mul], ['%', PREC.mul],
        ['??', PREC.eq],
      ].map(([op, p]) => prec.left(p, seq(
        field('left', $._expression), field('op', op), field('right', $._expression),
      ))),
    ),
    unary_expr: $ => prec.right(PREC.unary, seq(
      field('op', choice('-', '!', 'not', '&', '&mut', 'dup', 'await', 'move', 'spawn')),
      $._expression,
    )),
    call_expr: $ => prec(PREC.postfix, seq(field('fn', $._expression), $.args)),
    args: $ => seq('(', commaSep(choice($.named_arg, $._expression)), ')'),
    named_arg: $ => seq(field('name', $.identifier), ':', $._expression),
    member_expr: $ => prec(PREC.postfix, seq(
      field('object', $._expression), choice('.', '?.'), field('field', $.identifier),
    )),
    index_expr: $ => prec(PREC.postfix, seq(field('object', $._expression), '[', $._expression, ']')),
    type_literal: $ => prec(PREC.postfix, seq(
      field('type', $.qualified_name),
      '{', commaSep(seq(field('field', $.identifier), ':', $._expression)), '}',
    )),
    array_literal: $ => seq('[', commaSep($._expression), ']'),

    // ── tokens ──────────────────────────────────────────────────
    identifier: _ => /[A-Za-z_][A-Za-z0-9_]*/,
    number: _ => token(choice(
      /0x[0-9a-fA-F_]+/, /0b[01_]+/,
      /[0-9][0-9_]*(\.[0-9][0-9_]*)?([eE][+-]?[0-9]+)?/,
    )),
    // A leading `$` marks an interpolated string ($"...${expr}..."); both the
    // single- and triple-quoted forms accept it. Triple-quoted strings span
    // multiple lines.
    string: _ => token(choice(
      /\$?"""[\s\S]*?"""/,
      seq(optional('$'), '"', repeat(choice(/[^"\\]/, /\\./)), '"'),
    )),
    char: _ => token(seq("'", choice(/[^'\\]/, /\\./), "'")),
    boolean: _ => choice('true', 'false'),
    regex: _ => token(prec(-1, seq('/', repeat(choice(/[^/\\\n]/, /\\./)), '/'))),
  },
});

function commaSep(rule) { return optional(commaSep1(rule)); }
function commaSep1(rule) { return seq(rule, repeat(seq(',', rule)), optional(',')); }

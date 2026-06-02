; Tree-sitter highlight queries for X (Zed capture names).
; More specific patterns come first; the generic identifier rule is last.

; ── comments ──────────────────────────────────────────────────────
(line_comment) @comment
(block_comment) @comment

; ── declarations: names ───────────────────────────────────────────
(type_decl name: (identifier) @type)
(interface_decl name: (identifier) @type)
(class_decl name: (identifier) @type)

(function_decl name: (identifier) @function)
(creator_decl name: (identifier) @function)
(entry_decl name: (identifier) @function)
(method_sig name: (identifier) @function)

; ── calls ─────────────────────────────────────────────────────────
(call_expr fn: (identifier) @function.call)
(call_expr fn: (member_expr field: (identifier) @function.method))

; ── type expressions ──────────────────────────────────────────────
(primitive_type) @type.builtin
(named_type (qualified_name (identifier) @type))

; ── fields / properties ───────────────────────────────────────────
(field_def name: (identifier) @property)
(dep name: (identifier) @property)
(member_expr field: (identifier) @property)
(named_arg name: (identifier) @property)
(type_literal field: (identifier) @property)

; ── parameters / bindings ─────────────────────────────────────────
(param name: (identifier) @variable.parameter)
(let_stmt name: (identifier) @variable)
(for_stmt name: (identifier) @variable)

; ── built-in pseudo-variables ─────────────────────────────────────
(self) @variable.special
(input) @variable.special
(value) @variable.special

; ── literals ──────────────────────────────────────────────────────
(string) @string
(char) @string
(regex) @string.regex
(number) @number
(boolean) @boolean
"none" @constant.builtin

; ── keywords ──────────────────────────────────────────────────────
(function_kind) @keyword

[
  "type" "interface" "class" "implements" "extends" "deps" "when" "otherwise"
  "bind" "as" "module" "scope" "creator" "entry" "let" "return" "if" "else"
  "match" "async" "await" "own" "dup" "unsafe" "extern" "export" "import"
  "namespace" "for" "while" "loop" "break" "continue" "spawn" "where"
  "singleton" "transient" "scoped" "move"
] @keyword

[ "and" "or" "not" "is" "in" "matches" ] @keyword.operator

; ── operators / punctuation ───────────────────────────────────────
[
  "+" "-" "*" "/" "%" "==" "!=" "<" ">" "<=" ">=" "=" "->" "=>"
  "&" "&mut" "|" "!" "?" "??" "?." "+=" "-=" "*=" "/=" "%="
] @operator

[ "(" ")" "{" "}" "[" "]" ] @punctuation.bracket
[ "," ":" "." ] @punctuation.delimiter

; ── catch-all (must be last) ──────────────────────────────────────
(identifier) @variable

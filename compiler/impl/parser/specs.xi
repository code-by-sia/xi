// xc parser — the spec/AST data model (FieldSpec .. Program)
// (part of the parser — spliced via the xc.xi manifest)

// A field in a compound type or interface
type FieldSpec = { name: String, ctype: String }

// A parameter in a function signature
type ParamSpec = { name: String, ctype: String }

// A function method signature
type MethodSpec = {
    isAsync:   Bool,
    kind:      String,  // "mapper",...,"listener","action"
    name:      String,
    params:    String,  // comma-separated "ctype name" pairs
    retCtype:  String,
    bodyTokens: Token[],
    topic:     String,  // for `listener` methods: the subscribed topic ("" otherwise)
    hasWhere:  Bool,    // `where`-guarded overload (routing / dispatch by guard)
    whereTokens: Token[],
    fnDeps:    DepSpec[] // method-level dependencies: kind (d: I) name(...)
}

// A type declaration (refined or compound)
type TypeSpec = {
    name:       String,
    isCompound: Bool,
    baseCtype:  String,        // for refined types
    fields:     String[],      // for compound types: "name:ctype" pairs
    hasWhere:   Bool,
    whereSrc:   String,        // (legacy, unused)
    whereTokens: Token[],      // refined-type constraint tokens (no `where`)
    isSum:      Bool,          // tagged-union (sum / algebraic) type
    variants:   String[]       // for sum types: "Variant|f1:ct1,f2:ct2" per variant
}

// An interface
type IfaceSpec = {
    name:     String,
    extendsNames: String[],
    methList: MethodSpec[]
}

// A dep in a class or function.
//   form: "single" | "list" | "or" | "where" | "opt"
type DepSpec = {
    name:       String,
    ctype:      String,
    ifaceName:  String,    // element/interface X name (without xc_ wrapping)
    hasWhen:    Bool,
    form:       String,
    orAlt:      String,    // fallback class for `I or J`
    whereTokens: Token[]   // guard tokens for `I where <cond>`
}

// A class
type ClassSpec = {
    name:       String,
    implNames:  String[],
    depList:    DepSpec[],
    methList:   MethodSpec[]
}

// A module binding
type BindSpec = {
    ifaceName:    String,
    concreteName: String,
    scopeKind:    String,
    configPath:   String    // non-empty for `bind I -> readConfig("file")`
}

// A module — DI container plus optional package metadata.
type ModuleSpec = {
    name:        String,
    bindings:    BindSpec[],
    id:          String,    // binary name (xc uses this if set)
    title:       String,    // the `name = "..."` field (display name)
    description: String,
    version:     String,
    license:     String,
    includes:    String[],  // source globs for this module (default ["./**"])
    excludes:    String[],  // globs to drop (default [])
    dependencies: String[]  // URLs to source archives, fetched by `xi install`
}

// A top-level function or creator
type FuncSpec = {
    isCreator:   Bool,
    isAsync:     Bool,
    kind:        String,
    name:        String,
    params:      String,    // C param list
    retCtype:    String,
    bodyTokens:  Token[],   // tokens of the body block, excl. outer braces
    hasWhere:    Bool,
    whereTokens: Token[],   // tokens of the overload-selection guard (no braces)
    fnDeps:      DepSpec[], // function-level dependencies:  kind { d: I } name(...)
    topic:       String    // for `listener`: subscribed topic ("" otherwise)
}

// An `atom` (active-state / store): a holder of an immutable state value, with
// `transition`s (reducers) that produce the next value.
type AtomSpec = {
    name:          String,
    stateTypeName: String,     // e.g. "Cart" — the state type (for .current)
    initToks:      Token[],    // tokens of the `initial` expression
    transitions:   FuncSpec[] // transition f(s: T, ...) -> T { body }
}

// One arrow of a machine: name(params) : from(,from)* -> to [where g] [update {..}]
type MachineTransition = {
    name:        String,
    params:      String,      // C param string ("" if none)
    froms:       String,      // comma-joined source states
    toState:     String,
    hasGuard:    Bool,
    guardTokens: Token[],     // boolean over params + `data` (no `where`)
    hasUpdate:   Bool,
    updateTokens: Token[]     // tokens inside `update { field: expr, ... }`
}

// A `machine` (finite state machine): named states, optional machine-wide `data`
// context, and transitions with optional params / `where` guards / `update`.
type MachineSpec = {
    name:        String,
    states:      String[],    // ordered; index = state id
    initial:     String,
    terminals:   String[],
    hasData:     Bool,
    dataFields:  String[],    // "name:ctype" for the data context
    dataInit:    Token[],     // tokens inside `data { name: T = expr, ... }`
    transitions: MachineTransition[]
}

// The whole program
type Program = {
    types:      TypeSpec[],
    ifaces:     IfaceSpec[],
    classes:    ClassSpec[],
    modules:    ModuleSpec[],
    functions:  FuncSpec[],
    externs:    FuncSpec[],   // extern "C" signatures (bodyTokens empty)
    entrySpec:  FuncSpec,     // isCreator=false, kind="entry"
    interrupts: String[],     // names of declared `interrupt` types (for type ids)
    atoms:      AtomSpec[],   // declared `atom`s
    machines:   MachineSpec[], // declared `machine`s
    eventTypes: String[],     // names of declared `event` types (typed payloads)
    tables:     DecisionTable[], // table-form `decision`s (emitted by codegen)
    tests:      FuncSpec[],    // `test "name" (deps) { ... }` cases (kind="test")
    scheduled:  FuncSpec[],    // `scheduled name() cron "..." { }` jobs (cron in .topic)
    libraries:  ModuleSpec[],  // `library { id/version/includes/... }` manifest(s); inert in codegen
    infixFns:   String[],      // names of `infix`-declared functions (callable as `a f b`)
    cIncludes:  String[],      // C headers from `extern "C" { include "..." }`
    cFlags:     String[]       // build-flag tokens: -lX / -I.. / pkg:NAME (extern "C")
}

// C helpers for building typed arrays used by Program

// Compiler — the driver contract. `XcCompiler` (xc_compiler.xi) depends on the
// three pipeline stages through their interfaces and orchestrates
// load -> lex -> parse -> generate -> cc. The stages are reached only through
// the injected `lexer` / `parser` / `codegen`; the rest stays as free helpers
// in driver.xi. The `module` (app.xi) binds the implementations.
interface Compiler {
    producer build(srcPath: String) -> Integer
    producer buildAll() -> Integer
    predicate isBuildable(path: String) -> Bool
    producer run(args: String[]) -> Integer
}

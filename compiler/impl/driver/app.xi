// Composition root for the `xc` binary: bind each stage interface to its
// implementation, then resolve the Compiler and run it.
module App {
    bind Text        -> StdText        as singleton
    bind TokenArrays -> StdTokenArrays as singleton
    bind SpecArrays  -> StdSpecArrays  as singleton
    bind Host        -> PosixHost      as singleton
    bind Diagnostics -> Diag           as singleton
    bind Lexer       -> XiLexer        as singleton
    bind Parser      -> XiParser       as singleton
    bind Codegen     -> XiCodegen      as singleton
    bind ModuleLoader -> XiModuleLoader as singleton
    bind Compiler    -> XcCompiler     as singleton
}

async entry main(args: String[]) -> Integer {
    let xc = App.resolve(Compiler)
    return xc.run(args)
}

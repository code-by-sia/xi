// ModuleLoader — resolves `import`s into one token stream and gathers a module's
// source set. Implemented by XiModuleLoader (impl/driver/module_loader.xi),
// which depends on the Lexer + Host services.
interface ModuleLoader {
    producer load(rawPath: String, visited: String[]) -> LoadResult
    producer gather(srcPath: String, inc: String[], exc: String[]) -> LoadResult
}

// Codegen — stage 3 contract: Program -> C99 source.
// Implemented by XiCodegen (xi_codegen.xi); the generator is split across the
// core/xtype/expr/seq/postfix/stmt/decl/emit/top files in this folder.
interface Codegen {
    mapper generate(prog: Program, srcPath: String) -> String
}

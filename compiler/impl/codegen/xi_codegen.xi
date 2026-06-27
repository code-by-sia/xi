// XiCodegen — the default Codegen: delegates to the `genAll` driver of the
// generator passes (top.xi).
class XiCodegen implements Codegen {
    deps { codecs: Codecs }
    mapper generate(prog: Program, srcPath: String) -> String { return genAll(prog, srcPath, codecs) }
}

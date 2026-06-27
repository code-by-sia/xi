// Codecs — JSON (de)serialization + event/web dispatch generation. A leaf
// codegen component (no recursion into expression/statement gen). Implemented by
// JsonCodecs (impl/codegen/codecs.xi); resolved by genAll.
interface Codecs {
    mapper genEventCodecs(prog: Program) -> String
    mapper genEventFwd(prog: Program) -> String
    mapper genEventDispatch(prog: Program) -> String
    mapper genWebDispatch(prog: Program) -> String
}

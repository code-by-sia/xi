// Serialization in three formats over one value tree. Build a `Json` value with
// std/json, then render it as JSON, YAML, or XML — and parse each back. The
// document model (`Json`) is shared; only the encoder/decoder differs.
import "std/log.xi"
import "std/json.xi"
import "std/yaml.xi"
import "std/xml.xi"

mapper sample() -> Json {
    let langs = json.array()
    langs = json.push(langs, json.str("X"))
    langs = json.push(langs, json.str("C"))
    let o = json.object()
    o = json.set(o, "name", json.str("John Doe"))
    o = json.set(o, "age", json.int(36))
    o = json.set(o, "admin", json.of(true))
    o = json.set(o, "langs", langs)
    return o
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let o = sample()
    logger.print("=== YAML ===")
    let y = yaml.stringify(o)
    logger.print(y)
    logger.print("--- parse back -> json ---")
    let yb = yaml.parse(y)
    logger.print(json.stringify(yb))

    logger.print("=== XML ===")
    let x = xml.stringify(o)
    logger.print(x)
    logger.print("--- parse back -> json ---")
    let xb = xml.parse(x)
    logger.print(json.stringify(xb))
    return 0
}

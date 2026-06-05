// Serialization in three formats over one value tree. Build a `Json` value with
// std/json, then render it as JSON, YAML, or XML — and parse each back. The
// document model (`Json`) is shared; only the encoder/decoder differs.
import "std/json.xi"
import "std/yaml.xi"
import "std/xml.xi"

mapper sample() -> Json {
    let langs = json.array()
    langs = json.push(langs, json.str("X"))
    langs = json.push(langs, json.str("C"))
    let o = json.object()
    o = json.set(o, "name", json.str("Ada"))
    o = json.set(o, "age", json.int(36))
    o = json.set(o, "admin", json.of(true))
    o = json.set(o, "langs", langs)
    return o
}

async entry main(args: String[]) -> Integer {
    let o = sample()
    system.stdout.writeln("=== YAML ===")
    let y = yaml.stringify(o)
    system.stdout.write(y)
    system.stdout.writeln("--- parse back -> json ---")
    let yb = yaml.parse(y)
    system.stdout.writeln(json.stringify(yb))

    system.stdout.writeln("=== XML ===")
    let x = xml.stringify(o)
    system.stdout.write(x)
    system.stdout.writeln("--- parse back -> json ---")
    let xb = xml.parse(x)
    system.stdout.writeln(json.stringify(xb))
    return 0
}

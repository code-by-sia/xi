// std/json — X's serialization library. Build a Json value tree, render it to
// text (compact or pretty), parse text back, and read fields. Malformed input is
// reported through `isValid`.
import "std/json.x"

async entry main(args: String[]) -> Integer {
    // Build an object: { "name": "Ada", "age": 36, "langs": ["X","C"], "admin": true }
    let langs = json.array()
    langs = json.push(langs, json.str("X"))
    langs = json.push(langs, json.str("C"))

    let obj = json.object()
    obj = json.set(obj, "name", json.str("Ada"))
    obj = json.set(obj, "age", json.int(36))
    obj = json.set(obj, "langs", langs)
    obj = json.set(obj, "admin", json.of(true))

    system.stdout.writeln(json.stringify(obj))
    system.stdout.writeln(json.pretty(obj))

    // Round-trip: parse text back and read fields.
    let txt = "{\"city\":\"Paris\",\"pop\":2148327,\"tags\":[\"eu\",\"capital\"]}"
    let p = json.parse(txt)
    if json.isValid(p) {
        system.stdout.writeln("city = " + json.getString(p, "city"))
        system.stdout.writeln("pop  = " + json.getNumber(p, "pop"))
        let tags = json.get(p, "tags")
        system.stdout.writeln("ntags = " + json.length(tags))
        system.stdout.writeln("tag0 = " + json.asString(json.at(tags, 0)))
    }

    // Malformed input is detected.
    let bad = json.parse("{ oops")
    if not json.isValid(bad) { system.stdout.writeln("bad json rejected") }
    return 0
}

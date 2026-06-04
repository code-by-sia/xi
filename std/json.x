// std/json — JSON serialization.  import "std/json.x"  then  json.stringify(v)
//
// `Json` is an opaque value tree. Build one with the constructors, compose
// objects/arrays with `set`/`push`, turn it into text with `stringify`/`pretty`,
// and read text back with `parse`. This is X's serialization library: any value
// that can be expressed as a Json tree can be sent over the wire or stored.
namespace json

extern "C" {
    producer xstd_json_null() -> Json
    producer xstd_json_bool(b: Bool) -> Json
    producer xstd_json_number(n: Number) -> Json
    producer xstd_json_string(s: String) -> Json
    producer xstd_json_array() -> Json
    producer xstd_json_object() -> Json
    producer xstd_json_push(arr: Json, v: Json) -> Json
    producer xstd_json_set(obj: Json, key: String, v: Json) -> Json

    mapper    xstd_json_stringify(v: Json) -> String
    mapper    xstd_json_pretty(v: Json) -> String
    producer  xstd_json_parse(s: String) -> Json
    predicate xstd_json_ok(v: Json) -> Bool

    mapper    xstd_json_kind(v: Json) -> Integer
    mapper    xstd_json_length(v: Json) -> Integer
    mapper    xstd_json_at(arr: Json, i: Integer) -> Json
    mapper    xstd_json_get(obj: Json, key: String) -> Json
    predicate xstd_json_has(obj: Json, key: String) -> Bool
    mapper    xstd_json_key_at(obj: Json, i: Integer) -> String
    mapper    xstd_json_as_string(v: Json) -> String
    mapper    xstd_json_as_number(v: Json) -> Number
    predicate xstd_json_as_bool(v: Json) -> Bool
}

// Kind tags (what `kind(v)` returns).
mapper KIND_NULL()   -> Integer { return 0 }
mapper KIND_BOOL()   -> Integer { return 1 }
mapper KIND_NUMBER() -> Integer { return 2 }
mapper KIND_STRING() -> Integer { return 3 }
mapper KIND_ARRAY()  -> Integer { return 4 }
mapper KIND_OBJECT() -> Integer { return 5 }
mapper KIND_ERROR()  -> Integer { return 6 }

// ── Constructors ───────────────────────────────────────────────────
producer nul() -> Json            { return xstd_json_null() }
producer of(b: Bool) -> Json      { return xstd_json_bool(b) }
producer num(n: Number) -> Json   { return xstd_json_number(n) }
producer int(n: Integer) -> Json  { return xstd_json_number(n) }
producer str(s: String) -> Json   { return xstd_json_string(s) }
producer array() -> Json          { return xstd_json_array() }
producer object() -> Json         { return xstd_json_object() }

// Compose. `push`/`set` return the container so calls can be chained.
producer push(arr: Json, v: Json) -> Json          { return xstd_json_push(arr, v) }
producer set(obj: Json, key: String, v: Json) -> Json { return xstd_json_set(obj, key, v) }

// ── Serialize / parse ──────────────────────────────────────────────
mapper   stringify(v: Json) -> String { return xstd_json_stringify(v) }
mapper   pretty(v: Json) -> String    { return xstd_json_pretty(v) }
producer parse(s: String) -> Json     { return xstd_json_parse(s) }
predicate isValid(v: Json)            { return xstd_json_ok(v) }

// ── Inspect ────────────────────────────────────────────────────────
mapper kind(v: Json) -> Integer   { return xstd_json_kind(v) }
mapper length(v: Json) -> Integer { return xstd_json_length(v) }

predicate isNull(v: Json)   { return xstd_json_kind(v) == 0 }
predicate isBool(v: Json)   { return xstd_json_kind(v) == 1 }
predicate isNumber(v: Json) { return xstd_json_kind(v) == 2 }
predicate isString(v: Json) { return xstd_json_kind(v) == 3 }
predicate isArray(v: Json)  { return xstd_json_kind(v) == 4 }
predicate isObject(v: Json) { return xstd_json_kind(v) == 5 }

// ── Access ─────────────────────────────────────────────────────────
mapper    at(arr: Json, i: Integer) -> Json        { return xstd_json_at(arr, i) }
mapper    get(obj: Json, key: String) -> Json      { return xstd_json_get(obj, key) }
predicate has(obj: Json, key: String)              { return xstd_json_has(obj, key) }
mapper    keyAt(obj: Json, i: Integer) -> String   { return xstd_json_key_at(obj, i) }

// Coerce a leaf to a host value (returns a zero value on a kind mismatch).
mapper    asString(v: Json) -> String { return xstd_json_as_string(v) }
mapper    asNumber(v: Json) -> Number { return xstd_json_as_number(v) }
predicate asBool(v: Json)             { return xstd_json_as_bool(v) }

// Convenience: read a string/number field straight off an object.
mapper getString(obj: Json, key: String) -> String { return xstd_json_as_string(xstd_json_get(obj, key)) }
mapper getNumber(obj: Json, key: String) -> Number { return xstd_json_as_number(xstd_json_get(obj, key)) }

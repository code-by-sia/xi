// std/bytes — raw byte buffers.  import "std/bytes.xi"  then  bytes.fromString("hi")
namespace bytes

extern "C" {
    mapper   bytes_len(b: Bytes) -> Integer
    mapper   bytes_get(b: Bytes, i: Integer) -> Integer
    mapper   bytes_slice(b: Bytes, from: Integer, to: Integer) -> Bytes
    mapper   bytes_concat(a: Bytes, b: Bytes) -> Bytes
    mapper   bytes_from_string(s: String) -> Bytes
    mapper   bytes_to_string(b: Bytes) -> String
    producer bytes_empty() -> Bytes
}

mapper   length(b: Bytes) -> Integer { return bytes_len(b) }
mapper   at(b: Bytes, i: Integer) -> Integer { return bytes_get(b, i) }
mapper   slice(b: Bytes, from: Integer, to: Integer) -> Bytes { return bytes_slice(b, from, to) }
mapper   concat(a: Bytes, b: Bytes) -> Bytes { return bytes_concat(a, b) }
mapper   fromString(s: String) -> Bytes { return bytes_from_string(s) }
mapper   toString(b: Bytes) -> String { return bytes_to_string(b) }
producer empty() -> Bytes { return bytes_empty() }
predicate isEmpty(b: Bytes) { return bytes_len(b) == 0 }

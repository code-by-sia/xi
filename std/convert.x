// std/convert — parsing and stringification.  import "std/convert.x"
namespace convert

extern "C" {
    mapper xstd_num_ok(s: String) -> Bool
    mapper xstd_to_number(s: String) -> Number
    mapper xstd_int_ok(s: String) -> Bool
    mapper xstd_to_integer(s: String) -> Integer
    mapper number_to_str(n: Number) -> String
    mapper int_to_string(n: Integer) -> String
}

mapper toString(n: Number) -> String  { return number_to_str(n) }
mapper intToString(n: Integer) -> String { return int_to_string(n) }
mapper boolToString(b: Bool) -> String { if b { return "true" } return "false" }

// Parse, returning a Result (Err on malformed input).
mapper parseNumber(s: String) -> Number! {
    if xstd_num_ok(s) { return ok(xstd_to_number(s)) }
    return err("not a number: " + s)
}
mapper parseInteger(s: String) -> Integer! {
    if xstd_int_ok(s) { return ok(xstd_to_integer(s)) }
    return err("not an integer: " + s)
}

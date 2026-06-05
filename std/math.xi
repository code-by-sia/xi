// std/math — numeric functions.  Use as:  import "std/math.xi"  then  math.sqrt(2)
namespace math

extern "C" {
    mapper xstd_sqrt(x: Number) -> Number
    mapper xstd_pow(x: Number, y: Number) -> Number
    mapper xstd_exp(x: Number) -> Number
    mapper xstd_ln(x: Number) -> Number
    mapper xstd_log10(x: Number) -> Number
    mapper xstd_sin(x: Number) -> Number
    mapper xstd_cos(x: Number) -> Number
    mapper xstd_tan(x: Number) -> Number
    mapper xstd_floor(x: Number) -> Number
    mapper xstd_ceil(x: Number) -> Number
    mapper xstd_round(x: Number) -> Number
    mapper xstd_fabs(x: Number) -> Number
    mapper xstd_pi() -> Number
    mapper xstd_e() -> Number
}

mapper pi() -> Number { return xstd_pi() }
mapper e()  -> Number { return xstd_e() }

mapper abs(x: Number) -> Number   { return xstd_fabs(x) }
mapper sqrt(x: Number) -> Number  { return xstd_sqrt(x) }
mapper pow(x: Number, y: Number) -> Number { return xstd_pow(x, y) }
mapper exp(x: Number) -> Number   { return xstd_exp(x) }
mapper ln(x: Number) -> Number    { return xstd_ln(x) }
mapper log10(x: Number) -> Number { return xstd_log10(x) }
mapper sin(x: Number) -> Number   { return xstd_sin(x) }
mapper cos(x: Number) -> Number   { return xstd_cos(x) }
mapper tan(x: Number) -> Number   { return xstd_tan(x) }
mapper floor(x: Number) -> Number { return xstd_floor(x) }
mapper ceil(x: Number) -> Number  { return xstd_ceil(x) }
mapper round(x: Number) -> Number { return xstd_round(x) }

mapper min(a: Number, b: Number) -> Number { if a < b { return a } return b }
mapper max(a: Number, b: Number) -> Number { if a > b { return a } return b }
mapper clamp(x: Number, lo: Number, hi: Number) -> Number {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

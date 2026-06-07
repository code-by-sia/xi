# Error handling

Xi models recoverable failure with a result type, constructors `ok`/`err`, and
the `?` propagation operator.

## The result type `T!`

`T!` means "a `T` or an error". The error is a `String` in v1.

## Constructing results

Use `ok(value)` and `err("message")` inside a function whose return type is a
result:

```x
type Age = Number where value >= 0 and value <= 130

mapper checkAge(n: Number) -> Age! {
    if n < 0   { return err("age is negative") }
    if n > 130 { return err("age too large") }
    return ok(n)
}
```

## Propagating with `?`

`let x = expr?` evaluates `expr`; if it is an `Err`, the **enclosing function
returns that error immediately**; otherwise `x` is bound to the unwrapped `Ok`
value. (`expr?` as a bare statement propagates the error and discards the value.)

```x
mapper classify(n: Number) -> String! {
    let a = checkAge(n)?            // returns early if checkAge failed
    if a < 18 { return ok("minor") }
    return ok("adult")
}
```

## Inspecting results

`isOk(r)` / `isErr(r)` test a result; `.value` and `.err` read its parts.

```x
import "std/log.xi"

consumer (logger: Logger) report(label: String, r: String!) {
    if isOk(r) { logger.info(label + " -> " + r.value) }
    else       { logger.error(label + " -> " + r.err) }
}

async entry main(args: String[]) -> Integer {
    report("25",  classify(25))    // [info]  25 -> adult
    report("200", classify(200))   // [error] 200 -> age too large
    report("-5",  classify(-5))    // [error] -5 -> age is negative
    return 0
}
```

Run the full example:

```console
$ xi errors.xi
25 -> adult
10 -> minor
200 -> error: age too large
-5 -> error: age is negative
```

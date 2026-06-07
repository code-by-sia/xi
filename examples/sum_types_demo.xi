// Sum (algebraic) types — a value is one of several variants, each optionally
// carrying its own fields. Construct a variant by name; deconstruct with `match`,
// binding the payload.
//
//   xc examples/sum_types_demo.xi && ./build/sum_types_demo
import "std/log.xi"
import "std/convert.xi"

// Variants with payloads, and a nullary variant (Empty).
type Shape =
    | Circle { radius: Number }
    | Rect   { w: Number, h: Number }
    | Empty

// A pure enum is just a sum type whose variants carry no payload.
type Color = | Red | Green | Blue

mapper area(s: Shape) -> Number {
    match s {
        Circle c -> { return 3.14159 * c.radius * c.radius }   // c bound to the payload
        Rect r   -> { return r.w * r.h }
        Empty    -> { return 0.0 }
    }
    return 0.0
}

mapper label(c: Color) -> String {
    match c {
        Red   -> { return "red" }
        Green -> { return "green" }
        Blue  -> { return "blue" }
    }
    return "?"
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let shapes: Shape[] = [ Circle { radius: 2.0 }, Rect { w: 3.0, h: 4.0 }, Empty ]
    for s in shapes {
        logger.print(number_to_str(area(s)))
    }
    logger.print(label(Green))
    return 0
}

module App {}

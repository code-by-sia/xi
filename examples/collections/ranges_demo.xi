// Integer ranges — a concise way to drive `for` loops (and a value you can pass
// around). `a..b` is inclusive; `until` is exclusive; `downTo` counts down; an
// optional `step` sets the stride. Operands can be any Integer expression.
//
//   xc examples/ranges_demo.xi && ./build/ranges_demo
import "std/log.xi"
import "std/convert.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    let a = ""
    for i in 1..5            { a = a + int_to_string(i) + " " }   // 1 2 3 4 5
    logger.print("1..5            = " + a)

    let b = ""
    for i in 0 until 5       { b = b + int_to_string(i) + " " }   // 0 1 2 3 4
    logger.print("0 until 5       = " + b)

    let c = ""
    for i in 10 downTo 6     { c = c + int_to_string(i) + " " }   // 10 9 8 7 6
    logger.print("10 downTo 6     = " + c)

    let d = ""
    for i in 0..10 step 2    { d = d + int_to_string(i) + " " }   // 0 2 4 6 8 10
    logger.print("0..10 step 2    = " + d)

    let e = ""
    for i in 9 downTo 1 step 3 { e = e + int_to_string(i) + " " } // 9 6 3
    logger.print("9 downTo 1 step3= " + e)

    // expression operands, and a range stored in a value
    let n = 4
    let sum = 0
    for i in 1..n { sum = sum + i }                              // 1+2+3+4 = 10
    logger.print("sum 1..n        = " + int_to_string(sum))
    return 0
}

module App {}

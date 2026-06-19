// generateSequence — a lazy, possibly-infinite source: the value starts at the
// seed and advances through the generator each step. The whole chain fuses into
// one loop, so nothing is materialized until a bounded terminal runs. Always
// bound an infinite source with take / takeWhile / first.
//
//   xc examples/generate_sequence_demo.xi && ./build/generate_sequence_demo
import "std/log.xi"
import "std/convert.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    // Powers of two — take a finite prefix of an infinite source.
    let powers = generateSequence(1) { it * 2 }.take(8).toList()
    logger.info("powers: " + powers.joinToString(", ") { int_to_string(it) })

    // Sum the first ten naturals (fused: no intermediate list).
    let sum = generateSequence(1) { it + 1 }.take(10).fold(0) { a, b => a + b }
    logger.info("sum 1..10 = " + int_to_string(sum))

    // takeWhile bounds the source by a predicate instead of a count.
    let evens = generateSequence(0) { it + 2 }.takeWhile { it < 10 }.toList()
    logger.info("evens < 10: " + evens.joinToString(", ") { int_to_string(it) })
    return 0
}

module GenerateSequenceDemo {}

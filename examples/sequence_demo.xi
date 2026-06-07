// Lazy sequences — `asSequence()` turns a list into a lazy pipeline. The whole
// chain of lazy ops + the terminal compile into ONE loop (loop fusion): no
// intermediate lists are built, and `take` short-circuits.
//
//   xc examples/sequence_demo.xi && ./build/sequence_demo
import "std/log.xi"
import "std/convert.xi"

type Order = { item: String, total: Number, active: Bool }

async entry (logger: Logger) main(args: String[]) -> Integer {
    let nums = listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)

    // filter -> map -> fold, fused into a single loop
    let sumSq = nums.asSequence()
        .filter { it % 2 == 0 }
        .map    { it * it }
        .fold(0) { a, b => a + b }
    logger.info("sum of squares of evens = " + int_to_string(sumSq))   // 220

    // take short-circuits — only the first 3 elements are visited
    logger.info("first 3 sum = " + int_to_string(nums.asSequence().take(3).sum()))   // 6

    let big = nums.asSequence().map { it * 10 }.filter { it > 50 }.toList()
    logger.info("toList = " + big.joinToString(",") { int_to_string(it) })   // 60,70,80,90,100

    if let firstOdd = nums.asSequence().filter { it % 2 == 1 }.firstOrNone() {
        logger.info("first odd = " + int_to_string(firstOdd))   // 1
    }

    let orders = listOf(
        Order { item: "pen",  total: 3.0,  active: true },
        Order { item: "book", total: 9.0,  active: false },
        Order { item: "ink",  total: 12.0, active: true }
    )
    let revenue = orders.asSequence().filter { it.active }.map { it.total }.fold(0.0) { a, b => a + b }
    logger.info("active revenue = " + number_to_str(revenue))   // 15
    return 0
}

module App {}

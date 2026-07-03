import "std/log.xi"
import "std/convert.xi"

// Whole-list reductions and the index/running/flatten helpers added to the
// List<T> functional API. Every call is inlined into a loop — no allocations
// beyond the result.

type Item = { name: String, price: Integer }

async entry (logger: Logger) main(args: String[]) -> Integer {
    let nums = listOf(3, 1, 4, 1, 5, 9, 2)

    // reductions over the elements
    logger.info("sum     = " + nums.sum())                 // 25
    logger.info("min/max = " + nums.min() + "/" + nums.max())   // 1/9
    logger.info("has 4?  = " + nums.contains(4))           // true
    logger.info("indexOf5= " + nums.indexOf(5))            // 4

    // optionals when the list might be empty
    if let lo = nums.minOrNone() { logger.info("minOrNone = " + lo) }

    // projection reductions: extreme of a computed key (not the element)
    let items = listOf(
        Item { name: "pen",  price: 3 },
        Item { name: "book", price: 12 },
        Item { name: "ink",  price: 7 }
    )
    logger.info("dearest = " + items.maxOf { it.price })   // 12
    logger.info("only>10 = " + items.single { it.price > 10 }.name)  // book

    // index pairs, running totals, flatten
    nums.withIndex().forEach { logger.info("  [" + it.first + "] = " + it.second) }
    let running = nums.scan(0) { acc, x => acc + x }       // 0 3 4 8 9 14 23 25
    logger.info("running = " + running.joinToString(" ") { int_to_string(it) })

    let grid = listOf(listOf(1, 2), listOf(3, 4), listOf(5))
    logger.info("flatten = " + grid.flatten().joinToString(",") { int_to_string(it) })  // 1,2,3,4,5
    return 0
}

module App {}

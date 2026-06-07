// Functional operations on List<T> — lambdas are written `{ it ... }` (implicit
// element) or `{ a, b => ... }` (explicit params). Each call is inlined into a
// loop, so chains are zero-overhead. No import needed for the operations.
//
//   xc examples/functional_demo.xi && ./build/functional_demo
import "std/log.xi"
import "std/convert.xi"

type Order = { item: String, qty: Integer, paid: Bool }

async entry (logger: Logger) main(args: String[]) -> Integer {
    let nums = listOf(1, 2, 3, 4, 5, 6)

    let doubled = nums.map { it * 2 }                  // 2 4 6 8 10 12
    let evens   = nums.filter { it % 2 == 0 }          // 2 4 6
    logger.info("doubled sum = " + int_to_string(doubled.sumOf { it }))  // 42
    logger.info("evens       = " + evens.joinToString(", ") { int_to_string(it) })
    logger.info("product     = " + int_to_string(nums.reduce { a, b => a * b }))  // 720
    logger.info("any even?   = " + nums.any { it % 2 == 0 })            // true
    logger.info("all < 10?   = " + nums.all { it < 10 })               // true
    logger.info("count odd   = " + int_to_string(nums.count { it % 2 == 1 }))  // 3

    // map to another type, then aggregate — chained, fused into loops
    let orders = listOf(
        Order { item: "pen",  qty: 3, paid: true },
        Order { item: "book", qty: 1, paid: false },
        Order { item: "ink",  qty: 5, paid: true }
    )
    let paidQty = orders.filter { it.paid }.map { it.qty }.fold(0) { a, b => a + b }  // 8
    logger.info("paid qty    = " + int_to_string(paidQty))
    logger.info("items       = " + orders.map { it.item }.joinToString(" | ") { it })

    orders.forEach { logger.info("  " + it.item + " x" + int_to_string(it.qty)) }
    return 0
}

module App {}

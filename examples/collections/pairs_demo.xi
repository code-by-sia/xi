// Pair<A,B> and the list operations built on it: zip, partition, unzip.
//
//   xc examples/pairs_demo.xi && ./build/pairs_demo
import "std/log.xi"
import "std/convert.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    // A pair: build with `to`, read with .first / .second.
    let p = "ada" to 36
    logger.info(p.first + " is " + int_to_string(p.second))

    // zip — pair up two lists element-by-element (truncated to the shorter).
    let names = listOf("ada", "bo", "cy")
    let ages  = listOf(36, 28, 41)
    let people = names.zip(ages)
    for who in people {
        logger.info(who.first + " (" + int_to_string(who.second) + ")")
    }

    // partition — split a list by a predicate into (matching, not-matching).
    let nums = listOf(1, 2, 3, 4, 5, 6)
    let split = nums.partition { it % 2 == 0 }
    logger.info("evens = " + int_to_string(split.first.len()))
    logger.info("odds  = " + int_to_string(split.second.len()))

    // unzip — recover the two columns from a list of pairs.
    let cols = people.unzip
    logger.info("names = " + int_to_string(cols.first.len())
              + ", ages = " + int_to_string(cols.second.len()))
    return 0
}

module PairsDemo {}

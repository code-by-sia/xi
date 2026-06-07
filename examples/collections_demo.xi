// Collections — built-in generics (like T[] arrays), created with `empty`:
//   List<T>  growable ordered list (push/get/set/len/removeAt/...)
//   Set<T>   hash set of unique elements (add/contains/remove/items/...)
// No import needed for the collections themselves.
//
//   xc examples/collections_demo.xi && ./build/collections_demo
import "std/log.xi"
import "std/convert.xi"

type Item = { name: String, qty: Integer }

mapper totalQty(items: List<Item>) -> Integer {     // List<T> as a parameter
    let sum = 0
    for it in items { sum = sum + it.qty }
    return sum
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    let nums = empty List<Integer>
    nums.push(10)
    nums.push(20)
    nums.push(30)
    logger.print("len   = " + int_to_string(nums.len()))      // 3
    logger.print("at 1  = " + int_to_string(nums.get(1)))     // 20
    nums.set(1, 99)
    nums.removeAt(0)                                                    // drop the 10
    let sum = 0
    for n in nums { sum = sum + n }
    logger.print("sum   = " + int_to_string(sum))             // 99 + 30 = 129
    if nums.isEmpty() { logger.print("empty") } else { logger.print("not empty") }

    let items = empty List<Item>                                       // list of compounds
    items.push(Item { name: "pen", qty: 2 })
    items.push(Item { name: "book", qty: 5 })
    logger.print("qty   = " + int_to_string(totalQty(items))) // 7

    // Set<T> — unique elements; add is idempotent, contains/remove are O(1) avg.
    let tags = empty Set<String>
    tags.add("new")
    tags.add("sale")
    tags.add("new")                                                    // duplicate ignored
    logger.print("tags  = " + int_to_string(tags.len()))      // 2
    logger.print("has?  = " + tags.contains("sale"))          // true (Bool coerces in +)
    tags.remove("sale")
    let listed = ""
    for t in tags { listed = listed + t + " " }               // iterate the set
    logger.print("kept  = " + listed)                         // new
    return 0
}

module App {}

// Collections — built-in generics (like T[] arrays), created with `empty`:
//   List<T>     growable ordered list (push/get/set/len/removeAt/...)
//   Set<T>      hash set of unique elements (add/contains/remove/items/...)
//   Map<K, V>   hash map (put/get/getOr/has/remove/keys/values/...)
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

    // Map<K, V> — keys are primitives or String; values can be any type.
    let ages = empty Map<String, Integer>
    ages.put("ada", 36)
    ages.put("bo", 20)
    ages.put("ada", 37)                                       // overwrite
    logger.print("ada   = " + int_to_string(ages.get("ada"))) // 37
    logger.print("zz?   = " + int_to_string(ages.getOr("zz", -1)))  // -1 (absent)
    let total = 0
    for name in ages.keys() { total = total + ages.get(name) } // iterate via keys()
    logger.print("total = " + int_to_string(total))           // 57
    return 0
}

module App {}

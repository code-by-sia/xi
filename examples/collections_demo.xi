// List<T> — a growable, typed list. It's a built-in generic (like T[] arrays):
// create one with `empty List<T>`, then push/get/set/etc. No import needed.
//
//   xc examples/collections_demo.xi && ./build/collections_demo
import "std/convert.xi"

type Item = { name: String, qty: Integer }

mapper totalQty(items: List<Item>) -> Integer {     // List<T> as a parameter
    let sum = 0
    for it in items { sum = sum + it.qty }
    return sum
}

async entry main(args: String[]) -> Integer {
    let nums = empty List<Integer>
    nums.push(10)
    nums.push(20)
    nums.push(30)
    system.stdout.writeln("len   = " + int_to_string(nums.len()))      // 3
    system.stdout.writeln("at 1  = " + int_to_string(nums.get(1)))     // 20
    nums.set(1, 99)
    nums.removeAt(0)                                                    // drop the 10
    let sum = 0
    for n in nums { sum = sum + n }
    system.stdout.writeln("sum   = " + int_to_string(sum))             // 99 + 30 = 129
    if nums.isEmpty() { system.stdout.writeln("empty") } else { system.stdout.writeln("not empty") }

    let items = empty List<Item>                                       // list of compounds
    items.push(Item { name: "pen", qty: 2 })
    items.push(Item { name: "book", qty: 5 })
    system.stdout.writeln("qty   = " + int_to_string(totalQty(items))) // 7
    return 0
}

module App {}

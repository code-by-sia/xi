// Regression: a stateful service that accumulates posted payloads in a list,
// and a controller that returns them as JSON.
//
// Three things this pins down (all were broken):
//   1. a `List<T>` field in class `state` persists across calls on a singleton;
//   2. a `List<T>` field on a DTO serializes to a JSON array (`obj as Json`) —
//      it used to be silently dropped, yielding `{}`;
//   3. the list round-trips back (`json as T`).
//
// The matching runnable server is web_store_demo.xi. Note the service MUST be
// bound `as singleton` — a stateful service left transient gets a fresh instance
// per resolve, so its state never accumulates.
import "std/web.xi"
import "std/json.xi"

type  Item     = { name: String, qty: Integer }
event ItemList = { items: List<Item> }

interface Store {
    consumer add(it: Item)
    projector all() -> List<Item>
    projector size() -> Integer
}
class ItemStore implements Store {
    deps {}
    state { items: List<Item> = empty List<Item> }
    consumer add(it: Item)        { this.items.push(it) }
    projector all() -> List<Item> => this.items
    projector size() -> Integer   => this.items.len()
}
module App { bind Store -> ItemStore as singleton }

test "List<T> service state accumulates across calls (singleton)" {
    // the singleton is shared across tests, so check the delta, not the total
    let s = App.resolve(Store)
    let before = s.size()
    s.add(Item { name: "pen",  qty: 2 })
    s.add(Item { name: "book", qty: 5 })
    assertEq(s.size(), before + 2)
}

test "a DTO with a List<T> field serializes to a JSON array" {
    let xs = empty List<Item>
    xs.push(Item { name: "pen", qty: 2 })
    let wire = json.stringify(ItemList { items: xs } as Json)
    assertEq(wire, "{\"items\":[{\"name\":\"pen\",\"qty\":2}]}")
}

test "the list round-trips through JSON" {
    let wire = "{\"items\":[{\"name\":\"pen\",\"qty\":2},{\"name\":\"book\",\"qty\":5}]}"
    let back = (json.parse(wire)) as ItemList
    assertEq(back.items.len(), 2)
    assertEq(back.items.get(0).name, "pen")
    assertEq(back.items.get(1).qty, 5)
}

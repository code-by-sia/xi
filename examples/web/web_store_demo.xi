// A stateful web service: POST payloads accumulate in a service's state, GET
// returns them as JSON. Demonstrates the full pattern end to end.
//
//   xc examples/web/web_store_demo.xi && ./build/web_store_demo
//   curl -X POST -d '{"name":"pen","qty":2}'  localhost:8080/add
//   curl -X POST -d '{"name":"book","qty":5}' localhost:8080/add
//   curl localhost:8080/list
//     -> {"items":[{"name":"pen","qty":2},{"name":"book","qty":5}]}
//
// Two things that make it work:
//   - the service is bound `as singleton`, so its state is shared across every
//     request (a transient service would forget everything between calls);
//   - state and DTOs use `List<T>` — growable in memory (`.push`) AND serialized
//     as a JSON array, so `res.send`/`req.parse` round-trip it.
import "std/web.xi"

type  Item      = { name: String, qty: Integer }
event ItemList  = { items: List<Item> }
event CountResp = { count: Integer }

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

class StoreController implements WebRequestHandler {
    deps { store: Store }
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/add" {
        store.add(req.parse(Item))                       // deserialize the posted payload
        res.send(CountResp { count: store.size() })
    }
    action handle(req: HttpRequest, res: HttpResponse) where req.path == "/list" {
        res.send(ItemList { items: store.all() })        // serialize the stored list
    }
}

module App { bind Store -> ItemStore as singleton }      // stateful service: singleton

async entry main(args: String[]) -> Integer {
    web.serve(8080)
    return 0
}

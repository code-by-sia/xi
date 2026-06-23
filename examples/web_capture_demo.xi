// A WebRequestHandler that parses path + body + headers separately, and uses
// `capture` to name a value computed inside a guard so it's reusable in the body.
//
//   xc examples/web_capture_demo.xi && ./build/web_capture_demo   # serves until Ctrl-C
//
// Try it:
//   curl -s -X POST localhost:8080/orders/42 \
//     -H "Authorization: Bearer k" \
//     -d '{"item":"book","qty":3,"price":1200}'
import "std/log.xi"
import "std/web.xi"

type OrderId = { id: Integer }                 // from the path  (:id)
type Order   = { item: String, qty: Integer, price: Integer }   // from the body
type Auth    = { authorization: String }       // from the headers

event Receipt { id: Integer, item: String, total: Integer }

mapper lineTotal(o: Order) -> Integer { return o.qty * o.price }

class OrderApi implements WebRequestHandler {
    deps { logger: Logger }

    // POST /orders/:id  { item, qty, price }   Authorization: ...
    action handle(req: HttpRequest, res: HttpResponse) where web.route(req, "POST", "/orders/:id") {
        let ref  = web.params(req)  as OrderId     // path   -> typed
        let order = web.body(req)   as Order       // body   -> typed
        let auth = web.headers(req) as Auth        // header -> typed

        // capture the computed total once (inside the guard) and reuse it below
        if lineTotal(order) capture total: Integer > 0 {
            logger.info("order " + ref.id + " by " + auth.authorization + ": " + order.item + " = " + total)
            res.send(Receipt { id: ref.id, item: order.item, total: total })
        } else {
            res.sendStatus(400, "empty order")
        }
    }

    action handle(req: HttpRequest, res: HttpResponse) {
        res.sendStatus(404, "Not Found")
    }
}

module App { bind WebRequestHandler -> OrderApi }

async entry main(args: String[]) -> Integer {
    web.serve(8080)
    return 0
}

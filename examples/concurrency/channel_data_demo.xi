// Channels carry any data, not just strings: a String passes through as-is, a
// structured value (an `event`/`type`) is JSON-serialized on send and rebuilt
// with `recv(T)`, and numbers/bools stringify automatically.
//
//   xc examples/channel_data_demo.xi && ./build/channel_data_demo
import "std/log.xi"
import "std/thread.xi"
import "std/convert.xi"

type Order = { id: Integer, item: String, qty: Integer }

async entry (logger: Logger) main(args: String[]) -> Integer {
    let jobs    = thread.channel()
    let results = thread.channel()

    let worker = parallel (jobs, results) {
        while not thread.stopped() {
            let o = jobs.recv(Order)               // typed receive
            if o.id == 0 { return 0 }              // sentinel = stop
            results.send(Order { id: o.id, item: o.item, qty: o.qty + 1 })
        }
        return 0
    }

    jobs.send(Order { id: 1, item: "book", qty: 2 })   // structured send
    jobs.send(Order { id: 2, item: "pen",  qty: 5 })

    let a = results.recv(Order)
    let b = results.recv(Order)
    logger.print(a.item + " x" + int_to_string(a.qty))   // book x3
    logger.print(b.item + " x" + int_to_string(b.qty))   // pen x6

    jobs.send(Order { id: 0, item: "", qty: 0 })       // stop the worker
    worker.wait()
    logger.print("done")
    return 0
}

module App {}

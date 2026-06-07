// Atoms — an active-state store: an immutable `state` value changed only through
// `transition`s (reducers). Dispatch swaps the held value; `.current` reads it.
import "std/log.xi"
state Cart = { items: Integer, total: Number }

atom cart {
    initial Cart { items: 0, total: 0.0 }
    transition addItem(s: Cart, price: Number) -> Cart {
        return Cart { items: s.items + 1, total: s.total + price }
    }
    transition clear(s: Cart) -> Cart { return empty Cart }
}

async entry (logger: Logger) main(args: String[]) -> Integer {
    cart.addItem(9.99)
    cart.addItem(5.00)
    cart.addItem(0.50)
    logger.print("items = " + cart.current.items)
    logger.print("total = " + cart.current.total)

    cart.clear()
    logger.print("after clear -> items = " + cart.current.items)

    // Time-travel: undo reverts to the previous state.
    cart.undo()
    logger.print("after undo  -> items = " + cart.current.items)   // back to 3
    return 0
}

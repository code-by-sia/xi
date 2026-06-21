// Stack / Queue / SortedQueue / Vec — the linear container types.
//
//   xc examples/containers_demo.xi && ./build/containers_demo
import "std/log.xi"
import "std/convert.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    // Stack<T> — LIFO. push / pop / peek (pop & peek abort if empty).
    let st = empty Stack<Integer>
    st.push(1)  st.push(2)  st.push(3)
    logger.info("stack peek=" + st.peek() + " len=" + st.len())
    logger.info("pop " + st.pop() + ", " + st.pop() + " -> len " + st.len())

    // Queue<T> — FIFO. enqueue / dequeue / peek.
    let q = queueOf("a", "b", "c")
    logger.info("queue front=" + q.peek())
    logger.info("dequeue " + q.dequeue() + ", " + q.dequeue() + " -> len " + q.len())

    // SortedQueue<T> — priority queue (min-heap); pop returns the smallest.
    let pq = sortedQueueOf(5, 1, 9, 3, 7)
    let drained = "" + pq.pop()
    while not pq.isEmpty() { drained = drained + " " + pq.pop() }
    logger.info("sorted drain = " + drained)        // 1 3 5 7 9

    // Vec<T> — dynamic array; the full List API plus insert / swap.
    let v = vecOf(1, 2, 4)
    v.insert(2, 3)                                   // 1 2 3 4
    v.swap(0, 3)                                     // 4 2 3 1
    logger.info("vec = " + v.joinToString(" ") { int_to_string(it) })
    logger.info("vec sum = " + v.sum() + ", max = " + v.max())
    return 0
}

module App {}

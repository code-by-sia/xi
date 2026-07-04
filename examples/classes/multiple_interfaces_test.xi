// Feature: a class can implement multiple interfaces (`implements A, B`). Bound
// to each — even as a singleton — one shared instance satisfies all of them.
interface Reader { mapper read() -> String }
interface Writer { consumer write(s: String) }

class Buffer implements Reader, Writer {
    deps {}
    state { buf: String = "" }
    mapper read() -> String => this.buf
    consumer write(s: String) { this.buf = this.buf + s }
}

module App {
    bind Reader -> Buffer as singleton
    bind Writer -> Buffer as singleton
}

test "one class satisfies multiple interfaces via a shared singleton" {
    let w = App.resolve(Writer)
    let r = App.resolve(Reader)
    w.write("hello ")
    w.write("world")
    assertEq(r.read(), "hello world")   // same instance behind both interfaces
}

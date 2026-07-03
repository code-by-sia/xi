// A tiny compute program that runs the same whether built native or to the web.
//
//   Native:  xc examples/wasm_demo.xi && ./build/wasm_demo
//   Web:     xc --target wasm examples/wasm_demo.xi
//            python3 -m http.server -d build   # then open wasm_demo.html
//
// The web build needs Emscripten (`brew install emscripten`). Output goes to
// build/wasm_demo.{html,js,wasm}; open the .html and watch the page console.
import "std/log.xi"
import "std/convert.xi"

mapper fib(n: Integer) -> Integer {
    if n < 2 { return n }
    return fib(n - 1) + fib(n - 2)
}

entry (logger: Logger) main(args: String[]) {
    logger.info("hello from Xi → WebAssembly")
    let i = 0
    while i <= 10 {
        logger.info("fib(" + int_to_string(i) + ") = " + int_to_string(fib(i)))
        i = i + 1
    }
}

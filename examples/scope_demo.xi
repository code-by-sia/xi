// `scope { }` — reclaim a block's heap allocations when it ends.
//
// Ξ reclaims memory automatically where it matters: a spawned thread frees its
// allocations on exit, and `web.serve` frees each request. `scope { }` gives you
// the same per-region reclamation by hand — wrap a long-running loop body and
// every string/list/object it builds is freed at the end of each iteration,
// instead of accumulating.
//
//   xc examples/scope_demo.xi && ./build/scope_demo
//
// Rule (same as threads): a value built inside a scope must not escape it — copy
// out anything you need to keep. Don't `return` out of a scope block.
import "std/log.xi"
import "std/convert.xi"

async entry (logger: Logger) main(args: String[]) -> Integer {
    let i = 0
    while i < 5 {
        scope {
            // All of this — concatenations, conversions — is freed when the
            // scope ends, so a million iterations stay flat instead of leaking.
            let label = "row-" + int_to_string(i)
            let line  = label + " = " + int_to_string(i * i)
            logger.info(line)
        }
        i = i + 1
    }
    logger.info("done — each iteration's strings were reclaimed")
    return 0
}

module ScopeDemo {}

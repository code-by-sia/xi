// =============================================================
// xi — the X REPL and run tool, written in X
//
// Manifest for the `xi` binary. The REPL is standalone: it shells out to the
// `xc` compiler to build sessions, so it imports only its own parts. As with
// xc.xi, each interface / class lives in its own file.
//
//   repl/runner.xi    the session loop, file runner and test runner (helpers)
//   repl/repl.xi      the Repl interface
//   repl/xi_repl.xi   the XiRepl implementation
// =============================================================

import "repl/runner.xi"
import "repl/repl.xi"
import "repl/xi_repl.xi"

// ── composition root (in the manifest, not a part file — see xc.xi) ──
module App {
    bind Repl -> XiRepl as singleton
}

async entry main(args: String[]) -> Integer {
    let xi = App.resolve(Repl)
    return xi.run(args)
}

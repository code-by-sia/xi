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
//   repl/app.xi       composition root (module + entry)
// =============================================================

import "repl/runner.xi"
import "repl/repl.xi"
import "repl/xi_repl.xi"
import "repl/app.xi"

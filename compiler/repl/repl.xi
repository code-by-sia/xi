// Repl — the `xi` tool's front-end contract: parse the CLI and dispatch to the
// session loop / file runner / test runner. Implemented by XiRepl (xi_repl.xi);
// the helpers it calls live in runner.xi.
interface Repl {
    producer run(args: String[]) -> Integer
}

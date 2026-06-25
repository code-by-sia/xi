// =============================================================
// xitest — the X test runner, written in X (the `Test` module)
//
//   xitest <file_test.xi> [--filter <substr>]   run one test file
//   xitest --all                                run every *_test.xi under cwd
//
// Reads XC (compiler path) and XC_RUNTIME from the environment, like xi.
// =============================================================

import "testing/tester.xi"
import "testing/test_runner.xi"

module Test {
    bind Tester -> XiTester as singleton
}

async entry main(args: String[]) -> Integer {
    let tester = Test.resolve(Tester)
    if args.len < 2 {
        system.stdout.writeln("usage: xitest <file_test.xi> [--filter <substr>]   (or: xitest --all)")
        return 1
    }
    let sub = args.data[1]
    if sub == "--all" { return tester.testAll() }
    let filter = ""
    if args.len >= 4 and args.data[2] == "--filter" { filter = args.data[3] }
    return tester.test(sub, filter)
}

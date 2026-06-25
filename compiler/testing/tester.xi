// Tester — the test-runner contract for the `xt` binary.
// Implemented by XiTester (testing/test_runner.xi).
interface Tester {
    producer test(path: String, filter: String) -> Integer
    producer testAll() -> Integer
}

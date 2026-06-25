// XiTester — the default Tester. Compiles a *_test.xi in test mode (XC_TEST=1)
// via xc, runs the produced binary, and forwards its output + exit code. This is
// the same logic the `xi test` subcommand uses, here as a standalone tool.
extern "C" {
    mapper   string_len(s: String) -> Integer
    mapper   string_char_at(s: String, i: Integer) -> Integer
    mapper   string_slice(s: String, from: Integer, to: Integer) -> String
    mapper   run_command(cmd: String) -> Integer
    producer file_read_all(path: String) -> String
    producer file_write(path: String, content: String) -> Bool
    mapper   get_env(name: String, dflt: String) -> String
}

// path "a/b/c.xi" -> "c"  (drop dir + a trailing ".x"/".xi")
mapper stripExt(path: String) -> String {
    let n = string_len(path)
    if n > 3 {
        if string_char_at(path, n - 3) == 46 and string_char_at(path, n - 2) == 120 and string_char_at(path, n - 1) == 105 {
            return string_slice(path, 0, n - 3)
        }
    }
    if n > 2 {
        if string_char_at(path, n - 2) == 46 and string_char_at(path, n - 1) == 120 {
            return string_slice(path, 0, n - 2)
        }
    }
    return path + ".bin"
}

mapper baseName(path: String) -> String {
    let n = string_len(path)
    let lastSp = 0 - 1
    let i = 0
    while i < n {
        if string_char_at(path, i) == 47 { lastSp = i }
        i = i + 1
    }
    return stripExt(string_slice(path, lastSp + 1, n))
}

// Pull the built binary's path out of xc's "built executable <path>" line.
mapper builtPath(log: String) -> String {
    let marker = "built executable "
    let ml = string_len(marker)
    let n = string_len(log)
    let i = 0
    while i + ml <= n {
        if string_slice(log, i, i + ml) == marker {
            let j = i + ml
            let k = j
            while k < n and string_char_at(log, k) != 10 { k = k + 1 }
            return string_slice(log, j, k)
        }
        i = i + 1
    }
    return ""
}

// Compile one *_test.xi in test mode and run it; nonzero exit if any test fails.
producer runTests(xc: String, rt: String, path: String, filter: String) -> Integer {
    let cmd = "XC_TEST=1 XC_OUT=/tmp XC_RUNTIME='" + rt + "' '" + xc + "' '" + path + "' >/tmp/xtest.log 2>&1"
    let rc = run_command(cmd)
    let log = file_read_all("/tmp/xtest.log")
    if rc != 0 {
        system.stdout.writeln("xitest: compilation failed:")
        system.stdout.writeln(log)
        return 1
    }
    let bin = builtPath(log)
    if string_len(bin) == 0 { bin = "/tmp/" + baseName(path) }
    let pre = ""
    if string_len(filter) > 0 { pre = "XC_TEST_FILTER='" + filter + "' " }
    return run_command(pre + "'" + bin + "'")
}

// Discover every *_test.xi under the cwd, run each, report a pass/fail summary.
producer runTestsAll(xc: String, rt: String) -> Integer {
    let sh = "set -u\n"
    sh = sh + "XC=\"$1\"; RT=\"$2\"; files=$(find . -name '*_test.xi' -not -path '*/build/*' -not -path '*/.git/*' | sort)\n"
    sh = sh + "if [ -z \"$files\" ]; then echo \"xitest: no *_test.xi files found\"; exit 0; fi\n"
    sh = sh + "fails=0; n=0\n"
    sh = sh + "for f in $files; do\n"
    sh = sh + "  n=$((n+1)); echo \"== $f ==\"\n"
    sh = sh + "  if ! XC_TEST=1 XC_OUT=/tmp XC_RUNTIME=\"$RT\" \"$XC\" \"$f\" >/tmp/xta.log 2>&1; then echo \"  compile failed:\"; cat /tmp/xta.log; fails=$((fails+1)); continue; fi\n"
    sh = sh + "  bin=$(grep 'built executable ' /tmp/xta.log | head -1 | sed 's/.*built executable //')\n"
    sh = sh + "  [ -z \"$bin\" ] && bin=\"/tmp/$(basename \"${f%.xi}\")\"\n"
    sh = sh + "  \"$bin\" || fails=$((fails+1))\n"
    sh = sh + "done\n"
    sh = sh + "echo; echo \"$n test file(s), $fails failed\"\n"
    sh = sh + "[ \"$fails\" -eq 0 ]\n"
    file_write("/tmp/xitest-all.sh", sh)
    return run_command("sh /tmp/xitest-all.sh '" + xc + "' '" + rt + "'")
}

class XiTester implements Tester {
    deps {}
    producer test(path: String, filter: String) -> Integer {
        let xc = get_env("XC", "compiler/xc")
        let rt = get_env("XC_RUNTIME", "runtime")
        return runTests(xc, rt, path, filter)
    }
    producer testAll() -> Integer {
        let xc = get_env("XC", "compiler/xc")
        let rt = get_env("XC_RUNTIME", "runtime")
        return runTestsAll(xc, rt)
    }
}

// =============================================================
// x — the X REPL and run tool (written in X)
//
//   x                 start the interactive REPL
//   x file.x          compile file.x and run it
//
// The REPL is a compile-and-run loop: declarations accumulate across
// the session; each statement is appended and the whole session is
// recompiled and re-run, showing only the new output.  Use `print(...)`
// to display values.  Commands: :quit  :reset  :help  :dump
// =============================================================

extern "C" {
    mapper  string_len(s: String) -> Integer
    mapper  string_char_at(s: String, i: Integer) -> Integer
    mapper  string_slice(s: String, from: Integer, to: Integer) -> String
    producer read_line() -> String
    predicate stdin_eof() -> Bool
    consumer flush_out()
    mapper  run_command(cmd: String) -> Integer
    producer file_read_all(path: String) -> String
    producer file_write(path: String, content: String) -> Bool
    mapper  get_env(name: String, dflt: String) -> String
}

// ── small helpers ────────────────────────────────────────────────

mapper firstWord(s: String) -> String {
    let n = string_len(s)
    let i = 0
    // skip leading spaces
    while i < n and string_char_at(s, i) == 32 { i = i + 1 }
    let start = i
    while i < n and string_char_at(s, i) != 32 { i = i + 1 }
    return string_slice(s, start, i)
}

mapper trimLeft(s: String) -> String {
    let n = string_len(s)
    let i = 0
    while i < n and string_char_at(s, i) == 32 { i = i + 1 }
    return string_slice(s, i, n)
}

predicate isBlank(s: String) {
    let n = string_len(s)
    let i = 0
    while i < n {
        if string_char_at(s, i) != 32 { return false }
        i = i + 1
    }
    return true
}

predicate isDeclLine(s: String) {
    let w = firstWord(s)
    if w == "type"       { return true }
    if w == "interface"  { return true }
    if w == "class"      { return true }
    if w == "mapper"     { return true }
    if w == "projector"  { return true }
    if w == "predicate"  { return true }
    if w == "consumer"   { return true }
    if w == "producer"   { return true }
    if w == "reducer"    { return true }
    if w == "creator"    { return true }
    if w == "module"     { return true }
    if w == "extern"     { return true }
    if w == "import"     { return true }
    if w == "namespace"  { return true }
    return false
}

mapper stripExt(path: String) -> String {
    let n = string_len(path)
    if n > 2 {
        if string_char_at(path, n - 2) == 46 and string_char_at(path, n - 1) == 120 {
            return string_slice(path, 0, n - 2)
        }
    }
    return path + ".bin"
}

// Build the full program text for the current session.
mapper buildProgram(decls: String, stmts: String) -> String {
    return decls
         + "\nconsumer print(s: String) { system.stdout.writeln(s) }\n"
         + "async entry main(args: String[]) -> Integer {\n"
         + stmts
         + "    return 0\n}\n"
}

// Base name of a path: drop the directory and a trailing ".x".
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

// Compile the session program; return 0 on success. Writes /tmp/xrepl.x.
mapper compileSession(xc: String, rt: String, prog: String) -> Integer {
    file_write("/tmp/xrepl.x", prog)
    let cmd = "XC_OUT=/tmp XC_RUNTIME='" + rt + "' '" + xc + "' /tmp/xrepl.x >/tmp/xrepl.log 2>&1"
    return run_command(cmd)
}

// ── modes ────────────────────────────────────────────────────────

consumer runFile(xc: String, rt: String, path: String) {
    let cmd = "XC_OUT=/tmp XC_RUNTIME='" + rt + "' '" + xc + "' '" + path + "' >/tmp/xrun.log 2>&1"
    let rc = run_command(cmd)
    if rc != 0 {
        system.stdout.writeln("x: compilation failed:")
        system.stdout.writeln(file_read_all("/tmp/xrun.log"))
    } else {
        run_command("'/tmp/" + baseName(path) + "'")
    }
}

consumer repl(xc: String, rt: String) {
    system.stdout.writeln("X REPL — :help for commands, :quit to exit")
    let decls = ""
    let stmts = ""
    let prevLen = 0
    let running = true
    while running {
        system.stdout.write("x> ")
        flush_out()
        let line = read_line()
        if stdin_eof() {
            running = false
        } else {
            if isBlank(line) {
                // ignore
            } else {
                let cmd = firstWord(line)
                if cmd == ":quit" {
                    running = false
                } else {
                if cmd == ":help" {
                    system.stdout.writeln("  <decl>        define a type/function (persists)")
                    system.stdout.writeln("  <statement>   run a statement; use print(x) to show values")
                    system.stdout.writeln("  :reset        clear the session")
                    system.stdout.writeln("  :dump         show accumulated source")
                    system.stdout.writeln("  :quit         exit")
                } else {
                if cmd == ":reset" {
                    decls = ""
                    stmts = ""
                    prevLen = 0
                    system.stdout.writeln("(session cleared)")
                } else {
                if cmd == ":dump" {
                    system.stdout.writeln(buildProgram(decls, stmts))
                } else {
                    if isDeclLine(line) {
                        let trial = decls + line + "\n"
                        let rc = compileSession(xc, rt, buildProgram(trial, stmts))
                        if rc == 0 {
                            decls = trial
                            system.stdout.writeln("(defined)")
                        } else {
                            system.stdout.writeln("error:")
                            system.stdout.writeln(file_read_all("/tmp/xrepl.log"))
                        }
                    } else {
                        let trial = stmts + "    " + line + "\n"
                        let rc = compileSession(xc, rt, buildProgram(decls, trial))
                        if rc != 0 {
                            system.stdout.writeln("error:")
                            system.stdout.writeln(file_read_all("/tmp/xrepl.log"))
                        } else {
                            run_command("/tmp/xrepl >/tmp/xrepl.out 2>&1")
                            let out = file_read_all("/tmp/xrepl.out")
                            let total = string_len(out)
                            if total > prevLen {
                                system.stdout.write(string_slice(out, prevLen, total))
                                flush_out()
                            }
                            prevLen = total
                            stmts = trial
                        }
                    }
                }
                }
                }
                }
            }
        }
    }
    system.stdout.writeln("bye")
}

async entry main(args: String[]) -> Integer {
    let xc = get_env("XC", "compiler/xc")
    let rt = get_env("XC_RUNTIME", "runtime")
    if args.len >= 2 {
        runFile(xc, rt, args.data[1])
        return 0
    }
    repl(xc, rt)
    return 0
}

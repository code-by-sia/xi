class XiRepl implements Repl {
    deps {}

    producer run(args: String[]) -> Integer {
        let xc = get_env("XC", "compiler/xc")
        let rt = get_env("XC_RUNTIME", "runtime")
        if args.len >= 2 {
            let sub = args.data[1]
            if sub == "version" or sub == "--version" or sub == "-v" {
                system.stdout.writeln("xi " + xiVersion() + " \"" + xiCodename() + "\"")
                return 0
            }
            if sub == "update" {
                doUpdate(args.data[0])
                return 0
            }
            if sub == "skill" {
                doSkill()
                return 0
            }
            if sub == "install" {
                // Fetch each module's `dependencies` archives into ./modules.
                let target = ""
                if args.len >= 3 { target = " " + args.data[2] }
                return run_command(xc + " --install" + target)
            }
            if sub == "pack" {
                // Build a shareable library archive (dist/<id>-<version>.tar.gz).
                let target = ""
                if args.len >= 3 { target = " " + args.data[2] }
                return run_command(xc + " --pack" + target)
            }
            if sub == "test" {
                if args.len < 3 {
                    system.stdout.writeln("usage: xi test <file.xi> [--filter <substr>]   (or: xi test --all)")
                    return 1
                }
                if args.data[2] == "--all" { return runTestsAll(xc, rt) }
                let filter = ""
                if args.len >= 5 and args.data[3] == "--filter" { filter = args.data[4] }
                return runTests(xc, rt, args.data[2], filter)
            }
            runFile(xc, rt, sub)
            return 0
        }
        repl(xc, rt)
        return 0
    }
}


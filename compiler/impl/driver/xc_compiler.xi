class XcCompiler implements Compiler {
    deps { lexer: Lexer, parser: Parser, codegen: Codegen, host: Host, diag: Diagnostics, text: Text, arrays: TokenArrays, loader: ModuleLoader }

    // Compile one source file (resolving imports + module source sets) to a
    // native binary. Returns 0 on success.
    producer build(srcPath: String) -> Integer {
        system.stdout.writeln("xc: loading + lexing " + srcPath + " ...")
        let lr = loader.load(srcPath, emptyStrings())
        let collapsed = collapseQualified(lr.tokens, lr.qnames, lr.qrepl)
        let tokens = appendToken(collapsed, Token { kind: 0, text: "", line: 0 })

        system.stdout.writeln("xc: parsing ...")
        diag.setFile(srcPath)           // parse errors report the main source
        let prog = parser.parse(tokens)

        // Module source set: if a module declares includes/excludes, glob-gather
        // the matching .xi files under the source's directory and re-parse.
        let inc = moduleGlobs(prog, 0)
        let exc = moduleGlobs(prog, 1)
        // Installed dependencies under ./modules join the gather automatically,
        // so `xi install`ed libraries compile in without an explicit include.
        let modBase = dirOf(srcPath)
        if text.len(modBase) == 0 { modBase = "." }
        if dirHasXi(modBase + "/modules") { inc = arrays.pushString(inc, "modules/**") }
        if arrays.stringLen(inc) > 0 or arrays.stringLen(exc) > 0 {
            if arrays.stringLen(inc) == 0 { inc = ["./**"] }   // default when only excludes given
            system.stdout.writeln("xc: gathering module sources ...")
            let lr2 = loader.gather(srcPath, inc, exc)
            let collapsed2 = collapseQualified(lr2.tokens, lr2.qnames, lr2.qrepl)
            let tokens2 = appendToken(collapsed2, Token { kind: 0, text: "", line: 0 })
            diag.setFile(srcPath)
            prog = parser.parse(tokens2)
        }

        prog = monomorphize(prog)        // expand generic interface instantiations
        checkMachines(prog)              // static machine-graph validation
        checkPurity(prog)                // pure-kind functions stay side-effect-free

        system.stdout.writeln("xc: generating C ...")
        let cSource = codegen.generate(prog, srcPath)

        let outDir = host.env("XC_OUT", "build")
        host.exec("mkdir -p '" + outDir + "'")
        // Binary name: the module's `id` if it declares one, else the basename.
        let base = baseName(srcPath)
        let mid = moduleId(prog)
        if text.len(mid) > 0 { base = mid }
        let outPath = outDir + "/" + base + ".gen.c"
        host.writeFile(outPath, cSource)
        let binPath = outDir + "/" + base

        system.stdout.writeln("xc: compiling C to native binary ...")
        let rc = host.compileC(outPath, binPath)
        if rc == 0 {
            // Drop the generated C once it's built (XC_KEEP_C=1 retains it).
            if text.len(host.env("XC_KEEP_C", "")) == 0 {
                host.exec("rm -f '" + outPath + "'")
            }
            if host.env("XC_TARGET", "") == "wasm" {
                system.stdout.writeln("xc: built WebAssembly " + binPath + ".{html,js,wasm}")
                system.stdout.writeln("xc: serve it, e.g.  python3 -m http.server -d " + outDir + "  then open " + base + ".html")
            } else {
                system.stdout.writeln("xc: built executable " + binPath)
            }
            return 0
        }
        system.stderr.writeln("xc: C compilation failed")
        return 1
    }

    // A file is a buildable module if it has both an `entry` and a `module`.
    predicate isBuildable(path: String) -> Bool {
        let toks = lexer.lex(host.readFile(path))
        let n = arrays.tokenLen(toks)
        let hasEntry = false
        let hasModule = false
        let i = 0
        while i < n {
            let k = arrays.tokenAt(toks, i).kind
            if k == 219 { hasEntry = true }
            if k == 210 { hasModule = true }
            i = i + 1
        }
        return hasEntry and hasModule
    }

    // `xc --all` — discover every buildable module under the current directory
    // and build each (into its own binary, named by its module `id`).
    producer buildAll() -> Integer {
        host.exec("find . -name '*.xi' -not -path '*/build/*' -not -path '*/.git/*' | sort > /tmp/xi-modules.txt 2>/dev/null")
        let files = splitLines(host.readFile("/tmp/xi-modules.txt"))
        let built = 0
        let fails = 0
        let i = 0
        let n = arrays.stringLen(files)
        while i < n {
            let f = arrays.stringAt(files, i)
            // Skip the Xi toolchain itself: a manifest sitting next to
            // xc_helpers.c is the compiler/tooling, which links private FFI via
            // XC_HELPERS and is built by bootstrap.sh, not `xc --all`.
            if isBuildable(f) and not host.fileExists(dirOf(f) + "/xc_helpers.c") {
                system.stdout.writeln("=== xc --all: building " + f + " ===")
                built = built + 1
                if build(f) != 0 { fails = fails + 1 }
            }
            i = i + 1
        }
        system.stdout.writeln("xc --all: built " + text.fromInt(built) + " module(s), " + text.fromInt(fails) + " failed")
        if fails > 0 { return 1 }
        return 0
    }

    // CLI dispatch — the body that `entry main` used to run directly.
    producer run(args: String[]) -> Integer {
        if args.len < 2 {
            system.stdout.writeln("Usage: xc <source.xi>   (or: xc --all, xc --target wasm <source.xi>, xc version)")
            return 1
        }
        let tgt = argTarget(args)
        if text.len(tgt) > 0 {
            if tgt != "wasm" and tgt != "native" {
                system.stderr.writeln("xc: unknown --target '" + tgt + "' (expected: native, wasm)")
                return 1
            }
            host.setEnv("XC_TARGET", tgt)
        }
        let srcPath = cliSource(args)
        if srcPath == "version" or srcPath == "--version" or srcPath == "-v" {
            system.stdout.writeln("xc " + xcVersion())
            return 0
        }
        if srcPath == "--all" { return buildAll() }
        if srcPath == "--install" {
            if args.len >= 3 { return installDeps(args.data[2]) }
            return installAll()
        }
        if srcPath == "--pack" {
            if args.len >= 3 { return packLibrary(args.data[2]) }
            return packLibrary("")
        }
        return build(srcPath)
    }
}


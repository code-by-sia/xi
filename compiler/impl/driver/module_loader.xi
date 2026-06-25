// XiModuleLoader — the default ModuleLoader: resolves `import`s into one
// token stream (with namespace prefixing) and gathers a module's source set.
// It reaches the lexer + file IO through injected services, so the import
// resolver is no longer a set of loose functions.
class XiModuleLoader implements ModuleLoader {
    deps { lexer: Lexer, host: Host }

    producer load(rawPath: String, visited: String[]) -> LoadResult {
        let path = canonPath(rawPath)   // dedup key: same file via any spelling
        if strArrContains(visited, path) {
            return LoadResult { tokens: [], visited: visited, qnames: [], qrepl: [] }
        }
        let vis = appendString(visited, path)
        let src = host.readFile(path)
        diag_set_file(path)              // lexer errors report this file
        let toks = lexer.lex(src)
        let dir = dirOf(path)

        let nsName = scanNamespaceName(toks)
        let prefix = nsPrefixOf(nsName)
        let hasNs = string_len(nsName) > 0
        let exports: String[] = []
        let qnames: String[] = []
        let qrepl: String[] = []
        if hasNs {
            exports = collectExports(toks)
            let ei = 0
            let en = stringArrLen(exports)
            while ei < en {
                let nm = stringArrGet(exports, ei)
                qnames = appendString(qnames, nsName + "." + nm)
                qrepl  = appendString(qrepl,  prefix + "__" + nm)
                ei = ei + 1
            }
        }

        let out: Token[] = []
        let prevKind = 0
        let i = 0
        let n = tokenArrLen(toks)
        while i < n {
            let t = tokenArrGet(toks, i)
            if t.kind == 244 and tokenArrGet(toks, i + 1).kind == 4 {
                let rel = tokenArrGet(toks, i + 1).text
                let sub = load(resolveImport(dir, rel), vis)
                vis = sub.visited
                out = concatTokens(out, sub.tokens)
                qnames = concatStrings(qnames, sub.qnames)
                qrepl  = concatStrings(qrepl,  sub.qrepl)
                i = i + 2
                prevKind = 0
            } else {
                if t.kind == 255 {
                    i = i + 1
                    let cont = true
                    while cont and i < n {
                        let nt = tokenArrGet(toks, i).kind
                        if nt == 1 or nt == 107 { i = i + 1 } else { cont = false }
                    }
                } else {
                    if t.kind == 0 {
                        i = i + 1
                    } else {
                        // Rename top-level names, but NOT identifiers after '.'
                        // (those are field/method accesses, never namespaced).
                        if hasNs and prevKind != 107 and prevKind != 129 {
                            out = appendToken(out, renameTok(t, prefix, exports))
                        } else {
                            out = appendToken(out, t)
                        }
                        prevKind = t.kind
                        i = i + 1
                    }
                }
            }
        }
        return LoadResult { tokens: out, visited: vis, qnames: qnames, qrepl: qrepl }
    }

    producer gather(srcPath: String, inc: String[], exc: String[]) -> LoadResult {
        let base = dirOf(srcPath)
        if string_len(base) == 0 { base = "." }   // bare filename -> current directory
        host.exec("find '" + base + "' -name '*.xi' > /tmp/xi-srcs.txt 2>/dev/null")
        let files = splitLines(host.readFile("/tmp/xi-srcs.txt"))
        let acc = load(srcPath, emptyStrings())
        let toks = acc.tokens
        let visited = acc.visited
        let qn = acc.qnames
        let qr = acc.qrepl
        let i = 0
        let n = stringArrLen(files)
        while i < n {
            let f = stringArrGet(files, i)
            let cf = canonPath(f)
            let rel = relPath(base, f)
            if cf != canonPath(srcPath) and not strArrContains(visited, cf) and not isDepNonLib(f, rel) and matchesAny(inc, rel) and not matchesAny(exc, rel) {
                let sub = load(f, visited)
                visited = sub.visited
                toks = concatTokens(toks, sub.tokens)
                qn = concatStrings(qn, sub.qnames)
                qr = concatStrings(qr, sub.qrepl)
            }
            i = i + 1
        }
        return LoadResult { tokens: toks, visited: visited, qnames: qn, qrepl: qr }
    }

    // Does the file declare its own `entry` or `module`? (app/demo, not lib.)
    predicate declaresEntryOrModule(path: String) {
        let toks = lexer.lex(host.readFile(path))
        let n = tokenArrLen(toks)
        let i = 0
        while i < n {
            let k = tokenArrGet(toks, i).kind
            if k == 219 { return true }   // entry
            if k == 210 { return true }   // module
            i = i + 1
        }
        return false
    }

    // A gathered ./modules file that is NOT library source (example/test/app).
    predicate isDepNonLib(path: String, rel: String) {
        if not startsWith2(rel, "modules/") { return false }
        if containsSub(rel, "/examples/") or containsSub(rel, "/example/") { return true }
        if containsSub(rel, "/tests/") or containsSub(rel, "/test/") { return true }
        if containsSub(rel, "/.claude/") or containsSub(rel, "/build/") { return true }
        if endsWith2(baseNameOf(rel), "_test.xi") { return true }
        if declaresEntryOrModule(path) { return true }
        return false
    }
}

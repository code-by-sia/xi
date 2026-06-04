// xc driver — multi-file import resolution + entry point
// ── Main entry ────────────────────────────────────────────────────

// ── Multi-file support: import resolution ────────────────────────
//
// `import "path.x"` (top level) splices another file's declarations into the
// compilation unit.  Imports are resolved recursively and de-duplicated by
// path, so a diamond of imports includes each file once.  `namespace a.b`
// prefixes a file's top-level symbol names with `a_b__` so independently
// authored files can reuse short names without colliding (see applyNamespace).

extern "C" {
    predicate xstd_file_exists(path: String) -> Bool
    mapper    get_env(name: String, dflt: String) -> String
    mapper    run_command(cmd: String) -> Integer
    consumer  diag_set_file(path: String)
    consumer  diag_error(line: Integer, msg: String)
}

// LoadResult carries the merged tokens, the visited-paths set (dedup), and a
// registry mapping qualified names "ns.Name" -> mangled "ns__Name" so that
// cross-file references can be collapsed after all files are merged.
type LoadResult = {
    tokens:  Token[],
    visited: String[],
    qnames:  String[],   // "ns.Name"
    qrepl:   String[]    // parallel: "ns__Name"
}

mapper concatTokens(a: Token[], b: Token[]) -> Token[] {
    let out = a
    let i = 0
    let n = tokenArrLen(b)
    while i < n {
        out = appendToken(out, tokenArrGet(b, i))
        i = i + 1
    }
    return out
}

mapper lastSlash(s: String) -> Integer {
    let n = string_len(s)
    let last = 0 - 1
    let i = 0
    while i < n {
        if string_char_at(s, i) == 47 { last = i }
        i = i + 1
    }
    return last
}

mapper dirOf(path: String) -> String {
    let ls = lastSlash(path)
    if ls < 0 { return "" }
    return string_slice(path, 0, ls)
}

mapper joinPath(dir: String, rel: String) -> String {
    if string_len(dir) == 0 { return rel }
    if string_len(rel) > 0 {
        if string_char_at(rel, 0) == 47 { return rel }
    }
    return dir + "/" + rel
}

// Resolve an import: first relative to the importing file, then relative to the
// standard-library/search root in $XC_STD (default ".").  This lets programs
// `import "std/math.x"` from anywhere the library is installed.
mapper resolveImport(dir: String, rel: String) -> String {
    let local = joinPath(dir, rel)
    if xstd_file_exists(local) { return local }
    let alt = joinPath(get_env("XC_STD", "."), rel)
    if xstd_file_exists(alt) { return alt }
    return local
}

predicate isDeclKw(k: Integer) {
    if k == 200 { return true }   // type
    if k == 201 { return true }   // interface
    if k == 202 { return true }   // class
    if k == 212 { return true }   // creator
    if k == 213 { return true }   // mapper
    if k == 214 { return true }   // projector
    if k == 215 { return true }   // predicate
    if k == 216 { return true }   // consumer
    if k == 217 { return true }   // producer
    if k == 218 { return true }   // reducer
    return false
}

// The dotted namespace name as written (e.g. "app.util"), or "" if none.
mapper scanNamespaceName(toks: Token[]) -> String {
    let i = 0
    let n = tokenArrLen(toks)
    while i < n {
        if tokenArrGet(toks, i).kind == 255 {   // namespace
            let name = ""
            let j = i + 1
            let cont = true
            while cont and j < n {
                let t = tokenArrGet(toks, j)
                if t.kind == 1 { name = name + t.text }
                else { if t.kind == 107 { name = name + "." } else { cont = false } }
                if cont { j = j + 1 }
            }
            return name
        }
        i = i + 1
    }
    return ""
}

// "app.util" -> "app_util"  (C-safe prefix)
mapper nsPrefixOf(nsName: String) -> String {
    let out = ""
    let i = 0
    let n = string_len(nsName)
    while i < n {
        let c = string_char_at(nsName, i)
        if c == 46 { out = out + "_" } else { out = out + string_slice(nsName, i, i + 1) }
        i = i + 1
    }
    return out
}

// Collect TOP-LEVEL declared names of a file (depth 0 only, so method names
// inside classes/interfaces are NOT namespaced — that would break dispatch).
mapper collectExports(toks: Token[]) -> String[] {
    let out: String[] = []
    let depth = 0
    let i = 0
    let n = tokenArrLen(toks)
    while i < n {
        let k = tokenArrGet(toks, i).kind
        if k == 102 {
            depth = depth + 1
        } else {
            if k == 103 {
                depth = depth - 1
            } else {
                if depth == 0 and isDeclKw(k) {
                    // The name follows the keyword, unless a function-level deps
                    // block `kind { ... } name(...)` comes first — skip over it.
                    let ni = i + 1
                    if tokenArrGet(toks, ni).kind == 102 {
                        let d2 = 1
                        ni = ni + 1
                        while d2 > 0 and ni < n {
                            let kk = tokenArrGet(toks, ni).kind
                            if kk == 102 { d2 = d2 + 1 }
                            if kk == 103 { d2 = d2 - 1 }
                            ni = ni + 1
                        }
                    }
                    let nameTok = tokenArrGet(toks, ni)
                    if nameTok.kind == 1 { out = appendString(out, nameTok.text) }
                }
            }
        }
        i = i + 1
    }
    return out
}

mapper renameTok(t: Token, prefix: String, exports: String[]) -> Token {
    if t.kind == 1 and strArrContains(exports, t.text) {
        return Token { kind: 1, text: prefix + "__" + t.text, line: t.line }
    }
    return t
}

// Read `path`, recursively splice imports, strip import/namespace lines, and
// apply namespace prefixing.  Returns merged tokens (no trailing EOF) plus the
// qualified-name registry for cross-file reference collapsing.
// Typed empty String[] (a bare `[]` is only valid in a typed context, not as
// a call argument, so we build it via a return-cast here).
creator emptyStrings() -> String[] {
    return []
}

creator loadModule(path: String, visited: String[]) -> LoadResult {
    if strArrContains(visited, path) {
        return LoadResult { tokens: [], visited: visited, qnames: [], qrepl: [] }
    }
    let vis = appendString(visited, path)
    let src = file_read_all(path)
    diag_set_file(path)              // lexer errors report this file
    let toks = tokenise(src)
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
            let sub = loadModule(resolveImport(dir, rel), vis)
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

mapper concatStrings(a: String[], b: String[]) -> String[] {
    let out = a
    let i = 0
    let n = stringArrLen(b)
    while i < n {
        out = appendString(out, stringArrGet(b, i))
        i = i + 1
    }
    return out
}

// Collapse cross-file qualified references: IDENT(ns) '.' IDENT(name) whose
// "ns.name" is in the registry becomes a single IDENT(ns__name).
mapper collapseQualified(toks: Token[], qnames: String[], qrepl: String[]) -> Token[] {
    let out: Token[] = []
    let i = 0
    let n = tokenArrLen(toks)
    while i < n {
        let t = tokenArrGet(toks, i)
        if t.kind == 1 and i + 2 < n {
            let dot = tokenArrGet(toks, i + 1)
            let nm = tokenArrGet(toks, i + 2)
            if dot.kind == 107 and nm.kind == 1 {
                let q = t.text + "." + nm.text
                let idx = strArrIndexOf(qnames, q)
                if idx >= 0 {
                    out = appendToken(out, Token { kind: 1, text: stringArrGet(qrepl, idx), line: t.line })
                    i = i + 3
                } else {
                    out = appendToken(out, t)
                    i = i + 1
                }
            } else {
                out = appendToken(out, t)
                i = i + 1
            }
        } else {
            out = appendToken(out, t)
            i = i + 1
        }
    }
    return out
}

mapper strArrIndexOf(arr: String[], s: String) -> Integer {
    let i = 0
    let n = stringArrLen(arr)
    while i < n {
        if stringArrGet(arr, i) == s { return i }
        i = i + 1
    }
    return 0 - 1
}

async entry main(args: String[]) -> Integer {
    if args.len < 2 {
        system.stdout.writeln("Usage: xc <source.x|.xi>")
        return 1
    }

    let srcPath = args.data[1]

    system.stdout.writeln("xc: loading + lexing " + srcPath + " ...")
    let lr = loadModule(srcPath, emptyStrings())
    let collapsed = collapseQualified(lr.tokens, lr.qnames, lr.qrepl)
    let tokens = appendToken(collapsed, Token { kind: 0, text: "", line: 0 })

    system.stdout.writeln("xc: parsing ...")
    diag_set_file(srcPath)           // parse errors report the main source
    let prog = parseProgram(tokens)

    system.stdout.writeln("xc: generating C ...")
    let cSource = genAll(prog)

    // Build artifacts go to the output directory ($XC_OUT, default "build"),
    // keeping source trees clean.
    let outDir = get_env("XC_OUT", "build")
    run_command("mkdir -p '" + outDir + "'")
    let base = baseName(srcPath)
    let outPath = outDir + "/" + base + ".gen.c"
    file_write(outPath, cSource)
    let binPath = outDir + "/" + base

    system.stdout.writeln("xc: compiling C to native binary ...")
    let rc = compile_c(outPath, binPath)
    if rc == 0 {
        system.stdout.writeln("xc: built executable " + binPath)
        return 0
    }
    system.stderr.writeln("xc: C compilation failed")
    return 1
}

// Base name of a path: drop the directory and a trailing ".x" or ".xi".
mapper baseName(path: String) -> String {
    let ls = lastSlash(path)
    let start = ls + 1
    let n = string_len(path)
    let nm = string_slice(path, start, n)
    let m = string_len(nm)
    // ".xi"  (46='.', 120='x', 105='i')
    if m > 3 {
        if string_char_at(nm, m - 3) == 46 and string_char_at(nm, m - 2) == 120 and string_char_at(nm, m - 1) == 105 {
            return string_slice(nm, 0, m - 3)
        }
    }
    // ".x"
    if m > 2 {
        if string_char_at(nm, m - 2) == 46 and string_char_at(nm, m - 1) == 120 {
            return string_slice(nm, 0, m - 2)
        }
    }
    return nm
}

# Editor support for Xi

- **`tree-sitter-x/`** — a Tree-sitter grammar for Xi (syntax tree + highlight
  queries). Used by Zed, Neovim, Helix, and any Tree-sitter-based editor.
- **`zed/`** — a Zed extension that wires the grammar + queries into Zed.
- **`vim/`** — a Vim / Neovim plugin (syntax, filetype detection, indentation).
  See `vim/README.md`.
- **`vscode/`** — a Visual Studio Code extension (TextMate highlighting,
  snippets, keyword/stdlib completion). See `vscode/README.md`.

The grammar parses every `.x` file in this repository — the examples, the
standard library, and the compiler's own sources — with no errors.

## Zed

Zed fetches the grammar from a git repo at a pinned commit. The grammar lives in
this same repo under `editors/tree-sitter-x` (the extension uses Zed's `path` to
point at the subdirectory), so no separate repository is needed.

1. **Push the repo and get the commit.**

   ```console
   $ git push -u origin main
   $ git rev-parse HEAD        # the commit SHA Zed will fetch
   ```

2. **Pin the commit.** In `editors/zed/extension.toml`, set `commit` to that SHA
   (the `repository` and `path` are already filled in):

   ```toml
   [grammars.x]
   repository = "https://github.com/code-by-sia/x"
   commit = "<sha from step 1>"
   path = "editors/tree-sitter-x"
   ```

   Update this commit (and re-install) whenever you change `grammar.js`.

3. **Install the extension.** In Zed open the command palette and run
   **`zed: install dev extension`**, then choose the `editors/zed/` directory.

Open any `.x` file and you'll get syntax highlighting, an outline (types,
interfaces, classes, functions), comment toggling, and bracket auto-close.

What the extension provides (`editors/zed/languages/x/`):

| File | Purpose |
|------|---------|
| `config.toml`     | file association (`.x`), comments, brackets, autoclose |
| `highlights.scm`  | syntax highlighting queries |
| `outline.scm`     | symbols for the outline panel |
| `indents.scm`     | auto-indentation |

## Regenerating the grammar

After editing `editors/tree-sitter-x/grammar.js`:

```console
$ cd editors/tree-sitter-x
$ npx tree-sitter-cli generate --no-bindings   # regenerate src/parser.c only
$ npx tree-sitter-cli parse ../../examples/showcase/main.x   # sanity-check
```

(`--no-bindings` keeps the repo free of generated Node/Python/Rust/Swift binding
scaffolding — only `src/` is needed.)

Then commit the updated `src/` and bump the `commit` in `extension.toml`.

## Other editors

The grammar's `queries/highlights.scm` works directly with Neovim
(`nvim-treesitter`) and Helix — register the grammar and copy the queries into
the editor's runtime, associating the `x` filetype with `source.x`.

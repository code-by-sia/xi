# Xi for Visual Studio Code

Syntax highlighting, snippets, and completion for the
[Xi programming language](https://github.com/code-by-sia/x).

## Features

- **Syntax highlighting** for `.x` files (TextMate grammar): comments, strings
  (incl. `"""triple"""`), numbers, the seven function kinds plus `decision`,
  declarations (`type`/`interface`/`class`/`module`/`namespace`), control flow,
  refined-type `where`, operators, primitive and user types.
- **Snippets** for common constructs — `mapper`, `predicate`, `consumer`,
  `producer`, `decision`, `interface`, `class` (with `deps`), `module`, refined
  `type`, `match`, `for`, `iflet`, `ok`/`err`, `entry`, `import`.
- **Completion** for keywords, function kinds, primitive types, and standard
  library members after a namespace dot (e.g. `text.`, `fs.`, `net.`, `http.`,
  `system.stdout.`).

## Install (from source)

This extension is not yet on the Marketplace. To use it locally:

```sh
# Option A — run the Extension Development Host
code editors/vscode      # then press F5

# Option B — install into your VS Code extensions folder
cp -R editors/vscode ~/.vscode/extensions/x-language-0.0.3
# then reload VS Code
```

To package a `.vsix` (requires `@vscode/vsce`):

```sh
cd editors/vscode && npx @vscode/vsce package
```

Highlighting uses a TextMate grammar (VS Code does not use the Tree-sitter
grammar in `editors/tree-sitter-x`). Completion is keyword/snippet/namespace
based; a full language server (diagnostics, go-to-definition) is future work.

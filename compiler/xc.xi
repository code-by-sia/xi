// =============================================================
// xc — the X language compiler, written in X (self-hosting)
//
// This file is the manifest: it imports the compiler's parts.
// The `import` mechanism (implemented in driver.x) splices each
// file's declarations into one compilation unit.
//
//   lexer.x    source text -> tokens
//   parser.x   tokens -> Program (spec structs)
//   codegen.x  Program -> C99
//   driver.x   import resolution + entry point (main)
// =============================================================

import "lexer.xi"
import "parser.xi"
import "codegen.xi"
import "driver.xi"

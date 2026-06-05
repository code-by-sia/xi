" Vim syntax file for the X programming language.
" Language: X
" Works in Vim and Neovim (legacy syntax).

if exists("b:current_syntax")
  finish
endif

" ── keywords ─────────────────────────────────────────────────────
syn keyword xKeyword type interface class implements extends deps bind as
syn keyword xKeyword module scope import export namespace extern
syn keyword xKeyword let return if else match for while loop break continue
syn keyword xKeyword unsafe spawn when otherwise where
syn keyword xStorage async own dup move
syn keyword xScope   singleton transient scoped
syn keyword xFunctionKind mapper projector predicate consumer producer reducer creator action entry
syn keyword xOperator and or not is in matches await
syn keyword xBoolean true false
syn keyword xConstant none
syn keyword xBuiltin self input value

" ── primitive types ──────────────────────────────────────────────
syn keyword xType Number Integer Bool String Char Timestamp Void Size cstring

" Uppercase-led identifiers read as type names.
syn match xTypeName "\<\u\w*\>"

" Lowercase identifier immediately before '(' reads as a function/call.
syn match xFunction "\<[a-z_]\w*\>\ze\s*("

" ── literals ─────────────────────────────────────────────────────
syn match xNumber "\<0x\x\+\>"
syn match xNumber "\<0b[01]\+\>"
syn match xNumber "\<\d\+\(\.\d\+\)\=\([eE][+-]\=\d\+\)\=\>"

syn match  xEscape "\\." contained
syn region xString start=+"""+ end=+"""+ keepend
syn region xString start=+"+ skip=+\\"+ end=+"+ contains=xEscape
syn match  xChar   "'\(\\.\|[^']\)'"

" ── comments ─────────────────────────────────────────────────────
syn match  xLineComment  "//.*$" contains=@Spell
syn region xBlockComment start="/\*" end="\*/" contains=@Spell

" ── highlight links ──────────────────────────────────────────────
hi def link xKeyword      Keyword
hi def link xStorage      StorageClass
hi def link xScope        StorageClass
hi def link xFunctionKind Keyword
hi def link xOperator     Operator
hi def link xBoolean      Boolean
hi def link xConstant     Constant
hi def link xBuiltin      Identifier
hi def link xType         Type
hi def link xTypeName     Type
hi def link xFunction     Function
hi def link xNumber       Number
hi def link xString       String
hi def link xEscape       SpecialChar
hi def link xChar         Character
hi def link xLineComment  Comment
hi def link xBlockComment Comment

let b:current_syntax = "x"

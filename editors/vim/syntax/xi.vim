" Vim syntax file for the Xi programming language.
" Language: Xi
" Works in Vim and Neovim (legacy syntax).

if exists("b:current_syntax")
  finish
endif

" ── keywords ─────────────────────────────────────────────────────
syn keyword xKeyword type interface class implements extends deps bind as
syn keyword xKeyword module scope import export namespace extern event const
syn keyword xKeyword let return if else match for while loop break continue
syn keyword xKeyword unsafe spawn when otherwise where hit test assert
" interrupts / resumable conditions
syn keyword xKeyword interrupt interrupts signal try catch recover skip
" atoms & state machines
syn keyword xKeyword atom state transition machine states initial terminal data update on
" threading (parallel block + channel/thread builtins)
syn keyword xKeyword parallel

syn keyword xStorage async own dup move
syn keyword xScope   singleton transient scoped
" function kinds (intent annotations)
syn keyword xFunctionKind mapper projector predicate consumer producer reducer creator action decision listener entry
syn keyword xOperator and or not is in matches await
syn keyword xBoolean true false
syn keyword xConstant none
" built-in facilities / pseudo-values
syn keyword xBuiltin this input value thread Events

" ── primitive & runtime types ─────────────────────────────────────
syn keyword xType Number Integer Bool String Char Timestamp Void Size cstring Bytes Json
syn keyword xType Channel Thread Event HttpRequest HttpResponse
syn keyword xType Query QueryPlan QueryProvider Repository CrudRepository Logger Ptr

" Uppercase-led identifiers read as type names (incl. sum-type variants).
syn match xTypeName "\<\u\w*\>"

" Lowercase identifier immediately before '(' reads as a function/call.
syn match xFunction "\<[a-z_]\w*\>\ze\s*("

" ── literals ─────────────────────────────────────────────────────
syn match xNumber "\<0x\x\+\>"
syn match xNumber "\<0b[01]\+\>"
syn match xNumber "\<\d\+\(\.\d\+\)\=\([eE][+-]\=\d\+\)\=\>"

syn match  xEscape "\\." contained
" interpolation hole ${ expr } — highlighted inside $"..." / $"""..."""
syn region xInterp matchgroup=xInterpDelim start="${" end="}" contained contains=xNumber,xBoolean,xConstant,xOperator,xFunction,xType,xKeyword,xBuiltin,xString
" interpolated strings (opt-in `$` prefix)
syn region xString start=+\$"""+ end=+"""+ keepend contains=xInterp
syn region xString start=+\$"+ skip=+\\"+ end=+"+ keepend contains=xEscape,xInterp
" plain strings (never interpolated)
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
hi def link xInterpDelim  PreProc
hi def link xChar         Character
hi def link xLineComment  Comment
hi def link xBlockComment Comment

let b:current_syntax = "xi"

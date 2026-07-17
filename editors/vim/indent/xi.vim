" Indentation for Xi — brace-based, C-like.
if exists("b:did_indent")
  finish
endif
let b:did_indent = 1

setlocal indentexpr=GetXIndent()
setlocal indentkeys=0{,0},!^F,o,O
setlocal nolisp
setlocal autoindent

if exists("*GetXIndent")
  finish
endif

function! GetXIndent() abort
  let lnum = prevnonblank(v:lnum - 1)
  if lnum == 0
    return 0
  endif

  let prev = getline(lnum)
  let ind = indent(lnum)

  " indent after a line ending in an opening bracket
  if prev =~ '[\[{(]\s*$'
    let ind += shiftwidth()
  endif

  " dedent a line that starts with a closing bracket
  if getline(v:lnum) =~ '^\s*[\]})]'
    let ind -= shiftwidth()
  endif

  return ind < 0 ? 0 : ind
endfunction

" Filetype settings for Xi.
if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

setlocal commentstring=//\ %s
setlocal comments=s1:/*,mb:*,ex:*/,://
setlocal expandtab
setlocal shiftwidth=4
setlocal softtabstop=4

let b:undo_ftplugin = "setlocal commentstring< comments< expandtab< shiftwidth< softtabstop<"

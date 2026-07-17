" Detect Xi source files.
" Vim's built-in detection maps *.x to rpcgen, so force filetype=xi here
" (ftdetect autocmds run after the built-ins and win).
autocmd BufRead,BufNewFile *.xi,*.x setlocal filetype=xi

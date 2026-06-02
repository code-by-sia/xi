" Detect X source files.
" Vim's built-in detection maps *.x to rpcgen, so force filetype=x here
" (ftdetect autocmds run after the built-ins and win).
autocmd BufRead,BufNewFile *.x setlocal filetype=x

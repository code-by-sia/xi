# Vim / Neovim support for Xi

Syntax highlighting, filetype detection, comment settings, and brace-based
indentation for `.x` files. Works in both Vim and Neovim (legacy Vim syntax).

```
vim/
├── ftdetect/x.vim   associate *.x with filetype `x`
├── syntax/x.vim     syntax highlighting
├── ftplugin/x.vim   commentstring, comments, indentation width
└── indent/x.vim     auto-indent
```

## Install

### Manual

Copy the four subdirectories into your Vim runtime:

```console
# Vim
$ cp -R editors/vim/* ~/.vim/

# Neovim
$ cp -R editors/vim/* ~/.config/nvim/
```

### Plugin managers

Point the manager at this repo (the plugin lives in `editors/vim`).

```vim
" vim-plug
Plug 'code-by-sia/x', { 'rtp': 'editors/vim' }

" lazy.nvim
{ "code-by-sia/x", config = function() end }   -- then add editors/vim to runtimepath
```

Or symlink for local development:

```console
$ ln -s "$PWD/editors/vim" ~/.vim/pack/x/start/x
```

Open any `.x` file to get highlighting. For richer, tree-based highlighting in
Neovim, you can instead register the Tree-sitter grammar in `../tree-sitter-x`
with `nvim-treesitter`.

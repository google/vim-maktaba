
"" Removes all autocmds in {augroup}, then removes {augroup}.
function! maktaba#autocmd#ClearGroup(augroup) abort
  execute 'augroup' a:augroup
    autocmd!
  augroup END
  execute 'augroup!' a:augroup
endfunction

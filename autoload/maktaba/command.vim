
"" Runs {command} silently, returns its output as a string.
function! maktaba#command#GetOutput(command) abort
  try
    redir => l:output
      execute 'silent verbose' a:command
  finally
    " Restore redir on success or error.
    redir END
  endtry
  if empty(l:output)
    " In the case of functions that return no output, l:output will be empty.
    " Example: #GetOutput('echo')
    return l:output
  else
    " Neovim's UI2 handles captured output differently.
    if has('nvim') && luaeval('pcall(require, "vim._core.ui2") and (require("vim._core.ui2").cfg ~= nil) and true or false')
      return l:output
    endif

    " Vim will dump an extra newline at the beginning of the redir output.
    " Yeah, I think it's dumb too.
    call maktaba#ensure#IsTrue(
        \ l:output[0] == "\n",
        \ ':redir behavior has changed')
    return l:output[1:]
  endif
endfunction

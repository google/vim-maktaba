if !exists('s:disable_python')
  let s:disable_python = 0
endif


""
" @private
" Forces the disabling of the Python implementation of the maktaba#json
" functions, to enable testing. This must be called before referencing any of
" the maktaba#json functions, since it will only take effect on first load.
function! maktaba#json#python#SetDisabled(disabled) abort
  if islocked('s:disable_python')
    call maktaba#error#Shout(
       \ 'maktaba#json#python#SetDisabled() has no effect if called after '
       \ . 'the first call to another maktaba#json function.')
  else
    let s:disable_python = a:disabled
  endif
endfunction


""
" @private
" Returns whether the Python implementation of the maktaba#json functions is
" disabled, and prevents further changes.
function! maktaba#json#python#GetDisabled() abort
  lockvar s:disable_python
  return s:disable_python
endfunction

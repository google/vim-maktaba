" Copied from maktaba/path.vim, which Override may not depend upon.
let s:is_windows = exists('+shellslash')
let s:use_backslash = s:is_windows && !&shellslash
let s:slash = s:use_backslash ? '\' : '/'

" Nonce to generate unique nonexistent autoload func name that won't collide.
let s:nonce = localtime()


""
" Simplified version of |maktaba#function#Call|.
" Code assumes arguments have appropriate types.
let s:apply_function_lines = [
    \ 'function! s:ApplyFunction(F, ...) abort',
    \ '  let l:args = get(a:, 1, [])',
    \ '  if type(a:F) == type({})',
    \ '    let l:dict = get(a:, 2, a:F.dict)',
    \ '    return s:ApplyFunction(a:F.func, a:F.arglist + l:args, l:dict)',
    \ '  endif',
    \ '  let l:dict = get(a:, 2)',
    \ '  if type(l:dict) == type({})',
    \ '    return call(a:F, l:args, l:dict)',
    \ '  endif',
    \ '  return call(a:F, l:args)',
    \ 'endfunction',
    \]


""
" Overrides the function {target} such that when it is called, {replacement} is
" called instead. This is particularly useful for overloading autoloaded
" functions, which can only be done in files that are named correctly.
" (name#spaced#Function must be defined in .../name/spaced.vim).
"
" You can de-override the function via the 'runtime' command, for example:
" >
"   runtime autoload/name/spaced.vim
" <
" will source the original name/spaced.vim, clobbering the overridden function.
"
" Due to vim's naming limitations, this function must make (and source) an
" adequately named temporary file. As such, {replacement} MUST be a string,
" funcref, or funcdict usable from any given scope (i.e., not script-local).
function! maktaba#test#Override(target, replacement) abort
  " This function cannot use maktaba autoload functions, as those may be the
  " target of the Override. Hence the complexity.

  " call maktaba#ensure#IsString(a:target)
  if type(a:target) != type('')
    throw 'ERROR(WrongType): Target autoload function name must be a string.'
  endif

  " call maktaba#ensure#TypeMatchesOneOf(a:replacement, ['', {}])
  if type(a:replacement) != type('') && type(a:replacement) != type({})
    throw 'ERROR(WrongType):' .
        \ ' Autoload function replacement must be a string or funcdict.'
  endif

  let l:data = s:apply_function_lines + [
      \ 'function! ' . a:target . '(...) abort',
      \ '  return s:ApplyFunction(' . string(a:replacement) . ', a:000)',
      \ 'endfunction',
      \ ]
  " The parts of name#spaced#Function are ['name', 'spaced', 'Function']
  let l:parts = split(a:target, '#')

  " In the trivial case of non-autoload target (no "#" in name), just define
  " function directly.
  if len(l:parts) < 2
    execute join(l:data, "\n")
    return
  endif

  " In the autoload case, write a vimscript file and get it autoloaded.
  let l:tmpdir = fnamemodify(tempname(), ':h')
  " The parent dir of the file defining name#spaced#Function is autoload/name.
  let l:dir = join([l:tmpdir, 'autoload'] + l:parts[:-3], s:slash)
  " The filepath of the file defining name#spaced#Function is
  " autoload/name/spaced.vim.
  let l:file = join([l:tmpdir, 'autoload'] + l:parts[:-2], s:slash) . '.vim'

  " Write file that defines the target function and force vim to autoload it.
  " Manually sourcing the file doesn't work reliably since vim 8.0.1378.
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  call writefile(l:data, l:file)
  let l:prev_rtp = &runtimepath
  try
    let &runtimepath = l:tmpdir
    " Force autoload by triggering an autoload func call that can never work.
    let l:nonexistent_func_name = a:target . 'NonexistentFunc_' . s:nonce
    execute 'delfunction!' l:nonexistent_func_name
    silent! execute 'call' l:nonexistent_func_name . '()'
  finally
    let &runtimepath = l:prev_rtp
  endtry
endfunction

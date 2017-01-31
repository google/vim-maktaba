
""
" Imports python module {name} into vim from {plugin}.
" Checks for {name} in the plugin's python/ subdirectory for the named module.
" @throws NotFound if the module or python/ subdirectory wasn't found.
"
" For example:
" >
"   call maktaba#python#ImportModule(maktaba#plugin#Get('foo'), 'foo.bar')
"   python print foo.bar
" <
" will print something like
"
"   <module 'foo.bar' from 'repopath/foo/python/foo/bar.py'>
function! maktaba#python#ImportModule(plugin, name) abort
  let l:path = maktaba#path#Join([a:plugin.location, 'python'])
  python <<EOF
import sys
import vim

sys.path.insert(0, vim.eval('l:path'))
EOF
  try
    execute 'python' 'import' a:name
  catch /Vim(python):/
    throw maktaba#error#NotFound('Python module %s', a:name)
  endtry
  python del sys.path[:1]
endfunction


""
" Evaluate python {expr} and return the result.
"
" Polyfill for vim's |pyeval()| that works on vim versions older than 7.3.569.
" You can call pyeval() directly if you don't intend to support vim versions
" older than that.
"
" Supports simple types (number, string, list, dict), but not other python-only
" types like None, True, or False that have no direct vimscript analog. Those
" will fail on older vim versions, so either take care to avoid them in the
" return value or just skip the polyfill and use pyeval() directly.
function! maktaba#python#Eval(expr) abort
  if exists('*pyeval')
    return pyeval(a:expr)
  endif
  python import json, vim
  python vim.command('return ' + json.dumps(eval(vim.eval('a:expr'))))
endfunction


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

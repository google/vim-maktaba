let s:unescaped_comma = '\v\\@<!%(\\\\)*\zs,'
let s:escaped_char = '\v\\([\,])'
" Some users have local vimfiles in .vim, others in .config/vim.
" Some distros install vim files into /usr/share/vimfiles, others in
" /usr/share/vim/vimN where N is a version number (like /usr/share/vim/vim73).
" Some users add runtime/ directories to their runtimepaths, and all plugins
" can contain an after/ directory.
" So all paths whose final component matches the following regex are not
" considered to be plugins.
let s:leaf_pathcomponent = '\v^(\.vim|vim%(files)?\d*|after|runtime)$'

if !exists('s:cache_string')
  let s:cache_string = ''
  let s:cache_list = []
endif



""
" Split a string of comma-separated values into a list of values.
" Handles unescaping the commas.
" [path] The string to split.
" @default path=|runtimepath|
function! maktaba#rtp#Split(...) abort
  let l:path = get(a:, 1, &runtimepath)
  if l:path !=# s:cache_string
    let s:cache_string = l:path
    let s:cache_list = map(
        \ split(l:path, s:unescaped_comma),
        \ "substitute(v:val, s:escaped_char, '\\1', 'g')")
  endif
  return copy(s:cache_list)
endfunction


""
" Joins {paths}, a list of strings, into a comma-separated strings.
" Handles the escaping of commas in {paths}.
function! maktaba#rtp#Join(paths) abort
  call maktaba#ensure#IsList(a:paths)
  return join(map(a:paths, "escape(v:val, '\,')"), ',')
endfunction


""
" Adds {path} to the runtimepath.
"
" In vanilla vim, the runtime path is sorted as follows:
" 1. User's vim files.
" 2. System vim files.
" 3. System after/ files.
" 4. User's after/ files.
" This lets the user run both first and last, which is nice.
" This function puts plugin vim files between 2nd in the list (between 1 and 2),
" and puts plugin after/ files 2nd to last in the list (between 3 and 4). The
" newest plugin that you've installed will be the 2nd thing sourced (after user
" files) and its after directory will be the 2nd to last thing sourced (before
" user files). Thus, plugins stack outwards from the middle, like an onion.
"
" If {path} is already in the runtimepath, the existing instances will be
" removed and {path} will be re-inserted as described above.
"
" If you have more than one directory of files that you'd like to run
" before/after all plugins, it is recommended that you add that directory after
" all plugins and/or sort the runtimepath yourself. @function(#Split) and
" @function(#Join) may be of some use.
function! maktaba#rtp#Add(path) abort
  call maktaba#ensure#IsString(a:path)
  let l:rtp = maktaba#rtp#Split(&runtimepath)
  let l:end = len(l:rtp) == 0 ? 1 : -1
  call maktaba#list#RemoveAll(l:rtp, a:path)
  call insert(l:rtp, a:path, 1)
  let l:after = maktaba#path#Join([a:path, 'after'])
  if isdirectory(l:after)
    call maktaba#list#RemoveAll(l:rtp, l:after)
    call insert(l:rtp, l:after, l:end)
  endif
  let &runtimepath = maktaba#rtp#Join(l:rtp)
  let s:cache_string = &runtimepath
  let s:cache_list = l:rtp
endfunction


""
" Removes {path} from the runtimepath.
function! maktaba#rtp#Remove(path) abort
  call maktaba#ensure#IsString(a:path)
  let l:rtp = maktaba#rtp#Split(&runtimepath)
  call maktaba#list#RemoveAll(l:rtp, a:path)
  let &runtimepath = maktaba#rtp#Join(l:rtp)
  let s:cache_string = &runtimepath
  let s:cache_list = l:rtp
endfunction


""
" Returns a dictionary of {leaf path} for runtimepath directories that appear
" to be plugins. The key is the name of the leaf directory, the path is the
" precise position of the leaf directory (as given in the runtimepath).
"
" A leaf directory is the final path component of any runtimepath directory,
" excepting directories named like the following:
" * .vim
" * vimfiles
" * vim\d*
" * runtime
" * after
" which are assumed to be user-, system-, or plugin-owned runtimepath
" components.
"
" This can be used heuristically to return a dictionary of installed plugins,
" so long as the user has not added non-standard directories to their
" runtimepath. Note however that we can't guarantee that all non-system
" non-user non-after runtimepath components actually correspond to valid
" plugins.
function! maktaba#rtp#LeafDirs() abort
  let l:plugins = {}
  for l:path in maktaba#rtp#Split(&rtp)
    let l:components = maktaba#path#Split(l:path)
    if l:components[-1] !~? s:leaf_pathcomponent
      let l:plugins[l:components[-1]] = l:path
    endif
  endfor
  return l:plugins
endfunction


""
" Returns 1 if it looks like {leaf} exists on the runtimepath. This is
" a guess, and should not be treated as a guarantee. If you have a directory
" named like {leaf} on your runtimepath, or if {leaf} looks like it's
" a normal vim runtime directory, then this function may return a false
" positive/negative.
function! maktaba#rtp#HasLeafDir(leaf) abort
  return has_key(maktaba#rtp#LeafDirs(), a:leaf) > 0
endfunction


""
" Mimics the normal vim load sequence for {dir}, which will be added to the
" runtimepath if it is not already there. This should be done only on
" directories that were not present for the normal vim load sequence.
"
" All files in the plugin/ directory will be sourced. After that,
" maktaba#filetype#Cycle will be called if the plugin has installed any new
" filetypes.
"
" If the plugin is a maktaba plugin, you should use maktaba#plugin#Install
" instead.
" @throws NotFound if {dir} does not exist.
" @throws BadValue if {dir} does not describe a directory.
function! maktaba#rtp#Load(dir) abort
  call maktaba#ensure#IsDirectory(a:dir)
  call maktaba#rtp#Add(a:dir)
  let l:plugindir = maktaba#path#Join([a:dir, 'plugin'])
  let l:afterdir = maktaba#path#Join([a:dir, 'after', 'plugin'])
  for l:dir in [l:plugindir, l:afterdir]
    if isdirectory(l:dir)
      let l:sources = maktaba#path#Join([l:dir, '**', '*.vim'])
      " NOTE: This will fail if any files have newlines in their names.
      " Please never put newlines in plugin names. If we ever drop Vim7.3
      " support, this warning can be removed after changing the call to
      " glob(l:sources, 1, 1).
      for l:source in split(glob(l:sources, 1), '\n')
        execute 'source' l:source
      endfor
    endif
  endfor
  if maktaba#rtp#DirDefinesFiletypes(a:dir)
    call maktaba#filetype#Cycle()
  endif
endfunction


""
" Whether or not runtimepath directory {dir} defines a new filetype.
function! maktaba#rtp#DirDefinesFiletypes(dir) abort
  return isdirectory(maktaba#path#Join([a:dir, 'ftdetect']))
      \ || isdirectory(maktaba#path#Join([a:dir, 'after', 'ftdetect']))
endfunction

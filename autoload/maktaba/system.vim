"" Utilities for making system calls and dealing with the shell.

let s:plugin = maktaba#plugin#Get('maktaba')
let s:usable_shell = '\v^/bin/sh$'

" Note: '' denotes that we should use the default (currently 'hidden').
let s:contexts = ['', 'hidden', 'foreground', 'foreground_pause']
let s:default_context = 'hidden'

""
" Join {words} together into a single shell command, escaping if necessary.
" Also accepts a bare string for convenience and simply returns it, with the
" assumption that it's been properly escaped beforehand.
" Functions in maktaba#system# pass any system command arguments to this
" function, allowing you to use lists or escaped strings anywhere.
function! maktaba#system#Command(words) abort
  if maktaba#value#IsString(a:words)
    " Accept strings for convenience, return as-is.
    return a:words
  endif
  let l:words = map(a:words, 'maktaba#string#Strip(v:val)')
  let l:words = filter(l:words, '!empty(v:val)')
  let l:words = map(l:words, 's:SoftShellEscape(v:val)')
  return join(l:words)
endfunction

""
" Runs {cmd} in [context] and returns a dictionary of results data.
" {cmd} is either a bare string that's already properly escaped or a list of
" "word" strings that are escaped for you.
" [context] is the execution context for the call.
" * 'hidden' executes without affecting vim UI.
" * 'foreground' scrolls the output on-screen as it executes.
" * 'foreground_pause' scrolls the output on-screen and waits for the user to
"   dismiss it when it finishes.
" * '' (the empty string) means to use the default value.  (This is the only way
"   to use the default for this, but specify a non-default value for
"   [throw_errors].)
" @default context='hidden'
" * [throw_errors] is whether exit codes should trigger a ShellError to be
"   thrown. If 0, the caller is responsible for checking v:shell_error.
" @default throw_errors=1
" Returns a dictionary with the following fields:
" * 'stdout': the shell command's entire stdout string, if available.
" * 'stderr': the shell command's entire stderr string, if available.
" @throws BadValue if [context] is unrecognized.
" @throws ShellError if the shell command returns an exit code.
function! maktaba#system#Call(cmd, ...) abort
  let l:execution = maktaba#ensure#IsString(get(a:, 1, ''))
  call maktaba#ensure#IsIn(l:execution, s:contexts)
  if empty(l:execution)
    let l:execution = s:default_context
  endif
  let l:throw_error = maktaba#ensure#IsBool(get(a:, 2, 1))
  let l:return_data = {}
  let l:error_file = tempname()

  " Force shell to /bin/sh since vim only works properly with POSIX shells.
  " If the shell is a whitelisted wrapper, override the wrapped shell via $SHELL
  " instead.
  if &shell !~# s:usable_shell
    let l:save_shell = &shell
    set shell=/bin/sh
  endif
  if $SHELL !~# s:usable_shell
    let l:save_env_shell = $SHELL
    let $SHELL = '/bin/sh'
  endif

  try
    let l:cmd = maktaba#system#Command(a:cmd)
    call s:plugin.logger.Debug(
        \ 'Executing syscall "%s" in execution mode "%s"',
        \ l:cmd,
        \ l:execution)
    if l:execution ==# 'hidden'
      let l:full_cmd = printf('%s 2> %s', l:cmd, l:error_file)
      let l:return_data.stdout = system(l:full_cmd)
    elseif l:execution ==# 'foreground'
      " TODO(dbarnett): Can we capture 'stderr' here without messing up output?
      silent execute '!' . s:EscapeSpecialChars(l:cmd)
      redraw!
    elseif l:execution ==# 'foreground_pause'
      execute '!' . s:EscapeSpecialChars(l:cmd)
    else
      " Value was already checked above. This code shouldn't be reachable.
      throw maktaba#error#BadValue(
          \ 'Expected one of "hidden", "foreground", or "foreground_pause".' .
          \ 'Got "%s".', l:execution)
    endif
    " TODO(dbarnett): Implement 'deferred' execution (queued until cursorhold).
  finally
    " Restore configured shell.
    if exists('l:save_shell')
      let &shell = l:save_shell
    endif
    if exists('l:save_env_shell')
      let $SHELL = l:save_env_shell
    endif

    if filereadable(l:error_file)
      let l:return_data.stderr = join(add(readfile(l:error_file), ''), "\n")
      call delete(l:error_file)
    endif
  endtry

  if !l:throw_error || !v:shell_error
    return l:return_data
  endif
  " If {throw_errors} is on, translate exit code into thrown ShellError.
  let l:err_msg = 'Error running: %s'
  if has_key(l:return_data, 'stderr')
    let l:err_msg .= "\n" . l:return_data.stderr
  endif
  throw maktaba#error#Message('ShellError', l:err_msg, l:cmd)
endfunction

" TODO(jhoak): correctly handle <cword>, <cfile>, etc.,
""
" Escape the special chars in a {string}.  This is useful for when "execute
" '!foo'" is used. The \ is then removed again by the :! command.  See helpdocs
" on shellescape.
function! s:EscapeSpecialChars(string) abort
  return escape(a:string, '!%#')
endfunction

""
" Runs {cmd} from {working_dir} and returns a dictionary of results data.
" * {cmd} is the string to execute as a shell command.
" * {working_dir} is a path for vim to cd into before executing the command (or
"   0). If it's a file instead of a directory, the parent directory will be
" assumed automatically.
" * [context] is the execution context for the call. It should be one of
"   'hidden', 'foreground', or 'foreground_pause'. See @function(#Call) for
"   details.
" @default context='hidden'
" * [throw_errors] is whether exit codes should trigger a ShellError to be
"   thrown. If 0, the caller is responsible for checking v:shell_error.
" @default throw_errors=1
" Returns a dictionary with the following fields:
" * 'stdout': the shell command's entire stdout string, if available.
" * 'stderr': the shell command's entire stderr string, if available.
" @throws BadValue if [context] is unrecognized.
" @throws NotFound if {working_dir} is invalid.
" @throws ShellError if the shell command returns an exit code.
function! maktaba#system#CallAt(cmd, working_dir, ...) abort
  let l:working_dir = a:working_dir
  if !isdirectory(l:working_dir) && filereadable(l:working_dir)
    let l:working_dir = fnamemodify(l:working_dir, ':h')
  endif
  if !isdirectory(l:working_dir)
    throw maktaba#error#NotFound('Directory %s does not exist.', l:working_dir)
  endif
  let l:cmd = maktaba#system#And([['cd', l:working_dir], a:cmd])
  return call('maktaba#system#Call', [l:cmd] + a:000)
endfunction

""
" Escapes a string for the shell, but only if it contains special characters.
" Special characters are anything besides letters, numbers, or [-=/.:_].
function! s:SoftShellEscape(word) abort
  if a:word =~# '\m^[-=/.:_a-zA-Z0-9]*$'
    " Simple value, no need to escape.
    return a:word
  endif
  return shellescape(a:word)
endfunction

""
" Chain {cmds} together with logical AND operations ('&&').
" {cmds} is a list of shell command strings.
function! maktaba#system#And(cmds) abort
  return join(map(a:cmds, 'maktaba#system#Command(v:val)'), ' && ')
endfunction

""
" Chain {cmds} together with logical OR operations ('||').
" {cmds} is a list of shell command strings.
function! maktaba#system#Or(cmds) abort
  return join(map(a:cmds, 'maktaba#system#Command(v:val)'), ' || ')
endfunction

""
" @private
" Sets the regex that @function(#Call) uses to decide whether 'shell' is
" usable. If 'shell' is unusable, @function(#Call) will use /bin/sh instead. You
" should NOT use this function to make vim use your preferred shell (ESPECIALLY
" if your shell is sh-incompatible) as that will break all plugins using
" @function(#Call) and expecting sh syntax.
"
" Rather, this function is often useful with vim test frameworks, which hijack
" the shell script (to stub it out / verify the commands).
function! maktaba#system#SetUsableShellRegex(regex) abort
  call maktaba#ensure#IsString(a:regex)
  let s:usable_shell = a:regex
endfunction

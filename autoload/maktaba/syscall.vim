"" Utilities for making system calls and dealing with the shell.

if !exists('s:usable_shell')
  let s:usable_shell = '\v^/bin/sh$'
endif


" TODO(jhoak): correctly handle <cword>, <cfile>, etc.,
""
" Escape the special chars in a {string}.  This is useful for when "execute
" '!foo'" is used. The \ is then removed again by the :! command.  See helpdocs
" on shellescape.
function! s:EscapeSpecialChars(string) abort
  return escape(a:string, '!%#')
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
" Execute {syscall} using the specific call implementation {CallFunc}, handling
" settings overrides and error propagation.
" Used to implement @function(#Call) and @function(#CallForeground).
" @throws ShellError if {syscall} returns an exit code and {throw_errors} is 1.
function! s:DoSyscallCommon(syscall, CallFunc, throw_errors) abort
  call maktaba#ensure#IsBool(a:throw_errors)
  let l:return_data = {}

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
    let l:return_data = maktaba#function#Apply(a:CallFunc)
  finally
    " Restore configured shell.
    if exists('l:save_shell')
      let &shell = l:save_shell
    endif
    if exists('l:save_env_shell')
      let $SHELL = l:save_env_shell
    endif
  endtry

  if !a:throw_errors || !v:shell_error
    return l:return_data
  endif

  " Translate exit code into thrown ShellError.
  let l:err_msg = 'Error running: %s'
  if has_key(l:return_data, 'stderr')
    let l:err_msg .= "\n" . l:return_data.stderr
  endif
  throw maktaba#error#Message('ShellError', l:err_msg, a:syscall.GetCommand())
endfunction


""
" @private
" @dict Syscall
" Calls |system()| and returns a stdout/stderr dict.
" The specific implementation for @function(#Call).
function! maktaba#syscall#DoCall() abort dict
  let l:error_file = tempname()
  let l:return_data = {}
  try
    let l:full_cmd = printf('%s 2> %s', self.GetCommand(), l:error_file)
    let l:return_data.stdout = system(l:full_cmd)
  finally
    if filereadable(l:error_file)
      let l:return_data.stderr = join(add(readfile(l:error_file), ''), "\n")
      call delete(l:error_file)
    endif
  endtry
  return l:return_data
endfunction

""
" @private
" @dict Syscall
" Executes the ! command and returns empty dict, respecting {pause}.
" The specific implementation for @function(#CallForeground).
function! maktaba#syscall#DoCallForeground(pause) abort dict
  let l:return_data = {}
  if a:pause
    execute '!' . s:EscapeSpecialChars(self.GetCommand())
  else
    silent execute '!' . s:EscapeSpecialChars(self.GetCommand())
    redraw!
  endif
  return l:return_data
endfunction

""
" @dict Syscall
" A maktaba representation of a system call, which is used to configure and
" execute a system command.


""
" Creates a @dict(Syscall) object that can be used to execute {cmd} with
" @function(Syscall.Call).
" {cmd} may be a pre-escaped string, a list of words to be automatically escaped
" and joined. Also accepts an existing Syscall object and returns it for
" convenience.
" @throws WrongType
function! maktaba#syscall#Create(cmd) abort
  if maktaba#value#IsDict(a:cmd)
    return a:cmd
  endif
  return {
      \ 'cmd': maktaba#ensure#TypeMatchesOneOf(a:cmd, ['', []]),
      \ 'WithCwd': function('maktaba#syscall#WithCwd'),
      \ 'And': function('maktaba#syscall#And'),
      \ 'Or': function('maktaba#syscall#Or'),
      \ 'Call': function('maktaba#syscall#Call'),
      \ 'CallForeground': function('maktaba#syscall#CallForeground'),
      \ 'GetCommand': function('maktaba#syscall#GetCommand')}
endfunction


""
" @dict Syscall
" Returns a copy of the @dict(Syscall) configured to be executed in {directory}.
" @throws WrongType
" @throws NotFound if {directory} is invalid.
function! maktaba#syscall#WithCwd(directory) abort dict
  let l:directory = a:directory
  if !isdirectory(l:directory) && filereadable(l:directory)
    let l:directory = fnamemodify(l:directory, ':h')
  endif
  if !isdirectory(l:directory)
    throw maktaba#error#NotFound('Directory %s does not exist.', l:directory)
  endif
  let l:new_cmd = copy(self)
  let l:orig_cmd_value = self.cmd
  let l:new_cmd.cmd = ['cd', l:directory]
  return l:new_cmd.And(l:orig_cmd_value)
endfunction


""
" @dict Syscall
" Returns a new @dict(Syscall) that chains self and {cmd} together with a
" logical AND operation ("&&").
" {cmd} may be any valid @function(#Create) argument.
" @throws WrongType
function! maktaba#syscall#And(cmd) abort dict
  let l:cmd_string = maktaba#syscall#Create(a:cmd).GetCommand()
  let l:new_cmd = copy(self)
  let l:new_cmd.cmd = join([self.GetCommand(), l:cmd_string], ' && ')
  return l:new_cmd
endfunction


""
" @dict Syscall
" Returns a new @dict(Syscall) that chains self and {cmd} together with a
" logical OR operation ("&&").
" {cmd} may be any valid @function(#Create) argument.
" @throws WrongType
function! maktaba#syscall#Or(cmd) abort dict
  let l:cmd_string = maktaba#syscall#Create(a:cmd).GetCommand()
  let l:new_cmd = copy(self)
  let l:new_cmd.cmd = join([self.GetCommand(), l:cmd_string], ' || ')
  return l:new_cmd
endfunction


""
" @dict Syscall
" Executes the system call without showing output to the user.
" If [throw_errors] is 1, any exit code from the command will cause a ShellError
" to be thrown. Otherwise, the caller is responsible for checking
" |v:shell_error| and handling error conditions.
" @default throw_errors=1
" Returns a dictionary with the following fields:
" * stdout: the shell command's entire stdout string, if available.
" * stderr: the shell command's entire stderr string, if available.
" @throws WrongType
" @throws ShellError if the shell command returns an exit code.
function! maktaba#syscall#Call(...) abort dict
  let l:throw_errors = maktaba#ensure#IsBool(get(a:, 1, 1))
  let l:call_func = maktaba#function#Create('maktaba#syscall#DoCall', [], self)
  return s:DoSyscallCommon(self, l:call_func, l:throw_errors)
endfunction


""
" @dict Syscall
" Executes the system call in the foreground, showing the output to the user.
" If {pause} is 1, output will stay on the screen until the user presses Enter.
" If [throw_errors] is 1, any exit code from the command will cause a ShellError
" to be thrown. Otherwise, the caller is responsible for checking
" |v:shell_error| and handling error conditions.
" @default throw_errors=1
" Returns a dictionary with the following fields:
" * stdout: the shell command's entire stdout string, if available.
" * stderr: the shell command's entire stderr string, if available.
" @throws WrongType
" @throws ShellError if the shell command returns an exit code.
function! maktaba#syscall#CallForeground(pause, ...) abort dict
  let l:throw_errors = maktaba#ensure#IsBool(get(a:, 1, 1))
  let l:call_func = maktaba#function#Create(
      \ 'maktaba#syscall#DoCallForeground', [a:pause], self)
  return s:DoSyscallCommon(self, l:call_func, l:throw_errors)
endfunction


""
" @dict Syscall
" Gets the literal command string that would be executed by
" @function(Syscall.Call) or @function(Syscall.CallForeground), with words
" joined and special characters escaped.
function! maktaba#syscall#GetCommand() abort dict
  if maktaba#value#IsString(self.cmd)
    " Accept strings for convenience, return as-is.
    return self.cmd
  endif
  let l:words = map(self.cmd, 'maktaba#string#Strip(v:val)')
  let l:words = filter(l:words, '!empty(v:val)')
  let l:words = map(l:words, 's:SoftShellEscape(v:val)')
  return join(l:words)
endfunction


""
" @private
" Sets the regex that @function(Syscall.Call) and
" @function(Syscall.CallForeground) use to decide whether 'shell' is usable. If
" 'shell' is unusable, they will use /bin/sh instead. You should NOT use this
" function to make vim use your preferred shell (ESPECIALLY if your shell is
" sh-incompatible) as that will break all plugins using |maktaba#syscall| and
" expecting sh syntax.
"
" Rather, this function is often useful with vim test frameworks, which hijack
" the shell script (to stub it out / verify the commands).
function! maktaba#syscall#SetUsableShellRegex(regex) abort
  call maktaba#ensure#IsString(a:regex)
  let s:usable_shell = a:regex
endfunction

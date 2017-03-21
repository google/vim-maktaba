if !exists('s:num_invocations')
  let s:num_invocations = 0
endif

""
" Gets a number uniquely identifying a SyscallInvocation.
function! s:CreateInvocationId()
  let s:num_invocations += 1
  return s:num_invocations
endfunction

" Compiles a dictionary describing the current vim state.
function! s:CurrentEnv()
  return {
      \ 'tab': tabpagenr(),
      \ 'buffer': bufnr('%'),
      \ 'path': expand('%:p'),
      \ 'column': col('.'),
      \ 'line': line('.')}
endfunction


""
" @dict SyscallInvocation
" A maktaba representation of a single invocation of a @dict(Syscall).
" Provides a mechanism for interacting with a syscall invocation, checking
" status, etc.
"
" Public variables:
" * finished: 0 if invocation is pending, 1 if finished. The result variables
"   (status, stdout, stderr) will not exist if invocation is not finished.
"   Guaranteed to be 1 when an invocation's callback is called.
" * status: the shell exit code from the invocation (typically 0 for success).
" * stdout: the invocation's entire stdout string.
" * stderr: the invocation's entire stderr string, if available.
"
" Note one Syscall invoked multiple times would produce multiple independent
" SyscallInvocations.


""
" @private
" Create a @dict(SyscallInvocation).
" Private helper only for use by Syscall.CallAsync.
function! maktaba#syscall#invocation#Create(Callback) abort
  return {
      \ 'id': s:CreateInvocationId(),
      \ 'finished': 0,
      \ '_env': s:CurrentEnv(),
      \ '_callback': a:Callback,
      \ '_TriggerCallback':
          \ function('maktaba#syscall#invocation#TriggerCallback'),
      \ 'Finish': function('maktaba#syscall#invocation#Finish')}
endfunction


""
" @private
" Executes the invocation's callback. The callback must be of prototype:
" callback(result_dict) or legacy prototype callback(env_dict, result_dict).
" The latter will be deprecated and stop working in future versions of maktaba.
function! maktaba#syscall#invocation#TriggerCallback() abort dict
  try
    " Try prototype callback({result_dict}).
    call maktaba#function#Call(self._callback, [self])
  catch /E119:/
    " Not enough arguments.
    " Fall back to legacy prototype callback({env_dict}, {result_dict}).
    " TODO(#180): Deprecate and shout an error for this case.
    call maktaba#function#Call(self._callback, [self._env, self])
  endtry
endfunction


""
" @private
" @dict SyscallInvocation
" Executes the asynchronous callback setup by @function(Syscall.CallAsync).
" The callback must be of prototype: callback(result_dict) or legacy prototype
" callback(env_dict, result_dict). The latter will be deprecated and stop
" working in future versions of maktaba.
function! maktaba#syscall#invocation#Finish(result) abort dict
  let self.status = a:result.status
  let self.stdout = a:result.stdout
  if has_key(a:result, 'stderr')
    let self.stderr = a:result.stderr
  endif
  let self.finished = 1
  call self._TriggerCallback()
endfunction

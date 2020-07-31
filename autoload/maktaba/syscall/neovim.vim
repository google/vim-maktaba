" CallAsync implementation using neovim's job support.

""
" @private
function! maktaba#syscall#neovim#CreateInvocation(syscall, invocation) abort
  " We'll pass this entire invocation to jobstart, which will pass it to the
  " on_exit callback.
  return {
      \ '_syscall': a:syscall,
      \ '_invocation': a:invocation,
      \ 'Start': function('maktaba#syscall#neovim#Start'),
      \ 'stdout_buffered': 1,
      \ 'stderr_buffered': 1,
      \ 'on_exit': function('maktaba#syscall#neovim#HandleJobExit')}
endfunction


""
" @private
" @dict SyscallNeovimInvocation
" Dispatches syscall through |jobstart()|, and invokes the invocation's
" callback once the command completes, passing in stdout, stderr and exit code
" to it.
" The neovim |job_control| implementation for @function(#CallAsync).
function! maktaba#syscall#neovim#Start() abort dict
  let self._job = jobstart(self._syscall.GetCommand(), self)
  " Send stdin immediately and close. Streaming input to stdin not supported.
  if has_key(self._syscall, 'stdin')
    call chansend(self._job, self._syscall.stdin)
  endif
  call chanclose(self._job, 'stdin')
endfunction


""
" @private
" @dict SyscallNeovimInvocation
function! maktaba#syscall#neovim#HandleJobExit(
      \ unused_job,
      \ status,
      \ unused_event) abort dict
  " jobcontrol sets stdout and stderr when no callbacks are given.
  call self._invocation.Finish({
      \ 'status': a:status,
      \ 'stdout': join(self.stdout, "\n"),
      \ 'stderr': join(self.stderr, "\n")})
endfunction

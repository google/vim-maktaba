""
" @dict KeyMapping
" A maktaba representation of a vim key mapping, which is used to configure and
" unmap it from vim.


if !exists('s:next_keymap_id')
  let s:next_keymap_id = 0
endif

if !exists('s:KEYMAPS_BY_ID')
  let s:KEYMAPS_BY_ID = {}
endif


function! s:ReserveKeyMapId() abort
  let l:keymap_id = s:next_keymap_id
  let s:next_keymap_id += 1
  return l:keymap_id
endfunction


function! s:GetMappingById(id) abort
  try
    return s:KEYMAPS_BY_ID[a:id]
  catch /E716:/
    return 0
  endtry
endfunction


function! s:GetFuncCallKeystrokes(funcstr, mode) abort
  if a:mode ==# 'n'
    return printf(':call %s<CR>', a:funcstr)
  elseif a:mode ==# 'i'
    return printf('<C-\><C-o>:call %s<CR>', a:funcstr)
  elseif a:mode ==# 'v'
    " Uses "gv" at the end to re-enter visual mode.
    return printf(':<C-u>call %s<CR>gv', a:funcstr)
  elseif a:mode ==# 's'
    " Uses "gv<C-g>" at the end to re-enter select mode.
    return printf('<C-\><C-o>:<C-u>call %s<CR>gv<C-g>', a:funcstr)
  endif
  throw maktaba#error#NotImplemented(
      \ 'MapOnce not implemented for mode %s', a:mode)
endfunction


""
" @dict KeyMapping
" Unmaps the mapping in vim.
" Returns 1 if mapping was found and unmapped, 0 if mapping was gone already.
function! maktaba#keymapping#Unmap() dict abort
  if self.IsMapped()
    let l:arg_prefix = self._maparg.buffer ? '<buffer> ' : ''
    execute printf(
        \ 'silent %sunmap %s%s',
        \ self._maparg.mode,
        \ l:arg_prefix,
        \ self._maparg.lhs)
    if has_key(s:KEYMAPS_BY_ID, self._id)
      unlet s:KEYMAPS_BY_ID[self._id]
    endif
    return 1
  else
    return 0
  endif
endfunction


""
" @dict KeyMapping
" Returns 1 if the mapping is still defined, 0 otherwise
"
" Caveat: This detection can currently false positive if the original mapping
" was unmapped but then another similar one mapped afterwards.
function! maktaba#keymapping#IsMapped() dict abort
  let l:foundmap = maparg(self._lhs, self._mode, 0, 1)
  return !empty(l:foundmap) && l:foundmap == self._maparg
endfunction


""
" @dict KeyMapping
" Return a copy of the spec used to issue this mapping.
function! maktaba#keymapping#GetSpec() dict abort
  return copy(self._spec)
endfunction


let s:IsMapped = function('maktaba#keymapping#IsMapped')
let s:Unmap = function('maktaba#keymapping#Unmap')
let s:GetSpec = function('maktaba#keymapping#GetSpec')


""
" Set up a key mapping in vim, mapping key sequence {lhs} to replacement
" sequence {rhs} in the given [mode]. This is a convenience wrapper for
" @function(#Spec) and its |KeyMappingSpec.Map| that supports the basic mapping
" options. It is equivalent to calling: >
"   :call maktaba#keymapping#Spec({lhs}, {rhs}, [mode]).Map()
" <
"
" See those functions for usage and behavior details.
"
" @default mode=all of 'n', 'v', and 'o' (vim's default)
function! maktaba#keymapping#Map(lhs, rhs, ...) abort
  if a:0 >= 1
    let l:spec = maktaba#keymappingspec#Spec(a:lhs, a:rhs, a:1)
  else
    let l:spec = maktaba#keymappingspec#Spec(a:lhs, a:rhs)
  endif
  return l:spec.Map()
endfunction


""
" @private
" Unmap the one-shot mapping identified by {id} (an internal ID generated in the
" implementation) and mapped with @function(KeyMappingSpec.MapOnce) or
" MapOnceWithTimeout.
" Returns 1 if mapping was found and unmapped, 0 if mapping was gone already.
function! maktaba#keymapping#UnmapById(id) abort
  let l:keymap = s:GetMappingById(a:id)
  if l:keymap is 0
    return 0
  endif
  call l:keymap.Unmap()
  return 1
endfunction


""
" @private
" Performs the actions needed for a MapOnceWithTimestamp mapping, unmapping it
" by {id} if it's still mapped and conditionally mapping a simpler version of
" itself to be triggered by the upcoming LHS keystrokes (mapped if
" {timeout_start} + 'timeoutlen' hasn't elapsed).
function! maktaba#keymapping#UnwrapForIdAndTimeoutWithRhs(
    \ id, timeout_start, orig_rhs) abort
  let l:keymap = s:GetMappingById(a:id)
  call l:keymap.Unmap()
  if reltimefloat(reltime(a:timeout_start)) < &timeoutlen
    " Timeout hasn't elapsed.
    " Remap a version of {orig_rhs} to be invoked immediately.
    let l:spec_without_timestamp_or_remap = l:keymap.GetSpec().WithRemap(0)
    let l:spec_without_timestamp_or_remap._rhs = a:orig_rhs
    call l:spec_without_timestamp_or_remap.MapOnce()
  else
    " Timeout has elapsed.
    " Register nothing, so we fall back to original {rhs}.
  endif
endfunction


""
" @private
" Creates a skeleton @dict(KeyMapping) from {spec}.
" Internal helper only intended to be called by @function(KeyMappingSpec.Map).
function! maktaba#keymapping#PopulateFromSpec(spec) abort
  return {
      \ '_id': s:ReserveKeyMapId(),
      \ '_spec': a:spec,
      \ '_lhs': a:spec._lhs,
      \ '_mode': a:spec._mode,
      \ '_is_noremap': a:spec._is_noremap,
      \ '_is_bufmap': a:spec._is_bufmap,
      \ 'IsMapped': s:IsMapped,
      \ 'Unmap': s:Unmap,
      \ 'GetSpec': s:GetSpec,
      \ '_DoMap': function('maktaba#keymapping#MapSelf'),
      \ '_DoMapOnce': function('maktaba#keymapping#MapSelfOnce'),
      \ '_DoMapOnceWithTimeout':
          \ function('maktaba#keymapping#MapSelfOnceWithTimeout'),
      \ }
endfunction


""
" @private
" @dict KeyMapping
" Defines the key mapping in vim via the |:map| commands for the keymap in self.
" Core internal implementation of @function(KeyMappingSpec.Map).
function! maktaba#keymapping#MapSelf() dict abort
  " TODO(dbarnett): Perform a sweep for expired mapping timeouts before trying
  " to register more mappings (which might conflict).
  let l:spec = self._spec
  let s:KEYMAPS_BY_ID[self._id] = self
  execute printf('%s%smap %s %s %s',
      \ l:spec._mode,
      \ l:spec._is_noremap ? 'nore' : '',
      \ join(l:spec._args, ' '),
      \ l:spec._lhs,
      \ l:spec._rhs)
  let self._maparg = maparg(l:spec._lhs, self._mode, 0, 1)
endfunction


""
" @private
" @dict KeyMapping
" Define a buffer-local one-shot vim mapping from spec that will only trigger
" once and then unmap itself.
"
" @throws NotImplemented if used with `WithRemap(1)`
function! maktaba#keymapping#MapSelfOnce() dict abort
  let l:spec = self._spec
  if !l:spec._is_noremap
    throw maktaba#error#NotImplemented(
        \ "MapOnce doesn't support recursive mappings")
  endif
  let s:KEYMAPS_BY_ID[self._id] = self
  execute printf(
      \ '%snoremap %s %s %s%s',
      \ self._mode,
      \ join(l:spec._args, ' '),
      \ l:spec._lhs,
      \ s:GetFuncCallKeystrokes(
          \ 'maktaba#keymapping#UnmapById(' . self._id . ')',
          \ self._mode),
      \ l:spec._rhs)
  let self._maparg = maparg(l:spec._lhs, self._mode, 0, 1)
endfunction


""
" @private
" @dict KeyMapping
" Define a short-lived vim mapping from spec that will only trigger once and
" will also expire if 'timeoutlen' duration expires with 'timeout' setting
" active. See |KeyMappingSpec.MapOnceWithTimeout()| for details.
"
" @throws NotImplemented if used with `WithRemap(1)`
function! maktaba#keymapping#MapSelfOnceWithTimeout() dict abort
  if !self._spec._is_noremap
    throw maktaba#error#NotImplemented(
        \ "MapOnceWithTimeout doesn't support recursive mappings")
  endif

  " Handle cases for !has('reltime') and 'notimeout', which map without timeout.
  if !has('reltime')
    call s:plugin.logger.Info(
        \ 'Vim is missing +reltime feature. '
        \ . 'MapOnceWithTimeout fell back to mapping without timeout')
    call self._DoMapOnce()
    return
  elseif !&timeout
    call self._DoMapOnce()
    return
  endif
  " Handle case for timeoutlen=0, which "times out" immediately and skips the
  " mapping entirely. Handle will always have IsMapped()=0.
  if &timeoutlen == 0
    return
  endif

  " This conditionally sends keystrokes by using a recursive mapping that will
  " check reltime/timeout and then invoke either
  "   (a) a version of itself with no time check, if timeout hasn't elapsed, or
  "   (b) a fallback to the behavior if the mapping hadn't existed.
  " The recursive wrapper always starts by unmapping itself and mapping an
  " unwrapped RHS mapping, which avoids recursing indefinitely.
  let l:spec = self._spec
  let s:KEYMAPS_BY_ID[self._id] = self
  " Escapes any special keystroke sequences (example: convert <Esc> to <LT>Esc>)
  " since they would be passed to map as special keysrokes instead of part of
  " the arg string.
  let l:escaped_rhs = substitute(l:spec._rhs, '\m<\([^>]*\)>', '<LT>\1>', 'g')
  " TODO(dbarnett): Also schedule a timer_start job if +timers is available to
  " sweep away expired maps after timeout expires.
  execute printf(
      \ '%smap %s %s %s%s',
      \ self._mode,
      \ join(['<nowait>', '<silent>'] + l:spec._args, ' '),
      \ l:spec._lhs,
      \ s:GetFuncCallKeystrokes(printf(
              \ 'maktaba#keymapping#UnwrapForIdAndTimeoutWithRhs(%d, %s, %s)',
              \ self._id,
              \ string(reltime()),
              \ string(l:escaped_rhs)),
          \ self._mode),
      \ l:spec._rhs)
  let self._maparg = maparg(l:spec._lhs, self._mode, 0, 1)
endfunction

let s:plugin = maktaba#Maktaba()


""
" @dict KeyMappingSpec
" A spec for a key mapping that can be mapped in Vim with
" @function(KeyMappingSpec.Map).


""
" Create a @dict(KeyMappingSpec) that can be configured with options and then
" mapped in Vim with @function(KeyMappingSpec.Map). The eventual mapping will
" map {lhs} to {rhs} in the given [mode].
"
" Initialized with recursive mappings disallowed by default (see |:noremap|).
" To allow them, use @function(KeyMappingSpec.WithRemap).
"
" Arguments will be configured with |map-<unique>| by default. Use the
" "overwrite" option of `.WithArgs(…, 1)` if you want to map without <unique>.
"
" @default mode=all of 'n', 'v', and 'o' (Vim's default)
function! maktaba#keymappingspec#Spec(lhs, rhs, ...) abort
  let l:mode = get(a:, 1, '')

  let l:spec = {
      \ '_lhs': a:lhs,
      \ '_rhs': a:rhs,
      \ '_mode': l:mode,
      \ '_args': ['<unique>'],
      \ '_is_noremap': 1,
      \ '_is_bufmap': 0,
      \ 'WithArgs': function('maktaba#keymappingspec#WithArgs'),
      \ 'WithRemap': function('maktaba#keymappingspec#WithRemap'),
      \ 'Map': function('maktaba#keymappingspec#MapSelf'),
      \ 'MapOnce': function('maktaba#keymappingspec#MapSelfOnce'),
      \ 'MapOnceWithTimeout': 
          \ function('maktaba#keymappingspec#MapSelfOnceWithTimeout'),
      \ }
  return l:spec
endfunction


""
" @dict KeyMappingSpec
" Add {args} as |map-arguments| to spec (appended to any already configured on
" spec), or overwrite instead of appending if [overwrite] is passed and is true.
" {args} is a list of strings in the literal syntax accepted by |:map|, such as
" `['<buffer>', '<nowait>']`.
" @default overwrite=0
function! maktaba#keymappingspec#WithArgs(args, ...) dict abort
  let l:should_overwrite = maktaba#ensure#IsBool(get(a:, 1, 0))
  let l:spec = copy(self)
  if l:should_overwrite
    " TODO: Test this case
    let l:spec._args = a:args
  else
    let l:spec._args += a:args
  endif
  if index(a:args, '<buffer>') >= 0
    let l:spec._is_bufmap = 1
  endif
  return l:spec
endfunction


""
" @dict KeyMappingSpec
" Configure whether spec should have nested/recursive mappings {enabled}.
" @throws WrongType
function! maktaba#keymappingspec#WithRemap(enabled) dict abort
  let l:spec = copy(self)
  let l:spec._is_noremap = !maktaba#ensure#IsBool(a:enabled)
  return l:spec
endfunction


""
" @dict KeyMappingSpec.Map
" Define a Vim mapping from spec via the |:map| commands.
function! maktaba#keymappingspec#MapSelf() dict abort
  let l:keymap = maktaba#keymapping#PopulateFromSpec(self)
  call l:keymap._DoMap()
  return l:keymap
endfunction


""
" @dict KeyMappingSpec.MapOnce
" Define a buffer-local one-shot Vim mapping from spec that will only trigger
" once and then unmap itself.
"
" Not supported for recursive mappings.
" @throws NotImplemented if used with `WithRemap(1)`
function! maktaba#keymappingspec#MapSelfOnce() dict abort
  let l:keymap = maktaba#keymapping#PopulateFromSpec(self)
  call l:keymap._DoMapOnce()
  return l:keymap
endfunction


""
" @dict KeyMappingSpec.MapOnceWithTimeout
" Define a short-lived Vim mapping from spec that will only trigger once and
" will also expire if 'timeoutlen' duration expires with 'timeout' setting
" active.
"
" This is useful to detect if the user presses a key immediately after something
" else happens, and respond with a particular behavior.
"
" It can also be used for an improved version of Vim's |map-ambiguous| behavior
" when one mapping is a prefix of another. You can create a prefix mapping that
" does one thing immediately and then a different follow-up behavior on another
" keystroke.
"
" For example, this defines a mapping that immediately unfolds one level but
" unfolds all levels if the ">" keypress is repeated: >
"   nnoremap z> zr:call maktaba#keymappingspec#Spec('>', 'zR', 'n')
"       \.WithArgs(['<buffer>']).MapOnceWithTimeout()<CR>
" <
"
" Caveat: Unlike Vim's |map-ambiguous| behavior, this currently doesn't stop
" waiting for keypresses if another unrelated key is pressed while it's waiting.
" Caveat: For long mappings, you might notice that the timeout is currently for
" the entire mapping and not for each keystroke. If you need to work around that
" you can define a chain of single-key mappings that each map the next key in
" the sequence.
function! maktaba#keymappingspec#MapSelfOnceWithTimeout() dict abort
  let l:keymap = maktaba#keymapping#PopulateFromSpec(self)
  call l:keymap._DoMapOnceWithTimeout()
  return l:keymap
endfunction

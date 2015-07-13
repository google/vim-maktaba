" Sentinel constants used to serialize/deserialize JSON primitives.
if !exists('maktaba#json#NULL')
  let maktaba#json#NULL = {'__json__': 'null'}
  let s:NULL = maktaba#json#NULL
  let maktaba#json#TRUE = {'__json__': 'true'}
  let s:TRUE = maktaba#json#TRUE
  let maktaba#json#FALSE = {'__json__': 'false'}
  let s:FALSE = maktaba#json#FALSE
  lockvar! maktaba#json#NULL maktaba#json#TRUE maktaba#json#FALSE

  let s:DEFAULT_CUSTOM_VALUES = {
      \ 'null': s:NULL, 'true': s:TRUE, 'false': s:FALSE}
endif

" Python implementation:

" Initialize Vim's Python environment with the helpers we'll need.
function! s:InitPython() abort
  python << EOF
import json
import vim


def _maktaba_vim2py_deepcopy(value, null, true, false):
    if isinstance(value, vim.List):
        value = [_maktaba_vim2py_deepcopy(e, null, true, false)
                 for e in value]
    elif isinstance(value, vim.Dictionary):
        # vim.Dictionary doesn't support items() or iter() until 7.3.1061.
        value = {_maktaba_vim2py_deepcopy(k, null, true, false):
                 _maktaba_vim2py_deepcopy(value[k], null, true, false)
                 for k in value.keys()}

    if value == null:
        return None
    if value == true:
        return True
    if value == false:
        return False

    return value


def _maktaba_py2vim_scalar(value, null, true, false):
    if value is None:
        return null
    if value is True:
        return true
    if value is False:
        return false
    return value


def _maktaba_py2vim_list_inplace(value, null, true, false):
    for i in range(len(value)):
        v = value[i]
        if isinstance(v, list):
            _maktaba_py2vim_list_inplace(v, null, true, false)
        elif isinstance(v, dict):
            _maktaba_py2vim_dict_inplace(v, null, true, false)
        else:
            value[i] = _maktaba_py2vim_scalar(v, null, true, false)


def _maktaba_py2vim_dict_inplace(value, null, true, false):
    for k in value:
        # JSON only permits string keys, so there's no need to transform the
        # key, just the value.
        v = value[k]
        if isinstance(v, list):
            _maktaba_py2vim_list_inplace(v, null, true, false)
        elif isinstance(v, dict):
            _maktaba_py2vim_dict_inplace(v, null, true, false)
        else:
            value[k] = _maktaba_py2vim_scalar(v, null, true, false)


def maktaba_json_format():
    buffer = vim.bindeval('l:buffer')
    custom_values = buffer[0]
    value = buffer[1]
    # Now translate the Vim value to something that uses Python types (e.g.
    # None, True, False), based on the custom values we're using.  Note that
    # this must return a copy of the input, as we cannot store None (or True
    # or False) in a Vim value.  (Doing that also avoids needing to tell
    # json.dumps() how to serialize a vim.List or vim.Dictionary.)

    # Note that to do this we need to check our custom values for equality,
    # which we can't do if they're a vim.List or vim.Dictionary.
    # Fortunately, there's an easy way to fix that.
    custom_values = _maktaba_vim2py_deepcopy(custom_values, None, None, None)

    # Now we can use those custom values to translate the real value.
    value = _maktaba_vim2py_deepcopy(
        value,
        custom_values['null'], custom_values['true'], custom_values['false'])
    try:
      buffer[2] = json.dumps(value, allow_nan=False)
    except ValueError as e:  # e.g. attempting to format NaN
      buffer[3] = e.message
    except TypeError as e:  # e.g. attempting to format a Function
      buffer[3] = e.message


def maktaba_json_parse():
    buffer = vim.bindeval('l:buffer')

    custom_values = buffer[0]
    json_str = buffer[1]
    try:
      value = [json.loads(json_str)]
    except ValueError as e:
      buffer[3] = e.message
      return

    # Now mutate the resulting Python object to something that can be stored
    # in a Vim value (i.e. has no None values, which Vim won't accept).
    _maktaba_py2vim_list_inplace(
        value,
        custom_values['null'], custom_values['true'], custom_values['false'])
    buffer[2] = value[0]
EOF
endfunction

" Try to initialize Vim's Python environment. If that fails, we'll use the
" Vimscript implementations instead.

" maktaba#SetJsonPythonDisabled() can be used to skip trying to use the Python
" implementation.
let s:disable_python = maktaba#GetJsonPythonDisabled()
" We require Vim >= 7.3.1042 to use the Python implementation:
"   7.3.569 added bindeval().
"   7.3.996 added the vim.List and vim.Dictionary types.
"   7.3.1042 fixes assigning a dict() containing Unicode keys to a Vim value.
if v:version < 703 || (v:version == 703 && !has('patch1042'))
      \ || s:disable_python
  let s:use_python = 0  " Not a recent Vim, or explicitly disabled
else
  try
    call s:InitPython()
    let s:use_python = 1
  catch /E319:/  " No +python
    let s:use_python = 0
  endtry
endif

" Python implementation of maktaba#json#Format()
function! s:PythonFormat(value) abort
  let l:buffer = [s:DEFAULT_CUSTOM_VALUES, a:value, 0, 0]
  python maktaba_json_format()
  if l:buffer[3] isnot# 0
    throw maktaba#error#BadValue(
        \ 'Value cannot be represented as JSON: %s.', l:buffer[3])
  endif

  return l:buffer[2]
endfunction

" Python implementation of s:ParsePartial()
function! s:PythonParsePartial(json, custom_values) abort
  let l:buffer = [a:custom_values, a:json, 0, 0]
  python maktaba_json_parse()
  if l:buffer[3] isnot# 0
    throw maktaba#error#BadValue(
        \ 'Input is not valid JSON text: %s.', l:buffer[3])
  endif

  return l:buffer[2]
endfunction

" Vimscript implementation:

function! s:Ellipsize(str, limit) abort
  return len(a:str) > a:limit ? a:str[ : a:limit - 4] . '...' : a:str
endfunction

function! s:FormatKeyAndValue(key, value) abort
  if maktaba#value#IsString(a:key)
    return printf('"%s": %s', a:key, maktaba#json#Format(a:value))
  endif
  throw maktaba#error#BadValue(
      \ 'Non-string keys not allowed for JSON dicts: %s.', string(a:key))
endfunction

""
" Formats {value} as a JSON text.
" {value} may be any Vim value other than a Funcref or non-finite Float (or a
" Dictionary or List containing either).
" @throws BadValue if the input cannot be represented as JSON.
function! maktaba#json#Format(value) abort
  if s:use_python
    return s:PythonFormat(a:value)
  endif

  if a:value is s:NULL
    return 'null'
  elseif a:value is s:TRUE
    return 'true'
  elseif a:value is s:FALSE
    return 'false'
  elseif maktaba#value#IsNumeric(a:value)
    let l:json = string(a:value)
    if index(['nan', 'inf', '-nan', '-inf'], l:json) != -1
      throw maktaba#error#BadValue(
          \ 'Value cannot be represented as JSON: %s', l:json)
    endif
    return l:json
  elseif maktaba#value#IsString(a:value)
    let l:escaped = substitute(escape(a:value, '"\'), "\n", '\\n', 'g')
    let l:escaped = substitute(l:escaped, "\t", '\\t', 'g')
    " TODO(dbarnett): Escape other special characters.
    return '"' . l:escaped . '"'
  elseif maktaba#value#IsList(a:value)
    let l:json_items = map(copy(a:value), 'maktaba#json#Format(v:val)')
    return '[' . join(l:json_items, ', ') . ']'
  elseif maktaba#value#IsDict(a:value)
    if maktaba#value#IsCallable(a:value)
      throw maktaba#error#BadValue(
          \ 'Funcdict for func %s cannot be represented as JSON.',
          \ string(a:value.func))
    endif
    let l:json_items =
        \ map(items(a:value), 's:FormatKeyAndValue(v:val[0], v:val[1])')
    return '{' . join(l:json_items, ', ') . '}'
  endif
  throw maktaba#error#BadValue(a:value)
endfunction

function! s:Consume(str, count) abort
  return maktaba#string#StripLeading(a:str[a:count : ])
endfunction

function! s:ParsePartial(json, custom_values) abort
  " null, true, or false
  if a:json =~# '\m^null\>'
    let l:value = a:custom_values.null
    return [l:value, s:Consume(a:json, 4)]
  endif
  if a:json =~# '\m^true\>'
    let l:value = a:custom_values.true
    return [l:value, s:Consume(a:json, 4)]
  endif
  if a:json =~# '\m^false\>'
    let l:value = a:custom_values.false
    return [l:value, s:Consume(a:json, 5)]
  endif
  " Number
  " TODO(dbarnett): Handle scientific notation.
  let l:num_match = matchstr(a:json, '\v^-?[0-9]+(\.[0-9]+)?>')
  if !empty(l:num_match)
    return [eval(l:num_match), s:Consume(a:json, len(l:num_match))]
  endif
  " String
  let l:str_match = matchstr(a:json, '\v^"([^\\"]|\\.)*"')
  if !empty(l:str_match)
    " JSON strings use the same syntax as JSON strings.
    " TODO(dbarnett): Handle special escape sequences like \uxxxx.
    let l:value = eval(l:str_match)
    return [l:value, s:Consume(a:json, len(l:str_match))]
  endif
  " First character if any, empty string otherwise.
  let l:first_char = a:json[0:0]
  " List
  if l:first_char is# '['
    let [l:items, l:remaining] = s:ParseListPartial(a:json, a:custom_values)
    return [l:items, l:remaining]
  endif
  " Dict
  if l:first_char is# '{'
    let [l:dict, l:remaining] = s:ParseDictPartial(a:json, a:custom_values)
    return [l:dict, l:remaining]
  endif
  throw maktaba#error#BadValue('Input is not valid JSON text.')
endfunction

function! s:ParseListPartial(json, custom_values) abort
  let l:remaining = s:Consume(a:json, 1)
  if l:remaining[0:0] is# ']'
    return [[], s:Consume(l:remaining, 1)]
  endif
  let l:items = []
  while !empty(l:remaining)
    " Parse and consume one value as the next list item.
    let [l:item, l:remaining] = s:ParsePartial(l:remaining, a:custom_values)
    call add(l:items, l:item)
    unlet l:item
    " If next character is "]", consume and finish list.
    if l:remaining[0:0] is# ']'
      let l:remaining = s:Consume(l:remaining, 1)
      break
    endif
    " Only other acceptable character is comma. Consume and continue.
    if l:remaining[0:0] isnot# ','
      throw maktaba#error#BadValue(
          \ 'Junk after JSON array item: %s', s:Ellipsize(l:remaining, 30))
    endif
    let l:remaining = s:Consume(l:remaining, 1)
  endwhile
  return [l:items, l:remaining]
endfunction

function! s:ParseDictPartial(json, custom_values) abort
  let l:remaining = s:Consume(a:json, 1)
  if l:remaining[0:0] is# '}'
    return [{}, s:Consume(l:remaining, 1)]
  endif
  let l:dict = {}
  while !empty(l:remaining)
    " Parse and consume one value as the key.
    let [l:key, l:remaining] = s:ParsePartial(l:remaining, a:custom_values)
    if !maktaba#value#IsString(l:key)
      throw maktaba#error#BadValue(
          \ 'Non-string keys not allowed for JSON dicts: %s.', string(l:key))
    endif
    " Consume separating ":".
    if l:remaining[0:0] isnot# ':'
      throw maktaba#error#BadValue(
          \ 'Junk after JSON key: %s', s:Ellipsize(l:remaining, 30))
    endif
    let l:remaining = s:Consume(l:remaining, 1)
    " Parse and consume one value as the item value.
    let [l:value, l:remaining] = s:ParsePartial(l:remaining, a:custom_values)
    let l:dict[l:key] = l:value
    unlet l:value

    " If next character is "}", consume and finish list.
    if l:remaining[0:0] is# '}'
      let l:remaining = s:Consume(l:remaining, 1)
      break
    endif
    " Only other acceptable character is comma. Consume and continue.
    if l:remaining[0:0] isnot# ','
      throw maktaba#error#BadValue(
          \ 'Junk after JSON object item: %s', s:Ellipsize(l:remaining, 30))
    endif
    let l:remaining = s:Consume(l:remaining, 1)
  endwhile
  return [l:dict, l:remaining]
endfunction

function! s:SetDifference(a, b) abort
  let l:difference = []
  for l:a_item in a:a
    if index(a:b, l:a_item) == -1
      call add(l:difference, l:a_item)
    endif
  endfor
  return l:difference
endfunction

""
" Parses the JSON text {json} to a Vim value. If [custom_values] is passed, it
" is a dictionary mapping JSON primitives (in string form) to custom values to
" use instead of maktaba#json# sentinels. For example: >
"   let value = maktaba#json#Parse('[null]', {'null': ''})
" <
" @throws WrongType if {json} is not a string or [custom_values] is not a dict.
" @throws BadValue if {json} is not a valid JSON text.
" @throws BadValue if [custom_values] keys are invalid JSON primitive names.
function! maktaba#json#Parse(json, ...) abort
  let l:json = maktaba#string#Strip(maktaba#ensure#IsString(a:json))
  let l:custom_values = maktaba#ensure#IsDict(get(a:, 1, {}))
  if empty(l:custom_values)  " common case
    let l:custom_values = s:DEFAULT_CUSTOM_VALUES
  else
    let l:custom_values = copy(l:custom_values)
    call extend(l:custom_values, s:DEFAULT_CUSTOM_VALUES, 'keep')
  endif
  " Ensure custom values only has 'null', 'true', or 'false' as keys.
  let l:allowed_custom_keys = ['null', 'true', 'false']
  let l:unrecognized_custom_keys =
      \ s:SetDifference(keys(l:custom_values), l:allowed_custom_keys)
  if !empty(l:unrecognized_custom_keys)
    throw maktaba#error#BadValue(
        \ 'Invalid JSON primitive name(s) in custom_values: %s',
        \ join(l:unrecognized_custom_keys, ', '))
  endif

  if s:use_python
    return s:PythonParsePartial(a:json, l:custom_values)
  endif

  let [l:value, l:remaining] = s:ParsePartial(l:json, l:custom_values)
  if empty(l:remaining)
    return l:value
  endif
  throw maktaba#error#BadValue('Input is not valid JSON text.')
endfunction

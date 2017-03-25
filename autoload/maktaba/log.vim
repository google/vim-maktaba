if !exists('s:log_queue')
  let s:log_queue = []
endif

if !exists('s:truncation_count')
  let s:truncation_count = 0
endif

""
" The enumeration dict encapsulating the list of logging levels.
let maktaba#log#LEVELS = maktaba#enum#Create([
    \ 'DEBUG',
    \ 'INFO',
    \ 'WARN',
    \ 'ERROR',
    \ 'SEVERE',
    \ ])
lockvar! maktaba#log#LEVELS

let s:LEVELS = maktaba#log#LEVELS

if !exists('s:notification_level')
  let s:notification_level = s:LEVELS.WARN
endif


""
" @usage {level} {context} {message} [args...]
" Sends a log {message} to the log at {level} on behalf of {context}.
" Extra [args...] are rendered into {message} using |printf()|.
function! s:DoMessage(level, context, message, ...) abort
  call maktaba#ensure#IsNumber(a:level)
  call maktaba#ensure#IsString(a:context)
  call maktaba#ensure#IsString(a:message)
  if len(a:000)
    let l:message = call('printf', [a:message] + a:000)
  else
    let l:message = a:message
  endif

  call s:SendToHandlers([a:level, localtime(), a:context, l:message])
  if s:notification_level isnot -1 && a:level >= s:notification_level
    call s:NotifyMessage(printf('[%s] %s', a:context, l:message), a:level)
  endif
endfunction


""
" Append {logitem} to s:log_queue and pass to handlers.
function! s:SendToHandlers(logitem) abort
  let l:maktaba = maktaba#Maktaba()
  " Append to s:log_queue.
  call add(s:log_queue, a:logitem)
  " Vim's 'history' setting controls the length of several history queues. Use
  " it to also control the length of the internal log message queue.
  if len(s:log_queue) > &history
    " Truncate leaving headroom for truncation message.
    let l:truncated_logs =
        \ remove(s:log_queue, 0, len(s:log_queue) - &history)
    let s:truncation_count += len(l:truncated_logs)
    let l:truncation_timestamp = l:truncated_logs[-1][1]
    let l:truncation_msg = printf(
        \ '%s messages not available because logging was configured late.',
        \ s:truncation_count)
    call insert(
        \ s:log_queue,
        \ [s:LEVELS.INFO, l:truncation_timestamp, 'maktaba', l:truncation_msg],
        \ 0)
  endif

  " Send to handlers.
  for l:Handler in l:maktaba.globals.loghandlers.Items()
    call maktaba#function#Call(l:Handler, a:logitem)
  endfor
endfunction


function! s:NotifyMessage(message, level) abort
  if a:level >= s:LEVELS.ERROR
    call maktaba#error#Shout(a:message)
  elseif a:level >= s:LEVELS.WARN
    call maktaba#error#Warn(a:message)
  else
    echomsg a:message
  endif
endfunction


""
" Sets the minimum {level} that will be immediately shown to the user using
" @function(maktaba#error#Warn) or @function(maktaba#error#Shout). The
" notification level defaults to WARN if it was never explicitly configured.
" If {level} is -1, notifications will be disabled entirely.
" @throws BadValue
function! maktaba#log#SetNotificationLevel(level) abort
  call maktaba#ensure#IsTrue(
      \ a:level is -1 || maktaba#value#IsIn(a:level, s:LEVELS.Values()),
      \ 'Expected {level} to be maktaba#log#LEVELS value or -1')
  let s:notification_level = a:level
endfunction


""
" @dict Logger
" Interface for a plugin to send log messages to maktaba.


""
" Creates a @dict(Logger) interface for {context}.
function! maktaba#log#Logger(context) abort
  return {
      \ '_context': a:context,
      \ 'Debug': function('maktaba#log#Debug'),
      \ 'Info': function('maktaba#log#Info'),
      \ 'Warn': function('maktaba#log#Warn'),
      \ 'Error': function('maktaba#log#Error'),
      \ 'Severe': function('maktaba#log#Severe'),
      \ }
endfunction


""
" @dict Logger
" Logs a {message} with [args...] at DEBUG level.
function! maktaba#log#Debug(message, ...) dict abort
  call call('s:DoMessage', [s:LEVELS.DEBUG, self._context, a:message] + a:000)
endfunction


""
" @dict Logger
" Logs a {message} with [args...] at INFO level.
function! maktaba#log#Info(message, ...) dict abort
  call call('s:DoMessage', [s:LEVELS.INFO, self._context, a:message] + a:000)
endfunction


""
" @dict Logger
" Logs a {message} with [args...] at WARN level.
function! maktaba#log#Warn(message, ...) dict abort
  call call('s:DoMessage', [s:LEVELS.WARN, self._context, a:message] + a:000)
endfunction


""
" @dict Logger
" Logs a {message} with [args...] at ERROR level.
function! maktaba#log#Error(message, ...) dict abort
  call call('s:DoMessage', [s:LEVELS.ERROR, self._context, a:message] + a:000)
endfunction


""
" @dict Logger
" Logs a {message} with [args...] at SEVERE level.
function! maktaba#log#Severe(message, ...) dict abort
  call call('s:DoMessage', [s:LEVELS.SEVERE, self._context, a:message] + a:000)
endfunction


""
" @usage {handler} [fire_recent]
" Registers {handler} to receive log messages. {handler} must refer to a
" function that takes 4 arguments: level (number), timestamp (number),
" context (string), and message (string).
"
" If [fire_recent] is 1 and messages have already been logged before a handler
" is added, some recent messages may be passed to the handler as soon as it's
" registered. The number of messages stored is controlled by vim's 'history'
" setting.
"
" This function returns a function which, when applied, unregisters {handler}.
" Hold on to it if you expect you'll need to remove {handler}.
" @default fire_recent=0
function! maktaba#log#AddHandler(Handler, ...) abort
  let l:maktaba = maktaba#Maktaba()
  call maktaba#ensure#IsCallable(a:Handler)
  let l:fire_recent = maktaba#ensure#IsBool(get(a:, 1, 0))
  let l:remover = l:maktaba.globals.loghandlers.Add(a:Handler)
  if l:fire_recent
    " Send recent queued messages to handler.
    for l:logitem in s:log_queue
      call maktaba#function#Call(a:Handler, l:logitem)
    endfor
  endif
  return l:remover
endfunction

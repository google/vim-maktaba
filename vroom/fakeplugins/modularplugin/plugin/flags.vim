let [s:plugin, s:enter] = maktaba#plugin#Enter(expand('<sfile>:p'))
if !s:enter
  finish
endif

echomsg 'The flags file is sourced on first flag access if not already loaded.'

call s:plugin.Flag('plugin[optin]', 0)

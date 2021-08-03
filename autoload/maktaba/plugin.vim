let s:maktaba = maktaba#Maktaba()

""
" @private
" Used by maktaba#library to help throw good error messages about non-library
" directories.
function! maktaba#plugin#NonlibraryDirs() abort
  return maktaba#internal#plugin#NonlibraryDirs()
endfunction

""
" This function is used to both control when plugin files are entered, and get
" a handle to the current plugin object. It should be called from the top of
" an autoload/*.vim, plugin/*.vim, ftplugin/*.vim, or instant/*.vim file as
" follows:
" >
"   let [s:plugin, s:enter] = maktaba#plugin#Enter(expand('<sfile>:p'))
"   if !s:enter
"     finish
"   endif
" <
" The result is a tuple containing the plugin object and a boolean specifying
" whether the file should be entered (taking user preferences and whether the
" file has already been sourced into account). If the second value is false, the
" script should finish immediately.
"
" autoload/*.vim files are entered on demand (see |autoload|), this function
" only helps prevent re-entry.
"
" For plugin/*.vim and instant/*.vim files, maktaba ensures that the file is
" only entered once, and then only if the user has not disabled the file via
" the plugin[*] or instant[*] flags.
"
" In ftplugin/*.vim files, maktaba ensures that the file is loaded only once per
" buffer.
"
" Note that maktaba does NOT set the g:loaded_{plugin} variable, as recommended
" in the write-plugin helpfiles. This is because maktaba plugins may span
" multiple files, and there is no clear moment when the plugin is "loaded". If
" you feel you must adhere to this convention, be sure to set the appropriate
" g:loaded_* variable when appropriate.
function! maktaba#plugin#Enter(file) abort
  return maktaba#internal#plugin#Enter(a:file)
endfunction


""
" Scans 'runtimepath' for any unregistered plugins and registers them with
" maktaba. May trigger instant/ hooks for newly-registered plugins.
function! maktaba#plugin#Detect() abort
  return maktaba#internal#plugin#Detect()
endfunction


""
" A list of all installed plugins in alphabetical order.
" Automatically detects unregistered plugins using @function(#Detect).
function! maktaba#plugin#RegisteredPlugins() abort
  return maktaba#internal#plugin#RegisteredPlugins()
endfunction


""
" 1 if {plugin} was registered with maktaba#plugin#Register.
" This is more reliable for determining if a Maktaba compatible plugin by
" the name of {plugin} was registered, but can not be used to dependency check
" non-Maktaba plugins.
" Detects plugins added to 'runtimepath' even if they haven't been explicitly
" registered with maktaba.
function! maktaba#plugin#IsRegistered(plugin) abort
  return maktaba#internal#plugin#IsRegistered(a:plugin)
endfunction


""
" The canonical name of {plugin}.
" This is the name of the plugin directory with any "vim-" prefix or ".vim"
" suffix stripped off: both "vim-unimpaired" and "unimpaired.vim" would become
" simply "unimpaired".
"
" Note that plugins with different names in the filesystem can conflict in
" maktaba. If you've loaded a plugin in the directory "plugins/vim-myplugin"
" then maktaba can't handle a plugin named "plugins/myplugin". Make sure your
" plugins have sufficiently different names!
function! maktaba#plugin#CanonicalName(plugin) abort
  return maktaba#internal#plugin#CanonicalName(a:plugin)
endfunction


""
" @usage dir [settings]
" Installs the plugin located at {dir}. Installation entails adding the plugin
" to the runtimepath, loading its flags.vim file, and sourcing any files in its
" instant/ directory.
"
" Returns the maktaba plugin object describing the installed plugin.
"
" {dir} should be the full path to the plugin directory. The plugin itself
" should be the last component in the directory path. If the plugin doesn't have
" an explicit name declared in addon-info.json, the plugin name will be the name
" of this directory with all invalid characters converted to underscores (see
" @function(#CanonicalName)).
"
" If the plugin contains a plugin/ directory it will have a special "plugin"
" dictionary flag that controls which plugin files are loaded. For example, if
" the plugin contains plugin/commands.vim, you can use
" >
"   let plugin = maktaba#plugin#Install(path)
"   call plugin.Flag('plugin[commands]', 0)
" <
" to disable it. More generally, "plugin" is a dictionary whose keys control the
" loading of plugin files. A file's key is its filename without the '.vim'
" extension. Set the key to 0 to prevent the file from loading or 1 to allow it
" to load.
"
" Note that setting the key to 1 only ALLOWS the file to load: if load time has
" already passed, enabling the plugin file will not cause it to load. To load
" plugin files late use |Plugin.Load|.
"
" All plugin files are loaded by default EXCEPT the file plugin/mappings.vim,
" which is opt-in. (Set plugin[mappings] to 1 to enable.)
"
" If the plugin contains an instant/ directory it will also have a special
" "instant" flag, which acts similarly to the special "plugin" flag for
" instant/*.vim files. For example, in a plugin with an instant/earlyfile.vim,
" the following DOES NOT WORK:
" >
"   let plugin = maktaba#plugin#Install(path)
"   call plugin.Flag('instant[earlyfile]', 0)
" <
" All instant/*.vim files are sourced during installation. In order to configure
" the "instant" flag, you must pass [settings] to the installation function. If
" given, they must be a list of maktaba settings (see |maktaba#setting#Create|).
" They will be applied after instant/flags.vim is sourced (if present), but
" before any other instant files are sourced. For example:
" >
"   let noearly = maktaba#setting#Parse('instant[earlyfile]=0')
"   let plugin = maktaba#plugin#Install(path, [noearly])
" <
" @throws BadValue if {dir} is empty.
" @throws AlreadyExists if the plugin already exists.
" @throws ConfigError if [settings] cannot be applied to this plugin.
function! maktaba#plugin#Install(dir, ...) abort
  return call('maktaba#internal#plugin#Install', [a:dir] + a:000)
endfunction


""
" Gets the plugin object associated with {plugin}. {plugin} may either be the
" name of the plugin directory, or the canonicalized plugin name (with any
" "vim-" prefix or ".vim" suffix stripped off). See @function(#CanonicalName).
" Detects plugins added to 'runtimepath' even if they haven't been explicitly
" registered with maktaba.
" @throws NotFound if the plugin object does not exist.
function! maktaba#plugin#Get(name) abort
  return maktaba#internal#plugin#Get(a:name)
endfunction


""
" Installs the plugin located at {dir}, unless it already exists. The
" appropriate maktaba plugin object is returned.
"
" [settings], if given, must be a list of maktaba settings (see
" |maktaba#setting#Create|). If the plugin is new, they will be applied as in
" @function(#Install). Otherwise, they will be applied before returning the
" plugin object.
"
" See also @function(#Install).
" @throws AlreadyExists if the existing plugin comes from a different directory.
" @throws ConfigError if [settings] cannot be applied to this plugin.
function! maktaba#plugin#GetOrInstall(dir, ...) abort
  return call('maktaba#internal#plugin#GetOrInstall', [a:dir] + a:000)
endfunction

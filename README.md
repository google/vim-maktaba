Maktaba is a vimscript plugin library. It is designed for plugin authors.
Features include:

* Plugin objects (for manipulating plugins in vimscript)
* Plugin flags (used to configure plugins without global settings)
* Universal logger interface
* Dependency management tools
* Real closures

Maktaba advocates a plugin structure that, when adhered to, gives the plugin
access to many powerful tools such as configuration flags. Within Google, these
conventions standardize behavior across a wide variety of plugins.

Also contained are many utility functions that ease the pain of working with
vimscript. This includes, among other things:

* Exception handling
* Variable type enforcement
* Filepath manipulation

# Usage example

Maktaba plugins can be installed using any plugin manager. However, maktaba
plugins make heavy use of dependency management, so it's recommended to use a
plugin manager with dependency management capabilities, like
[VAM](https://github.com/MarcWeber/vim-addon-manager).

Installation of a few plugins using VAM looks something like
```vim
set runtimepath+=~/.vim/bundle/vim-addon-manager/
" Loads glaive, vtd, and their maktaba dependency.
call vam#ActivateAddons(['glaive', 'vtd'])
" Initializes all maktaba plugins.
call maktaba#plugin#Detect()
```

# Further reading

In the `vroom/` directory you'll find literate test files that walk you through
maktaba features in depth. `vroom/main.vroom` is a good place to start.

In the `examples/` directory you can find an example maktaba plugin to give you
a feel for how maktaba plugins look.

In the `doc/` directory you'll find helpfiles for maktaba. These are also
available via `:help maktaba` if maktaba has been installed and helptags have
been generated. The help files document the maktaba API in its entirety.

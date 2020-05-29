# Maktaba UI Elements

This directory contains several useful helpers for creating UI helpers with
Maktaba. Beyond the [Vim Style
guide](https://google.github.io/styleguide/vimscriptguide.xml), these UI
elements are designed with several principles in mind:

1. **Cross-compatible**: They should be generally useful for both terminal-vim
   and GUI vim implementations.
1. **Graceful fallback**: UI elements may use modern Vim ui elements like
   popups, but should have graceful fallback for when these elements are not
   supported.
1. **Quick**: Elements should be quick to load and quick to close. Vim is all
   about speed; users should not need to manage the UI elements.

# Walkthrough

Below is a walkthrough of the various elements supported by Maktaba.

## Selector Window

* **Description**: The Selector Window is a way to provide a quick window for
  selecting text. It can be used as a replacement for quickfix or
  locationlist, adding several quality of life improvements on those ui
  elements, while adding much more customizability.

* **Status**: In Development

* **Usage**:

  ```vim
  let l:text = [
    \ 'line one',
    \ 'line two',
    \ 'line three ' ]

  call maktaba#ui#selector#Create(l:text).Show()
  ```

* **Other Links**:

  * Help Docs: `:h selector`
  * Vroom Examples: [Vroom tests](../../../vroom/selector.vroom)

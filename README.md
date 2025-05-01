# Fruitilities
Fruitilities is a set of Lua libraries to assist in game development.

The libraries are written in vanilla Lua (specifically 5.1 and LuaJIT, but should be compatible with newer versions), but all graphics-related functionality is dependent on your environment.

In [LÖVE](https://love2d.org/), graphics work out of the box, but for any other use, if you intend to make use of the libraries rendering anything, you have to implement the functionality for it yourself.
The libraries make it easy enough by exposing all rendering-related functions into a table in `<library>.graphics`, which you can overwrite with your specific implementations.

Outside of LÖVE, the libraries all still work with no tweaks needed, but the rendering functions simply won't do anything.

## Documentation

TBA im sorry im busy ☹️

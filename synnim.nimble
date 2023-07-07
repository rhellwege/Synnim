# Package

version       = "0.1.0"
author        = "Ryan Hellwege"
description   = "synthesizer"
license       = "MIT"
srcDir        = "src"
bin           = @["synnim"]


# Dependencies

requires "nim >= 1.9.5", "naylib", "sdl2"

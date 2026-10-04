# Building Tux Racer Modern

## macOS Apple Silicon
The current reference platform is macOS on Apple Silicon ARM64, validated on an M5 Max.

Install Apple Command Line Tools and Homebrew dependencies:

```sh
xcode-select --install
brew install cmake sdl2 sdl2_mixer tcl-tk
```

Build and run:

```sh
./scripts/bootstrap-macos.sh
./build/tuxracer
```

The development build discovers the repository `data/` directory automatically when the configured historical `/usr/local/share/tuxracer` path is unavailable.

## Linux
Linux validation is part of the v0.1.x preservation work. CMake is the canonical build system. SDL2, SDL2_mixer, Tcl, OpenGL development headers and C/C++ build tools are required.

## Windows
Windows is a supported target but lower priority than macOS and Linux during early modernization. The renderer architecture must remain portable even while Metal is developed first.

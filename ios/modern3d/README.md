# Modern iOS 3D vertical slice

This directory is a clean-slate iOS gameplay experiment, **not** the original Tux Racer engine or preservation project.

Run with the CMake option `-DTUX_IOS_MODERN3D=ON` (enabled by default on `feature/ios-modern-3d`). The last working 2.5D SDL renderer remains selectable via `-DTUX_IOS_MODERN3D=OFF`.

## First milestone
- Use the proven SDL2 / UIKit UIScene bootstrap to create an actual CAMetalLayer
- Render a 3D downhill course with a depth buffer, real perspective projection, shading, and a mobile-friendly render loop
- Parse `course.json` as the first data-driven course definition; **this initial slice uses only course length, width, slope and speeds**
- Provide steering and braking using touch zones and keyboard, with a simple course-following placeholder player
- Keep course assets and rendering source entirely outside the macOS preservation release

## Planned game content
The next gates are a rigged/high-resolution Tux mesh, a genuine glTF / asset conversion pipeline, materials and lighting, fish and collision, 3D trees, course authoring, clothing/hat attachment points, animations and saved race results.

Avoid confusing a 3D rendering slice with a finished game. It does not yet include the original code-driven physics or modern authored models.

## Simulator build

```sh
cd ~/Desktop/tuxracer-modern-github
git fetch origin
git switch feature/ios-modern-3d
git pull --ff-only origin feature/ios-modern-3d
sh ios/build-xcode.sh iphonesimulator
open "$HOME/Library/Caches/tuxracer-modern-ios/iphonesimulator/TuxRacerModernIOS.xcodeproj"
```

Because the build directory is shared with the previous branch, the CMake
cache can be made explicit with:

```sh
cmake -S ios -B "$HOME/Library/Caches/tuxracer-modern-ios/iphonesimulator" \
  -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DTUX_IOS_MODERN3D=ON \
  -DTUX_IOS_METAL_SMOKE=OFF
```

Expected first result: a native 3D snow-covered slope and a small
procedurally modeled 3D penguin, not the old 2D overlay. This new slice has
**not been compiled or simulator-tested on the developer's machine**.
On a linker/compiler failure, collect the first error (not only the final
`clang` summary). The original iOS prototype is selectable with
`-DTUX_IOS_MODERN3D=OFF`.

### Input
- Left/right arrow keys, A/D, or hold left/right sides of the touchscreen to steer
- Down arrow, S, or hold the lower center of the touchscreen to brake
- R restarts the initial camera position and speed

### Content strategy
- New authored courses are defined in versioned JSON, then compiled into
  efficient runtime terrain and object buffers.
- New character and scenery assets are authored separately, with rigged,
  textured models replacing the procedural penguin.
- The original macOS preservation branch remains unchanged.

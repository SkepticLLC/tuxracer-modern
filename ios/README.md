# iOS Metal smoke target

This is the first native rendering bootstrap for iPhone. It draws a dark blue Metal frame via SDL2; it does **not** compile or run the Tux Racer game yet.

## Requirements
- macOS with Xcode and an installed iOS SDK
- SDL2 iOS-compatible XCFramework or SDL2 iOS source target
- iOS device or simulator with Metal support

## Integrating in Xcode
1. Create an iOS App project named **Tux Racer Modern iOS** (Objective-C language, UIKit lifecycle), landscape orientations only.
2. Add `metal_smoke_main.m` to the application target, and remove the generated `main.m` so only one entry point exists.
3. Add SDL2's iOS-compatible library/framework and headers, including its iOS application bootstrap. **Do not** use a macOS SDL2 Homebrew binary.
4. Link `Metal.framework`, `QuartzCore.framework`, `Foundation.framework`, and SDL2's required iOS frameworks.
5. Make sure the SDL2 header search path supports `#include <SDL.h>` and `#include <SDL_metal.h>`.
6. Configure `UIApplicationSceneManifest`/scene lifecycle according to the selected SDL2 release; avoid a conflicting UIKit app delegate.
7. Build and run. Expected result: a landscape dark-blue Metal screen, not gameplay.

## Exit criteria
- Simulator and physical device compile and launch.
- Metal drawable matches device native resolution.
- Touch and game controller events are delivered through SDL2.
- Background and foreground transitions do not crash or leak rendering resources.

## Known limitations
- The smoke main exits on background; the production game must instead pause and resume.
- This initial smoke target has no signed, checked-in .xcodeproj and is not a one-click build.
- The legacy game engine remains dependent on OpenGL/GLU, and must not be linked into this Metal-only target until renderer separation is complete.
- Exact SDL2 framework/bootstrap setup depends on the pinned SDL2 version. Pin that version before generating the production Xcode project.

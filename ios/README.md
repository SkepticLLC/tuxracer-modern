# Tux Racer Modern — iOS 26+ Metal bootstrap

Status: **interactive downhill prototype** by default on SDL2's Metal renderer.
This is a playable *control sandbox*, **not yet the original Tux Racer engine,
physics, character model, or original Tcl courses**. The tested dark-blue
Metal smoke app remains available using `-DTUX_IOS_METAL_SMOKE=ON`.
The macOS preservation build is unaffected.

## iOS 27 SDK: UIScene lifecycle migration

Apple requires UIScene lifecycle support for applications built with the iOS 27
SDK. Unmodified SDL2 2.32.x still uses the older UIKit launch path, and fails
at startup with `UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`.

The repository includes an **isolated, source-pinned compatibility bridge**:

- `Info.plist` declares a single `UIWindowScene` and `TuxSceneDelegate`.
- `scene_lifecycle.m` adds the UIKit scene-configuration callback to SDL2's
  existing application delegate and starts SDL_main only after scene connection.
- `patch-sdl2-scene.cmake` applies a checked two-file SDL2 source adaptation to
  the **fetched build checkout** (not the macOS source or upstream repository):
  it defers the legacy launch callback, disables the unattached SDL2 splash
  window, and creates SDL2's UIWindow via `initWithWindowScene`.
- The smoke renderer pauses when the scene enters the background.

This is a compatibility backport, not an upstream SDL2 feature. It must be
revalidated when SDL2 is updated or before App Store packaging.

Run the fast static check before compiling:

```sh
sh ios/check-scene-setup.sh
```

The script validates the plist, integration references, and populated SDL2
source patches without rebuilding the game. `sh ios/build-xcode.sh
iphonesimulator` applies/reapplies patches during CMake configuration.


## Supported platform / dependency baseline

- Minimum device and simulator OS: **iOS 26.0**.
- Target testing SDK/runtime: **iOS 27.0** (also test an iOS 26 runtime).
- SDL2: pinned to upstream **release-2.32.10**, built as a static dependency.
- SDL Metal: enabled. **OpenGL ES and Vulkan backends disabled** for iOS.
- Xcode plus CMake >= 3.24; network access on first configure.

The old `15.0` deployment target was accidental and has been corrected in
both the CMake target and the project-generator script. SDK version and minimum
OS version are separate: compiling with SDK 27 does not imply requiring 27.

## Verify the previous signing failure *without recompiling*

If an older, already-linked simulator `.app` exists, run:

```sh
sh ios/repair-simulator-signing.sh
```

This prints extended attributes on the **existing build product**, strips only
those bundle attributes, ad-hoc signs the simulator app, and verifies its
signature. It deliberately never modifies the source checkout. If this works,
it confirms that the previous failure was invalid extended attributes rather
than a compiler, linker, certificate, or provisioning problem.

## Generate the new iOS 26+ Xcode project

From the root of the repository:

```sh
sh ios/build-xcode.sh iphonesimulator
open "$HOME/Library/Caches/tuxracer-modern-ios/iphonesimulator/TuxRacerModernIOS.xcodeproj"
```

For physical iPhone testing:

```sh
sh ios/build-xcode.sh iphoneos
open "$HOME/Library/Caches/tuxracer-modern-ios/iphoneos/TuxRacerModernIOS.xcodeproj"
```

The project-generation script prints its final project path. Generated files
are intentionally outside Desktop/iCloud-managed source directories to reduce
Apple extended-attribute contamination. To override the build location, set
`TUXRACER_IOS_BUILD_ROOT` before generating.

Select the `TuxRacerModernIOS` scheme. Run on an iOS 27 (or iOS 26)
simulator. Physical device builds need a valid development team selected in
Xcode; simulator builds use local ad-hoc signing.

## Automated signing safeguards

1. `prepare-signing.sh` runs from the generated Xcode target's **PRE_LINK**
   phase to recursively clear extended attributes on the generated app bundle.
2. On host versions of `codesign` supporting `--strip-disallowed-xattrs`,
   CMake configures that code-signing flag as a second line of defense.
3. Build products live under the user's Library Caches directory, not Desktop.
4. The one-shot `repair-simulator-signing.sh` can inspect and repair an already
   compiled simulator app without rebuilding.

These protect generated artifacts only. Do **not** run `xattr -cr .` against
the entire repository, and do not disable signing for distributable device
builds. If code signing still fails, capture the offending app's
`xattr -lr /path/to/TuxRacerModernIOS.app` output.

Apple reference: Technical Q&A QA1940 on resource-fork/Finder information.

## Warning cleanup strategy

The previous SDK 27 log showed hundreds of SDL2 warnings, overwhelmingly from
its deprecated OpenGL ES/EAGL render implementation. The new iOS configuration
does not compile either OpenGL ES renderer; it uses Metal instead. SDL2 was
updated from 2.30.12 to 2.32.10 for maintenance fixes.

Some SDL2 UIKit/legacy GameController deprecation warnings may remain. Those
are not errors; do not globally suppress warnings or modify Apple SDK headers.
Track them separately for the next dependency/platform cleanup.

## Exit criteria

- Xcode project configures with iOS 26.0 minimum.
- SDL2, UIKit host, and Metal smoke target compile and link.
- Xcode signs and launches the app on iOS 27 simulator.
- Screen clears dark blue in landscape without crash.
- Physical iOS 26+ device test follows once simulator is stable.
- SDL2 source warning count is reduced; any remaining warnings are categorized.

The interactive prototype and smoke source pause on background. Original
physics/gameplay, Tcl, bundled courses/assets, audio
interruptions, safe areas, touch/game-controller action mapping, and more
complete scene restoration are separate future implementation gates.

## Original Bunny Hill data integration — first engine port slice

The iOS build now bundles the complete, unmodified original `data/` directory
inside `TuxRacerModernIOS.app/data`. The native `original_course.c` parser
reads the original `data/courses/bunny_hill/course.tcl` at runtime and passes
Bunny Hill's playable length (470 meters) to the existing race timer, progress
bar and finish state. Its 90m x 480m dimensions, 25-degree course angle and
`elev.rgb` / `terrain.rgb` filenames are also loaded, but their bitmap
contents are **not yet decoded or used to render terrain**.

This is a compatibility milestone rather than a completed original-engine port.
The downhill movement and course visuals remain the interim prototype.

The metadata parsing test runs without an iOS build:

```sh
sh ios/test-original-course.sh
```

It checks the actual unmodified Bunny Hill file from the repository. The iOS
debug console will log `Loaded ORIGINAL course metadata` on successful load,
or explicitly warn that the app bundle lacks the source course.

After the host test succeeds, generate the Xcode project as before and launch
on the iOS 27 simulator. The header should read
`BUNNY HILL - ORIGINAL COURSE DATA` and finishing should occur at the real
470-meter playable length. If the header still says `MOBILE PROTOTYPE`,
check bundle copy execution and the SDL_GetBasePath debug warning.

**Next port slices:** decode original SGI RGB elevation and terrain maps,
then connect sampling/collisions and eventually the original physics module
plus embedded Tcl. Keep the macOS preservation release isolated.

## Playable control prototype (next development gate)

The default `TuxRacerModernIOS` app now runs `ios/prototype_race.c` instead of
`metal_smoke_main.m`. It uses `SDL_CreateRenderer` with the Metal driver,
imports the existing cross-platform `src/platform/mobile_input.c` abstraction,
and provides an interactive downhill race with a finish line, timer, touch
steering, braking, jumping, collisions and score. It is a deliberately small
throwaway **playability test** while the original OpenGL-dependent renderer,
physics and Tcl are ported. No claim of original gameplay parity is made.

**Controls:** hold the lower-left or lower-right overlay to steer; tap/hold
center to jump; press lower center edge to brake. In the simulator keyboard:
left/right or A/D steer, Space/up jumps, S/down brakes, P or Escape pauses,
R restarts. Game controllers: left stick steer, A jump, B brake.

**Launch:**

```sh
sh ios/build-xcode.sh iphonesimulator
open "$HOME/Library/Caches/tuxracer-modern-ios/iphonesimulator/TuxRacerModernIOS.xcodeproj"
```

Select a concrete iOS 27 simulator destination and press Command+R. The screen
should show a TUX RACER - MOBILE PROTOTYPE header, track, moving penguin,
controls, timer and progress bar. Expect warnings from SDL2 dependency code;
report fatal compile/link errors separately. This new target has **not yet been
built on the developer's iOS 27 Xcode SDK**.

To return to the known-good original dark-blue smoke target:

```sh
cmake -S ios -B "$HOME/Library/Caches/tuxracer-modern-ios/iphonesimulator" -G Xcode \\
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \\
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 -DTUX_IOS_METAL_SMOKE=ON
```

Disable fallback later with `-DTUX_IOS_METAL_SMOKE=OFF`.

### Full Tux Racer port blocker

The macOS Modern branch (`feature/renderer-abstraction`) has substantial Metal
work, but its CMake target still requires `OpenGL::GL`, `OpenGL::GLU`, Tcl,
SDL2_mixer and macOS `AppKit`. Its renderer also uses some legacy GL paths.
The original game cannot simply be added to this iOS target. The next real
port gate is to extract a platform-agnostic game loop/physics and adapt the
Modern Metal renderer from macOS window presentation to iOS SDL Metal layer.
This prototype must not be shipped as a replacement for the original game.

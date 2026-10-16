# Tux Racer Modern — iOS 26+ Metal bootstrap

Status: **SDL2/Metal smoke target only**. This draws a dark blue screen; it does
not yet compile the original game, load courses, or provide touch controls.
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

The smoke source now pauses on background. Full gameplay, Tcl, assets, audio
interruptions, safe areas, touch/game-controller action mapping, and more
complete scene restoration are separate future implementation gates.

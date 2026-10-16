# iOS Metal smoke build

This is a **native SDL2 + Metal smoke test**, not a playable Tux Racer port.
It draws a dark blue Metal frame. The desktop engine is intentionally not
linked because it still requires legacy OpenGL/GLU.

## Requirements

- macOS, Xcode and its iOS SDK, CMake >= 3.24
- Network access on first configure to fetch SDL2 release-2.30.12
- iPhone or iOS simulator with Metal support

## Generate and open the Xcode project

From the repository root:

```sh
sh ios/build-xcode.sh iphonesimulator
open build/ios-iphonesimulator/TuxRacerModernIOS.xcodeproj
```

For a physical iPhone:

```sh
sh ios/build-xcode.sh iphoneos
open build/ios-iphoneos/TuxRacerModernIOS.xcodeproj
```

Select the TuxRacerModernIOS application scheme and destination. For device
signing, select your Apple development team in Xcode. The example bundle ID
may need changing if it is already registered to another team.

## Expected result

The app launches in landscape and clears its Metal surface to dark blue.
There is no gameplay, touch HUD, sound, or bundled course data yet.

## Caveats and next gates

- This Xcode project is **generated locally**, not checked in.
- The CMake/SDL2 iOS bootstrap is not yet verified on Xcode hardware here;
  report the first configure/build error verbatim.
- The current smoke implementation exits on background. Production must
  suspend/resume instead.
- We still need a complete renderer port, Tcl linkage, immutable asset
  bundle and sandboxed save paths before gameplay can run.
- Do not merge into preservation or tag a release until device testing.

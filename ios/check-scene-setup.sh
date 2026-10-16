#!/bin/sh
# Fast, no-compile verification of the UIKit scene migration.
set -eu
root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
plist="$root/ios/Info.plist"
source="$root/ios/scene_lifecycle.m"
cmake_file="$root/ios/CMakeLists.txt"
patch_file="$root/ios/patch-sdl2-scene.cmake"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Scene preflight requires macOS (PlistBuddy)." >&2
  exit 2
fi

/usr/bin/plutil -lint "$plist"
scene_name=$(/usr/libexec/PlistBuddy -c "Print :UIApplicationSceneManifest:UISceneConfigurations:UIWindowSceneSessionRoleApplication:0:UISceneDelegateClassName" "$plist")
if [ "$scene_name" != "TuxSceneDelegate" ]; then
  echo "Missing TuxSceneDelegate in Info.plist (found: $scene_name)" >&2
  exit 1
fi
echo "PASS: Scene manifest and delegate class"

grep -q 'scene:.*willConnectToSession' "$source" || grep -q 'willConnectToSession:(UISceneSession' "$source"
grep -q 'configurationForConnectingSceneSession' "$source"
grep -q 'initWithWindowScene' "$patch_file"
grep -q 'defer SDL_main until UIWindowScene connects' "$patch_file"
grep -q 'scene_lifecycle.m' "$cmake_file"
grep -q 'patch-sdl2-scene.cmake' "$cmake_file"
grep -q 'IPHONEOS_DEPLOYMENT_TARGET "26.0"' "$cmake_file"
echo "PASS: UIKit scene bridge and SDL2 patches referenced by build"

build_root="${TUXRACER_IOS_BUILD_ROOT:-$HOME/Library/Caches/tuxracer-modern-ios}"
sdl_dir="$build_root/iphonesimulator/_deps/sdl2-src"
if [ -d "$sdl_dir" ]; then
  if grep -q 'Tux iOS scene bridge calls postFinishLaunch' "$sdl_dir/src/video/uikit/SDL_uikitappdelegate.m" &&
     grep -q 'TuxGetActiveWindowScene' "$sdl_dir/src/video/uikit/SDL_uikitwindow.m"; then
    echo "PASS: Fetched SDL2 source patched"
  else
    echo "NOTE: Existing SDL2 source not yet patched; rerun sh ios/build-xcode.sh iphonesimulator"
  fi
else
  echo "NOTE: SDL2 not yet fetched into this build directory"
fi

echo "PASS: Scene migration preflight finished without compiling"

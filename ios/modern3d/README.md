# Tux Racer Modern — clean-slate iOS game

**Branch:** `feature/ios-modern-3d` — macOS preservation remains on its own release branch.

No classic course is imported into the new game. The default iOS bundle excludes
the original Tcl/SGI assets and does not compile the legacy course parser.
The new game is authored using JSON, original geometry, and native Metal.

## Modular character/animation milestone

The native Metal renderer now composes the character from separate replaceable
mesh parts under `character_mesh.h`: body, left/right flippers, scarf, and
hat. Each part owns a GPU buffer and model transform. Carving lean,
flipper motion, jump pitch, and cloth movement come from the platform-neutral
`character_animation.c` pose solver.

**These are enhanced procedural meshes, not a rigged production model or a
glTF importer yet.** The purpose of this milestone is proving the runtime
mesh/animation/accessory contract before introducing externally authored
assets, textures, and skeleton skinning.

In the simulator, use **H** to toggle the hat and **C** to toggle the scarf.
Steering animates the character's body lean, and jumping lifts the flippers.
Run `sh ios/modern3d/test-race.sh` to execute the animation tests alongside
the previous game-state tests without opening Xcode. The character module
is compiled only into the clean-slate iOS target, not macOS preservation.

## Playable milestone 2: Summit Run

Native Metal 3D with real depth testing and a procedurally generated
snow-covered track. The course mesh now extends before its start and beyond
the finish, while a terrain-following chase camera maintains above-snow
clearance. This targets the earlier 'looking under the snow' bug.

Gameplay is isolated in `race_system.c/.h`: deterministic fish and tree
locations, steering, braking, jumping/landing, collision penalties, race
timer, course checkpoints, finish state, and restart. The render layer draws
a 3D procedural penguin, evergreen trees, golden collectible fish, start,
checkpoint and finish arches. A native UIKit HUD shows time, distance,
speed and scores. These meshes are *provisional geometry*, not final
art-quality rigged assets.

### Quick regression test (no Xcode)

```sh
sh ios/modern3d/test-race.sh
```

This compiles the pure C game logic, tests object determinism, fish pickup,
jump/landing, pause, finish and restart, and validates the JSON manifest.
The test is provided for running on the developer's Mac; it has not been
executed on that machine in this session.

### Run on iOS 27 simulator

```sh
cd ~/Desktop/tuxracer-modern-github
git fetch origin
git switch feature/ios-modern-3d
git pull --ff-only origin feature/ios-modern-3d
sh ios/build-xcode.sh iphonesimulator
open "$HOME/Library/Caches/tuxracer-modern-ios/iphonesimulator/TuxRacerModernIOS.xcodeproj"
```

Select an iPhone simulator and press Command+R. `TUX_IOS_MODERN3D` is on by
default for this branch. If your CMake cache has previous options, set
`-DTUX_IOS_MODERN3D=ON -DTUX_IOS_METAL_SMOKE=OFF` when regenerating the
Xcode project.

### Controls

- Left/right thirds of the display, A/D, arrows, or controller left stick: steer
- Center touch (above 83% of height), space/up, or controller A: jump
- Center touch (lower 17%), S/down, or controller B: brake
- R / Enter: restart; P / Escape: pause or resume
- Touch the display after finishing: restart

### World authoring

`modern3d/course.json` defines the original Summit Run's length, width,
slope, starting/max speed, fish spacing, pine density and checkpoint spacing.
This is the seed of a multiple-course content pipeline; it isn't yet a level
editor. World objects currently use deterministic seeded positions.

### Roadmap to a complete game

1. Test first: verify camera clearance, actual rendering and hit-box feel on iPhone
2. Replace procedural penguin with a **rigged, skinned original 3D Tux asset**
   and sliding/carving/jumping animations
3. Proper asset pipeline (glTF ingestion -> optimized engine format and textures)
4. Better trees, snow/ice materials, flag fabric, fish pickup VFX, particles,
   snowboard tracks, shadows and spatial audio
5. Course select/menu, medal goals, difficulty, checkpoints, records,
   clothing and hat inventory, saves
6. More authored original courses, iOS performance profiling, accessibility,
   device testing, packaging and App Store readiness

Work is segmented into small modules and host regression gates to avoid
repeating the expensive Xcode / simulator bring-up for every gameplay tweak.

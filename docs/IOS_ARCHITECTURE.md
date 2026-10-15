# Native iOS architecture (initial assessment)

Status: design baseline; not yet an iOS-buildable target.

## Goals
- Preserve original Tux Racer 0.61 physics, game state, Tcl course scripts, attribution, and course data.
- Keep the macOS preservation release untouched.
- Build a native iPhone application using SDL2 for events/platform integration and Metal for rendering.
- Reuse the modern renderer implementation after auditing its current branch; do not assume it is available on main.

## Findings on main
- CMake currently requires OpenGL/GLU, Tcl, SDL2, and SDL2_mixer globally.
- src/main.c uses OpenGL setup directly and discovers data through cwd/executable-relative paths.
- The game loads Tcl scripts and resources from the data directory and uses existing save/config paths.
- Therefore main is not directly compilable for iOS.

## Proposed platform seams
1. **Game core:** isolate gameplay, physics, courses, and Tcl from window creation and renderer initialization.
2. **Renderer:** shared interface; legacy GL on preservation desktop, Metal on iOS and modern macOS. Port and validate all essential rendering paths, not only terrain.
3. **SDL2 host:** iOS app lifecycle, foreground/background, touch, controller hotplug, audio interruptions, and screen dimensions.
4. **Input abstraction:** actions STEER (-1..1), ACCELERATE, BRAKE, JUMP, TRICK, PAUSE, SELECT, BACK; keyboard, touch, and controllers translate into actions.
5. **Assets:** immutable bundled data directory; Tcl resource references remain relative to asset root. Avoid writes to app bundle.
6. **Persistence:** SDL_GetPrefPath() for configuration, saves and user state; migrate desktop assumptions out of core.
7. **Audio:** SDL2_mixer on iOS with AVAudioSession integration for interruptions and silent-switch policy.
8. **UI:** landscape-only initially, Retina-aware, safe-area insets and touch targets; adapt original menus rather than redesigning gameplay.
9. **Distribution:** iOS device and simulator targets, bundle identifier and signing configuration, app icons, privacy declarations, licenses/credits, TestFlight and App Store archive.

## Phase gates
- P0: audit modern renderer branch, existing platform code, third-party dependencies and licenses.
- P1: compile iOS app shell on simulator/device with SDL2, Tcl, asset manifest and Metal clear screen.
- P2: render original course, Tux, and UI with preserved physics.
- P3: touch and controller input parity; background/resume and audio.
- P4: saves, high-DPI and safe-area UI, performance and thermal tests.
- P5: TestFlight, packaging, attribution and App Store review preparation.

## Risk register
- Legacy OpenGL/GLU calls may be spread through UI and gameplay modules; renderer separation could be substantial.
- Tcl and SDL2_mixer dependencies must be built for device and simulator architectures.
- Original file access may assume current working directory and mutable bundled resources.
- Mobile frame pacing, memory, thermal and texture formats need on-device verification.
- GPLv2-or-later and bundled dependency license obligations require a distribution review before App Store submission.

## Immediate implementation plan
1. Inspect the modern renderer branch and identify portable interfaces, dependencies and unimplemented draw paths.
2. Introduce a cross-platform asset/persistence path abstraction with desktop behavior unchanged.
3. Add action-based input abstraction, with desktop mapping as regression reference.
4. Add a separately generated iOS Xcode project (CMake or XcodeGen decision after dependency audit).
5. Build and test on an actual iPhone before changing existing desktop build defaults.

Do not merge this branch into preservation without successful macOS regression tests.

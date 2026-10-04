# Preservation Policy

Tux Racer Modern exists both to preserve the original game and to provide a foundation for continued development.

## Preservation baseline
v0.1.8 is the first known-playable native Apple Silicon preservation milestone. A preservation branch/tag should remain available indefinitely so future renderer and content work can be compared against known original behavior.

## What preservation means
Original authorship, copyright, contributor credits and license notices remain intact. Original gameplay, course behavior, Tcl-driven data behavior and physics are not casually rewritten during platform modernization.

Compatibility fixes should be as narrow as practical. 64-bit safety, API replacement, input translation, display scaling, packaging and portability fixes are acceptable when they preserve behavior.

## Physics changes
Physics changes require explicit justification and comparison against the preservation baseline. Compiler warnings in original physics code are documented rather than automatically "fixed" when doing so could change gameplay.

## Renderer changes
Visual rendering may evolve substantially after the preservation baseline. The long-term architecture keeps a preservation/reference renderer path so gameplay regressions can be distinguished from graphics changes.

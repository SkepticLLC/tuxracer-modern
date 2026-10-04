# Tux Racer Modern — Design Principles

Tux Racer Modern is a continuation of **Tux Racer**, not a conversion into a generic skiing or winter-sports game.

## Core identity

**Modernize the world around Tux without modernizing Tux out of the game.**

Tux, penguins, fish, playful downhill racing, snow, mountains, exaggerated character movement and the lighthearted personality of the original game are core identity. Technical modernization must strengthen that identity rather than replace it.

## Preserve

- **Tux remains the central character and visual identity.**
- Penguins remain fundamental to the world and any future character/racer system.
- Fish and other recognizable Tux Racer gameplay elements remain part of the experience.
- The game remains playful and character-driven rather than becoming a realistic ski simulator.
- Original gameplay feel and physics remain the reference until a change is deliberately evaluated.
- Original authorship, contributors, history and open-source heritage remain visible.

## Modern renderer philosophy

The preservation renderer is a behavioral and historical reference, **not a visual ceiling**. Metal/Vulkan do not need to reproduce obsolete fixed-function or multipass implementation details when a modern technique can preserve the same course/game meaning with better quality.

Renderer parity means preserving:
- course geometry and intended terrain regions;
- camera/gameplay relationships;
- recognizable original assets and visual identity;
- gameplay-relevant visibility and feedback.

After those constraints are satisfied, modern backends should prefer physically coherent, GPU-native techniques over emulating legacy OpenGL artifacts.

## Modernize aggressively

- GPU renderer and platform architecture.
- Snow rendering and deformation.
- Terrain materials and geometric fidelity.
- Lighting, shadows and atmospheric effects.
- Ice, vegetation, particles and weather.
- Animation quality and frame pacing.
- Resolution, high-refresh and modern display support.
- Audio fidelity.
- Menu/UI implementation and accessibility.

Visual realism belongs primarily to the **world and rendering**, not to replacing Tux with a realistic human winter-sports aesthetic.

## Expand carefully

Future additions can include:

- AI-controlled penguin racers.
- Additional penguin characters and personalities.
- Clothing, accessories and character customization.
- New courses and environments.
- Weather and time-of-day systems.
- Additional race/game modes.
- Multiplayer.

These systems should feel native to Tux Racer. AI racers should be penguins with character, not anonymous ski competitors.

## Menu and presentation direction

A future Tux Racer Modern menu should retain Tux and the penguin personality prominently. Modern widescreen composition, animation, snow, lighting and typography are encouraged, but the result should immediately read as **Tux Racer**.

Tux may inhabit/react to menu scenes. Other penguins may appear in the environment. The presentation can become cinematic and modern without becoming sterile or generic.

## Classic preservation policy

The classic experience must remain recoverable throughout modernization.

- `main` / v0.1.9 preserves the first polished Apple Silicon classic application baseline.
- `preservation/v0.1` preserves the earlier porting baseline.
- `preservation/metal-parity-baseline` freezes the v0.2 renderer-transition state before intentional Metal visual redesign.
- The Legacy OpenGL renderer remains the behavioral/visual reference during v0.2 development.
- Modern renderer work must not require destructive changes to original course, Tcl, physics or gameplay data.
- Where practical, the project should retain a **Classic** rendering/presentation option even after Metal becomes the default modern renderer.

## Preservation test

When evaluating a feature or visual change, ask:

> If the logo were hidden, would this still unmistakably feel like Tux Racer?

If the answer is no, the change needs reconsideration.

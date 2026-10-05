# Phicid Productions splash

The standard studio intro: black background, centered logo, 0.45-second fade in,
1.5-second hold, then a 0.45-second fade out. A keyboard key, mouse click, or
gamepad button skips it. No sound, autoload, input actions, or game logic required.

## Copy into another Godot 4 game

Copy this entire `studio/` folder into the new project's root, keeping these files:

| File | Purpose |
| --- | --- |
| `phicid_splash.tscn` | Shared backdrop and aspect-preserving logo layout |
| `splash.gd` and `splash.gd.uid` | Fade sequence, skip input, and scene transition |
| `phicid_logo.png` | Original studio logo |
| `phicid_logo.png.import` | Import settings, including mipmaps for clean scaling |

Godot regenerates the texture cache in `.godot/`; do not copy that cache.

Create an **inherited scene** from `res://studio/phicid_splash.tscn` and save it
outside `studio/`, for example as `res://game/startup.tscn`. On its root node, set
**Next Scene Path** to the new game's opening scene. Set this inherited startup
scene as the project's **Application > Run > Main Scene**. The shared scene
deliberately leaves its destination empty; run the configured inherited scene.

Spiritbound's `game/startup.tscn` is a minimal example. Copy it if useful, but
replace `res://game/main.tscn` with your own scene path. Keep the shared files
unchanged so later games can use the same presentation.

For black startup before the scene loads, disable **Application > Boot Splash >
Show Image**, set **Boot Splash > BG Color** to black, and set **Rendering >
Environment > Defaults > Default Clear Color** to black. These settings belong
to each project, not to the copied scene.

Check normal startup and skipping with a gameplay key/button. The splash consumes
the skip event and waits one physics tick before loading the next scene, so that
press does not become a just-pressed gameplay action. A button still held down
can be read as held input by the next scene. Game resets should reload the game
scene rather than the startup scene.

## Recreate in another engine

Use the same PNG on a black full-screen layer. Fit the complete image, without
cropping or stretching, inside a centered rectangle covering 70% of the viewport
width and height. Use smooth downscaling. Fade only the logo with a sine easing
curve: 0.45 seconds in, 1.5 seconds at full opacity, 0.45 seconds out. On completion
or a fresh key/click/gamepad press, consume the event, remove the splash, and enter
the game's opening scene once. Ignore key repeats and stick drift.

The timing and image treatment are the shared standard; the destination and
engine-specific startup wiring belong to each game.

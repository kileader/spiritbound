# Spiritbound

[Play in your browser](https://kileader.github.io/spiritbound/)

A calm, single-room possession puzzle in Godot. An unexplained spirit moves through ordinary animals in a beautiful, reclaimed natural world. This prototype tests whether moving between bodies feels good, and whether their return behaviours make positioning interesting.

One Mouse, one Bird, one Bear, one exit. No combat, hazards, health, progression, menus, or world framework.

Development is paused at this playable prototype. Further changes can wait for a later playtest.

## Run

Use **Godot 4.7.2 Standard**, with the Compatibility renderer. Import `project.godot` in the editor and press **F5**. There are no external game dependencies.

Startup shows the Phicid Productions logo on black: a 0.45-second fade in, a 1.5-second hold, and a 0.45-second fade out. Click, press any keyboard key, or press a gamepad button to skip. Puzzle reset stays inside the game.

On Windows, the optional PowerShell wrapper accepts an installed or portable engine:

```powershell
$env:SPIRITBOUND_GODOT = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'
npm start
npm test
npm run check
```

It also discovers `godot` / `godot4` on PATH, or the ignored local `.tools/godot/` binary. Node/npm only provides convenience commands and an optional web preview server; gameplay is GDScript.

The equivalent portable engine commands are:

```text
godot --path .
godot --headless --path . --script tests/run_room.gd
godot --headless --path . --script tests/run_animation.gd
godot --headless --path . --script tests/run_splash.gd
godot --headless --path . --editor --import --quit
```

## Controls

| Action | Gamepad | Keyboard |
| --- | --- | --- |
| Move | Left stick / D-pad | WASD / arrows |
| Release / possess selected animal | A | Space |
| Return to the animal last released | B | Escape |
| Choose another nearby animal | LB / RB | Q / E |
| Reset puzzle immediately | Y | R |
| Show debug ranges and animal states | Back / Select | F1 |

A nearby animal focuses for 0.23 seconds. An early possession press is buffered, so transfer does not require precise timing. Valid, focused possession always succeeds. While disembodied, B / Escape immediately reclaims the animal you last released at its current position, even if it has returned beyond the tether. This cancels any pending transfer.

## Reuse the studio splash

The shared `studio/` folder has no Spiritbound dependency. Each game supplies a small inherited startup scene with its own destination; Spiritbound uses `game/startup.tscn`. See [the Phicid splash reuse guide](studio/README.md) for the files to copy, Godot setup, and equivalent behavior in another engine.

## Room solution

1. Move the Mouse through the root slit toward the Bird foraging on the west bank. Release and enter the Bird; the Mouse returns to its burrow.
2. Fly across the stream to the Bear. Release and enter the Bear; the Bird returns to the east perch.
3. Walk the Bear behind the fallen trunk and push left until it tears loose and settles into the stream.
4. Bring the Bear near the east perch, release, and reclaim the Bird. Fly back to the west perch and reclaim the Mouse near its burrow. Released animals can finish returning before either transfer.
5. Take the Mouse through the root slit, through the hollow trunk, and through the final root opening to the glowing exit.

The spirit's movement radius is **115 units from its fixed release point**. The animal can walk away without dragging that tether. Possession reaches another 72 units from the spirit. Release positions and the Bird's choice of the nearer perch are part of the puzzle. B / Escape provides a way back to the released body if every host leaves reach; Y / R still resets the whole puzzle.

## Implementation and assumptions

- `game/room_model.gd` owns explicit room geometry, movement, collision, focus, possession, and animal returns. Mouse gaps gently guide horizontal movement; the Bear cannot fit through the trunk crossing, and the Bird cannot enter the covered exit.
- `game/animal_view.gd` draws ordinary animals with scurrying feet, folding wings, banking flight, weight shifts, breathing, and quiet idle motions. Their visual poses do not change collision geometry.
- `game/room_art.gd` illustrates roots, reclaimed masonry, stream, burrow, perches, food, and hollow trunk. The artwork is procedural placeholder art rather than finished production assets.
- `game/room_feedback.gd` draws the fixed tether, focused hosts, and possession effects. `game/main.gd` handles native gamepad input, minimal HUD, particles, vibration, and small synthesized sound cues.
- Rules run at 60 ticks per second. Visual positions, facing, gait, and effects interpolate between ticks; pose changes ease continuously. Static scenery retains drawing commands to reduce per-frame work.
- There are no bugs in this room. The Mouse starts possessed, and the Bird starts foraging before returning to a perch on release.

The original JavaScript prototype is preserved in Git history. Godot replaces its runtime to make further movement, animation, and art iteration practical.

## Checks and exports

Headless checks exercise the full solution, all animal abilities, returning hosts, fixed release origin, focus buffering, manual target choice, reset, long idle states, and visual interpolation. Animation checks exercise the scene's drawing callbacks and pose transitions at simulated 30, 60, and 144 Hz. Startup checks cover splash timing, keyboard/click/gamepad skips, and fresh gameplay without leaking the skip press. Script/import checks catch GDScript errors. These checks do not establish perceived smoothness or physical controller feel; those require playing the build.

Install matching Godot export templates to create builds:

```powershell
npm run export:windows
npm run export:web
npm run serve
```

Windows output is `builds/windows/Spiritbound.exe` plus its neighbouring `.pck`. Web output is `builds/web/`, served at [http://127.0.0.1:5173](http://127.0.0.1:5173). Builds, engine binaries, and generated editor state are ignored. After code changes, restart the native game or refresh a newly exported web build.

GitHub Pages hosts the browser build at [kileader.github.io/spiritbound](https://kileader.github.io/spiritbound/). `.github/workflows/pages.yml` uses Godot 4.7.2 to import, run the headless checks, export, and publish on each push to `main`; it can also be run manually from GitHub Actions. No generated build files need to be committed. The web export is single-threaded and uses the Compatibility renderer, so it does not require special cross-origin isolation headers. Use a browser with WebGL 2 support and a keyboard or gamepad; touch controls are outside this prototype.

## Smallest playtest

- Do Mouse starts and turns feel nimble, Bird flight feel fluid, and Bear movement feel heavy without becoming sluggish?
- Do takeoff, stopping, pushing, release, and possession flow without visible pose pops?
- Does the Bird's return to a perch invite deliberate positioning, while the full route remains calm after animals settle?
- Can a player read the slit, hollow trunk, exit, valid hosts, and fixed tether with debug labels off?
- Does a physical gamepad feel responsive, including focus buffering and immediate reset?

The next change should address a specific moment observed in this room.

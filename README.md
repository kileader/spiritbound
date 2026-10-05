# Spiritbound

A calm, single-room possession puzzle prototype. The question is simple: **does moving between animal bodies feel good, especially when a released animal starts heading home?**

You begin inside a Mouse. Reach the far bank's covered burrow by borrowing a Bird and a Bear, then bringing the Mouse across. Placeholder shapes, range rings, return indicators, and immediate reset make this a small playtest rather than a broader game.

## Run

Requires Node.js 18 or newer. There are no package or runtime dependencies to install.

```powershell
npm start
```

Open [http://127.0.0.1:5173](http://127.0.0.1:5173). Connect a controller and press any button so the browser can detect it. The game starts immediately; there is no menu.

```powershell
npm test
npm run check
```

The first command runs the behavior tests. The second checks JavaScript syntax. The complete solution is exercised with movement, possession, and waits for returning animals. Browser release, re-possession, reset, and rendering have also been checked. A physical controller still needs its own playtest.

## Controls

| Action | Standard gamepad | Keyboard |
| --- | --- | --- |
| Move | Left stick or D-pad | WASD or arrow keys |
| Release body / possess selected host | A | Space |
| Select another nearby host | LB / RB | Q / E |
| Reset the entire puzzle | Y | R |

The on-screen Reset button also resets instantly. The Indicators button hides optional state and return annotations; the spirit tether and target highlights remain available while disembodied.

Press A or Space once to leave a body, then again to possess the selected nearby animal. A target briefly focuses for 0.23 seconds. An early possession press is buffered until focus completes, so you do not need to time the press precisely. Valid possession always succeeds.

## Room solution

1. **Mouse → Bird:** Move the Mouse through the narrow opening in the first wall, then toward the Bird feeding at the water's west edge. Release the Mouse and possess the Bird. The Mouse starts returning to its burrow.
2. **Bird → Bear:** Fly across the water and stop near the Bear's food spot. Release the Bird and possess the Bear. The Bird returns to the nearest marked perch, here the east perch.
3. **Make a crossing:** Walk the Bear to the slab's right side and push left. The slab settles into the water, opening a narrow crossing that the Mouse can use.
4. **Bear → Bird → Mouse:** Return the Bear near the east perch and switch into the Bird. Fly back toward the Mouse's burrow, release the Bird nearby, and possess the Mouse. The Bird heads to the west perch, which is close enough to the burrow for a calm transfer even after both animals finish returning.
5. **Mouse → exit:** Use the first wall's narrow opening again, cross the slab bridge, then use the final small opening to reach the glowing exit inside the covered burrow.

The first wall's opening is centered at y=417, the slab crossing at y=467, and the final opening at y=572. The Mouse gently centers when approached horizontally near these openings, so navigation does not depend on precise alignment.

The Bird's east perch is an intentionally useful host for getting back after the Bear pushes the slab. Its west perch makes reaching the returning Mouse possible. The player's short spirit range makes these release positions part of the puzzle.

## Prototype rules and assumptions

- The room contains exactly one Mouse, one Bird, and one Bear. There are no bugs in this room.
- The spirit can move up to 115 room units from the animal it exited. That tether follows the animal as it moves. Possession reaches another 72 units from the spirit.
- The Mouse returns to its burrow; the Bird returns to the nearer of its two perches; the Bear returns toward its food spot. Return speeds are deliberately slow. There are no hazards, death, or failure rolls.
- The Mouse fits the narrow passages and slab crossing. The Bird flies across water and ordinary walls, but cannot enter the covered exit burrow. Only the Bear can push the slab.
- Returning animals can be possessed again. Their home locations stay visible, and return destinations and animal states are shown with indicators enabled.
- The initial Mouse is already possessed so the first action is movement. The Bird begins at a feeding spot rather than on a perch.
- Controls assume the browser's standard gamepad mapping, with Xbox-style labels. Actual controller hardware behavior remains to be verified.
- This is a plain JavaScript Canvas game with a small Node static server. `src/model.js` owns room rules, `src/main.js` owns input and the frame loop, and `src/render.js` draws the room.

There is no progression, inventory, combat, lore system, menu, save system, or generalized world infrastructure.

## First playtest

Check only the smallest questions needed to decide whether the core is promising:

- **Transfer feel:** Is release → brief focus → possession readable and satisfying? Does A / Space do what the player expects?
- **Animal positioning:** Does the player notice that the Bird returns to a perch, and intentionally use that perch for the return trip?
- **Planning over timing:** Can the full route be solved calmly, including when animals finish returning before the next transfer?
- **Movement and clarity:** Do the Mouse openings, Bear push, spirit tether, valid targets, and covered exit communicate their rules without explanation?
- **Controller and reset:** Test a physical gamepad's stick deadzone, button mapping, target cycling, and immediate Y reset.

Avoid adding systems before these answers are clear. The next useful change should address a specific confusing or unsatisfying moment observed in this room.

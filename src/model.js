export const ROOM = {
  walls: [
    { x: 300, y: 24, w: 26, h: 376 },
    { x: 300, y: 434, w: 26, h: 242 },
    { x: 922, y: 24, w: 22, h: 532 },
    { x: 922, y: 588, w: 22, h: 88 },
  ],
  river: { x: 530, y: 24, w: 120, h: 652 },
  bridge: { x: 524, y: 441, w: 132, h: 52 },
  perches: [{ x: 360, y: 500 }, { x: 720, y: 245 }],
  burrow: { x: 190, y: 542 },
  food: { x: 865, y: 245 },
  exit: { x: 1022, y: 572, r: 30 },
  mouseGap: { x: 300, y: 400, w: 26, h: 34 },
  exitGap: { x: 922, y: 556, w: 22, h: 32 },
  coveredExit: { x: 944, y: 24, w: 132, h: 652 },
};

const SPEED = { mouse: 185, bird: 230, bear: 150 };
const RETURN_SPEED = { mouse: 74, bird: 82, bear: 64 };
const FOCUS_SECONDS = 0.23;
const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

export function createGame() {
  return {
    width: 1100, height: 700, room: ROOM, time: 0,
    mode: 'animal', activeId: 'mouse',
    animals: [
      { id: 'mouse', name: 'Mouse', x: 190, y: 542, radius: 10, color: '#e6bd7c', state: 'controlled', home: { ...ROOM.burrow }, visited: true },
      { id: 'bird', name: 'Bird', x: 490, y: 245, radius: 14, color: '#89cad7', state: 'resting', home: { ...ROOM.perches[0] }, visited: false },
      { id: 'bear', name: 'Bear', x: 865, y: 245, radius: 30, color: '#bf91d6', state: 'resting', home: { ...ROOM.food }, visited: false },
    ],
    spirit: { x: 190, y: 542, anchorId: null },
    spiritRange: 115, targetRange: 72,
    targetId: null, focus: 0, pendingPossession: false, manualTarget: false,
    bridgeOpen: false, block: { x: 688, y: 431, w: 132, h: 72 },
    hint: '', objectives: [], status: '',
    possessions: 0,
  };
}

export function animalById(game, id) {
  return game.animals.find(animal => animal.id === id);
}

function overlapsRect(x, y, radius, rect) {
  const closestX = clamp(x, rect.x, rect.x + rect.w);
  const closestY = clamp(y, rect.y, rect.y + rect.h);
  return Math.hypot(x - closestX, y - closestY) < radius - 0.001;
}

export function canOccupy(game, animal, x, y) {
  const r = animal.radius;
  if (x < 24 + r || x > game.width - 24 - r || y < 24 + r || y > game.height - 24 - r) return false;
  if (animal.id === 'bird') return !overlapsRect(x, y, r, game.room.coveredExit);
  if (game.room.walls.some(wall => overlapsRect(x, y, r, wall))) return false;
  if (!game.bridgeOpen && overlapsRect(x, y, r, game.block)) return false;
  if (overlapsRect(x, y, r, game.room.river)) {
    const bridge = game.room.bridge;
    if (!game.bridgeOpen || y - r < bridge.y || y + r > bridge.y + bridge.h) return false;
  }
  return true;
}

// The three narrow openings gently center the Mouse when approached nearby.
// This preserves the ability constraint without requiring pixel-perfect steering.
function guideMouse(game, animal, dx, dy, dt) {
  if (animal.id !== 'mouse' || Math.abs(dx) < Math.abs(dy) || Math.abs(dx) < 0.01) return;
  const gaps = [game.room.mouseGap, game.room.exitGap];
  if (game.bridgeOpen) gaps.push(game.room.bridge);
  for (const gap of gaps) {
    const middle = gap.y + gap.h / 2;
    const closeX = animal.x > gap.x - 44 && animal.x < gap.x + gap.w + 44;
    if (closeX && Math.abs(animal.y - middle) < 42) {
      const y = animal.y + clamp(middle - animal.y, -120 * dt, 120 * dt);
      if (canOccupy(game, animal, animal.x, y)) animal.y = y;
    }
  }
}

function pushSlab(game, animal, dx, dy) {
  if (animal.id !== 'bear' || game.bridgeOpen || dx >= 0) return;
  const block = game.block;
  const right = block.x + block.w;
  if (animal.x < right + animal.radius - 3 || Math.abs(animal.y - (block.y + block.h / 2)) > 32) return;
  if (!overlapsRect(animal.x + dx, animal.y + dy, animal.radius, block)) return;
  block.x += dx;
  if (block.x <= game.room.river.x + 5) {
    block.x = game.room.bridge.x;
    game.bridgeOpen = true;
  }
}

function moveAnimal(game, animal, dx, dy, dt, controlled = false) {
  if (controlled) {
    guideMouse(game, animal, dx, dy, dt);
    pushSlab(game, animal, dx, dy);
  }
  if (canOccupy(game, animal, animal.x + dx, animal.y)) animal.x += dx;
  if (canOccupy(game, animal, animal.x, animal.y + dy)) animal.y += dy;
}

function mouseReturnWaypoint(game, mouse) {
  if (mouse.x > 900) {
    if (Math.abs(mouse.y - 572) > 2) return { x: mouse.x, y: 572 };
    return { x: 890, y: 572 };
  }
  if (mouse.x > 338) {
    // A released Mouse on the east bank can come home once the slab is moved.
    if (mouse.x > 650) {
      if (Math.abs(mouse.y - 467) > 2) return { x: Math.max(685, mouse.x), y: 467 };
      return { x: 490, y: 467 };
    }
    if (mouse.x > 510) {
      if (Math.abs(mouse.y - 467) > 2) return { x: mouse.x, y: 467 };
      return { x: 490, y: 467 };
    }
    if (Math.abs(mouse.y - 417) > 2) return { x: Math.max(347, mouse.x), y: 417 };
    return { x: 278, y: 417 };
  }
  if (mouse.x > 278) {
    if (Math.abs(mouse.y - 417) > 2) return { x: mouse.x, y: 417 };
    return { x: 270, y: 417 };
  }
  return mouse.home;
}

function updateReturns(game, dt) {
  for (const animal of game.animals) {
    if (animal.state !== 'returning') continue;
    if (distance(animal, animal.home) < 2) {
      animal.x = animal.home.x;
      animal.y = animal.home.y;
      animal.state = 'resting';
      continue;
    }
    const waypoint = animal.id === 'mouse' ? mouseReturnWaypoint(game, animal) : animal.home;
    const dist = distance(animal, waypoint);
    if (dist < 0.01) continue;
    const step = Math.min(dist, RETURN_SPEED[animal.id] * dt);
    moveAnimal(game, animal, (waypoint.x - animal.x) / dist * step, (waypoint.y - animal.y) / dist * step, dt);
  }
}

export function getValidTargets(game) {
  if (game.mode !== 'spirit') return [];
  return game.animals.filter(animal => animal.id !== 'bug' && distance(animal, game.spirit) <= game.targetRange);
}

function setTarget(game, id) {
  if (game.targetId === id) return;
  game.targetId = id;
  game.focus = 0;
  game.pendingPossession = false;
  game.manualTarget = false;
}

function updateTarget(game, dt) {
  const valid = getValidTargets(game);
  if (!valid.some(animal => animal.id === game.targetId) ||
      (!game.manualTarget && game.targetId === game.spirit.anchorId && valid.some(animal => animal.id !== game.spirit.anchorId))) {
    valid.sort((a, b) => {
      if (a.id === game.spirit.anchorId && b.id !== game.spirit.anchorId) return 1;
      if (b.id === game.spirit.anchorId && a.id !== game.spirit.anchorId) return -1;
      return distance(a, game.spirit) - distance(b, game.spirit);
    });
    setTarget(game, valid[0]?.id ?? null);
  }
  if (game.targetId) game.focus = Math.min(1, game.focus + dt / FOCUS_SECONDS);
  else game.focus = 0;
}

export function cycleTarget(game, direction = 1) {
  const targets = getValidTargets(game);
  if (targets.length < 2) return;
  const index = targets.findIndex(animal => animal.id === game.targetId);
  setTarget(game, targets[(index + direction + targets.length) % targets.length].id);
  game.manualTarget = true;
}

export function releasePossession(game) {
  if (game.mode !== 'animal') return false;
  const animal = animalById(game, game.activeId);
  game.spirit = { x: animal.x, y: animal.y, anchorId: animal.id };
  if (animal.id === 'bird') {
    animal.home = { ...game.room.perches.reduce((nearer, perch) => distance(animal, perch) < distance(animal, nearer) ? perch : nearer) };
  }
  animal.state = 'returning';
  game.mode = 'spirit';
  game.activeId = null;
  game.targetId = null;
  game.focus = 0;
  game.pendingPossession = false;
  game.manualTarget = false;
  updateTarget(game, 0);
  return true;
}

export function tryPossess(game) {
  if (game.mode !== 'spirit' || game.focus < 1) return false;
  const animal = getValidTargets(game).find(candidate => candidate.id === game.targetId);
  if (!animal) return false;
  animal.state = 'controlled';
  animal.visited = true;
  game.activeId = animal.id;
  game.mode = 'animal';
  game.targetId = null;
  game.focus = 0;
  game.pendingPossession = false;
  game.possessions++;
  return true;
}

function updateHints(game) {
  const bird = animalById(game, 'bird');
  const bear = animalById(game, 'bear');
  game.objectives = [
    { label: 'Reach the feeding Bird', done: bird.visited },
    { label: 'Fly across to the Bear', done: bear.visited },
    { label: 'Push the slab left into the water', done: game.bridgeOpen },
    { label: 'Bring the Mouse through to the exit', done: game.mode === 'won' },
  ];
  if (game.mode === 'won') {
    game.status = 'Room complete';
    game.hint = 'You chained all three animals. Press Y / R to try again.';
  } else if (game.mode === 'spirit') {
    const target = animalById(game, game.targetId);
    game.status = target ? `Spirit · ${game.focus < 1 ? 'focusing on' : 'ready for'} ${target.name}` : 'Spirit · no host in reach';
    game.hint = 'The ring follows your last host. Move toward another animal; tap A / Space to possess. LB / RB changes targets.';
  } else if (game.activeId === 'mouse') {
    game.status = 'Mouse · small enough for the slits';
    game.hint = game.bridgeOpen ? 'Cross the narrow slab bridge, then use the small opening beside the glowing exit.' : bird.visited ? 'The Mouse needs a ground crossing. Use the Bird to reach the Bear.' : 'Go through the marked slit, then approach the feeding Bird above it. Tap A / Space to release.';
  } else if (game.activeId === 'bird') {
    game.status = 'Bird · flies over water and walls';
    game.hint = game.bridgeOpen ? 'Fly back west to the Mouse. After release you return to the nearer perch.' : 'Fly east to the Bear. On release, the nearer perch becomes your resting place—leave a return host on this bank.';
  } else {
    game.status = 'Bear · strong enough to push the slab';
    game.hint = game.bridgeOpen ? 'Return near the east perch to take the Bird back to the Mouse. The bridge is too narrow for the Bear.' : 'Stand on the slab’s right side and walk left to push it into the water.';
  }
}

export function updateGame(game, dt, input = {}) {
  dt = clamp(dt, 0, 1 / 20);
  game.time += dt;
  if (game.mode === 'won') { updateHints(game); return; }
  const wasSpirit = game.mode === 'spirit';
  let x = input.x || 0;
  let y = input.y || 0;
  const magnitude = Math.hypot(x, y);
  if (magnitude > 1) { x /= magnitude; y /= magnitude; }
  if (game.mode === 'animal') {
    const animal = animalById(game, game.activeId);
    moveAnimal(game, animal, x * SPEED[animal.id] * dt, y * SPEED[animal.id] * dt, dt, true);
    if (animal.id === 'mouse' && game.bridgeOpen && game.animals.every(host => host.visited) && distance(animal, game.room.exit) < game.room.exit.r) {
      game.mode = 'won';
    } else if (input.action) releasePossession(game);
  } else if (game.mode === 'spirit') {
    game.spirit.x = clamp(game.spirit.x + x * 185 * dt, 30, game.width - 30);
    game.spirit.y = clamp(game.spirit.y + y * 185 * dt, 30, game.height - 30);
  }
  updateReturns(game, dt);
  if (game.mode === 'spirit') {
    const anchor = animalById(game, game.spirit.anchorId);
    const dist = distance(game.spirit, anchor);
    if (dist > game.spiritRange) {
      const ratio = game.spiritRange / dist;
      game.spirit.x = anchor.x + (game.spirit.x - anchor.x) * ratio;
      game.spirit.y = anchor.y + (game.spirit.y - anchor.y) * ratio;
    }
    updateTarget(game, dt);
    if (input.cycle) cycleTarget(game, input.cycle);
    // A press during the short focus is buffered, so transfers are forgiving.
    if (input.action && wasSpirit && game.targetId) game.pendingPossession = true;
    if (game.pendingPossession) tryPossess(game);
  }
  updateHints(game);
}

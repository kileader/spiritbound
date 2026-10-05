import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createGame, updateGame, animalById, getValidTargets,
  releasePossession, tryPossess, cycleTarget,
} from './model.js';

const DT = 1 / 60;
const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

function tick(game, frames, input = {}) {
  for (let frame = 0; frame < frames; frame++) updateGame(game, DT, input);
}

function controlledBody(game) {
  return game.mode === 'spirit' ? game.spirit : animalById(game, game.activeId);
}

function moveTo(game, x, y, tolerance = 4) {
  for (let frame = 0; frame < 2400; frame++) {
    if (game.mode === 'won') return;
    const body = controlledBody(game);
    const d = distance(body, { x, y });
    if (d <= tolerance) return;
    updateGame(game, DT, { x: (x - body.x) / d, y: (y - body.y) / d });
  }
  const body = controlledBody(game);
  assert.fail(`Could not reach (${x}, ${y}); ${game.activeId ?? 'spirit'} stopped at (${body.x.toFixed(1)}, ${body.y.toFixed(1)})`);
}

function transferTo(game, id) {
  if (game.mode === 'animal') assert.equal(releasePossession(game), true);
  else assert.equal(game.mode, 'spirit');
  for (let frame = 0; frame < 1800; frame++) {
    const target = animalById(game, id);
    const d = distance(game.spirit, target);
    const input = d > game.targetRange - 12
      ? { x: (target.x - game.spirit.x) / d, y: (target.y - game.spirit.y) / d }
      : {};
    updateGame(game, DT, input);
    if (game.targetId === id && game.focus === 1) {
      assert.equal(tryPossess(game), true);
      assert.equal(game.activeId, id);
      return;
    }
  }
  assert.fail(`Could not transfer to ${id}`);
}

function reachFirstBird(game) {
  moveTo(game, 270, 417);
  moveTo(game, 350, 417);
  moveTo(game, 490, 245);
}

function selectAnimal(game, id, x, y) {
  for (const animal of game.animals) animal.state = 'resting';
  const animal = animalById(game, id);
  Object.assign(animal, { x, y, state: 'controlled' });
  game.mode = 'animal';
  game.activeId = id;
  return animal;
}

test('the Mouse is required to reach the first Bird through the narrow wall', () => {
  const game = createGame();
  moveTo(game, 278, 245);
  releasePossession(game);
  tick(game, 180, { x: 1 });
  assert.equal(getValidTargets(game).some(animal => animal.id === 'bird'), false);

  const throughGap = createGame();
  reachFirstBird(throughGap);
  assert.ok(animalById(throughGap, 'mouse').x > 326);
  transferTo(throughGap, 'bird');
  assert.equal(throughGap.activeId, 'bird');
});

test('ground animals cannot cross water; the Bird can fly across it and walls', () => {
  const mouseGame = createGame();
  const mouse = selectAnimal(mouseGame, 'mouse', 490, 467);
  tick(mouseGame, 120, { x: 1 });
  assert.ok(mouse.x <= mouseGame.room.river.x - mouse.radius + 0.01);

  const birdGame = createGame();
  const bird = selectAnimal(birdGame, 'bird', 490, 245);
  moveTo(birdGame, 800, 245);
  moveTo(birdGame, 200, 245);
  assert.ok(bird.x < 300);

  const bearGame = createGame();
  const bear = selectAnimal(bearGame, 'bear', 370, 417);
  tick(bearGame, 120, { x: -1 });
  assert.ok(bear.x > 326, 'the Bear must not fit through the Mouse slit');
});

test('possession requires a nearby focused host and buffers a press during focus', () => {
  const game = createGame();
  reachFirstBird(game);
  const mouse = animalById(game, 'mouse');
  const releasePosition = { x: mouse.x, y: mouse.y };
  assert.equal(releasePossession(game), true);
  assert.equal(game.spirit.x, releasePosition.x);
  assert.equal(game.spirit.y, releasePosition.y);
  assert.equal(game.spirit.anchorId, 'mouse');
  assert.equal(game.targetId, 'bird');
  assert.equal(tryPossess(game), false, 'focus must complete first');
  updateGame(game, DT, { action: true });
  assert.equal(game.mode, 'spirit');
  tick(game, 15);
  assert.equal(game.activeId, 'bird');
  assert.equal(game.mode, 'animal');

  const outOfRange = createGame();
  releasePossession(outOfRange);
  outOfRange.targetId = 'bird';
  outOfRange.focus = 1;
  assert.equal(tryPossess(outOfRange), false, 'a stale target cannot bypass range validation');
});

test('the released Mouse returns through its slit while the spirit remains tethered', () => {
  const game = createGame();
  reachFirstBird(game);
  releasePossession(game);
  const mouse = animalById(game, 'mouse');
  for (let frame = 0; frame < 700; frame++) {
    updateGame(game, DT, { x: 1 });
    assert.ok(distance(game.spirit, mouse) <= game.spiritRange + 0.001);
  }
  assert.equal(mouse.state, 'resting');
  assert.equal(mouse.x, game.room.burrow.x);
  assert.equal(mouse.y, game.room.burrow.y);
});

test('manual targeting preserves the released host while another valid host remains nearby', () => {
  const game = createGame();
  reachFirstBird(game);
  releasePossession(game);
  assert.equal(game.targetId, 'bird');
  cycleTarget(game);
  assert.equal(game.targetId, 'mouse');
  tick(game, 15);
  assert.ok(getValidTargets(game).some(animal => animal.id === 'bird'));
  assert.equal(game.targetId, 'mouse');
  assert.equal(game.focus, 1);
  assert.equal(tryPossess(game), true);
  assert.equal(game.activeId, 'mouse');
});

test('a Mouse released off the bridge center can still return to its burrow', () => {
  const game = createGame();
  game.bridgeOpen = true;
  const mouse = selectAnimal(game, 'mouse', 590, 453);
  releasePossession(game);
  tick(game, 1200);
  assert.equal(mouse.state, 'resting');
  assert.equal(mouse.x, game.room.burrow.x);
  assert.equal(mouse.y, game.room.burrow.y);
});

test('only the Bear moves the slab, and its narrow bridge remains inaccessible to the Bear', () => {
  const mouseGame = createGame();
  selectAnimal(mouseGame, 'mouse', 850, 467);
  const initialSlabX = mouseGame.block.x;
  tick(mouseGame, 100, { x: -1 });
  assert.equal(mouseGame.block.x, initialSlabX);
  assert.equal(mouseGame.bridgeOpen, false);

  const bearGame = createGame();
  const bear = selectAnimal(bearGame, 'bear', 855, 467);
  for (let frame = 0; frame < 240 && !bearGame.bridgeOpen; frame++) updateGame(bearGame, DT, { x: -1 });
  assert.equal(bearGame.bridgeOpen, true);
  tick(bearGame, 120, { x: -1 });
  assert.ok(bear.x >= bearGame.room.river.x + bearGame.room.river.w + bear.radius - 0.01);

  const mouse = selectAnimal(bearGame, 'mouse', 490, 467);
  moveTo(bearGame, 685, 467);
  assert.ok(mouse.x > bearGame.room.river.x + bearGame.room.river.w);
});

test('the final wall cannot be bypassed by walking around its top', () => {
  const game = createGame();
  game.bridgeOpen = true;
  const mouse = selectAnimal(game, 'mouse', 875, 245);
  tick(game, 100, { x: 1 });
  assert.ok(mouse.x < 922, 'the Mouse must use the final narrow opening');
});

test('the Bird cannot fly into the covered exit den', () => {
  const game = createGame();
  const bird = selectAnimal(game, 'bird', 900, 572);
  tick(game, 100, { x: 1 });
  assert.ok(bird.x <= game.room.coveredExit.x - bird.radius + 0.01);
  assert.notEqual(game.mode, 'won');
});

test('the intended chain completes the room with stable return hosts and a fresh reset', () => {
  const game = createGame();
  reachFirstBird(game);
  transferTo(game, 'bird');
  moveTo(game, 835, 245);
  transferTo(game, 'bear');
  assert.deepEqual(animalById(game, 'bird').home, game.room.perches[1]);

  moveTo(game, 855, 467);
  for (let frame = 0; frame < 240 && !game.bridgeOpen; frame++) updateGame(game, DT, { x: -1 });
  assert.equal(game.bridgeOpen, true);
  moveTo(game, 775, 245);
  releasePossession(game);
  tick(game, 300);
  assert.equal(animalById(game, 'bear').state, 'resting');
  assert.equal(animalById(game, 'bird').state, 'resting');
  transferTo(game, 'bird');
  moveTo(game, 360, 500);
  releasePossession(game);
  tick(game, 300);
  assert.equal(animalById(game, 'bird').state, 'resting');
  assert.equal(animalById(game, 'mouse').state, 'resting');
  transferTo(game, 'mouse');
  assert.deepEqual(animalById(game, 'bird').home, game.room.perches[0]);

  moveTo(game, 270, 417);
  moveTo(game, 350, 417);
  moveTo(game, 490, 467);
  moveTo(game, 685, 467);
  moveTo(game, 875, 572);
  moveTo(game, 980, 572);
  moveTo(game, 1022, 572);
  assert.equal(game.mode, 'won');
  assert.equal(game.possessions, 4);
  assert.ok(game.animals.every(animal => animal.visited));

  const reset = createGame();
  assert.equal(reset.mode, 'animal');
  assert.equal(reset.activeId, 'mouse');
  assert.equal(reset.bridgeOpen, false);
  assert.equal(reset.block.x, 688);
  assert.equal(reset.focus, 0);
  assert.equal(reset.possessions, 0);
  assert.equal(animalById(reset, 'bird').visited, false);
  assert.equal(animalById(reset, 'bear').visited, false);
});

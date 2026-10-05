import { createGame, updateGame } from './model.js';
import { drawGame } from './render.js';

const canvas = document.querySelector('#game');
const ctx = canvas.getContext('2d');
const status = document.querySelector('#status');
const hint = document.querySelector('#hint');
const objectives = document.querySelector('#objective-list');
const controllerStatus = document.querySelector('#controller-status');
const result = document.querySelector('#result');
const debugToggle = document.querySelector('#debug-toggle');
const keys = new Set();
let game = createGame();
let debug = true;
let actionQueued = false;
let resetQueued = false;
let cycleQueued = 0;
let previousButtons = [];
let previousPadId = null;
let last = performance.now();
let accumulator = 0;
let objectiveText = '';
let pixelRatio = Math.min(window.devicePixelRatio || 1, 2);

canvas.width = game.width * pixelRatio;
canvas.height = game.height * pixelRatio;
canvas.setAttribute('tabindex', '0');
updateGame(game, 0);

const movementKeys = ['KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowLeft', 'ArrowDown', 'ArrowRight'];
window.addEventListener('keydown', event => {
  if (movementKeys.includes(event.code) || ['Space', 'KeyQ', 'KeyE', 'KeyR'].includes(event.code)) {
    if (event.target instanceof HTMLButtonElement && ['Space', 'Enter'].includes(event.code)) return;
    event.preventDefault();
    keys.add(event.code);
    if (event.repeat) return;
    if (event.code === 'Space') actionQueued = true;
    if (event.code === 'KeyR') resetQueued = true;
    if (event.code === 'KeyQ') cycleQueued = -1;
    if (event.code === 'KeyE') cycleQueued = 1;
  }
});
window.addEventListener('keyup', event => keys.delete(event.code));
window.addEventListener('blur', () => {
  keys.clear();
  actionQueued = false;
  cycleQueued = 0;
});
document.addEventListener('visibilitychange', () => {
  keys.clear();
  last = performance.now();
  accumulator = 0;
});
canvas.addEventListener('pointerdown', () => canvas.focus({ preventScroll: true }));
document.querySelector('#reset').addEventListener('click', () => {
  resetQueued = true;
  canvas.focus({ preventScroll: true });
});
debugToggle.addEventListener('click', () => {
  debug = !debug;
  debugToggle.setAttribute('aria-pressed', String(debug));
  debugToggle.textContent = debug ? 'Debug indicators on' : 'Debug indicators off';
  canvas.focus({ preventScroll: true });
});

function readInput() {
  let x = Number(keys.has('KeyD') || keys.has('ArrowRight')) - Number(keys.has('KeyA') || keys.has('ArrowLeft'));
  let y = Number(keys.has('KeyS') || keys.has('ArrowDown')) - Number(keys.has('KeyW') || keys.has('ArrowUp'));
  const pad = [...(navigator.getGamepads?.() || [])].find(candidate => candidate?.connected);
  if (pad) {
    // Radial deadzone preserves analog speed and avoids diagonal speed boosts.
    const axisX = pad.axes[0] || 0;
    const axisY = pad.axes[1] || 0;
    const length = Math.hypot(axisX, axisY);
    if (length > 0.18) {
      const strength = Math.min(1, (length - 0.18) / 0.82);
      x = axisX / length * strength;
      y = axisY / length * strength;
    }
    const buttons = pad.buttons.map(button => button.pressed);
    if (pad.id !== previousPadId) previousButtons = [];
    const pressed = index => buttons[index] && !previousButtons[index];
    if (pressed(0)) actionQueued = true;
    if (pressed(3)) resetQueued = true;
    if (pressed(4)) cycleQueued = -1;
    if (pressed(5)) cycleQueued = 1;
    x += Number(Boolean(buttons[15])) - Number(Boolean(buttons[14]));
    y += Number(Boolean(buttons[13])) - Number(Boolean(buttons[12]));
    previousButtons = buttons;
    previousPadId = pad.id;
    controllerStatus.textContent = `Controller connected · ${pad.mapping === 'standard' ? 'standard layout' : 'layout may vary'} · A to transfer`;
    controllerStatus.dataset.connected = 'true';
  } else {
    previousButtons = [];
    previousPadId = null;
    controllerStatus.textContent = 'Press a gamepad button to connect · keyboard ready';
    controllerStatus.dataset.connected = 'false';
  }
  const input = { x, y, action: actionQueued, cycle: cycleQueued };
  actionQueued = false;
  cycleQueued = 0;
  return input;
}

function updateInterface() {
  if (status.textContent !== game.status) status.textContent = game.status;
  if (hint.textContent !== game.hint) hint.textContent = game.hint;
  const nextObjectives = game.objectives.map(objective => `${objective.done}:${objective.label}`).join('|');
  if (nextObjectives !== objectiveText) {
    objectives.replaceChildren(...game.objectives.map(objective => {
      const item = document.createElement('li');
      item.className = objective.done ? 'done' : '';
      item.textContent = objective.label;
      return item;
    }));
    objectiveText = nextObjectives;
  }
  result.hidden = game.mode !== 'won';
  if (game.mode === 'won') result.textContent = `Room complete — ${game.possessions} possessions. Y / R resets immediately.`;
}

function frame(now) {
  const elapsed = Math.min((now - last) / 1000, 0.1);
  last = now;
  if (document.hidden) { requestAnimationFrame(frame); return; }
  const input = readInput();
  if (resetQueued) {
    game = createGame();
    updateGame(game, 0);
    resetQueued = false;
    accumulator = 0;
    input.action = false;
    input.cycle = 0;
  }
  accumulator += elapsed;
  // Apply button edges even on a high-refresh display with no simulation step yet.
  if (input.action || input.cycle) updateGame(game, 0, { action: input.action, cycle: input.cycle });
  while (accumulator >= 1 / 60) {
    updateGame(game, 1 / 60, { x: input.x, y: input.y });
    accumulator -= 1 / 60;
  }
  updateInterface();
  ctx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
  drawGame(ctx, game, { debug });
  requestAnimationFrame(frame);
}

requestAnimationFrame(frame);

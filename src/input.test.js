import test from 'node:test';
import assert from 'node:assert/strict';

// Exercise the real browser entrypoint, input polling, simulation and renderer.
// The fake DOM only supplies canvas no-ops and records the visible status/labels.
async function browserHarness() {
  class Element {
    textContent = ''; dataset = {}; listeners = {}; hidden = false;
    addEventListener(type, listener) { this.listeners[type] = listener; }
    setAttribute(name, value) { this[name] = value; }
    replaceChildren(...children) { this.children = children; }
    focus() { this.focused = true; }
  }
  const elements = Object.fromEntries(['game', 'status', 'hint', 'objective-list', 'controller-status', 'result', 'reset', 'debug-toggle'].map(id => [id, new Element()]));
  const labels = new Map();
  let spirit;
  const noop = () => {};
  const ctx = new Proxy({
    measureText: value => ({ width: value.length * 7 }),
    clearRect() { labels.clear(); spirit = null; },
    fillText(value, x, y) { labels.set(value, { x, y }); },
    arc(x, y, radius, start, end) { if (radius === 10 && start === Math.PI && end === 0) spirit = { x, y: y + 2 }; },
  }, { get: (target, property) => target[property] ?? noop });
  elements.game.getContext = () => ctx;
  const listeners = {};
  let queuedFrame;
  let now = 0;
  const pad = { id: 'test-controller', connected: true, mapping: 'standard', axes: [0, 0], buttons: Array.from({ length: 16 }, () => ({ pressed: false })) };
  const names = ['window', 'document', 'navigator', 'HTMLButtonElement', 'requestAnimationFrame', 'performance'];
  const originals = names.map(name => [name, Object.getOwnPropertyDescriptor(globalThis, name)]);
  const globals = {
    window: { devicePixelRatio: 1, addEventListener(type, listener) { listeners[type] = listener; } },
    document: { hidden: false, querySelector: selector => elements[selector.slice(1)], createElement: () => new Element(), addEventListener: noop },
    navigator: { getGamepads: () => pad.connected ? [null, pad] : [] },
    HTMLButtonElement: Element,
    requestAnimationFrame: callback => { queuedFrame = callback; },
    performance: { now: () => now },
  };
  for (const [name, value] of Object.entries(globals)) Object.defineProperty(globalThis, name, { value, configurable: true });
  await import(`./main.js?input-test=${Date.now()}`);
  function frame(milliseconds = 20) { now += milliseconds; queuedFrame(now); }
  function frames(count) { for (let n = 0; n < count; n++) frame(); }
  function press(index) { pad.buttons[index].pressed = true; frame(); pad.buttons[index].pressed = false; frame(); }
  function key(type, code, options = {}) {
    const event = { code, target: {}, repeat: false, prevented: false, preventDefault() { this.prevented = true; }, ...options };
    listeners[type](event);
    return event;
  }
  function position(name) {
    const point = labels.get(name);
    assert.ok(point, `The renderer must expose the ${name} label`);
    return { x: point.x, y: point.y - ({ Mouse: 10, Bird: 14, Bear: 30 }[name] + 21) };
  }
  function moveTo(name, x, y, tolerance = 5) {
    for (let n = 0; n < 1500; n++) {
      const point = name === 'Spirit' ? spirit : position(name);
      const distance = Math.hypot(x - point.x, y - point.y);
      if (distance < tolerance || elements.status.textContent === 'Room complete') { pad.axes = [0, 0]; return; }
      pad.axes = [(x - point.x) / distance, (y - point.y) / distance];
      frame();
    }
    assert.fail(`Could not move ${name} to ${x}, ${y}`);
  }
  function transferTo(name) {
    if (!elements.status.textContent.startsWith('Spirit')) press(0);
    const target = position(name);
    moveTo('Spirit', target.x, target.y, 66);
    press(0);
    frames(15);
    assert.ok(elements.status.textContent.startsWith(`${name} ·`), `Expected possession of ${name}, got ${elements.status.textContent}`);
  }
  frame();
  return { elements, pad, frame, frames, press, key, position, moveTo, transferTo, listeners,
    reset() { pad.axes = [0, 0]; press(3); },
    restore() { for (const [name, descriptor] of originals) { if (descriptor) Object.defineProperty(globalThis, name, descriptor); else delete globalThis[name]; } },
  };
}

test('browser inputs control the actual playable room', async t => {
  const browser = await browserHarness();
  const { elements, pad, frame, frames, press, key, position, moveTo, transferTo } = browser;
  try {
    await t.test('A acts once per press and Y resets immediately from spirit mode', () => {
      pad.buttons[0].pressed = true;
      frame(1); // Button edges must work even before the next 60 Hz step.
      assert.match(elements.status.textContent, /^Spirit/);
      frames(30);
      assert.match(elements.status.textContent, /^Spirit/, 'holding A must not immediately repossess');
      pad.buttons[0].pressed = false; frame();
      press(0);
      assert.match(elements.status.textContent, /^Mouse/);
      press(0);
      assert.match(elements.status.textContent, /^Spirit/);
      browser.reset();
      assert.match(elements.status.textContent, /^Mouse/);
      assert.deepEqual(position('Mouse'), { x: 190, y: 542 });
      assert.equal(elements.result.hidden, true);
    });

    await t.test('left stick uses a radial deadzone and analog movement', () => {
      pad.axes = [0.17, 0]; frames(25);
      assert.equal(position('Mouse').x, 190);
      pad.axes = [0.59, 0]; frames(25);
      assert.ok(Math.abs(position('Mouse').x - 236.25) < 3.2);
      browser.reset();
      pad.axes = [1, -1]; frames(15);
      const mouse = position('Mouse');
      assert.ok(Math.abs((mouse.x - 190) - (542 - mouse.y)) < 0.01);
      assert.ok(Math.hypot(mouse.x - 190, mouse.y - 542) <= 58.6, 'diagonal movement must not exceed full stick speed');
      browser.reset();
    });

    await t.test('keyboard fallback clears movement on blur and respects button focus', () => {
      pad.connected = false;
      const event = key('keydown', 'KeyD');
      assert.equal(event.prevented, true);
      frames(10);
      assert.ok(position('Mouse').x > 220);
      browser.listeners.blur();
      const stopped = position('Mouse').x; frames(10);
      assert.equal(position('Mouse').x, stopped);
      const buttonEvent = key('keydown', 'Space', { target: elements.reset }); frame();
      assert.equal(buttonEvent.prevented, false);
      assert.match(elements.status.textContent, /^Mouse/);
      key('keydown', 'Space'); frame();
      key('keydown', 'Space', { repeat: true }); frames(20);
      assert.match(elements.status.textContent, /^Spirit/);
      key('keyup', 'Space'); key('keydown', 'KeyR'); frame(); key('keyup', 'KeyR');
      assert.match(elements.status.textContent, /^Mouse/);
      assert.equal(elements['controller-status'].dataset.connected, 'false');
      elements.reset.listeners.click(); frame();
      assert.equal(elements.game.focused, true);
      pad.connected = true;
    });

    await t.test('gamepad transfers complete the room and Y resets the win', () => {
      browser.reset();
      moveTo('Mouse', 270, 417); moveTo('Mouse', 350, 417); moveTo('Mouse', 480, 280);
      press(0);
      assert.match(elements.status.textContent, /Bird$/);
      press(4); frames(2);
      assert.match(elements.status.textContent, /Mouse$/, 'LB must retain a manually selected released host');
      press(5); frames(2);
      assert.match(elements.status.textContent, /Bird$/, 'RB must advance to the other host');
      transferTo('Bird');
      moveTo('Bird', 835, 245); transferTo('Bear');
      moveTo('Bear', 855, 467);
      pad.axes = [-1, 0]; frames(110); pad.axes = [0, 0];
      assert.match(elements.hint.textContent, /Return near the east perch/);
      moveTo('Bear', 775, 245); transferTo('Bird');
      moveTo('Bird', 360, 500); transferTo('Mouse');
      moveTo('Mouse', 270, 417); moveTo('Mouse', 350, 417); moveTo('Mouse', 490, 467);
      moveTo('Mouse', 685, 467); moveTo('Mouse', 875, 572); moveTo('Mouse', 980, 572); moveTo('Mouse', 1022, 572);
      assert.equal(elements.status.textContent, 'Room complete');
      assert.equal(elements.result.hidden, false);
      browser.reset();
      assert.match(elements.status.textContent, /^Mouse/);
      assert.deepEqual(position('Mouse'), { x: 190, y: 542 });
      assert.equal(elements.result.hidden, true);
      assert.equal(elements['controller-status'].dataset.connected, 'true');
    });
  } finally { browser.restore(); }
});

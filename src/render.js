const COLORS = {
  floor: '#202d40', grid: '#28364b', wall: '#455168', wallTop: '#657086',
  water: '#223e58', waterLine: '#4d7187', text: '#e4e1d3', muted: '#99acc5',
  spirit: '#d5e6ff', mouse: '#e8c992', bird: '#91c5df', bear: '#d69984',
  exit: '#cfdb9d', tether: '#a4badd',
};

function roundedRect(ctx, x, y, w, h, radius = 6) {
  ctx.beginPath();
  ctx.roundRect(x, y, w, h, radius);
}

function circle(ctx, x, y, r) {
  ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2);
}

function label(ctx, value, x, y, options = {}) {
  ctx.save();
  ctx.font = `${options.bold ? '600' : '500'} ${options.size || 12}px system-ui, sans-serif`;
  ctx.textAlign = options.align || 'center';
  ctx.textBaseline = 'middle';
  if (options.backdrop) {
    const width = ctx.measureText(value).width + 14;
    ctx.fillStyle = '#172337dd';
    roundedRect(ctx, x - width / 2, y - 11, width, 22, 5); ctx.fill();
  }
  ctx.fillStyle = options.color || COLORS.muted;
  ctx.fillText(value, x, y);
  ctx.restore();
}

function line(ctx, x1, y1, x2, y2, color, width = 1, dashed = false) {
  ctx.save(); ctx.strokeStyle = color; ctx.lineWidth = width;
  if (dashed) ctx.setLineDash([5, 6]);
  ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke(); ctx.restore();
}

function arrow(ctx, x1, y1, x2, y2, color) {
  line(ctx, x1, y1, x2, y2, color, 2);
  const angle = Math.atan2(y2 - y1, x2 - x1);
  line(ctx, x2, y2, x2 - Math.cos(angle - .5) * 9, y2 - Math.sin(angle - .5) * 9, color, 2);
  line(ctx, x2, y2, x2 - Math.cos(angle + .5) * 9, y2 - Math.sin(angle + .5) * 9, color, 2);
}

function drawWall(ctx, wall) {
  ctx.fillStyle = '#101a2b66';
  roundedRect(ctx, wall.x + 4, wall.y + 7, wall.w, wall.h, 4); ctx.fill();
  ctx.fillStyle = COLORS.wall; roundedRect(ctx, wall.x, wall.y, wall.w, wall.h, 4); ctx.fill();
  ctx.strokeStyle = COLORS.wallTop; ctx.lineWidth = 1;
  roundedRect(ctx, wall.x + .5, wall.y + .5, wall.w - 1, wall.h - 1, 4); ctx.stroke();
  line(ctx, wall.x + 6, wall.y + 8, wall.x + wall.w - 6, wall.y + 8, '#78829955');
}

function drawHome(ctx, animal, game) {
  const { x, y } = animal.home;
  ctx.save(); ctx.globalAlpha = .65;
  if (animal.id === 'mouse') {
    ctx.fillStyle = '#111c2d';
    ctx.beginPath(); ctx.ellipse(x, y, 30, 18, 0, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = '#927f62'; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.ellipse(x, y, 29, 18, 0, Math.PI, Math.PI * 2); ctx.stroke();
    label(ctx, 'Mouse burrow', x, y + 32, { size: 11 });
  } else if (animal.id === 'bear') {
    ctx.strokeStyle = '#796b60'; ctx.lineWidth = 2;
    circle(ctx, x, y, 29); ctx.stroke();
    ctx.fillStyle = '#af9a72';
    for (const [dx, dy] of [[-9, 5], [5, -2], [8, 11]]) {
      circle(ctx, x + dx, y + dy, 6); ctx.fill();
    }
    label(ctx, 'Bear food', x, y + 46, { size: 11 });
  }
  ctx.restore();
}

function drawPerches(ctx, room, bird) {
  for (const [index, perch] of room.perches.entries()) {
    const selected = bird && Math.hypot(bird.home.x - perch.x, bird.home.y - perch.y) < 10;
    ctx.save(); ctx.strokeStyle = selected ? '#81b8d3' : '#56748c'; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(perch.x - 25, perch.y + 8); ctx.lineTo(perch.x + 25, perch.y + 8); ctx.stroke();
    line(ctx, perch.x, perch.y + 8, perch.x, perch.y + 25, '#56748c', 4);
    circle(ctx, perch.x, perch.y, 26); ctx.setLineDash([3, 5]); ctx.lineWidth = 1; ctx.stroke();
    ctx.restore();
    label(ctx, `Bird perch ${index === 0 ? 'W' : 'E'}`, perch.x, perch.y + 42, { size: 11 });
  }
}

function drawExit(ctx, room, game) {
  const { x, y, r } = room.exit;
  ctx.save(); ctx.fillStyle = '#9eae6620';
  circle(ctx, x, y, r + 7); ctx.fill();
  ctx.strokeStyle = COLORS.exit; ctx.lineWidth = 2;
  circle(ctx, x, y, r); ctx.stroke();
  ctx.fillStyle = COLORS.exit;
  const pulse = 1 + Math.sin(game.time * 2.4) * .1;
  ctx.beginPath();
  ctx.moveTo(x, y - 13 * pulse); ctx.lineTo(x + 8, y); ctx.lineTo(x, y + 13 * pulse); ctx.lineTo(x - 8, y); ctx.closePath(); ctx.fill();
  label(ctx, 'EXIT', x, y - 48, { color: '#d0dda7', bold: true, size: 13 });
  label(ctx, 'Mouse only', x, y + 49, { size: 11 });
  ctx.restore();
}

function drawRoom(ctx, game) {
  const room = game.room;
  ctx.fillStyle = '#172132'; ctx.fillRect(0, 0, game.width, game.height);
  ctx.fillStyle = COLORS.floor; roundedRect(ctx, 24, 24, game.width - 48, game.height - 48, 12); ctx.fill();
  ctx.save();
  for (let x = 50; x < game.width - 24; x += 50) {
    for (let y = 50; y < game.height - 24; y += 50) {
      ctx.fillStyle = COLORS.grid; circle(ctx, x, y, 1.1); ctx.fill();
    }
  }
  const river = room.river;
  ctx.fillStyle = COLORS.water; ctx.fillRect(river.x, river.y, river.w, river.h);
  line(ctx, river.x - 3, river.y, river.x - 3, river.y + river.h, '#60808e55', 3);
  line(ctx, river.x + river.w + 3, river.y, river.x + river.w + 3, river.y + river.h, '#60808e55', 3);
  ctx.strokeStyle = COLORS.waterLine; ctx.lineWidth = 1; ctx.globalAlpha = .35;
  for (let y = river.y + 28; y < river.y + river.h; y += 38) {
    const offset = Math.sin(game.time * .6 + y) * 5;
    ctx.beginPath(); ctx.moveTo(river.x + 22 + offset, y); ctx.quadraticCurveTo(river.x + 50, y + 6, river.x + 81 + offset, y); ctx.stroke();
  }
  ctx.restore();
  label(ctx, 'DEEP WATER', river.x + river.w / 2, 85, { size: 10, color: '#89abc1' });
  if (room.coveredExit) {
    const roof = room.coveredExit;
    ctx.save();
    ctx.fillStyle = '#67758c1c'; ctx.fillRect(roof.x, roof.y, roof.w, roof.h);
    ctx.beginPath(); ctx.rect(roof.x, roof.y, roof.w, roof.h); ctx.clip();
    ctx.strokeStyle = '#8996aa18'; ctx.lineWidth = 1;
    for (let y = roof.y - roof.w; y < roof.y + roof.h; y += 26) {
      ctx.beginPath(); ctx.moveTo(roof.x, y); ctx.lineTo(roof.x + roof.w, y + roof.w); ctx.stroke();
    }
    ctx.restore();
    label(ctx, 'Covered burrow', roof.x + roof.w / 2, roof.y + 43, { size: 11, color: '#b9c6d3' });
    label(ctx, 'Roof blocks Bird', roof.x + roof.w / 2, roof.y + 64, { size: 10 });
  }
  const bridge = room.bridge;
  ctx.save(); ctx.strokeStyle = game.bridgeOpen ? '#b9be9b' : '#68809166'; ctx.lineWidth = 1;
  if (!game.bridgeOpen) ctx.setLineDash([4, 6]);
  roundedRect(ctx, bridge.x, bridge.y, bridge.w, bridge.h, 3); ctx.stroke(); ctx.restore();
  if (game.bridgeOpen) label(ctx, 'Crossing open', bridge.x + bridge.w / 2, bridge.y + bridge.h + 21, { size: 11, color: '#c6d5ad', backdrop: true });
  else label(ctx, 'Push slab into water', 725, 513, { size: 11, color: '#c3a799' });
  drawPerches(ctx, room, game.animals.find(animal => animal.id === 'bird'));
  ctx.fillStyle = '#a5b99b66';
  for (const [dx, dy] of [[-8, 2], [4, -5], [8, 6]]) { circle(ctx, 490 + dx, 245 + dy, 2.5); ctx.fill(); }
  label(ctx, 'Bird feeding spot', 453, 207, { size: 11 });
  for (const animal of game.animals) drawHome(ctx, animal, game);
  for (const wall of room.walls) drawWall(ctx, wall);
  ctx.strokeStyle = '#4a5d76'; ctx.lineWidth = 4;
  roundedRect(ctx, 24, 24, game.width - 48, game.height - 48, 12); ctx.stroke();
  label(ctx, 'Mouse passage', room.mouseGap.x - 74, room.mouseGap.y + 17, { size: 11, color: '#cfbd94', backdrop: true });
  arrow(ctx, room.mouseGap.x - 25, room.mouseGap.y + 17, room.mouseGap.x - 3, room.mouseGap.y + 17, '#b3a27f');
  label(ctx, 'Mouse passage', room.exitGap.x - 64, room.exitGap.y - 18, { size: 11, color: '#cfbd94', backdrop: true });
  arrow(ctx, room.exitGap.x - 23, room.exitGap.y + room.exitGap.h / 2, room.exitGap.x - 3, room.exitGap.y + room.exitGap.h / 2, '#b3a27f');
  drawExit(ctx, room, game);
}

function drawBlock(ctx, game) {
  const block = game.bridgeOpen ? game.room.bridge : game.block;
  ctx.save();
  ctx.fillStyle = '#101b2c77'; roundedRect(ctx, block.x + 4, block.y + 6, block.w, block.h, 5); ctx.fill();
  ctx.fillStyle = game.bridgeOpen ? '#747c78' : '#817b7c';
  roundedRect(ctx, block.x, block.y, block.w, block.h, 5); ctx.fill();
  ctx.strokeStyle = '#b1a8a1'; ctx.lineWidth = 2;
  roundedRect(ctx, block.x + 1, block.y + 1, block.w - 2, block.h - 2, 4); ctx.stroke();
  line(ctx, block.x + 13, block.y + 13, block.x + block.w - 13, block.y + 13, '#d8cebf55', 2);
  if (!game.bridgeOpen) {
    arrow(ctx, block.x + block.w / 2 + 18, block.y + block.h / 2, block.x + block.w / 2 - 18, block.y + block.h / 2, '#e0cfb5');
    label(ctx, 'HEAVY', block.x + block.w / 2, block.y - 16, { size: 10, bold: true, color: '#c8b5aa', backdrop: true });
  }
  ctx.restore();
}

function drawAnimal(ctx, animal, controlled, targeted, valid, game) {
  const { x, y, radius: r } = animal;
  const color = animal.color || COLORS[animal.id];
  ctx.save();
  ctx.fillStyle = '#0b152640'; ctx.beginPath(); ctx.ellipse(x + 2, y + r * .65, r + 3, r * .53, 0, 0, Math.PI * 2); ctx.fill();
  if (controlled) {
    ctx.strokeStyle = '#eff0df'; ctx.lineWidth = 2;
    circle(ctx, x, y, r + 8); ctx.stroke();
    ctx.fillStyle = '#eff0df'; ctx.beginPath(); ctx.moveTo(x, y - r - 14); ctx.lineTo(x - 4, y - r - 21); ctx.lineTo(x + 4, y - r - 21); ctx.closePath(); ctx.fill();
  }
  if (valid) {
    ctx.strokeStyle = targeted ? '#d5e6ff' : '#9ab5ce99'; ctx.lineWidth = targeted ? 2 : 1;
    ctx.setLineDash([4, 4]); circle(ctx, x, y, r + 11); ctx.stroke(); ctx.setLineDash([]);
  }
  if (targeted && game.mode === 'spirit') {
    ctx.strokeStyle = '#e9d491'; ctx.lineWidth = 4;
    ctx.beginPath(); ctx.arc(x, y, r + 16, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * game.focus); ctx.stroke();
  }
  ctx.strokeStyle = '#182235'; ctx.lineWidth = 2; ctx.fillStyle = color;
  if (animal.id === 'mouse') {
    ctx.strokeStyle = color; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.moveTo(x - r + 3, y + 4); ctx.quadraticCurveTo(x - r - 18, y + 14, x - r - 15, y - 6); ctx.stroke();
    ctx.lineWidth = 2; ctx.strokeStyle = '#182235';
    ctx.beginPath(); ctx.ellipse(x, y + 2, r, r * .8, 0, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
    for (const dx of [-r * .47, r * .47]) { circle(ctx, x + dx, y - r * .56, r * .42); ctx.fill(); ctx.stroke(); }
    ctx.fillStyle = '#b59981'; circle(ctx, x - r * .47, y - r * .56, r * .2); ctx.fill(); circle(ctx, x + r * .47, y - r * .56, r * .2); ctx.fill();
  } else if (animal.id === 'bird') {
    ctx.beginPath(); ctx.moveTo(x - r - 8, y + 1); ctx.quadraticCurveTo(x - 8, y - r - 5, x, y); ctx.quadraticCurveTo(x + 10, y - r - 5, x + r + 8, y + 1); ctx.quadraticCurveTo(x + 10, y + 9, x, y + 7); ctx.quadraticCurveTo(x - 10, y + 9, x - r - 8, y + 1); ctx.fill(); ctx.stroke();
    circle(ctx, x, y, r * .7); ctx.fill(); ctx.stroke();
    ctx.fillStyle = '#e4c489'; ctx.beginPath(); ctx.moveTo(x - 4, y + 3); ctx.lineTo(x, y + 12); ctx.lineTo(x + 4, y + 3); ctx.closePath(); ctx.fill();
  } else {
    for (const dx of [-r * .63, r * .63]) { circle(ctx, x + dx, y - r * .64, r * .36); ctx.fill(); ctx.stroke(); }
    circle(ctx, x, y, r); ctx.fill(); ctx.stroke();
    ctx.fillStyle = '#e8b99e'; ctx.beginPath(); ctx.ellipse(x, y + 7, r * .45, r * .34, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#253044'; circle(ctx, x, y + 5, 4); ctx.fill();
  }
  ctx.fillStyle = '#253044';
  for (const dx of [-4, 4]) { circle(ctx, x + dx, y - 2, 1.7); ctx.fill(); }
  ctx.restore();
  label(ctx, animal.name || animal.id, x, y + r + 21, { color: controlled ? '#f0e8d1' : color, bold: true, backdrop: true });
}

function drawSpirit(ctx, game) {
  const spirit = game.spirit;
  const anchor = game.animals.find(animal => animal.id === spirit.anchorId);
  if (anchor) line(ctx, anchor.x, anchor.y, spirit.x, spirit.y, '#adc7e399', 1, true);
  ctx.save();
  const float = Math.sin(game.time * 3) * 1.8;
  ctx.shadowColor = '#adcfff'; ctx.shadowBlur = 15; ctx.fillStyle = '#d7e7ff';
  ctx.beginPath(); ctx.moveTo(spirit.x - 10, spirit.y + 9 + float);
  ctx.lineTo(spirit.x - 10, spirit.y - 2 + float);
  ctx.arc(spirit.x, spirit.y - 2 + float, 10, Math.PI, 0);
  ctx.lineTo(spirit.x + 10, spirit.y + 9 + float);
  ctx.quadraticCurveTo(spirit.x + 5, spirit.y + 5 + float, spirit.x, spirit.y + 11 + float);
  ctx.quadraticCurveTo(spirit.x - 5, spirit.y + 5 + float, spirit.x - 10, spirit.y + 9 + float); ctx.fill();
  ctx.shadowBlur = 0; ctx.fillStyle = '#51698b'; circle(ctx, spirit.x - 3, spirit.y - 2 + float, 1.5); ctx.fill(); circle(ctx, spirit.x + 3, spirit.y - 2 + float, 1.5); ctx.fill();
  ctx.restore();
}

function drawIndicators(ctx, game, debug) {
  if (game.mode !== 'spirit') return;
  const anchor = game.animals.find(animal => animal.id === game.spirit.anchorId);
  if (anchor) {
    ctx.save(); ctx.fillStyle = '#aec4e807'; ctx.strokeStyle = '#aec4e87a'; ctx.lineWidth = 2; ctx.setLineDash([7, 6]);
    circle(ctx, anchor.x, anchor.y, game.spiritRange); ctx.fill(); ctx.stroke(); ctx.restore();
    if (debug) label(ctx, 'Spirit tether', anchor.x, anchor.y - game.spiritRange - 14, { size: 10, color: '#adc1df', backdrop: true });
  }
  if (debug) {
    ctx.save(); ctx.strokeStyle = '#d4e6ff44'; ctx.lineWidth = 1; circle(ctx, game.spirit.x, game.spirit.y, game.targetRange); ctx.stroke(); ctx.restore();
  }
}

export function drawGame(ctx, game, options = {}) {
  const debug = options.debug !== false;
  ctx.save();
  ctx.clearRect(0, 0, game.width, game.height);
  drawRoom(ctx, game);
  drawBlock(ctx, game);
  if (debug) {
    for (const animal of game.animals) {
      if (animal.state === 'returning') {
        line(ctx, animal.x, animal.y, animal.home.x, animal.home.y, `${animal.color || COLORS[animal.id]}66`, 1, true);
      }
    }
  }
  drawIndicators(ctx, game, debug);
  for (const animal of game.animals) {
    const valid = game.mode === 'spirit' && Math.hypot(animal.x - game.spirit.x, animal.y - game.spirit.y) <= game.targetRange;
    drawAnimal(ctx, animal, game.mode === 'animal' && animal.id === game.activeId, animal.id === game.targetId, valid, game);
    if (debug && animal.state !== 'controlled') {
      const atHome = Math.hypot(animal.x - animal.home.x, animal.y - animal.home.y) < 3;
      const stateLabel = animal.state === 'returning' ? 'returning home' : atHome ? 'at home' : 'resting';
      label(ctx, stateLabel, animal.x, animal.y + animal.radius + 41, { size: 10, color: '#95a5bd', backdrop: true });
    }
  }
  if (game.mode === 'spirit') drawSpirit(ctx, game);
  if (debug) {
    label(ctx, game.mode === 'spirit' ? 'Dashed circle = tether · small circle = possession reach' : 'Bright ring = you · dashed line = return destination', 47, 650, { size: 10, color: '#879bb7', align: 'left' });
  }
  if (game.mode === 'won') {
    ctx.fillStyle = '#101b2d9c'; ctx.fillRect(0, 0, game.width, game.height);
    ctx.fillStyle = '#23364af5'; roundedRect(ctx, 330, 282, 440, 126, 12); ctx.fill();
    ctx.strokeStyle = '#719083'; ctx.lineWidth = 1; roundedRect(ctx, 330, 282, 440, 126, 12); ctx.stroke();
    label(ctx, 'You made the crossing.', 550, 323, { size: 25, color: '#e5efcd', bold: true });
    label(ctx, 'Press Y or R to try the chain again.', 550, 371, { size: 14, color: '#b7cbd7' });
  }
  ctx.restore();
}

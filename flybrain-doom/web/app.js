// Browser app: watch a fly play, run experiments in Web Workers, read the wiring.
/* global FlyCore, Renderer, drawEyes, REFERENCE */

const C = FlyCore;
const $ = (id) => document.getElementById(id);
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const css = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
const SERIES = { intact: '--s1', 'no-dopamine': '--s2', 'kc-block': '--s3', scrambled: '--s4', random: '--s5', 'lc10a-lesion': '--s6' };
const ORB_CSS = { blue: '--orb-blue', green: '--orb-green' };
const fmt = (x, d = 2) => (isFinite(x) ? (x >= 0 ? '+' : '−') + Math.abs(x).toFixed(d) : 'n/a');
const fmtP = C.fmtP;

// ---------- tabs ----------
const TABS = ['watch', 'lab', 'wiring'];
function showTab(name) {
  for (const t of TABS) {
    $('tab-' + t).setAttribute('aria-selected', String(t === name));
    $('view-' + t).hidden = t !== name;
  }
  try { localStorage.setItem('fbd-tab', name); } catch (e) { /* storage unavailable */ }
  if (name === 'lab') renderLab();
}
for (const t of TABS) $('tab-' + t).addEventListener('click', () => showTab(t));

// =====================================================================
// WATCH
// =====================================================================
const WATCH_CONDITIONS = ['intact', 'no-dopamine', 'kc-block', 'scrambled', 'lc10a-lesion'];
const S = {
  scenario: 'doom', condition: 'intact', speed: 1, playing: true, human: false,
  fly: 1, episode: 0, goodColor: 'blue', swapped: false, world: null, agent: null, ev: null,
  rates: {}, history: [], banner: null, bannerUntil: 0, acc: 0, last: 0, memory: null,
};
for (const [k, v] of Object.entries(C.SCENARIOS)) $('scenario').add(new Option(v.label, k));
for (const k of WATCH_CONDITIONS) $('condition').add(new Option(C.CONDITIONS[k].label, k));
$('scenario').value = S.scenario;

const renderer = new Renderer($('game'));

function newFly(seed) {
  S.fly = seed ?? (1 + Math.floor(Math.random() * 9999));
  S.agent = C.makeAgent(S.condition, C.hashSeed('watch', S.fly));
  S.goodColor = S.fly % 2 ? 'green' : 'blue';
  S.episode = 0;
  S.history = [];
  S.rates = {};
  for (const k of Object.keys(S.agent.brain.groups)) S.rates[k] = 0;
  rasterRows = buildRasterRows(S.agent.brain);
  buildBrainGeometry(S.agent);
  log(`New fly #${S.fly} (${C.CONDITIONS[S.condition].label}). ${cap(S.goodColor)} orbs heal.`);
  newEpisode();
}
function newEpisode() {
  S.world = new C.World({ scenario: S.scenario, seed: C.hashSeed('watch-world', S.fly, S.episode, S.scenario), goodColor: S.goodColor });
  S.agent.beginEpisode();
  S.ev = null;
  S.banner = `EPISODE ${S.episode + 1}`;
  S.bannerUntil = performance.now() + 1100;
}
const cap = (s) => s[0].toUpperCase() + s.slice(1);

// keyboard for "You play"
const keys = new Set();
addEventListener('keydown', (e) => {
  if (!S.human || $('view-watch').hidden) return;
  if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', ' '].includes(e.key)) e.preventDefault();
  keys.add(e.key.toLowerCase());
});
addEventListener('keyup', (e) => keys.delete(e.key.toLowerCase()));
function humanAction() {
  const k = (a, b) => keys.has(a) || keys.has(b);
  return {
    turn: (k('arrowleft', 'a') ? 1 : 0) - (k('arrowright', 'd') ? 1 : 0),
    forward: (k('arrowup', 'w') ? 1 : 0) - (k('arrowdown', 's') ? 1 : 0),
    strafe: (keys.has('q') ? 1 : 0) - (keys.has('e') ? 1 : 0),
    fire: keys.has(' '),
  };
}

function tick() {
  const w = S.world, a = S.agent;
  const brainAction = a.act(w, S.ev);
  const action = S.human ? humanAction() : brainAction;
  const ev = w.step(action);
  S.ev = ev;
  // smoothed group rates for the diagram
  const b = a.brain, k = 1 - Math.exp(-C.TIC / 0.12);
  for (const key in S.rates) S.rates[key] += k * (b.groupCount(key) / b.groups[key].length / C.TIC - S.rates[key]);
  pushRaster(b);
  if (ev.good) log(`<b>${w.time.toFixed(1)}s</b> touched ${S.goodColor} orb: healed +10. PAM dopamine fires.`);
  if (ev.bad) log(`<b>${w.time.toFixed(1)}s</b> touched ${C.otherColor(S.goodColor)} orb: burned −12. PPL1 dopamine fires.`);
  if (ev.kill) log(`<b>${w.time.toFixed(1)}s</b> killed an imp.`);
  if (ev.damage && !ev.bad) log(`<b>${w.time.toFixed(1)}s</b> hit for ${ev.damage}.`);
  if (ev.died) log(`<b>${w.time.toFixed(1)}s</b> the fly died.`);
  if (w.done) {
    const s = w.stats, n = s.good + s.bad;
    S.history.push({ pi: n ? (s.good - s.bad) / n : null, good: s.good, bad: s.bad, kills: s.kills, color: S.goodColor });
    if (S.history.length > 40) S.history.shift();
    log(`Episode ${S.episode + 1} over: ${s.good} healing, ${s.bad} burning orbs, ${s.kills} kills.`);
    S.episode++;
    newEpisode();
  }
}

function loop(now) {
  const dt = Math.min(0.25, (now - (S.last || now)) / 1000);
  S.last = now;
  if (S.playing) {
    S.acc += dt * C.TIC_RATE * S.speed;
    const t0 = performance.now();
    let n = 0;
    while (S.acc >= 1 && performance.now() - t0 < 14) { tick(); S.acc -= 1; n++; }
    if (S.acc > 4) S.acc = 0; // can't keep up: drop backlog
  }
  if (!$('view-watch').hidden) drawWatch(now);
  requestAnimationFrame(loop);
}

let memTimer = 0;
function drawWatch(now) {
  const w = S.world, a = S.agent;
  renderer.draw(w, { turn: a.lastAction?.turn || 0, banner: now < S.bannerUntil ? S.banner : (!S.playing ? 'PAUSED' : null) });
  drawEyes($('eyes'), a.lastOptics);
  drawBrain();
  drawRaster();
  if (now - memTimer > 250) { memTimer = now; S.memory = a.memory(); drawMemory(); drawMotor(); drawSession(); }
}

// ---------- event log ----------
function log(html) {
  const li = document.createElement('li');
  li.innerHTML = html;
  const ul = $('log');
  ul.prepend(li);
  while (ul.children.length > 40) ul.lastChild.remove();
}

// ---------- memory, motor, session ----------
function meter(label, value, lo, hi, color, text) {
  const mid = lo < 0 ? (0 - lo) / (hi - lo) : 0;
  const v = (clamp(value, lo, hi) - lo) / (hi - lo);
  const left = Math.min(mid, v) * 100, width = Math.abs(v - mid) * 100;
  return `<div class="meter"><span>${label}</span><span class="bar">${lo < 0 ? '<span class="mid"></span>' : ''}<i style="left:${left}%;width:${Math.max(width, 0.8)}%;background:${color}"></i></span><output>${text}</output></div>`;
}
function drawMemory() {
  const m = S.memory || {};
  const rows = [['blue', 'Blue orb', css('--orb-blue')], ['green', 'Green orb', css('--orb-green')], ['red', 'Imp (red)', css('--imp')], ['dark', 'Imp (dark)', css('--faint')]];
  $('memory').innerHTML = rows.map(([k, label, col]) => meter(label, m[k]?.valence ?? 0, -1, 1, col, fmt(m[k]?.valence ?? 0))).join('');
  const chip = $('heals-chip');
  chip.textContent = `${S.goodColor} heals`;
  chip.style.color = css(ORB_CSS[S.goodColor]);
}
function drawMotor() {
  const r = S.agent.lastAction || {};
  $('motor').innerHTML = [
    meter('Turn', r.turn || 0, -1, 1, css('--ink'), (r.turn || 0) > 0.05 ? 'left' : (r.turn || 0) < -0.05 ? 'right' : 'straight'),
    meter('Walk', r.forward || 0, -1, 1, css('--ink'), (r.forward || 0) >= 0 ? 'fwd' : 'back'),
    meter('Sidestep', r.strafe || 0, -1, 1, css('--ink'), Math.abs(r.strafe || 0) > 0.1 ? 'escape' : '–'),
    meter('Fire', r.fire ? 1 : 0, 0, 1, css('--accent'), r.fire ? 'BANG' : '–'),
  ].join('');
  $('brain-note').textContent = S.human ? 'You are steering; the brain is watching' : `${C.CONDITIONS[S.condition].label}, fly #${S.fly}`;
}
function drawSession() {
  const w = S.world, s = w.stats, n = s.good + s.bad;
  const recent = S.history.slice(-5).map((h) => h.pi).filter((x) => x !== null);
  const avg = recent.length ? recent.reduce((p, q) => p + q, 0) / recent.length : NaN;
  $('session').innerHTML = [
    `Episode <b>${S.episode + 1}</b>`,
    `This episode PI <b>${n ? fmt((s.good - s.bad) / n) : '–'}</b>`,
    `Last 5 episodes PI <b>${isFinite(avg) ? fmt(avg) : '–'}</b>`,
    `Kills <b>${s.kills}</b>`,
    `Health <b>${Math.round(w.player.health)}</b>`,
  ].join('');
}

// ---------- brain diagram ----------
const NODE_POS = {
  MECH: [50, 40], HS: [120, 40], LPLC2: [190, 40], LC4: [255, 40], LC10a: [330, 40], vPN: [420, 40],
  MECHb: [50, 120], AOTU025: [250, 145], AOTU019: [330, 145], KC: [425, 150], APL: [478, 92],
  LALi: [230, 255], MBON01: [310, 255], MBON11: [385, 255], PPL101: [452, 238], PAM: [482, 290],
  NOCI: [440, 345], GRN: [484, 382],
  DNp01: [110, 460], MDN: [190, 460], DNa01: [270, 460], DNa02: [340, 460], P9: [410, 460],
};
const SHORT = { MBON11: 'MBON-11', MBON01: 'MBON-01', PPL101: 'PPL1', DNp01: 'GF', AOTU019: 'AOTU019', AOTU025: 'AOTU025' };
let geo = null;
function buildBrainGeometry(agent) {
  const conn = agent.conn, nodes = [], edges = new Map();
  for (const [type, def] of Object.entries(C.CELL_TYPES)) {
    for (let s = 0; s < 2; s++) {
      const p = NODE_POS[type];
      if (!p) continue;
      nodes.push({ key: `${type}_${C.SIDES[s]}`, type, side: s, x: s === 0 ? p[0] : 1000 - p[0], y: p[1], r: Math.min(26, 6 + 1.6 * Math.sqrt(def.perSide)), nt: def.nt, sign: def.sign ?? C.NT_SIGN[def.nt] });
    }
  }
  const byKey = Object.fromEntries(nodes.map((n) => [n.key, n]));
  for (let k = 0; k < conn.pre.length; k++) {
    const a = conn.neurons[conn.pre[k]], b = conn.neurons[conn.post[k]];
    const ka = `${a.type}_${C.SIDES[a.side]}`, kb = `${b.type}_${C.SIDES[b.side]}`;
    if (ka === kb) continue;
    const id = ka + '>' + kb;
    let e = edges.get(id);
    if (!e) { e = { a: byKey[ka], b: byKey[kb], count: 0, sign: conn.sign[conn.pre[k]], plastic: a.type === 'KC' && (b.type === 'MBON11' || b.type === 'MBON01') }; edges.set(id, e); }
    e.count += conn.count[k];
  }
  geo = { nodes, edges: [...edges.values()].filter((e) => e.a && e.b), byKey };
}
const MAXRATE = { KC: 25, APL: 80, vPN: 150, LC10a: 140, LC4: 180, LPLC2: 200, HS: 120, MECH: 220, MECHb: 220, NOCI: 250, GRN: 250 };
function drawBrain() {
  const cv = $('brain'), g = cv.getContext('2d');
  g.clearRect(0, 0, cv.width, cv.height);
  g.fillStyle = css('--panel'); g.fillRect(0, 0, cv.width, cv.height);
  if (!geo) return;
  // midline
  g.strokeStyle = css('--grid'); g.lineWidth = 1; g.setLineDash([4, 6]);
  g.beginPath(); g.moveTo(500, 10); g.lineTo(500, 540); g.stroke(); g.setLineDash([]);
  g.font = `600 12px ${css('--body')}`; g.fillStyle = css('--faint'); g.textAlign = 'center';
  g.fillText('LEFT HEMISPHERE', 250, 545); g.fillText('RIGHT HEMISPHERE', 750, 545);
  const mem = S.memory;
  const plast = plasticBySide();
  for (const e of geo.edges) {
    const act = clamp((S.rates[e.a.key] || 0) / (MAXRATE[e.a.type] || 100), 0, 1);
    let width = 0.4 + Math.log10(1 + e.count) * 0.45, color = e.sign > 0 ? css('--exc') : css('--inh'), alpha = 0.1 + 0.55 * act;
    if (e.plastic) {
      const comp = e.b.type === 'MBON11' ? 0 : 2;
      const ratio = plast[comp + e.b.side];
      width = 0.5 + 5 * ratio; color = css('--reward'); alpha = 0.35 + 0.5 * act;
    }
    g.globalAlpha = alpha; g.strokeStyle = color; g.lineWidth = width;
    const mx = (e.a.x + e.b.x) / 2 + (e.a.side !== e.b.side ? 0 : (e.a.y - e.b.y) * 0.12);
    const my = (e.a.y + e.b.y) / 2;
    g.beginPath(); g.moveTo(e.a.x, e.a.y); g.quadraticCurveTo(mx, my, e.b.x, e.b.y); g.stroke();
  }
  g.globalAlpha = 1;
  // dopamine teaching signals (modulatory, dashed)
  for (let s = 0; s < 2; s++) {
    for (const [dan, mbon, col] of [['PPL101', 'MBON11', '--punish'], ['PAM', 'MBON01', '--reward']]) {
      const a = geo.byKey[`${dan}_${C.SIDES[s]}`], b = geo.byKey[`${mbon}_${C.SIDES[s]}`];
      const act = clamp((S.rates[a.key] || 0) / 120, 0, 1);
      g.globalAlpha = 0.25 + 0.75 * act; g.strokeStyle = css(col); g.lineWidth = 1.5 + 3 * act; g.setLineDash([3, 4]);
      g.beginPath(); g.moveTo(a.x, a.y); g.lineTo(b.x, b.y); g.stroke(); g.setLineDash([]);
    }
  }
  g.globalAlpha = 1;
  for (const n of geo.nodes) {
    const rate = S.rates[n.key] || 0;
    const act = clamp(rate / (MAXRATE[n.type] || 100), 0, 1);
    const base = n.nt === 'DA' ? (n.type === 'PAM' ? css('--reward') : css('--punish')) : n.sign > 0 ? css('--exc') : css('--inh');
    if (act > 0.02) {
      const gr = g.createRadialGradient(n.x, n.y, n.r * 0.3, n.x, n.y, n.r * 2.2);
      gr.addColorStop(0, base); gr.addColorStop(1, 'rgba(0,0,0,0)');
      g.globalAlpha = act * 0.7; g.fillStyle = gr; g.beginPath(); g.arc(n.x, n.y, n.r * 2.2, 0, 7); g.fill();
    }
    g.globalAlpha = 1;
    g.fillStyle = css('--panel-2'); g.beginPath(); g.arc(n.x, n.y, n.r, 0, 7); g.fill();
    g.globalAlpha = 0.25 + 0.75 * act; g.fillStyle = base; g.beginPath(); g.arc(n.x, n.y, n.r - 2, 0, 7); g.fill();
    g.globalAlpha = 1; g.strokeStyle = base; g.lineWidth = 1.5; g.beginPath(); g.arc(n.x, n.y, n.r, 0, 7); g.stroke();
    g.fillStyle = css('--ink'); g.font = `500 12px ${css('--mono')}`; g.textAlign = 'center';
    g.fillText(SHORT[n.type] || n.type, n.x, n.y + n.r + 14);
  }
}
function plasticBySide() {
  const b = S.agent.brain, sum = [0, 0, 0, 0], n = [0, 0, 0, 0];
  for (let p = 0; p < b.plSlot.length; p += 7) { const c = b.plComp[p]; sum[c] += b.outW[b.plSlot[p]] / b.plW0[p]; n[c]++; }
  return sum.map((s, i) => (n[i] ? s / n[i] : 1));
}

// ---------- spike raster ----------
let rasterRows = [];
function buildRasterRows(brain) {
  const rows = [];
  const add = (key, k, color) => { const ids = brain.groups[key]; for (let i = 0; i < Math.min(k, ids.length); i++) rows.push({ id: ids[i], color }); };
  const kc = css('--muted');
  add('KC_L', 34, kc); add('KC_R', 34, kc);
  for (const s of ['L', 'R']) { add('MBON11_' + s, 2, css('--inh')); add('MBON01_' + s, 2, css('--exc')); add('LALi_' + s, 2, css('--inh')); }
  for (const s of ['L', 'R']) { add('PPL101_' + s, 1, css('--punish')); add('PAM_' + s, 3, css('--reward')); }
  for (const s of ['L', 'R']) add('AOTU019_' + s, 4, css('--inh'));
  for (const t of ['DNa02', 'DNa01', 'P9', 'MDN', 'DNp01']) for (const s of ['L', 'R']) add(`${t}_${s}`, 2, css('--ink'));
  return rows;
}
const rasterBuf = [];
function pushRaster(brain) {
  const col = new Uint8Array(rasterRows.length);
  for (let i = 0; i < rasterRows.length; i++) col[i] = brain.counts[rasterRows[i].id] > 0 ? 1 : 0;
  rasterBuf.push(col);
  if (rasterBuf.length > 400) rasterBuf.shift();
}
function drawRaster() {
  const cv = $('raster'), g = cv.getContext('2d'), W = cv.width, H = cv.height;
  g.fillStyle = '#100d0b'; g.fillRect(0, 0, W, H);
  const rh = H / Math.max(1, rasterRows.length), cw = 2;
  const cols = Math.min(rasterBuf.length, Math.floor(W / cw));
  for (let c = 0; c < cols; c++) {
    const col = rasterBuf[rasterBuf.length - cols + c], x = W - (cols - c) * cw;
    for (let i = 0; i < col.length; i++) if (col[i]) { g.fillStyle = rasterRows[i].color; g.fillRect(x, i * rh, cw, Math.max(1, rh)); }
  }
}

// ---------- controls ----------
$('play').addEventListener('click', () => { S.playing = !S.playing; $('play').textContent = S.playing ? 'Pause' : 'Play'; });
$('speed').addEventListener('change', (e) => { S.speed = Number(e.target.value); });
$('scenario').addEventListener('change', (e) => { S.scenario = e.target.value; newEpisode(); log(`Scenario: ${C.SCENARIOS[S.scenario].label}.`); });
$('condition').addEventListener('change', (e) => { S.condition = e.target.value; newFly(S.fly); });
$('newfly').addEventListener('click', () => newFly());
$('swap').addEventListener('click', () => {
  S.goodColor = C.otherColor(S.goodColor);
  S.world.goodColor = S.goodColor;
  log(`<b>Colors swapped.</b> ${cap(S.goodColor)} orbs heal now. The fly's memory still says otherwise.`);
});
$('human').addEventListener('click', () => {
  S.human = !S.human;
  $('human').setAttribute('aria-pressed', String(S.human));
  $('human-note').hidden = !S.human;
  keys.clear();
});
$('game').addEventListener('click', () => { if (S.human) $('game').focus(); });

// =====================================================================
// LAB
// =====================================================================
const LAB_PROTOCOLS = { quick: 'Quick learning check', learning: 'Valence learning + reversal', combat: 'Imp combat' };
for (const [k, v] of Object.entries(LAB_PROTOCOLS)) $('protocol').add(new Option(v, k));
const ALL_CONDITIONS = Object.keys(C.CONDITIONS);
for (const k of ALL_CONDITIONS) {
  const id = 'cc-' + k;
  const l = document.createElement('label');
  l.innerHTML = `<input type="checkbox" id="${id}" value="${k}"><span class="dot" style="background:var(${SERIES[k]})"></span>${C.CONDITIONS[k].label}`;
  l.title = C.CONDITIONS[k].about;
  $('cond-checks').append(l);
}
function applyProtocolDefaults() {
  const P = C.PROTOCOLS[$('protocol').value];
  const small = $('protocol').value !== 'quick';
  $('subjects').value = small ? 8 : P.subjects;
  $('acq').value = small ? Math.min(P.acquisition, 8) : P.acquisition;
  $('rev').value = small ? Math.min(P.reversal, 4) : P.reversal;
  $('rev').disabled = P.scenario === 'combat';
  for (const k of ALL_CONDITIONS) $('cc-' + k).checked = P.conditions.includes(k);
  $('protocol-note').textContent = `${C.SCENARIOS[P.scenario].about} Defaults are trimmed for a browser; the CLI runs the full design.`;
}
$('protocol').addEventListener('change', () => { applyProtocolDefaults(); renderLab(); });
$('protocol').value = 'quick';
applyProtocolDefaults();

let lab = { analysis: null, source: null, results: null, workers: [], running: false };

function workerSource() {
  return document.getElementById('flycore').textContent + `
;self.onmessage = (e) => {
  const { protocol, condition, subject, baseSeed } = e.data;
  const r = FlyCore.runSubject({ protocol, condition, subject, baseSeed });
  self.postMessage(r);
};`;
}

function runLab() {
  const P = { ...C.PROTOCOLS[$('protocol').value] };
  P.subjects = clamp(Number($('subjects').value) || 4, 2, 64);
  P.acquisition = clamp(Number($('acq').value) || 4, 2, 40);
  P.reversal = P.scenario === 'combat' ? 0 : clamp(Number($('rev').value) || 0, 0, 20);
  P.conditions = ALL_CONDITIONS.filter((k) => $('cc-' + k).checked);
  if (!P.conditions.length) { $('lab-status').textContent = 'Pick at least one condition.'; return; }
  const seed = Number($('seed').value) || 1;
  const tasks = [...C.tasksFor(P)];
  const url = URL.createObjectURL(new Blob([workerSource()], { type: 'text/javascript' }));
  const nW = Math.max(1, Math.min(tasks.length, (navigator.hardwareConcurrency || 4) - 1, 8));
  const results = [];
  let next = 0, done = 0;
  const t0 = performance.now();
  lab.running = true;
  $('run').disabled = true; $('stop').disabled = false;
  $('lab-status').textContent = `Running ${tasks.length} fly runs on ${nW} workers…`;
  lab.workers = [];
  for (let i = 0; i < nW; i++) {
    const w = new Worker(url);
    const feed = () => { if (next < tasks.length) w.postMessage({ protocol: P, baseSeed: seed, ...tasks[next++] }); };
    w.onmessage = (e) => {
      results.push(e.data);
      done++;
      $('prog').style.width = `${(done / tasks.length) * 100}%`;
      $('lab-status').textContent = `${done} of ${tasks.length} fly runs, ${((performance.now() - t0) / 1000).toFixed(0)} s`;
      if (done % Math.max(1, P.conditions.length) === 0 || done === tasks.length) {
        lab.analysis = C.analyze(P, results);
        lab.results = { protocol: P, seed, results };
        lab.source = done === tasks.length ? `Your run, seed ${seed}` : `Your run so far (${done}/${tasks.length})`;
        renderLab();
      }
      if (done === tasks.length) finishLab();
      else feed();
    };
    w.onerror = (err) => { $('lab-status').textContent = `A worker failed: ${err.message}`; stopLab(); };
    lab.workers.push(w);
    feed();
  }
}
function finishLab() {
  stopLab(true);
  $('lab-status').textContent = `Done. ${$('lab-status').textContent.replace(/^Done\. /, '')}`;
}
function stopLab(quiet) {
  for (const w of lab.workers) w.terminate();
  lab.workers = []; lab.running = false;
  $('run').disabled = false; $('stop').disabled = true;
  if (!quiet) $('lab-status').textContent = 'Stopped.';
}
$('run').addEventListener('click', runLab);
$('stop').addEventListener('click', () => stopLab());
$('copy').addEventListener('click', async () => {
  const data = lab.results ? JSON.stringify(lab.results) : JSON.stringify(REFERENCE);
  try { await navigator.clipboard.writeText(data); $('lab-status').textContent = `Copied ${(data.length / 1024).toFixed(0)} KB of JSON.`; }
  catch (e) { $('lab-status').textContent = 'Clipboard is blocked here. Use the CLI (node cli/run.mjs) to save results.'; }
});

function renderLab() {
  const wantCombat = $('protocol').value === 'combat';
  const own = lab.analysis && (lab.analysis.protocol.scenario === 'combat') === wantCombat ? lab.analysis : null;
  const A = own || (wantCombat ? REFERENCE.combat : REFERENCE.learning);
  const source = own ? lab.source : `Reference run from the CLI: ${A.protocol.subjects} flies per condition, seed ${REFERENCE.seed}`;
  $('result-source').textContent = source;
  // verdicts
  $('verdicts').innerHTML = A.verdicts.map((v) => {
    const good = /^Learns|^Fights/.test(v.verdict);
    return `<div class="verdict"><span class="dot" style="background:var(${SERIES[v.condition]});margin-top:5px"></span><div><b>${v.label}</b><p>${v.why}</p></div><span class="chip ${good ? 'yes' : 'no'}">${v.verdict}</span></div>`;
  }).join('');
  if (A.protocol.scenario === 'combat') drawCombat(A); else drawCurve(A);
  drawTable(A);
}

// learning curve by encounter (SVG)
function drawCurve(A) {
  const svg = $('curve'), W = 760, H = 300, m = { l: 62, r: 16, t: 14, b: 40 };
  const conds = Object.keys(A.conditions);
  const hasRev = !!A.conditions[conds[0]]?.touchCurve?.rev;
  const nA = A.conditions[conds[0]].touchCurve.acq.length, nR = hasRev ? A.conditions[conds[0]].touchCurve.rev.length : 0;
  const N = nA + nR, gap = hasRev ? 1 : 0;
  const x = (i) => m.l + ((i + (i >= nA ? gap : 0)) / (N + gap - 1)) * (W - m.l - m.r);
  const y = (v) => m.t + ((1 - v) / 2) * (H - m.t - m.b);
  let s = '';
  for (const v of [-1, -0.5, 0, 0.5, 1]) {
    s += `<line x1="${m.l}" x2="${W - m.r}" y1="${y(v)}" y2="${y(v)}" stroke="var(${v === 0 ? '--faint' : '--grid'})" stroke-width="1"/>`;
    s += `<text x="${m.l - 8}" y="${y(v) + 4}" text-anchor="end">${v > 0 ? '+' : ''}${v}</text>`;
  }
  const bin = C.TOUCH_BIN;
  for (let i = 0; i < N; i += 2) {
    const k = i < nA ? i : i - nA;
    s += `<text x="${x(i)}" y="${H - m.b + 16}" text-anchor="middle">${k * bin + 1}</text>`;
  }
  if (hasRev) {
    const xs = (x(nA - 1) + x(nA)) / 2;
    s += `<line x1="${xs}" x2="${xs}" y1="${m.t}" y2="${H - m.b}" stroke="var(--muted)" stroke-width="1"/>`;
    s += `<text x="${xs + 6}" y="${m.t + 12}">colors swap</text>`;
  }
  s += `<text class="axis-title" x="${m.l}" y="${H - 6}">ORB TOUCH NUMBER${hasRev ? ' (TRAINING, THEN AFTER THE SWAP)' : ''}</text>`;
  s += `<text class="axis-title" x="14" y="${m.t}" transform="rotate(-90 14 ${m.t})" text-anchor="end">PREFERENCE INDEX</text>`;
  const series = [];
  for (const k of conds) {
    const c = A.conditions[k];
    // plot a bin only when enough flies reached it, so sparse tails don't swing the line
    const minN = Math.max(3, Math.ceil(0.4 * c.n));
    const pts = [...c.touchCurve.acq, ...(c.touchCurve.rev || [])].map((p, i) => ({ i, ...p })).filter((p) => p.n >= minN && isFinite(p.mean));
    if (!pts.length) continue;
    series.push({ k, c, pts });
    const seg = (arr) => arr.map((p, j) => `${j ? 'L' : 'M'}${x(p.i).toFixed(1)},${y(p.mean).toFixed(1)}`).join('');
    const band = (arr) => arr.map((p, j) => `${j ? 'L' : 'M'}${x(p.i).toFixed(1)},${y(clamp(p.mean + p.sem, -1, 1)).toFixed(1)}`).join('') + [...arr].reverse().map((p) => `L${x(p.i).toFixed(1)},${y(clamp(p.mean - p.sem, -1, 1)).toFixed(1)}`).join('') + 'Z';
    for (const part of [pts.filter((p) => p.i < nA), pts.filter((p) => p.i >= nA)]) {
      if (part.length < 1) continue;
      s += `<path d="${band(part)}" fill="var(${SERIES[k]})" opacity="0.1"/>`;
      s += `<path d="${seg(part)}" fill="none" stroke="var(${SERIES[k]})" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`;
    }
    const end = pts[pts.length - 1];
    s += `<circle cx="${x(end.i)}" cy="${y(end.mean)}" r="4.5" fill="var(${SERIES[k]})" stroke="var(--panel)" stroke-width="2"/>`;
  }
  s += `<line id="cross" x1="0" x2="0" y1="${m.t}" y2="${H - m.b}" stroke="var(--muted)" stroke-width="1" visibility="hidden"/>`;
  s += `<rect id="hit" x="${m.l}" y="${m.t}" width="${W - m.l - m.r}" height="${H - m.t - m.b}" fill="transparent"/>`;
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
  svg.innerHTML = s;
  $('curve-title').textContent = 'Learning curve by encounter';
  $('curve-legend').innerHTML = series.map((q) => `<span><i style="background:var(${SERIES[q.k]})"></i>${q.c.label}</span>`).join('');
  $('curve-note').textContent = `Mean preference index (± SEM band) over successive bins of ${bin} orb touches, scored against whichever color heals at the time. +1 means every touch was a healing orb.`;
  // hover
  const hit = svg.querySelector('#hit'), cross = svg.querySelector('#cross'), tip = $('tip');
  hit.onmousemove = (e) => {
    const r = svg.getBoundingClientRect(), sx = ((e.clientX - r.left) / r.width) * W;
    let best = 0, bd = 1e9;
    for (let i = 0; i < N; i++) { const d = Math.abs(x(i) - sx); if (d < bd) { bd = d; best = i; } }
    cross.setAttribute('x1', x(best)); cross.setAttribute('x2', x(best)); cross.setAttribute('visibility', 'visible');
    const k = best < nA ? best : best - nA;
    const rows = series.map((q) => { const p = q.pts.find((pp) => pp.i === best); return `<span class="dot" style="background:var(${SERIES[q.k]})"></span>${q.c.label}: ${p ? fmt(p.mean) + ' ± ' + p.sem.toFixed(2) + ` (n=${p.n})` : 'no data'}`; });
    tip.innerHTML = `<b>${best < nA ? 'Training' : 'After swap'}, touches ${k * bin + 1}–${(k + 1) * bin}</b><br>` + rows.join('<br>');
    tip.hidden = false;
    tip.style.left = Math.min(innerWidth - 290, e.clientX + 14) + 'px';
    tip.style.top = e.clientY + 14 + 'px';
  };
  hit.onmouseleave = () => { tip.hidden = true; cross.setAttribute('visibility', 'hidden'); };
}

// combat: kills per episode, horizontal bars
function drawCombat(A) {
  const svg = $('curve'), conds = Object.keys(A.conditions), W = 760, rowH = 34, m = { l: 170, r: 70, t: 10, b: 48 };
  const H = m.t + m.b + conds.length * rowH;
  const max = Math.max(1, Math.ceil(Math.max(...conds.map((k) => A.conditions[k].kills)) * 2) / 2);
  const x = (v) => m.l + (v / max) * (W - m.l - m.r);
  let s = '';
  for (let v = 0; v <= max; v += max > 4 ? 1 : 0.5) {
    s += `<line x1="${x(v)}" x2="${x(v)}" y1="${m.t}" y2="${H - m.b}" stroke="var(--grid)" stroke-width="1"/><text x="${x(v)}" y="${H - m.b + 16}" text-anchor="middle">${v}</text>`;
  }
  conds.forEach((k, i) => {
    const c = A.conditions[k], y0 = m.t + i * rowH + 8, w = Math.max(0, x(c.kills) - m.l), h = 18;
    s += `<text x="${m.l - 10}" y="${y0 + 13}" text-anchor="end" style="fill:var(--ink);font:13px var(--body)">${c.label}</text>`;
    if (w > 0) s += `<path d="M${m.l},${y0}h${Math.max(0, w - 4)}a4,4 0 0 1 4,4v${h - 8}a4,4 0 0 1 -4,4h${-Math.max(0, w - 4)}z" fill="var(${SERIES[k]})"><title>${c.label}: ${c.kills.toFixed(2)} kills per episode</title></path>`;
    s += `<text x="${m.l + w + 8}" y="${y0 + 13}">${c.kills.toFixed(2)}</text>`;
  });
  s += `<text class="axis-title" x="${m.l}" y="${H - 6}">IMPS KILLED PER EPISODE</text>`;
  svg.setAttribute('viewBox', `0 0 ${W} ${H}`);
  svg.innerHTML = s;
  $('curve-title').textContent = 'Kills per episode';
  $('curve-legend').innerHTML = '';
  $('curve-note').textContent = 'Each bar is the mean across flies and episodes. Accuracy, damage and survival are in the table.';
}

function drawTable(A) {
  const conds = Object.values(A.conditions);
  let h;
  if (A.protocol.scenario === 'combat') {
    h = '<tr><th>Condition</th><th>Kills/ep</th><th>Accuracy</th><th>Damage/ep</th><th>Survival</th><th>Kills early→late</th></tr>';
    h += conds.map((c) => `<tr><td>${c.label}</td><td class="num">${c.kills.toFixed(2)}</td><td class="num">${(c.accuracy * 100).toFixed(0)}%</td><td class="num">${c.damage.toFixed(0)}</td><td class="num">${c.survived.toFixed(1)} s</td><td class="num">${c.killsEarly.toFixed(2)} → ${c.killsLate.toFixed(2)}</td></tr>`).join('');
  } else {
    const pm = (q) => (q && isFinite(q.mean) ? `${fmt(q.mean)} ± ${(q.sem || 0).toFixed(2)}` : '–');
    const rev = conds[0]?.reversal;
    h = `<tr><th>Condition</th><th>First ${C.TOUCH_BIN} touches</th><th>Late training</th><th>p</th><th>Orbs/ep</th>${rev ? `<th>First ${C.TOUCH_BIN} after swap</th><th>End of reversal</th>` : ''}</tr>`;
    h += conds.map((c) => `<tr><td>${c.label}</td><td class="num">${pm(c.naive)}</td><td class="num">${pm(c.late)}</td><td class="num">${fmtP(c.late.perm.p)}</td><td class="num">${c.pickups.toFixed(1)}</td>${c.reversal ? `<td class="num">${pm(c.reversal.firstTouches)}</td><td class="num">${pm(c.reversal.last)}</td>` : ''}</tr>`).join('');
  }
  if (A.comparisons?.length) {
    const combat = A.protocol.scenario === 'combat';
    h += `<tr><th colspan="7" style="padding-top:16px">Intact vs each control, paired by fly</th></tr>`;
    h += A.comparisons.map((c) => `<tr><td>intact − ${A.conditions[c.b].label}</td><td class="num" colspan="2">${combat ? `${fmt(c.killsDiff)} kills/ep` : `${fmt(c.diff)} late PI`}</td><td class="num">${fmtP(combat ? c.killsPerm.p : c.perm.p)}</td><td class="num" colspan="3">${combat ? `${fmt(c.damageDiff, 1)} damage/ep (p ${fmtP(c.damagePerm.p)})` : `d = ${c.d.toFixed(2)}`}</td></tr>`).join('');
  }
  $('table').innerHTML = h;
}

// =====================================================================
// WIRING
// =====================================================================
function renderWiring() {
  const conn = C.buildConnectome(new C.RNG(1));
  const sum = C.connectomeSummary(conn);
  const rows = Object.entries(C.CELL_TYPES).map(([t, d]) => `<tr><td><b>${t}</b></td><td class="num">${d.perSide * 2}</td><td>${d.nt}${d.input ? ' (input)' : ''}</td><td>${d.region}</td><td>${d.role}</td></tr>`).join('');
  $('celltypes').innerHTML = `<tr><th>Type</th><th>Cells</th><th>Transmitter</th><th>Region</th><th>Role</th></tr>${rows}<tr><td><b>Total</b></td><td class="num">${sum.neurons}</td><td colspan="3">${sum.connections.toLocaleString()} connections, ${Math.round(sum.synapses).toLocaleString()} synapses</td></tr>`;
  const L = C.LIF;
  $('method').innerHTML = `
    <h2>How it works</h2>
    <p><b>World.</b> A small raycast shooter in the style of Doom (1993), running at Doom's 35 tics per second. Imps chase you and throw fireballs. Blue and green orbs float around; one color heals and the other burns. Which one heals is set per fly, so it has to be learned.</p>
    <p><b>Eyes.</b> Each compound eye is 16 ommatidial columns spanning 140&deg;, with 20&deg; of binocular overlap in front. The optic lobe is modeled as rate filters: small-object detectors (LC10a), looming detectors (LC4, LPLC2) that ignore the fly's own walking, horizontal optic flow (HS, from Reichardt correlators) and color channels for the mushroom body.</p>
    <p><b>Brain.</b> ${sum.neurons} spiking neurons and ${sum.connections.toLocaleString()} connections. Leaky integrate-and-fire with the parameters of Shiu et al. 2024: rest ${L.vRest} mV, threshold ${L.vTh} mV, &tau;<sub>m</sub> ${L.tauM} ms, &tau;<sub>syn</sub> ${L.tauSyn} ms, refractory ${L.tRef} ms, ${L.wSyn} mV per synapse, ${L.delay} ms delay. Signs follow the transmitter (ACh excitatory, GABA inhibitory, glutamate inhibitory except MBON-01, which is modeled as excitatory).</p>
    <p><b>Innate behavior.</b> LC10a &rarr; AOTU019/AOTU025 &rarr; DNa02 steers toward small objects, after the fly's courtship-pursuit circuit. The gun fires when both AOTU019 populations are active, meaning the target sits in the binocular zone. Looming drives the giant fiber (DNp01), which sidesteps away. Wall contact turns the fly and backs it off.</p>
    <p><b>Learning.</b> Color input reaches ~600 Kenyon cells through random 6-claw wiring that is different in every fly. Each KC synapse onto MBON-11 (approach) or MBON-01 (avoidance) is plastic. Damage excites nociceptors &rarr; PPL1-&gamma;1pedc dopamine, which depresses recently active KC&rarr;MBON-11 synapses. Healing and kills excite sweet-taste neurons &rarr; PAM-&gamma;5 dopamine, which depresses KC&rarr;MBON-01 synapses. MBON-11 inhibits MBON-01, so punished colors release MBON-01, which turns the fly away, backs it off and gates off pursuit through an inhibitory LAL interneuron.</p>
    <h2>What this is not</h2>
    <ul>
      <li>It is not the full connectome. FlyWire has ~140,000 neurons and MaleCNS ~166,700. This is a hand-built reduction to the named cell types and wiring motifs the game needs, with synapse counts tuned so it behaves.</li>
      <li>It is not AGI, and it is not trying to be. A fly brain is a narrow, superbly tuned controller. The point of the engine is to test learning claims properly: with controls, counterbalancing and statistics.</li>
      <li>The test engine checks behavior, and behavior can mislead. In combat, pain-driven learning makes the intact fly avoid imps and stop shooting, without taking less damage. Learning is real there, and it does not help it win.</li>
    </ul>
    <h2>Sources</h2>
    <ul>
      <li><a href="https://www.nature.com/articles/s41586-024-07763-9" target="_blank" rel="noopener">Shiu et al. 2024, A Drosophila computational brain model reveals sensorimotor processing (Nature)</a></li>
      <li><a href="https://elifesciences.org/articles/04580" target="_blank" rel="noopener">Aso et al. 2014, Mushroom body output neurons encode valence (eLife)</a></li>
      <li><a href="https://elifesciences.org/articles/75611" target="_blank" rel="noopener">Gkanias et al. 2022, An incentive circuit for memory dynamics in the mushroom body (eLife)</a></li>
      <li><a href="https://www.cell.com/neuron/fulltext/S0896-6273(15)00982-4" target="_blank" rel="noopener">Hige et al. 2015, Heterosynaptic plasticity underlies aversive olfactory learning (Neuron)</a></li>
      <li><a href="https://www.janelia.org/publication/neural-basis-for-looming-size-and-velocity-encoding-in-the-drosophila-giant-fiber-escape" target="_blank" rel="noopener">Ache et al. 2019, Looming size and velocity encoding in the giant fiber escape pathway</a></li>
      <li><a href="https://github.com/webergithub/fruitfly-lab" target="_blank" rel="noopener">fruitfly-lab: a FlyWire pursuit circuit that plays Doom, with scrambled-wiring and lesion controls</a></li>
      <li><a href="https://github.com/townie/awesome-fruit-fly" target="_blank" rel="noopener">awesome-fruit-fly: DOOMFLY and other connectome game projects</a></li>
      <li><a href="https://arxiv.org/abs/1605.02097" target="_blank" rel="noopener">Kempka et al. 2016, ViZDoom: a Doom-based AI research platform</a></li>
    </ul>`;
}

// ---------- boot ----------
renderWiring();
newFly(7);
let startTab = 'watch';
try { startTab = localStorage.getItem('fbd-tab') || 'watch'; } catch (e) { /* storage unavailable */ }
const hash = location.hash.replace('#', '');
if (TABS.includes(hash)) startTab = hash;
showTab(TABS.includes(startTab) ? startTab : 'watch');
requestAnimationFrame(loop);

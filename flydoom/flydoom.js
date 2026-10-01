/*
 * FlyDoom — a learning fly-brain simulation that plays a Doom-like shooter.
 *
 * Pipeline (each game tick ≈ 1/35 s, simulated as SUBSTEPS × 1 ms of neural time):
 *
 *   world ──raycast──▶ compound eye ──▶ lamina ──▶ lobula ──┬─▶ innate DN reflexes ──▶ motor
 *                     (ommatidia)      (L2)    (LC11/LC4/  │
 *                                              LPTC)       └─▶ mushroom body (KC → MBON) ─▶ DN
 *                                                                     ▲
 *                                         game reward ──▶ PAM / PPL1 dopamine (3-factor plasticity)
 *
 * The circuit is connectome-*inspired*: cell types and projection logic follow the
 * Drosophila literature (FlyWire / MaleCNS naming), but it is a few hundred LIF neurons,
 * not the real ~140k-neuron wiring. Learning happens only at KC→MBON synapses, gated by
 * dopamine, as in the real mushroom body.
 *
 * Works in the browser (window.FlyDoom) and in Node (require).
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.FlyDoom = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  // ───────────────────────────── RNG ─────────────────────────────
  class Rng {
    constructor(seed) {
      this.state = (seed >>> 0) || 1;
      this.spare = null;
    }
    float() {
      let t = (this.state = (this.state + 0x6d2b79f5) >>> 0);
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    }
    int(n) { return Math.floor(this.float() * n); }
    normal() {
      if (this.spare !== null) { const s = this.spare; this.spare = null; return s; }
      let u = 0;
      while (u === 0) u = this.float();
      const v = this.float();
      const r = Math.sqrt(-2 * Math.log(u));
      this.spare = r * Math.sin(2 * Math.PI * v);
      return r * Math.cos(2 * Math.PI * v);
    }
    shuffle(a) {
      for (let i = a.length - 1; i > 0; i--) {
        const j = this.int(i + 1);
        const t = a[i]; a[i] = a[j]; a[j] = t;
      }
      return a;
    }
  }

  const clamp = (x, lo, hi) => (x < lo ? lo : x > hi ? hi : x);
  const wrapAngle = (a) => {
    while (a > Math.PI) a -= 2 * Math.PI;
    while (a < -Math.PI) a += 2 * Math.PI;
    return a;
  };

  // ─────────────────────────── Doom world ───────────────────────────
  const DEFAULT_MAP = [
    '################',
    '#......#.......#',
    '#......#.......#',
    '#..##.....##...#',
    '#..#.......#...#',
    '#......##......#',
    '#..............#',
    '####..####..####',
    '#..............#',
    '#......##......#',
    '#..#.......#...#',
    '#..##.....##...#',
    '#......#.......#',
    '#......#.......#',
    '#..............#',
    '################',
  ];

  const WORLD_DEFAULTS = {
    maxTicks: 1050,        // 30 s at 35 Hz, Doom's tic rate
    maxEnemies: 4,
    spawnEvery: 30,
    enemyHp: 2,
    enemySpeed: 0.03,
    enemyDamage: 8,
    enemyAttackRange: 0.85,
    enemyAttackCooldown: 35,
    turnSpeed: 0.09,
    moveSpeed: 0.06,
    fireCooldown: 7,
    ammo: 200,
    rewards: { hit: 0.3, kill: 1.0, miss: -0.05, hurt: -0.5, death: -1.0, explore: 0.02 },
  };

  class DoomWorld {
    constructor(opts = {}) {
      this.opts = Object.assign({}, WORLD_DEFAULTS, opts);
      this.opts.rewards = Object.assign({}, WORLD_DEFAULTS.rewards, opts.rewards || {});
      this.map = this.opts.map || DEFAULT_MAP;
      this.h = this.map.length;
      this.w = this.map[0].length;
      this.reset(opts.seed || 1);
    }

    reset(seed) {
      this.rng = new Rng(seed);
      this.player = { x: 8.5, y: 6.5, a: this.rng.float() * 2 * Math.PI, health: 100, ammo: this.opts.ammo, cooldown: 0 };
      this.enemies = [];
      this.nextEnemyId = 1;
      this.tick = 0;
      this.kills = 0;
      this.shots = 0;
      this.hits = 0;
      this.damageTaken = 0;
      this.visited = new Set([this.cellKey(this.player.x, this.player.y)]);
      this.done = false;
      this.totalReward = 0;
      this.lastEvents = [];
      for (let i = 0; i < 2; i++) this.spawnEnemy();
    }

    cellKey(x, y) { return (Math.floor(y) * this.w + Math.floor(x)); }
    isWall(x, y) {
      const cx = Math.floor(x), cy = Math.floor(y);
      if (cx < 0 || cy < 0 || cx >= this.w || cy >= this.h) return true;
      return this.map[cy][cx] === '#';
    }

    /** DDA raycast; returns perpendicular-free euclidean distance and wall side. */
    castRay(angle, maxDist = 20) {
      const { x, y } = this.player;
      return this.castRayFrom(x, y, angle, maxDist);
    }
    castRayFrom(x, y, angle, maxDist = 20) {
      const dx = Math.cos(angle), dy = Math.sin(angle);
      let mapX = Math.floor(x), mapY = Math.floor(y);
      const ddx = Math.abs(1 / (dx || 1e-9)), ddy = Math.abs(1 / (dy || 1e-9));
      let stepX, stepY, sideX, sideY;
      if (dx < 0) { stepX = -1; sideX = (x - mapX) * ddx; } else { stepX = 1; sideX = (mapX + 1 - x) * ddx; }
      if (dy < 0) { stepY = -1; sideY = (y - mapY) * ddy; } else { stepY = 1; sideY = (mapY + 1 - y) * ddy; }
      let side = 0, dist = 0;
      for (let i = 0; i < 64; i++) {
        if (sideX < sideY) { dist = sideX; sideX += ddx; mapX += stepX; side = 0; }
        else { dist = sideY; sideY += ddy; mapY += stepY; side = 1; }
        if (dist > maxDist) return { dist: maxDist, side };
        if (mapX < 0 || mapY < 0 || mapX >= this.w || mapY >= this.h || this.map[mapY][mapX] === '#') return { dist, side };
      }
      return { dist: maxDist, side };
    }

    /** BFS distance field from the player's cell, so enemies path around walls toward the player. */
    computeFlowField() {
      const w = this.w, h = this.h;
      const dist = (this.flow = this.flow || new Int16Array(w * h));
      dist.fill(-1);
      const start = this.cellKey(this.player.x, this.player.y);
      const queue = [start];
      dist[start] = 0;
      for (let qi = 0; qi < queue.length; qi++) {
        const c = queue[qi], cx = c % w, cy = (c - cx) / w;
        const nb = [[cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]];
        for (const [nx, ny] of nb) {
          if (nx < 0 || ny < 0 || nx >= w || ny >= h || this.map[ny][nx] === '#') continue;
          const k = ny * w + nx;
          if (dist[k] < 0) { dist[k] = dist[c] + 1; queue.push(k); }
        }
      }
    }

    /** Direction an enemy should walk: straight at the player if visible, else downhill on the flow field. */
    chaseAngle(e) {
      const p = this.player;
      if (this.lineOfSight(e.x, e.y, p.x, p.y)) return Math.atan2(p.y - e.y, p.x - e.x);
      const w = this.w, cx = Math.floor(e.x), cy = Math.floor(e.y);
      let best = null, bestD = this.flow[cy * w + cx];
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const d = this.flow[(cy + dy) * w + cx + dx];
        if (d >= 0 && (bestD < 0 || d < bestD)) { bestD = d; best = [cx + dx + 0.5, cy + dy + 0.5]; }
      }
      return best ? Math.atan2(best[1] - e.y, best[0] - e.x) : Math.atan2(p.y - e.y, p.x - e.x);
    }

    lineOfSight(x0, y0, x1, y1) {
      const d = Math.hypot(x1 - x0, y1 - y0);
      return this.castRayFrom(x0, y0, Math.atan2(y1 - y0, x1 - x0), d + 0.01).dist >= d;
    }

    spawnEnemy() {
      for (let tries = 0; tries < 50; tries++) {
        const x = 1 + this.rng.int(this.w - 2) + 0.5;
        const y = 1 + this.rng.int(this.h - 2) + 0.5;
        if (this.isWall(x, y)) continue;
        if (Math.hypot(x - this.player.x, y - this.player.y) < 5) continue;
        this.enemies.push({ id: this.nextEnemyId++, x, y, hp: this.opts.enemyHp, cooldown: this.opts.enemyAttackCooldown, flash: 0 });
        return true;
      }
      return false;
    }

    /** Enemies in player-relative polar coords (angle > 0 = to the left). */
    relativeEnemies() {
      const p = this.player;
      return this.enemies.map((e) => {
        const dx = e.x - p.x, dy = e.y - p.y;
        return {
          enemy: e,
          dist: Math.hypot(dx, dy),
          angle: wrapAngle(Math.atan2(dy, dx) - p.a),
          visible: this.lineOfSight(p.x, p.y, e.x, e.y),
        };
      });
    }

    tryMove(obj, nx, ny, r = 0.2) {
      if (!this.isWall(nx + Math.sign(nx - obj.x) * r, obj.y)) obj.x = nx;
      if (!this.isWall(obj.x, ny + Math.sign(ny - obj.y) * r)) obj.y = ny;
    }

    /** action: { turn: -1..1 (+ = left), move: -1..1, fire: bool } */
    step(action) {
      if (this.done) return { reward: 0, done: true, events: [] };
      const o = this.opts, R = o.rewards, p = this.player;
      let reward = 0;
      const events = [];

      p.a = wrapAngle(p.a + clamp(action.turn || 0, -1, 1) * o.turnSpeed);
      const mv = clamp(action.move || 0, -1, 1) * o.moveSpeed;
      if (mv !== 0) this.tryMove(p, p.x + Math.cos(p.a) * mv, p.y + Math.sin(p.a) * mv);
      const key = this.cellKey(p.x, p.y);
      if (!this.visited.has(key)) { this.visited.add(key); reward += R.explore; }

      if (p.cooldown > 0) p.cooldown--;
      if (action.fire && p.cooldown === 0 && p.ammo > 0) {
        p.cooldown = o.fireCooldown;
        p.ammo--;
        this.shots++;
        let target = null;
        for (const r of this.relativeEnemies()) {
          const tol = Math.max(0.05, Math.atan(0.32 / r.dist));
          if (r.visible && Math.abs(r.angle) < tol && (!target || r.dist < target.dist)) target = r;
        }
        if (target) {
          this.hits++;
          target.enemy.hp--;
          target.enemy.flash = 4;
          reward += R.hit;
          events.push('hit');
          if (target.enemy.hp <= 0) {
            this.enemies = this.enemies.filter((e) => e !== target.enemy);
            this.kills++;
            reward += R.kill;
            events.push('kill');
          }
        } else {
          reward += R.miss;
          events.push('miss');
        }
      }

      this.computeFlowField();
      for (const e of this.enemies) {
        if (e.flash > 0) e.flash--;
        const dx = p.x - e.x, dy = p.y - e.y, d = Math.hypot(dx, dy);
        if (d > o.enemyAttackRange * 0.8) {
          const ang = this.chaseAngle(e) + (this.rng.float() - 0.5) * 0.6;
          this.tryMove(e, e.x + Math.cos(ang) * o.enemySpeed, e.y + Math.sin(ang) * o.enemySpeed);
        }
        if (e.cooldown > 0) e.cooldown--;
        if (d < o.enemyAttackRange && e.cooldown === 0) {
          e.cooldown = o.enemyAttackCooldown;
          p.health -= o.enemyDamage;
          this.damageTaken += o.enemyDamage;
          reward += R.hurt;
          events.push('hurt');
        }
      }

      this.tick++;
      if (this.tick % o.spawnEvery === 0 && this.enemies.length < o.maxEnemies) this.spawnEnemy();
      if (p.health <= 0) { reward += R.death; this.done = true; events.push('death'); }
      if (this.tick >= o.maxTicks) this.done = true;
      this.totalReward += reward;
      this.lastEvents = events;
      return { reward, done: this.done, events };
    }

    stats() {
      return {
        ticks: this.tick, kills: this.kills, shots: this.shots, hits: this.hits,
        accuracy: this.shots ? this.hits / this.shots : 0,
        damageTaken: this.damageTaken, survived: this.player.health > 0,
        explored: this.visited.size, reward: this.totalReward,
      };
    }
  }

  // ─────────────────────────── Compound eye ───────────────────────────
  /**
   * Drosophila has ~750 ommatidia per eye and near-panoramic vision. We model a
   * horizontal strip of `columns` ommatidia spanning `fov` — wider than the Doom screen.
   * Column 0 is leftmost.
   */
  class CompoundEye {
    constructor({ columns = 36, fov = (3 * Math.PI) / 2 } = {}) {
      this.columns = columns;
      this.fov = fov;
      this.colWidth = fov / columns;
      this.prevObject = new Float32Array(columns);
    }
    columnAngle(i) { return this.fov / 2 - (i + 0.5) * this.colWidth; }
    reset() { this.prevObject.fill(0); }

    sample(world) {
      const C = this.columns;
      const wall = new Float32Array(C), object = new Float32Array(C), loom = new Float32Array(C);
      const depth = new Float32Array(C);
      for (let i = 0; i < C; i++) {
        const d = world.castRay(world.player.a + this.columnAngle(i)).dist;
        depth[i] = d;
        wall[i] = Math.exp(-d / 1.5);
      }
      for (const r of world.relativeEnemies()) {
        if (!r.visible) continue;
        const halfW = Math.atan(0.3 / r.dist);
        const nearness = 0.4 + 0.6 * Math.min(1, 1.5 / r.dist);
        for (let i = 0; i < C; i++) {
          const off = Math.abs(wrapAngle(r.angle - this.columnAngle(i)));
          if (off < halfW + this.colWidth / 2 && r.dist < depth[i] + 0.5) object[i] = Math.max(object[i], nearness);
        }
      }
      for (let i = 0; i < C; i++) {
        loom[i] = clamp((object[i] - this.prevObject[i]) * 8, 0, 1);
        this.prevObject[i] = object[i];
      }
      return { wall, object, loom, depth };
    }
  }

  // ─────────────────────────── Spiking network ───────────────────────────
  /** Leaky integrate-and-fire network with exponential synapses, 1 ms steps, event-driven. */
  class SpikingNetwork {
    constructor(rng) {
      this.rng = rng;
      this.pops = {};
      this.order = [];
      this.n = 0;
      this.edges = [];
    }
    addPop(name, n, { tau = 10, bias = 0, noise = 0.02, region = name, label = name } = {}) {
      this.pops[name] = { name, n, offset: this.n, tau, bias, noise, region, label };
      this.order.push(name);
      this.n += n;
      return this.pops[name];
    }
    idx(pop, i) { return this.pops[pop].offset + i; }
    connect(pre, i, post, j, w, tag = '') { this.edges.push([this.idx(pre, i), this.idx(post, j), w, tag]); }

    finalize() {
      const n = this.n;
      this.v = new Float32Array(n);
      this.s = new Float32Array(n);
      this.ext = new Float32Array(n);
      this.bias = new Float32Array(n);
      this.noise = new Float32Array(n);
      this.alpha = new Float32Array(n);
      this.refr = new Uint8Array(n);
      this.spiked = new Uint8Array(n);
      this.counts = new Uint16Array(n);
      this.silenced = new Uint8Array(n);
      for (const name of this.order) {
        const p = this.pops[name];
        for (let i = 0; i < p.n; i++) {
          this.bias[p.offset + i] = p.bias;
          this.noise[p.offset + i] = p.noise;
          this.alpha[p.offset + i] = Math.exp(-1 / p.tau);
        }
      }
      // CSR by presynaptic neuron
      const deg = new Uint32Array(n + 1);
      for (const e of this.edges) deg[e[0] + 1]++;
      for (let i = 0; i < n; i++) deg[i + 1] += deg[i];
      this.rowStart = deg;
      this.targets = new Uint32Array(this.edges.length);
      this.weights = new Float32Array(this.edges.length);
      const fill = deg.slice(0, n);
      for (const e of this.edges) {
        const k = fill[e[0]]++;
        this.targets[k] = e[1];
        this.weights[k] = e[2];
      }
      this.synBeta = Math.exp(-1 / 5);
    }

    /** One 1 ms step. `hook(i)` is called for every spiking neuron (for plastic synapses). */
    step(hook) {
      const { v, s, ext, bias, noise, alpha, refr, spiked, counts, silenced, rng, rowStart, targets, weights } = this;
      const n = this.n, beta = this.synBeta;
      for (let i = 0; i < n; i++) {
        spiked[i] = 0;
        if (refr[i] > 0) { refr[i]--; v[i] = 0; continue; }
        // uniform noise with unit variance: much cheaper than Box–Muller in the hot loop
        const I = s[i] + ext[i] + bias[i] + (noise[i] > 0 ? noise[i] * (rng.float() - 0.5) * 3.4641 : 0);
        let vi = v[i] * alpha[i] + I;
        if (vi < -1) vi = -1;
        if (vi >= 1 && !silenced[i]) { spiked[i] = 1; counts[i]++; vi = 0; refr[i] = 2; }
        v[i] = vi;
      }
      for (let i = 0; i < n; i++) s[i] *= beta;
      for (let i = 0; i < n; i++) {
        if (!spiked[i]) continue;
        for (let k = rowStart[i]; k < rowStart[i + 1]; k++) s[targets[k]] += weights[k];
        if (hook) hook(i);
      }
    }
    popCounts(name) {
      const p = this.pops[name];
      return this.counts.subarray(p.offset, p.offset + p.n);
    }
  }

  // ─────────────────────────── Fly brain ───────────────────────────
  const ACTIONS = ['turnL', 'turnR', 'forward', 'backward', 'fire'];
  const DN_NAMES = { turnL: 'DNa02-L', turnR: 'DNa02-R', forward: 'DNp09', backward: 'MDN', fire: 'DN-fire' };

  const BRAIN_DEFAULTS = {
    seed: 7,
    columns: 36,
    fov: (3 * Math.PI) / 2, // 270°: flies see almost all the way around
    substeps: 20,
    nKC: 300,
    kcInputs: 5,
    dnPerAction: 4,
    plasticity: true,
    learningRate: 0.002,
    eligibilityDecay: 0.8,
    wMax: 0.5,
    kcMbonInit: 0.012,
    danGain: 1.2,
    weightDecay: 0.0005,     // per tick, toward the initial weight (slow forgetting)
    scrambleInnate: false,   // control: degree-preserving shuffle of the innate lobula→DN wiring
    lesion: [],              // control: names of populations to silence, e.g. ['KC']
  };

  class FlyBrain {
    constructor(opts = {}) {
      this.opts = Object.assign({}, BRAIN_DEFAULTS, opts);
      const o = this.opts;
      this.rng = new Rng(o.seed);
      this.eye = new CompoundEye({ columns: o.columns, fov: o.fov });
      this.build();
      this.lastDA = 0;
      this.pendingReward = 0;
      this.weightHistory = [];
    }

    build() {
      const o = this.opts, C = o.columns, rng = this.rng;
      const net = (this.net = new SpikingNetwork(rng));
      const sectors = 6;
      const S = (i) => Math.floor((i * sectors) / C);

      // Optic lobe
      net.addPop('R_wall', C, { region: 'Retina', label: 'R1-6 (luminance)', noise: 0.01 });
      net.addPop('R_obj', C, { region: 'Retina', label: 'R1-6 (dark object)', noise: 0.01 });
      net.addPop('R_loom', C, { region: 'Retina', label: 'R transient', noise: 0.01 });
      net.addPop('L2', C, { region: 'Lamina', label: 'L2 (OFF contrast)' });
      net.addPop('LC11', C, { region: 'Lobula', label: 'LC11 (small object)' });
      net.addPop('LC4', 4, { region: 'Lobula', label: 'LC4 (looming)' });
      net.addPop('LPTC', sectors, { region: 'Lobula plate', label: 'LPTC (near-wall flow)' });
      // Mushroom body
      net.addPop('KC', o.nKC, { region: 'Mushroom body', label: 'Kenyon cells', noise: 0.005 });
      net.addPop('APL', 1, { region: 'Mushroom body', label: 'APL (inhibition)', tau: 20, noise: 0 });
      net.addPop('MBON', ACTIONS.length, { region: 'Mushroom body', label: 'MBON', noise: 0.03 });
      net.addPop('PAM', 4, { region: 'Dopamine', label: 'PAM (reward)', noise: 0 });
      net.addPop('PPL1', 4, { region: 'Dopamine', label: 'PPL1 (punishment)', noise: 0 });
      // Descending neurons
      net.addPop('GF', 2, { region: 'Descending', label: 'Giant fiber', noise: 0 });
      for (const a of ACTIONS) {
        net.addPop('DN_' + a, o.dnPerAction, {
          region: 'Descending', label: DN_NAMES[a],
          bias: a === 'forward' ? 0.085 : 0, noise: a === 'fire' ? 0.06 : 0.05,
        });
      }

      // Retina → lamina: centre-surround on the object channel
      for (let i = 0; i < C; i++) {
        net.connect('R_obj', i, 'L2', i, 0.55);
        if (i > 0) net.connect('R_obj', i - 1, 'L2', i, -0.12);
        if (i < C - 1) net.connect('R_obj', i + 1, 'L2', i, -0.12);
        net.connect('L2', i, 'LC11', i, 0.6);
        net.connect('R_loom', i, 'LC4', Math.floor((i * 4) / C), 0.5);
        net.connect('R_wall', i, 'LPTC', S(i), 0.35);
      }
      net.connect('LC4', 0, 'GF', 0, 0.4); net.connect('LC4', 1, 'GF', 0, 0.4);
      net.connect('LC4', 2, 'GF', 1, 0.4); net.connect('LC4', 3, 'GF', 1, 0.4);

      // Innate visuomotor reflexes (lobula → DN). These are the edges the "scrambled" control shuffles.
      const innate = [];
      const toDN = (pre, i, action, w) => {
        for (let k = 0; k < o.dnPerAction; k++) innate.push([pre, i, 'DN_' + action, k, w]);
      };
      for (let i = 0; i < C; i++) {
        // object fixation: flies turn toward small dark vertical bars
        const ecc = (C / 2 - i - 0.5) / (C / 2); // +1 far left … −1 far right
        if (Math.abs(ecc) > 0.05) toDN('LC11', i, ecc > 0 ? 'turnL' : 'turnR', 0.22 * Math.sqrt(Math.abs(ecc)));
      }
      for (let s = 0; s < sectors; s++) {
        // obstacle avoidance: near-wall optic flow on one side → turn away
        if (s < sectors / 2 - 1) toDN('LPTC', s, 'turnR', 0.2);
        else if (s > sectors / 2) toDN('LPTC', s, 'turnL', 0.2);
        else { toDN('LPTC', s, 'backward', 0.12); toDN('LPTC', s, 'forward', -0.25); toDN('LPTC', s, 'turnL', 0.12); }
      }
      for (let g = 0; g < 2; g++) { toDN('GF', g, 'backward', 0.45); toDN('GF', g, 'forward', -0.4); }

      if (o.scrambleInnate) {
        const posts = innate.map((e) => [e[2], e[3]]);
        rng.shuffle(posts);
        innate.forEach((e, k) => { e[2] = posts[k][0]; e[3] = posts[k][1]; });
      }
      for (const e of innate) net.connect(e[0], e[1], e[2], e[3], e[4], 'innate');

      // Motor competition
      for (let a = 0; a < o.dnPerAction; a++) for (let b = 0; b < o.dnPerAction; b++) {
        // strong cross-inhibition makes steering winner-take-all, so two targets can't deadlock it
        net.connect('DN_turnL', a, 'DN_turnR', b, -0.5);
        net.connect('DN_turnR', a, 'DN_turnL', b, -0.5);
        net.connect('DN_forward', a, 'DN_backward', b, -0.15);
        net.connect('DN_backward', a, 'DN_forward', b, -0.15);
      }

      // Kenyon cells: sparse random sampling of lobula features (the "projection neuron" analogue)
      const features = [];
      for (let i = 0; i < C; i++) features.push(['LC11', i]);
      for (let i = 0; i < 4; i++) features.push(['LC4', i]);
      for (let i = 0; i < sectors; i++) features.push(['LPTC', i]);
      this.kcInputs = [];
      for (let k = 0; k < o.nKC; k++) {
        const chosen = rng.shuffle(features.slice()).slice(0, o.kcInputs);
        this.kcInputs.push(chosen.map((f) => f[0] + '[' + f[1] + ']'));
        for (const f of chosen) net.connect(f[0], f[1], 'KC', k, 0.24);
        net.connect('KC', k, 'APL', 0, 0.05);
        net.connect('APL', 0, 'KC', k, -0.6);
      }
      // MBON → DN (fixed); KC → MBON is plastic and handled outside the CSR.
      ACTIONS.forEach((a, j) => {
        for (let k = 0; k < o.dnPerAction; k++) net.connect('MBON', j, 'DN_' + a, k, 0.3);
      });

      net.finalize();
      for (const name of o.lesion) {
        const p = net.pops[name];
        if (!p) throw new Error('Unknown population to lesion: ' + name);
        net.silenced.fill(1, p.offset, p.offset + p.n);
      }

      const M = ACTIONS.length;
      this.W = new Float32Array(o.nKC * M);
      for (let i = 0; i < this.W.length; i++) this.W[i] = o.kcMbonInit * (0.5 + rng.float());
      this.W0 = Float32Array.from(this.W);
      this.elig = new Float32Array(o.nKC * M);
      this.kcOff = net.pops.KC.offset;
      this.mbonOff = net.pops.MBON.offset;
      const kcOff = this.kcOff, mbonOff = this.mbonOff, W = this.W, nKC = o.nKC;
      this.kcHook = (i) => {
        const k = i - kcOff;
        if (k < 0 || k >= nKC) return;
        const base = k * M;
        for (let j = 0; j < M; j++) net.s[mbonOff + j] += W[base + j];
      };
    }

    reset() {
      const net = this.net;
      net.v.fill(0); net.s.fill(0); net.refr.fill(0);
      this.elig.fill(0);
      this.eye.reset();
      this.pendingReward = 0;
    }

    setInput(name, values, gain) {
      const p = this.net.pops[name];
      for (let i = 0; i < p.n; i++) this.net.ext[p.offset + i] = values[i] * gain;
    }

    /** Run one game tick of neural time and return the decoded motor command. */
    think(world) {
      const o = this.opts, net = this.net, M = ACTIONS.length;
      const obs = (this.lastObs = this.eye.sample(world));
      this.setInput('R_wall', obs.wall, 0.18);
      this.setInput('R_obj', obs.object, 0.3);
      this.setInput('R_loom', obs.loom, 0.3);
      // Dopamine neurons report the reward from the previous action
      const r = this.pendingReward;
      // (signed sqrt compresses the range so small penalties like a missed shot still make PPL1 spike)
      const drive = Math.sqrt(Math.abs(r)) * o.danGain;
      this.setInput('PAM', [1, 1, 1, 1], r > 0 ? drive : 0);
      this.setInput('PPL1', [1, 1, 1, 1], r < 0 ? drive : 0);

      net.counts.fill(0);
      for (let t = 0; t < o.substeps; t++) net.step(this.kcHook);

      // Three-factor learning: Δw = η · DA · eligibility(KC activity × efference copy of chosen action)
      const sum = (a) => a.reduce((x, y) => x + y, 0);
      const maxDan = 4 * Math.ceil(o.substeps / 3);
      const da = (this.lastDA = (sum(net.popCounts('PAM')) - sum(net.popCounts('PPL1'))) / maxDan);
      if (o.plasticity && o.weightDecay > 0) {
        const W = this.W, W0 = this.W0, d = o.weightDecay;
        for (let i = 0; i < W.length; i++) W[i] += d * (W0[i] - W[i]);
      }
      if (o.plasticity && da !== 0) {
        const W = this.W, E = this.elig, eta = o.learningRate * da, wMax = o.wMax;
        for (let i = 0; i < W.length; i++) {
          if (E[i] === 0) continue;
          const w = W[i] + eta * E[i];
          W[i] = w < 0 ? 0 : w > wMax ? wMax : w;
        }
      }

      // Decode descending-neuron population counts into a motor command
      const dn = {};
      for (const a of ACTIONS) dn[a] = sum(net.popCounts('DN_' + a));
      const turn = clamp((dn.turnL - dn.turnR) / 6, -1, 1);
      const move = clamp((dn.forward - dn.backward) / 6, -1, 1);
      const fire = dn.fire >= 3;
      const chosen = [turn > 0.15, turn < -0.15, move > 0.15, move < -0.15, fire];

      const kc = net.popCounts('KC');
      const E = this.elig, lam = o.eligibilityDecay;
      for (let i = 0; i < E.length; i++) E[i] *= lam;
      for (let k = 0; k < o.nKC; k++) {
        if (!kc[k]) continue;
        const c = Math.min(kc[k], 3);
        for (let j = 0; j < M; j++) if (chosen[j]) E[k * M + j] += c;
      }
      this.lastDN = dn;
      this.lastChosen = chosen;
      return { turn, move, fire };
    }

    feedback(reward) { this.pendingReward = reward; }

    regionActivity() {
      const out = {};
      for (const name of this.net.order) {
        const p = this.net.pops[name];
        const c = this.net.popCounts(name);
        let s = 0;
        for (let i = 0; i < c.length; i++) s += c[i];
        out[name] = s / (p.n * this.opts.substeps / 3);
      }
      return out;
    }

    mbonWeights() {
      const M = ACTIONS.length, out = {};
      ACTIONS.forEach((a, j) => {
        let s = 0;
        for (let k = 0; k < this.opts.nKC; k++) s += this.W[k * M + j];
        out[a] = s / this.opts.nKC;
      });
      return out;
    }

    stats() {
      return { neurons: this.net.n, synapses: this.net.targets.length + this.W.length, plasticSynapses: this.W.length };
    }
  }

  // ─────────────────────────── Agents & simulation ───────────────────────────
  class RandomAgent {
    constructor(seed = 1) { this.rng = new Rng(seed); }
    reset() {}
    think() {
      const r = this.rng;
      return { turn: r.float() * 2 - 1, move: r.float() * 2 - 1, fire: r.float() < 0.15 };
    }
    feedback() {}
  }

  const CONDITIONS = {
    learning: { label: 'Fly brain + dopamine learning', brain: {} },
    frozen: { label: 'Fly brain, plasticity off', brain: { plasticity: false } },
    scrambled: { label: 'Scrambled innate wiring + learning', brain: { scrambleInnate: true } },
    'mb-lesion': { label: 'Mushroom body lesioned (KC silenced)', brain: { lesion: ['KC'] } },
    random: { label: 'Random actions (no brain)', random: true },
  };

  function makeAgent(condition, seed, brainOpts = {}) {
    const c = CONDITIONS[condition];
    if (!c) throw new Error('Unknown condition: ' + condition);
    if (c.random) return new RandomAgent(seed);
    return new FlyBrain(Object.assign({ seed }, brainOpts, c.brain));
  }

  class Simulation {
    constructor({ condition = 'learning', seed = 1, brain = {}, world = {} } = {}) {
      this.condition = condition;
      this.seed = seed;
      this.agent = makeAgent(condition, seed, brain);
      this.world = new DoomWorld(Object.assign({ seed }, world));
      this.episode = 0;
      this.history = [];
      this.startEpisode();
    }
    startEpisode() {
      this.world.reset(this.seed * 10007 + this.episode * 31 + 1);
      this.agent.reset();
    }
    /** Advance one tick; returns the finished-episode stats when an episode ends. */
    tick() {
      const action = this.agent.think(this.world);
      const res = this.world.step(action);
      this.agent.feedback(res.reward);
      this.lastAction = action;
      if (res.done) {
        const s = Object.assign({ episode: this.episode }, this.world.stats());
        this.history.push(s);
        this.episode++;
        this.startEpisode();
        return s;
      }
      return null;
    }
    runEpisode() {
      for (;;) { const s = this.tick(); if (s) return s; }
    }
  }

  // ─────────────────────────── Statistics ───────────────────────────
  function mean(a) { return a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0; }
  function variance(a) {
    if (a.length < 2) return 0;
    const m = mean(a);
    return a.reduce((x, y) => x + (y - m) * (y - m), 0) / (a.length - 1);
  }
  function sem(a) { return a.length ? Math.sqrt(variance(a) / a.length) : 0; }
  /** Welch's t statistic and approximate two-sided p (normal approximation for df ≥ ~10). */
  function welch(a, b) {
    const va = variance(a) / a.length, vb = variance(b) / b.length;
    const t = (mean(a) - mean(b)) / Math.sqrt(va + vb || 1e-12);
    const df = (va + vb) ** 2 / ((va * va) / (a.length - 1 || 1) + (vb * vb) / (b.length - 1 || 1) || 1e-12);
    const z = Math.abs(t);
    // Abramowitz–Stegun erf approximation
    const x = z / Math.SQRT2, k = 1 / (1 + 0.3275911 * x);
    const erf = 1 - (((((1.061405429 * k - 1.453152027) * k + 1.421413741) * k - 0.284496736) * k + 0.254829592) * k) * Math.exp(-x * x);
    return { t, df, p: 1 - erf };
  }
  function slope(ys) {
    const n = ys.length;
    if (n < 2) return 0;
    const mx = (n - 1) / 2, my = mean(ys);
    let num = 0, den = 0;
    ys.forEach((y, i) => { num += (i - mx) * (y - my); den += (i - mx) ** 2; });
    return num / den;
  }

  return {
    Rng, DoomWorld, CompoundEye, SpikingNetwork, FlyBrain, RandomAgent, Simulation,
    ACTIONS, DN_NAMES, CONDITIONS, DEFAULT_MAP, WORLD_DEFAULTS, BRAIN_DEFAULTS,
    makeAgent, stats: { mean, variance, sem, welch, slope }, wrapAngle,
  };
});

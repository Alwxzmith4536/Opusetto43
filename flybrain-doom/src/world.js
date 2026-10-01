// A small Doom-like world: grid walls, imps that throw fireballs, a hitscan pistol,
// and two colors of orb. One orb color heals and the other burns; which is which
// is set per world (goodColor), so no fixed wiring can know it in advance.
//
// Coordinates: x grows east, y grows south (rows of the map). An angle a points
// along (cos a, sin a). A bearing is measured from the heading and is positive
// to the left, so turning left lowers the heading angle.

import { RNG } from './rng.js';
import { MAPS } from './maps.js';

export const TIC_RATE = 35; // Doom's game tic rate
export const TIC = 1 / TIC_RATE;
export const DEG = Math.PI / 180;

export const SCENARIOS = {
  forage: {
    label: 'Valence forage', map: 'arena', imps: 0, orbsPerColor: 3, seconds: 40,
    about: 'Blue and green orbs in an open room. One color heals, the other burns.',
  },
  combat: {
    label: 'Imp hangar', map: 'hangar', imps: 3, orbsPerColor: 0, seconds: 40,
    about: 'Imps that chase and throw fireballs. Tests pursuit, aiming and escape.',
  },
  doom: {
    label: 'Mixed E1', map: 'hangar', imps: 3, orbsPerColor: 3, seconds: 60,
    about: 'Imps and orbs together.',
  },
};

export const ORB_COLORS = ['blue', 'green'];
export const otherColor = (c) => (c === 'blue' ? 'green' : 'blue');

export const PLAYER = { radius: 0.25, speed: 3.0, backSpeed: 1.8, strafeSpeed: 2.6, turnSpeed: 200 * DEG, maxHealth: 200 };
export const IMP = {
  radius: 0.32, hp: 60, speed: 1.5, sight: 12, fireMin: 2.2, fireMax: 4.0,
  melee: 0.85, meleeDmg: [3, 9], ballSpeed: 6, ballRadius: 0.22, ballDmg: [4, 10],
  painChance: 0.78, respawn: 3, minSpawnDist: 7,
};
export const PISTOL = { cooldown: 0.4, dmg: [12, 22], spread: 1.0 * DEG, range: 24, ammo: 200 };
export const ORB = { radius: 0.24, touch: 0.55, heal: 10, burn: 12, respawn: 2.5, minSpawnDist: 3 };

export const wrapAngle = (a) => {
  a = (a + Math.PI) % (2 * Math.PI);
  if (a < 0) a += 2 * Math.PI;
  return a - Math.PI;
};
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

export class World {
  constructor({ scenario = 'forage', seed = 1, goodColor = 'blue' } = {}) {
    this.scenarioName = scenario;
    this.sc = SCENARIOS[scenario];
    if (!this.sc) throw new Error(`unknown scenario ${scenario}`);
    this.map = MAPS[this.sc.map];
    this.goodColor = goodColor;
    this.seed = seed;
    this.reset();
  }

  reset() {
    const m = this.map;
    this.rng = new RNG(this.seed);
    this.time = 0;
    this.tic = 0;
    this.nextId = 1;
    this.duration = this.sc.seconds;
    this.player = {
      x: m.start.x, y: m.start.y, angle: m.start.angle + this.rng.range(-0.4, 0.4),
      vx: 0, vy: 0, health: 100, ammo: PISTOL.ammo, cooldown: 0, alive: true, hurtAt: -1, healAt: -1,
    };
    this.entities = [];
    for (let i = 0; i < this.sc.imps; i++) this.spawnImp();
    for (const color of ORB_COLORS) for (let i = 0; i < this.sc.orbsPerColor; i++) this.spawnOrb(color);
    this.stats = { good: 0, bad: 0, kills: 0, damage: 0, healed: 0, shots: 0, hits: 0, bumps: 0, distance: 0, touches: '' };
    this.lastShot = null;
    this.fx = []; // short-lived visual effects for the renderer
  }

  get done() { return !this.player.alive || this.time >= this.duration - 1e-9; }

  // ---------- geometry ----------
  cellAt(cx, cy) {
    const m = this.map;
    if (cx < 0 || cy < 0 || cx >= m.width || cy >= m.height) return 84; // 'T'
    return m.cells[cy * m.width + cx];
  }
  solid(x, y) { return this.cellAt(Math.floor(x), Math.floor(y)) !== 0; }

  // DDA ray cast. Returns distance to the first wall and where on it the ray hit.
  castRay(ox, oy, ang, maxDist = 40) {
    const dx = Math.cos(ang), dy = Math.sin(ang);
    let mx = Math.floor(ox), my = Math.floor(oy);
    const ddx = dx === 0 ? 1e30 : Math.abs(1 / dx);
    const ddy = dy === 0 ? 1e30 : Math.abs(1 / dy);
    let stepX, stepY, sx, sy;
    if (dx < 0) { stepX = -1; sx = (ox - mx) * ddx; } else { stepX = 1; sx = (mx + 1 - ox) * ddx; }
    if (dy < 0) { stepY = -1; sy = (oy - my) * ddy; } else { stepY = 1; sy = (my + 1 - oy) * ddy; }
    let side = 0, dist = 0;
    for (let i = 0; i < 96; i++) {
      if (sx < sy) { dist = sx; sx += ddx; mx += stepX; side = 0; } else { dist = sy; sy += ddy; my += stepY; side = 1; }
      if (dist > maxDist) return { dist: maxDist, cell: 0, side, u: 0, mx, my };
      const c = this.cellAt(mx, my);
      if (c) {
        let u = side === 0 ? oy + dist * dy : ox + dist * dx;
        u -= Math.floor(u);
        return { dist, cell: c, side, u, mx, my };
      }
    }
    return { dist: maxDist, cell: 0, side, u: 0, mx, my };
  }

  lineOfSight(ax, ay, bx, by) {
    const d = Math.hypot(bx - ax, by - ay);
    return this.castRay(ax, ay, Math.atan2(by - ay, bx - ax), d + 0.01).dist >= d - 0.05;
  }

  // Bearing of a point from the player: positive to the left, in (-pi, pi].
  bearingTo(x, y) {
    const p = this.player;
    return wrapAngle(p.angle - Math.atan2(y - p.y, x - p.x));
  }

  // Slide a circle through the grid. Returns true if a wall blocked it.
  moveCircle(o, dx, dy, r) {
    let bumped = false;
    const nx = o.x + dx;
    if (!this.solid(nx + Math.sign(dx) * r, o.y - r * 0.9) && !this.solid(nx + Math.sign(dx) * r, o.y + r * 0.9)) o.x = nx;
    else if (dx !== 0) bumped = true;
    const ny = o.y + dy;
    if (!this.solid(o.x - r * 0.9, ny + Math.sign(dy) * r) && !this.solid(o.x + r * 0.9, ny + Math.sign(dy) * r)) o.y = ny;
    else if (dy !== 0) bumped = true;
    return bumped;
  }

  randomOpenSpot(minDist) {
    const p = this.player, open = this.map.open;
    for (let tries = 0; tries < 200; tries++) {
      const [cx, cy] = open[this.rng.int(open.length)];
      const x = cx + 0.5 + this.rng.range(-0.2, 0.2), y = cy + 0.5 + this.rng.range(-0.2, 0.2);
      if (Math.hypot(x - p.x, y - p.y) < minDist) continue;
      if (this.entities.some((e) => e.alive !== false && Math.hypot(e.x - x, e.y - y) < 1.2)) continue;
      return { x, y };
    }
    const [cx, cy] = open[this.rng.int(open.length)];
    return { x: cx + 0.5, y: cy + 0.5 };
  }

  spawnImp() {
    const s = this.randomOpenSpot(IMP.minSpawnDist);
    const imp = {
      id: this.nextId++, kind: 'imp', x: s.x, y: s.y, vx: 0, vy: 0, radius: IMP.radius,
      hp: IMP.hp, alive: true, alert: false, cd: this.rng.range(1, 2.5), pain: 0,
      heading: this.rng.range(-Math.PI, Math.PI), wobble: 0, wobbleT: 0, respawn: 0, attackAt: -1,
    };
    this.entities.push(imp);
    return imp;
  }

  spawnOrb(color) {
    const s = this.randomOpenSpot(ORB.minSpawnDist);
    const orb = { id: this.nextId++, kind: 'orb', color, x: s.x, y: s.y, vx: 0, vy: 0, radius: ORB.radius, alive: true, respawn: 0 };
    this.entities.push(orb);
    return orb;
  }

  hurt(amount, ev) {
    const p = this.player;
    if (!p.alive) return;
    p.health -= amount;
    p.hurtAt = this.time;
    ev.damage += amount;
    this.stats.damage += amount;
    if (p.health <= 0) { p.health = 0; p.alive = false; ev.died = true; }
  }

  // ---------- one game tic ----------
  // action: { forward: -1..1, turn: -1..1 (left +), strafe: -1..1 (left +), fire: bool }
  step(action = {}) {
    const ev = { damage: 0, heal: 0, good: 0, bad: 0, kill: 0, shot: false, hit: false, bump: false, died: false };
    const p = this.player, rng = this.rng;
    if (this.done) return ev;

    // Player motion
    const turn = clamp(action.turn || 0, -1, 1);
    const fwd = clamp(action.forward || 0, -1, 1);
    const strafe = clamp(action.strafe || 0, -1, 1);
    p.angle = wrapAngle(p.angle - turn * PLAYER.turnSpeed * TIC);
    const sp = (fwd >= 0 ? PLAYER.speed : PLAYER.backSpeed) * fwd;
    const ss = strafe * PLAYER.strafeSpeed;
    // left of heading is (sin a, -cos a)
    const mvx = (Math.cos(p.angle) * sp + Math.sin(p.angle) * ss) * TIC;
    const mvy = (Math.sin(p.angle) * sp - Math.cos(p.angle) * ss) * TIC;
    const ox = p.x, oy = p.y;
    ev.bump = this.moveCircle(p, mvx, mvy, PLAYER.radius);
    // imps are solid
    for (const e of this.entities) {
      if (e.kind !== 'imp' || !e.alive) continue;
      const d = Math.hypot(p.x - e.x, p.y - e.y), min = PLAYER.radius + e.radius;
      if (d < min && d > 1e-6) { p.x = e.x + (p.x - e.x) / d * min; p.y = e.y + (p.y - e.y) / d * min; if (this.solid(p.x, p.y)) { p.x = ox; p.y = oy; } }
    }
    p.vx = (p.x - ox) / TIC; p.vy = (p.y - oy) / TIC;
    this.stats.distance += Math.hypot(p.x - ox, p.y - oy);
    if (ev.bump) this.stats.bumps++;

    // Pistol (hitscan)
    p.cooldown = Math.max(0, p.cooldown - TIC);
    if (action.fire && p.cooldown <= 0 && p.ammo > 0) {
      p.cooldown = PISTOL.cooldown; p.ammo--; ev.shot = true; this.stats.shots++;
      const ang = p.angle + rng.normal() * PISTOL.spread;
      const wallD = this.castRay(p.x, p.y, ang, PISTOL.range).dist;
      const cx = Math.cos(ang), cy = Math.sin(ang);
      let best = null, bestT = wallD;
      for (const e of this.entities) {
        if (e.kind !== 'imp' || !e.alive) continue;
        const ex = e.x - p.x, ey = e.y - p.y, t = ex * cx + ey * cy;
        if (t <= 0 || t >= bestT) continue;
        if (ex * ex + ey * ey - t * t <= e.radius * e.radius) { best = e; bestT = t; }
      }
      this.lastShot = { t: this.time, ang, dist: bestT, hit: !!best };
      if (best) {
        ev.hit = true; this.stats.hits++;
        best.hp -= Math.round(rng.range(PISTOL.dmg[0], PISTOL.dmg[1]));
        best.alert = true;
        this.fx.push({ kind: 'blood', x: best.x, y: best.y, t: this.time });
        if (best.hp <= 0) {
          best.alive = false; best.respawn = IMP.respawn; best.diedAt = this.time;
          ev.kill++; this.stats.kills++;
        } else if (rng.chance(IMP.painChance)) best.pain = 0.25;
      } else {
        this.fx.push({ kind: 'puff', x: p.x + cx * (bestT - 0.05), y: p.y + cy * (bestT - 0.05), t: this.time });
      }
    }

    // Entities
    const keep = [];
    for (const e of this.entities) {
      if (e.kind === 'imp') this.updateImp(e, ev);
      else if (e.kind === 'fireball') { if (!this.updateFireball(e, ev)) continue; }
      else if (e.kind === 'orb') this.updateOrb(e, ev);
      keep.push(e);
    }
    this.entities = keep;
    this.fx = this.fx.filter((f) => this.time - f.t < 0.6);

    this.time += TIC;
    this.tic++;
    return ev;
  }

  updateImp(e, ev) {
    const p = this.player, rng = this.rng;
    if (!e.alive) {
      e.respawn -= TIC;
      if (e.respawn <= 0) {
        const s = this.randomOpenSpot(IMP.minSpawnDist);
        Object.assign(e, { x: s.x, y: s.y, hp: IMP.hp, alive: true, alert: false, cd: rng.range(1.5, 3), pain: 0 });
      }
      e.vx = e.vy = 0;
      return;
    }
    const ox = e.x, oy = e.y;
    if (e.pain > 0) { e.pain -= TIC; e.vx = e.vy = 0; return; }
    const dx = p.x - e.x, dy = p.y - e.y, dist = Math.hypot(dx, dy);
    const sees = p.alive && dist < IMP.sight && this.lineOfSight(e.x, e.y, p.x, p.y);
    if (sees) e.alert = true;
    e.wobbleT -= TIC;
    if (e.wobbleT <= 0) { e.wobble = rng.range(-0.8, 0.8); e.wobbleT = rng.range(0.5, 1.2); }
    let speed;
    if (e.alert && p.alive) {
      e.heading = Math.atan2(dy, dx) + e.wobble;
      speed = dist > 1.1 ? IMP.speed : 0;
      e.cd -= TIC;
      if (e.cd <= 0 && sees) {
        e.attackAt = this.time;
        if (dist < IMP.melee) {
          this.hurt(Math.round(rng.range(IMP.meleeDmg[0], IMP.meleeDmg[1])), ev);
          e.cd = 1.0;
        } else {
          const a = Math.atan2(dy, dx) + rng.normal() * 2 * DEG;
          this.entities.push({
            id: this.nextId++, kind: 'fireball', x: e.x + Math.cos(a) * 0.45, y: e.y + Math.sin(a) * 0.45,
            vx: Math.cos(a) * IMP.ballSpeed, vy: Math.sin(a) * IMP.ballSpeed, radius: IMP.ballRadius, life: 4, alive: true, from: e.id,
          });
          e.cd = rng.range(IMP.fireMin, IMP.fireMax);
        }
      }
    } else {
      if (e.wobbleT > 1.0) e.heading += e.wobble;
      speed = IMP.speed * 0.4;
    }
    if (speed > 0) {
      const hit = this.moveCircle(e, Math.cos(e.heading) * speed * TIC, Math.sin(e.heading) * speed * TIC, e.radius);
      if (hit) e.heading += rng.range(1, 2.5);
      // don't walk into the player
      const d2 = Math.hypot(p.x - e.x, p.y - e.y), min = PLAYER.radius + e.radius;
      if (d2 < min) { e.x = ox; e.y = oy; }
    }
    e.vx = (e.x - ox) / TIC; e.vy = (e.y - oy) / TIC;
  }

  updateFireball(b, ev) {
    const p = this.player;
    b.life -= TIC;
    const nx = b.x + b.vx * TIC, ny = b.y + b.vy * TIC;
    if (b.life <= 0 || this.solid(nx, ny)) { this.fx.push({ kind: 'boom', x: b.x, y: b.y, t: this.time }); return false; }
    b.x = nx; b.y = ny;
    if (p.alive && Math.hypot(p.x - b.x, p.y - b.y) < PLAYER.radius + b.radius) {
      this.hurt(Math.round(this.rng.range(IMP.ballDmg[0], IMP.ballDmg[1])), ev);
      this.fx.push({ kind: 'boom', x: b.x, y: b.y, t: this.time });
      return false;
    }
    return true;
  }

  updateOrb(o, ev) {
    const p = this.player;
    if (!o.alive) {
      o.respawn -= TIC;
      if (o.respawn <= 0) { const s = this.randomOpenSpot(ORB.minSpawnDist); o.x = s.x; o.y = s.y; o.alive = true; }
      return;
    }
    if (!p.alive || Math.hypot(p.x - o.x, p.y - o.y) > ORB.touch) return;
    o.alive = false; o.respawn = ORB.respawn;
    if (o.color === this.goodColor) {
      p.health = Math.min(PLAYER.maxHealth, p.health + ORB.heal);
      p.healAt = this.time;
      ev.heal += ORB.heal; ev.good++; this.stats.good++; this.stats.healed += ORB.heal; this.stats.touches += 'g';
      this.fx.push({ kind: 'heal', x: o.x, y: o.y, t: this.time });
    } else {
      ev.bad++; this.stats.bad++; this.stats.touches += 'b';
      this.fx.push({ kind: 'burn', x: o.x, y: o.y, t: this.time });
      this.hurt(ORB.burn, ev);
    }
  }
}

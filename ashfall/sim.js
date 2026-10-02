// sim.js — fighters, camera, events, time-warp, and the sampled state tables (face, gait phase, scarves).
(function (root) {
'use strict';
const C = root.CORE;
const { clamp, lerp, EASE, Track, solveLocal, toWorld, groundY, depthScale, BODY, D2R } = C;

const RATE = 240; // sampling rate for derived tables
const SIM = {
  FPS: 30, W: 1280, H: 720, total: 60,
  colors: {
    G: { body: '#2fdc66', dark: '#0c3a1b', saber: '#3dff78', glow: 'rgba(61,255,120,', name: 'GREEN' },
    B: { body: '#3b8cff', dark: '#0b2459', saber: '#46a6ff', glow: 'rgba(70,166,255,', name: 'BLUE' },
    Y: { body: '#ffd21c', dark: '#4a3700', saber: '#ffe14a', glow: 'rgba(255,225,74,', name: 'YELLOW' },
  },
  F: { G: new Track('G'), B: new Track('B'), Y: new Track('Y') },
  names: ['G', 'B', 'Y'],
  evs: [], camKeys: [], texts: [], faceFix: [], warp: new C.Warp(), built: false,
};

SIM.ev = function (t, type, o) { const e = Object.assign({ t, type }, o || {}); e.id = SIM.evs.length; SIM.evs.push(e); return e; };
SIM.cam = function (t, o) { SIM.camKeys.push(Object.assign({ t, ease: 'io', tau: 0.22, zm: 1 }, o)); };
SIM.txt = function (t0, t1, o) { SIM.texts.push(Object.assign({ t0, t1 }, o)); };
SIM.fix = function (f, t0, t1, dir) { SIM.faceFix.push({ f, t0, t1, dir }); };
SIM.die = function (f, t) { SIM.F[f].deathT = t; SIM.ev(t, 'die', { f }); };

// ---------------------------------------------------------------- state
function rawState(name, s) {
  const e = SIM.F[name].eval(s);
  return e;
}
SIM.stateAt = function (name, s) {
  const tr = SIM.F[name], e = tr.eval(s);
  const i = clamp(Math.round(s * RATE), 0, SIM.N - 1);
  const face = SIM.face[name][i], phase = SIM.phase[name][i];
  const sc = depthScale(e.z), gy = groundY(e.z);
  const sk = solveLocal(e.pose, phase);
  return { name, x: e.x, z: e.z, h: e.h, rot: e.rot, on: e.held ? e.on : 0, held: e.held, pose: e.pose, face, sc, gy, lift: sk.lift, sk, phase, dead: s >= tr.deathT };
};
SIM.W = toWorld;
SIM.blade = function (st) { // world segment of the blade
  const sk = st.sk, L = BODY.blade * clamp(st.on, 0, 1);
  const a = toWorld(st, sk.hilt1);
  const b = toWorld(st, [sk.hilt1[0] + sk.bd[0] * L, sk.hilt1[1] + sk.bd[1] * L]);
  return [a, b];
};
SIM.hand = st => toWorld(st, st.sk.hand1);
SIM.pelvis = st => toWorld(st, [0, 0]);

function segClosest(a, b, c, d) { // closest points between segments ab and cd
  const ux = b[0] - a[0], uy = b[1] - a[1], vx = d[0] - c[0], vy = d[1] - c[1], wx = a[0] - c[0], wy = a[1] - c[1];
  const A = ux * ux + uy * uy, B = ux * vx + uy * vy, Cc = vx * vx + vy * vy, D = ux * wx + uy * wy, E = vx * wx + vy * wy;
  const den = A * Cc - B * B;
  let sN, sD = den, tN, tD = den;
  if (den < 1e-9) { sN = 0; sD = 1; tN = E; tD = Cc; }
  else {
    sN = B * E - Cc * D; tN = A * E - B * D;
    if (sN < 0) { sN = 0; tN = E; tD = Cc; } else if (sN > sD) { sN = sD; tN = E + B; tD = Cc; }
  }
  if (tN < 0) { tN = 0; sN = clamp(-D, 0, A) ; sD = A; } else if (tN > tD) { tN = tD; sN = clamp(-D + B, 0, A); sD = A; }
  const sc = Math.abs(sN) < 1e-9 ? 0 : sN / sD, tc = Math.abs(tN) < 1e-9 ? 0 : tN / tD;
  const p = [a[0] + ux * sc, a[1] + uy * sc], q = [c[0] + vx * tc, c[1] + vy * tc];
  return { p, q, d: Math.hypot(p[0] - q[0], p[1] - q[1]) };
}
SIM.segClosest = segClosest;

// ---------------------------------------------------------------- build
SIM.build = function () {
  const total = SIM.total, N = Math.ceil(total * RATE) + 2;
  SIM.N = N; SIM.RATE = RATE;
  const names = SIM.names, F = SIM.F;
  for (const n of names) F[n].keys.sort((a, b) => a.t - b.t);

  // 1) resolve blade locks (keys that pin the saber hand so two blades meet at a world point)
  for (const n of names) for (const k of F[n].keys) {
    if (!k.lock) continue;
    const L = k.lock, o = F[L.with].eval(k.t), me = F[n].eval(k.t);
    const dir = Math.sign(o.x - me.x) || 1, cx = L.cx !== undefined ? L.cx : (me.x + o.x) / 2;
    const cy = L.cy;
    const sc = depthScale(me.z), gy = groundY(me.z);
    const ang = L.ang * D2R, d = L.d !== undefined ? L.d : 62;
    // blade passes through C; hand sits d behind C along the blade
    const hx = cx - dir * Math.cos(ang) * d, hy = cy - Math.sin(ang) * d;
    const p = k.pose;
    const liftV = Math.max(-p.f1y, -p.f2y);
    const pelvX = me.x, pelvY = gy + (liftV + me.h) * sc;
    p.h1x = (hx - pelvX) * dir / sc; p.h1y = (hy - pelvY) / sc; p.sab = L.ang;
    p.two = L.two !== undefined ? L.two : 1;
  }

  // 2) facing table
  const face = {}, phase = {};
  for (const n of names) { face[n] = new Int8Array(N); phase[n] = new Float32Array(N); }
  const lastFlip = {}, cur = {};
  for (const n of names) { cur[n] = 1; lastFlip[n] = -9; }
  const xs = {}, ys = {};
  for (let i = 0; i < N; i++) {
    const s = i / RATE;
    for (const n of names) xs[n] = F[n].eval(s).x;
    for (const n of names) {
      let want = cur[n];
      const fx = SIM.faceFix.find(q => q.f === n && s >= q.t0 && s < q.t1);
      if (fx) want = fx.dir;
      else if (s < F[n].deathT) {
        let best = null, bd = 1e9;
        for (const m of names) {
          if (m === n || s >= F[m].deathT + 0.3) continue;
          const d = Math.abs(xs[m] - xs[n]); if (d < bd) { bd = d; best = m; }
        }
        if (best && bd > 28) want = xs[best] > xs[n] ? 1 : -1;
      }
      if (want !== cur[n] && (fx || s - lastFlip[n] > 0.16)) { cur[n] = want; lastFlip[n] = s; }
      face[n][i] = cur[n];
    }
  }
  SIM.face = face;
  // 3) gait phase
  for (const n of names) {
    let ph = 0, px = F[n].eval(0).x;
    for (let i = 0; i < N; i++) {
      const s = i / RATE, e = F[n].eval(s), P = e.pose;
      const dx = (e.x - px) * face[n][i]; px = e.x;
      const ws = P.walk + P.run;
      if (ws > 0.02) {
        const A = (P.walk * C.GAIT.walk.A + P.run * C.GAIT.run.A) / ws;
        ph += Math.PI * dx / (2 * A);
      }
      phase[n][i] = ph;
    }
  }
  SIM.phase = phase;

  // 4) scarves (verlet) anchored at the neck
  const M = 9, SEG = 11;
  SIM.scarfM = M;
  SIM.scarf = {};
  for (const n of names) {
    const buf = new Float32Array(N * M * 2);
    let pts = null, prev = null;
    const seed = n.charCodeAt(0);
    for (let i = 0; i < N; i++) {
      const s = i / RATE;
      const st = SIM.stateAt(n, s);
      const nk = toWorld(st, [st.sk.N[0] - 3 * Math.sign(1), st.sk.N[1] - 4]);
      if (!pts) { pts = []; prev = []; for (let k = 0; k < M; k++) { pts.push([nk[0] - k * SEG * 0.8, nk[1] - k * 2]); prev.push(pts[k].slice()); } }
      pts[0][0] = nk[0]; pts[0][1] = nk[1];
      const dt = 1 / RATE;
      const gust = 1 + 0.6 * C.vnoise(s * 0.7, seed) + 0.5 * C.vnoise(s * 2.3, seed + 3);
      const wind = (SIM.wind ? SIM.wind(s) : 1) * gust;
      for (let k = 1; k < M; k++) {
        const vx = (pts[k][0] - prev[k][0]) * 0.965, vy = (pts[k][1] - prev[k][1]) * 0.965;
        prev[k][0] = pts[k][0]; prev[k][1] = pts[k][1];
        const flut = C.vnoise(s * 9 + k * 1.7, seed + k) * 520;
        const fc = face[n][i];
        pts[k][0] += vx + (-fc * 1500 + 260 * wind) * dt * dt * (0.6 + k * 0.08);
        pts[k][1] += vy - 900 * dt * dt * 0.5 + flut * dt * dt * 6;
      }
      for (let it = 0; it < 3; it++) {
        for (let k = 1; k < M; k++) {
          const a = pts[k - 1], b = pts[k];
          let dx = b[0] - a[0], dy = b[1] - a[1], d = Math.hypot(dx, dy) || 1e-6;
          const diff = (d - SEG) / d;
          if (k === 1) { b[0] -= dx * diff; b[1] -= dy * diff; }
          else { a[0] += dx * diff * 0.5; a[1] += dy * diff * 0.5; b[0] -= dx * diff * 0.5; b[1] -= dy * diff * 0.5; }
        }
        pts[0][0] = nk[0]; pts[0][1] = nk[1];
      }
      for (let k = 0; k < M; k++) { buf[(i * M + k) * 2] = pts[k][0]; buf[(i * M + k) * 2 + 1] = pts[k][1]; }
    }
    SIM.scarf[n] = buf;
  }

  // 5) resolve event positions that depend on pose state
  for (const e of SIM.evs) {
    if (e.type === 'clash' && !e.pos) {
      const A = SIM.stateAt(e.a, e.t), B = SIM.stateAt(e.b, e.t);
      const ba = SIM.blade(A), bb = SIM.blade(B);
      const r = segClosest(ba[0], ba[1], bb[0], bb[1]);
      e.pos = [(r.p[0] + r.q[0]) / 2, (r.p[1] + r.q[1]) / 2]; e.gap = r.d;
    }
    if (e.type === 'push' && !e.pos) {
      const st = SIM.stateAt(e.f, e.t);
      e.pos = toWorld(st, [st.sk.hand2[0] + 10, st.sk.hand2[1]]);
      e.dir = st.face; e.gz = st.z;
    }
    if (e.type === 'spark' && !e.pos) { const st = SIM.stateAt(e.f, e.t); e.st = st; const hd = toWorld(st, st.sk.hand1), tp = [hd[0] + st.face * 0, hd[1]]; const b = [toWorld(st, st.sk.hilt1), toWorld(st, [st.sk.hilt1[0] + st.sk.bd[0] * BODY.blade, st.sk.hilt1[1] + st.sk.bd[1] * BODY.blade])]; e.pos = [b[1][0], Math.max(b[1][1], groundY(st.z))]; }
    if (e.type === 'sabre') {
      const st = SIM.stateAt(e.f, e.t); e.p0 = toWorld(st, st.sk.hand1);
      const T = e.tl - e.t, g = 1500; e.gy = groundY(e.lz !== undefined ? e.lz : 0.5) + 5;
      e.vx = (e.lx - e.p0[0]) / T; e.vy = (e.gy - e.p0[1] + 0.5 * g * T * T) / T;
      const sc = SIM.stateAt(e.f, e.tc); e.pc = toWorld(sc, sc.sk.hand1);
    }
    if (e.type === 'slice' && !e.pos && e.f) {
      const st = SIM.stateAt(e.f, e.t); const pv = toWorld(st, [0, 30]); e.pos = pv;
    }
    if (e.type === 'hit' && !e.pos) {
      const st = SIM.stateAt(e.f, e.t); e.pos = toWorld(st, e.at || [20, 40]);
    }
    if (e.type === 'ignite' && !e.pos) {
      const st = SIM.stateAt(e.f, e.t + 0.15); const b = SIM.blade(st); e.pos = b[0];
    }
    if (e.type === 'die') {
      // sample bone points at death time for disintegration
      const st = SIM.stateAt(e.f, e.t), sk = st.sk;
      const segs = [[[0, 0], sk.N], [sk.S, sk.e1], [sk.e1, sk.hand1], [sk.S, sk.e2], [sk.e2, sk.hand2], [[0, 0], sk.k1], [sk.k1, sk.foot1], [[0, 0], sk.k2], [sk.k2, sk.foot2]];
      const R = C.rng(900 + e.id), pts = [];
      for (let i = 0; i < 260; i++) {
        const sg = segs[Math.floor(R() * segs.length)], u = R();
        const p = toWorld(st, [lerp(sg[0][0], sg[1][0], u), lerp(sg[0][1], sg[1][1], u)]);
        pts.push(p);
      }
      for (let i = 0; i < 30; i++) { const a = R() * 6.28, r = R() * 12; const h = toWorld(st, sk.head); pts.push([h[0] + Math.cos(a) * r, h[1] + Math.sin(a) * r]); }
      e.pts = pts;
      let mn = 1e9, mx = -1e9; for (const p of pts) { mn = Math.min(mn, p[0]); mx = Math.max(mx, p[0]); }
      e.x0 = mn - 12; e.x1 = mx + 12;
    }
  }
  SIM.evs.sort((a, b) => a.t - b.t);

  // 6) camera table (smoothed)
  SIM.camTable = buildCamera();
  SIM.warp.build(total + 6);
  SIM.built = true;
};

function camTarget(k, s) {
  let x = k.x, y = k.y, z = k.zoom;
  if (k.fol) {
    let sx = 0, sy = 0, mn = 1e9, mx = -1e9, n = 0;
    for (const f of k.fol) {
      const st = SIM.stateAt(f, s);
      sx += st.x; sy += st.gy + st.h * 0.55 + (st.lift - 70) * 0.4; mn = Math.min(mn, st.x); mx = Math.max(mx, st.x); n++;
    }
    x = sx / n + (k.dx || 0); y = sy / n + 95 + (k.dy || 0);
    if (k.x !== undefined) x = k.x; if (k.y !== undefined) y = k.y;
    if (z === undefined) z = clamp(600 / (mx - mn + 330), 0.55, 1.7) * k.zm;
  }
  return { x, y, z, roll: k.roll || 0 };
}
function buildCamera() {
  const K = SIM.camKeys.slice().sort((a, b) => a.t - b.t);
  const N = SIM.N, tab = new Float32Array(N * 4);
  let cx = 0, cy = 95, cz = 0.7, started = false;
  for (let i = 0; i < N; i++) {
    const s = i / RATE;
    let a = K[0], b = K[0];
    for (let j = 0; j < K.length; j++) { if (K[j].t <= s) a = K[j]; if (K[j].t > s) { b = K[j]; break; } b = K[j]; }
    let tg;
    if (a === b || s <= a.t) tg = camTarget(a, s);
    else {
      const u = EASE[b.ease](clamp((s - a.t) / (b.t - a.t), 0, 1));
      const ta = camTarget(a, s), tb = camTarget(b, s);
      tg = { x: lerp(ta.x, tb.x, u), y: lerp(ta.y, tb.y, u), z: lerp(ta.z, tb.z, u), roll: lerp(ta.roll, tb.roll, u) };
      if (b.cut && s >= b.t - 1 / RATE) tg = tb; // hard cut handled below
    }
    // hard cut: the key exactly at this time has cut:true -> snap
    const cutKey = K.find(q => q.cut && Math.abs(q.t - s) < 0.5 / RATE + 1e-9);
    if (!started || cutKey) { const t0 = camTarget(cutKey || a, s); cx = t0.x; cy = t0.y; cz = t0.z; started = true; tg = t0; }
    const tau = a.tau || 0.2, kk = 1 - Math.exp(-1 / RATE / tau);
    cx += (tg.x - cx) * kk; cy += (tg.y - cy) * kk; cz += (tg.z - cz) * kk * 0.9;
    tab[i * 4] = cx; tab[i * 4 + 1] = cy; tab[i * 4 + 2] = cz; tab[i * 4 + 3] = tg.roll;
  }
  return tab;
}
SIM.camAt = function (s) {
  const f = clamp(s * RATE, 0, SIM.N - 2), i = Math.floor(f), u = f - i, T = SIM.camTable;
  return { x: lerp(T[i * 4], T[i * 4 + 4], u), y: lerp(T[i * 4 + 1], T[i * 4 + 5], u), zoom: lerp(T[i * 4 + 2], T[i * 4 + 6], u), roll: lerp(T[i * 4 + 3], T[i * 4 + 7], u) };
};
SIM.shakeAt = function (s, o) {
  let ax = 0, ay = 0, zp = 0;
  for (const e of SIM.evs) {
    if (!e.shk || s < e.t || s > e.t + 1.2) continue;
    const dt = s - e.t, a = e.shk * Math.exp(-dt / (e.decay || 0.16));
    ax += a * C.vnoise(o * 46 + e.id * 13, 1); ay += a * C.vnoise(o * 46 + e.id * 29, 2);
    if (e.shk >= 6) zp += e.shk * 0.0026 * Math.exp(-dt / 0.13);
  }
  return [ax, ay, Math.min(zp, 0.12)];
};

root.SIM = SIM;
})(typeof window !== 'undefined' ? window : globalThis);

// core.js — skeleton, IK, keyframe tracks, camera, time-warp. Pure maths, no DOM.
(function (root) {
'use strict';
const D2R = Math.PI / 180;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = (a, b, x) => { const u = clamp((x - a) / (b - a), 0, 1); return u * u * (3 - 2 * u); };

const EASE = {
  lin: u => u,
  in: u => u * u * u,
  inq: u => u * u,
  out: u => 1 - Math.pow(1 - u, 3),
  outq: u => 1 - (1 - u) * (1 - u),
  io: u => (u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2),
  snap: u => 1 - Math.pow(1 - u, 5),
  back: u => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(u - 1, 3) + c1 * Math.pow(u - 1, 2); },
  hold: u => (u < 1 ? 0 : 1),
};

function rng(seed) {
  let a = seed | 0;
  return function () {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hash(n) { // stateless 0..1 noise from an integer
  n = (n ^ 61) ^ (n >>> 16); n = n + (n << 3); n = n ^ (n >>> 4); n = Math.imul(n, 0x27d4eb2d); n = n ^ (n >>> 15);
  return (n >>> 0) / 4294967296;
}
function vnoise(x, seed) { // smooth 1-D value noise
  const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f);
  return lerp(hash(i * 7919 + seed * 104729), hash((i + 1) * 7919 + seed * 104729), u) * 2 - 1;
}

// ---------------------------------------------------------------- body
const BODY = { torso: 46, shoulder: 41, head: 14.5, neck: 19, upper: 36, fore: 35, thigh: 44, shin: 44, blade: 118, hilt: 20 };
const FIELDS = ['tor', 'hd', 'h1x', 'h1y', 'h2x', 'h2y', 'two', 'sab', 'f1x', 'f1y', 'f2x', 'f2y', 'walk', 'run'];
const BASE = { tor: 2, hd: 0, h1x: 12, h1y: -24, h2x: -8, h2y: -30, two: 0, sab: -80, f1x: 10, f1y: -86, f2x: -10, f2y: -86, walk: 0, run: 0 };
const POSE = {};
function defPose(name, o, from) { POSE[name] = Object.assign({}, BASE, from ? POSE[from] : {}, o); return POSE[name]; }
function resolvePose(p, over) {
  const base = typeof p === 'string' ? POSE[p] : p;
  if (!base) throw new Error('unknown pose ' + p);
  const out = {};
  for (const k of FIELDS) out[k] = (over && over[k] !== undefined) ? over[k] : (base[k] !== undefined ? base[k] : BASE[k]);
  return out;
}

// two-bone IK; returns both candidate mid-joints and the (possibly clamped) end point
function ik2(ax, ay, tx, ty, l1, l2) {
  let dx = tx - ax, dy = ty - ay, d = Math.hypot(dx, dy);
  if (d < 1e-6) { dx = 0; dy = -1; d = 1e-6; }
  const maxd = l1 + l2 - 0.02, mind = Math.abs(l1 - l2) + 0.5;
  const dd = clamp(d, mind, maxd);
  const ux = dx / d, uy = dy / d;
  const ex = ax + ux * dd, ey = ay + uy * dd;
  const a = (l1 * l1 - l2 * l2 + dd * dd) / (2 * dd);
  const h = Math.sqrt(Math.max(0, l1 * l1 - a * a));
  const mx = ax + ux * a, my = ay + uy * a;
  return { c1: [mx - uy * h, my + ux * h], c2: [mx + uy * h, my - ux * h], end: [ex, ey] };
}
function pickElbow(r) {
  const [a, b] = [r.c1, r.c2];
  if (Math.abs(a[1] - b[1]) > 5) return a[1] < b[1] ? a : b;
  return a[0] < b[0] ? a : b;
}
function pickKnee(r) { return r.c1[0] > r.c2[0] ? r.c1 : r.c2; }

const GAIT = { walk: { A: 24, L: 85, lift: 12 }, run: { A: 50, L: 77, lift: 36 } };
function gaitFeet(P, phase) {
  const g = clamp(P.walk + P.run, 0, 1);
  if (g < 1e-3) return null;
  const ws = P.walk + P.run;
  const A = (P.walk * GAIT.walk.A + P.run * GAIT.run.A) / ws;
  const L = (P.walk * GAIT.walk.L + P.run * GAIT.run.L) / ws;
  const lift = (P.walk * GAIT.walk.lift + P.run * GAIT.run.lift) / ws;
  const u1 = phase, u2 = phase + Math.PI;
  return {
    g, A,
    f1: [A * Math.sin(u1), -L + lift * Math.max(0, Math.cos(u1))],
    f2: [A * Math.sin(u2), -L + lift * Math.max(0, Math.cos(u2))],
    sw: [A * 0.6 * Math.sin(u2), 0.6 * lift * Math.cos(u2)],
  };
}

// Solve local skeleton (pelvis at origin, facing +x, y up). Returns lift needed so lowest foot touches ground.
function solveLocal(P, phase) {
  let f1x = P.f1x, f1y = P.f1y, f2x = P.f2x, f2y = P.f2y;
  let h2x = P.h2x, h2y = P.h2y, bob = 0;
  const G = gaitFeet(P, phase);
  if (G) {
    f1x = lerp(f1x, G.f1[0], G.g); f1y = lerp(f1y, G.f1[1], G.g);
    f2x = lerp(f2x, G.f2[0], G.g); f2y = lerp(f2y, G.f2[1], G.g);
    const rw = clamp(P.run, 0, 1);
    h2x = lerp(h2x, 6 + 30 * Math.sin(phase + Math.PI) , rw * 0.9);
    h2y = lerp(h2y, 8 + 14 * Math.cos(phase + Math.PI), rw * 0.9);
    bob = (4 * Math.abs(Math.cos(phase))) * G.g;
  }
  const lift = Math.max(-f1y, -f2y) + bob;
  const tr = P.tor * D2R;
  const dirT = [Math.sin(tr), Math.cos(tr)];
  const N = [dirT[0] * BODY.torso, dirT[1] * BODY.torso];
  const S = [dirT[0] * BODY.shoulder, dirT[1] * BODY.shoulder];
  const hr = (P.tor + P.hd) * D2R;
  const Hd = [N[0] + Math.sin(hr) * BODY.neck, N[1] + Math.cos(hr) * BODY.neck];
  const sr = P.sab * D2R, bd = [Math.cos(sr), Math.sin(sr)];
  // hands
  const hand1 = [P.h1x, P.h1y];
  const grip = [hand1[0] - bd[0] * 12, hand1[1] - bd[1] * 12];
  const hand2t = [lerp(h2x, grip[0], P.two), lerp(h2y, grip[1], P.two)];
  const a1 = ik2(S[0], S[1], hand1[0], hand1[1], BODY.upper, BODY.fore);
  const a2 = ik2(S[0], S[1], hand2t[0], hand2t[1], BODY.upper, BODY.fore);
  const l1 = ik2(0, 0, f1x, f1y, BODY.thigh, BODY.shin);
  const l2 = ik2(0, 0, f2x, f2y, BODY.thigh, BODY.shin);
  const hilt0 = [a1.end[0] - bd[0] * 6, a1.end[1] - bd[1] * 6];
  const hilt1 = [a1.end[0] + bd[0] * BODY.hilt, a1.end[1] + bd[1] * BODY.hilt];
  return {
    lift, N, S, head: Hd, hr,
    e1: pickElbow(a1), hand1: a1.end, e2: pickElbow(a2), hand2: a2.end,
    k1: pickKnee(l1), foot1: l1.end, k2: pickKnee(l2), foot2: l2.end,
    hilt0, hilt1, bd,
  };
}

// ---------------------------------------------------------------- tracks
const CH = ['x', 'z', 'h', 'rot', 'on'];
class Track {
  constructor(name, color) { this.name = name; this.keys = []; this.color = color; this.deathT = Infinity; }
  k(t, pose, o) {
    o = o || {};
    let at = this.keys.length;
    while (at > 0 && this.keys[at - 1].t > t + 1e-6) at--;
    const prev = this.keys[at - 1];
    const key = {
      t, pose: resolvePose(pose, o.p), poseName: typeof pose === 'string' ? pose : '',
      x: o.x !== undefined ? o.x : (prev ? prev.x : 0),
      z: o.z !== undefined ? o.z : (prev ? prev.z : 0.5),
      h: o.h !== undefined ? o.h : (prev ? prev.h : 0),
      rot: o.rot !== undefined ? o.rot : (prev ? prev.rot : 0),
      on: o.on !== undefined ? o.on : (prev ? prev.on : 0),
      held: o.held !== undefined ? o.held : (prev ? prev.held : 1),
      ease: o.ease || 'io', easeX: o.ex, easeH: o.eh, easeR: o.er, easeP: o.ep,
      lock: o.lock || null,
    };
    if (prev && Math.abs(t - prev.t) < 1e-6) { this.keys[at - 1] = key; } else this.keys.splice(at, 0, key);
    return key;
  }
  idx(s) {
    const K = this.keys;
    if (s <= K[0].t) return 0;
    let lo = 0, hi = K.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (K[m].t <= s) lo = m; else hi = m; }
    return lo;
  }
  // numeric channels + pose at time s
  eval(s) {
    const K = this.keys, i = this.idx(s);
    const a = K[i], b = K[Math.min(i + 1, K.length - 1)];
    if (s <= a.t || a === b) return { x: a.x, z: a.z, h: a.h, rot: a.rot, on: a.on, held: a.held, pose: a.pose };
    let u = clamp((s - a.t) / (b.t - a.t), 0, 1);
    const eg = EASE[b.ease](u);
    const ex = b.easeX ? EASE[b.easeX](u) : eg;
    const eh = b.easeH ? EASE[b.easeH](u) : eg;
    const er = b.easeR ? EASE[b.easeR](u) : eg;
    const ep = b.easeP ? EASE[b.easeP](u) : eg;
    const pose = {};
    for (const f of FIELDS) pose[f] = lerp(a.pose[f], b.pose[f], ep);
    return { x: lerp(a.x, b.x, ex), z: lerp(a.z, b.z, ex), h: lerp(a.h, b.h, eh), rot: lerp(a.rot, b.rot, er), on: lerp(a.on, b.on, eg), held: a.held, pose };
  }
}

// ---------------------------------------------------------------- world mapping
const groundY = z => -(z - 0.5) * 120;
const depthScale = z => 1 + (z - 0.5) * 0.32;

// local (pelvis-origin) -> world, given state
function toWorld(st, lp) {
  let x = lp[0], y = lp[1];
  if (st.rot) { const th = -st.rot * D2R, c = Math.cos(th), s = Math.sin(th); const nx = x * c - y * s, ny = x * s + y * c; x = nx; y = ny; }
  y += st.lift + st.h;
  return [st.x + st.face * x * st.sc, st.gy + y * st.sc];
}

// ---------------------------------------------------------------- time warp
class Warp {
  constructor() { this.slows = []; this.holds = []; this.tbl = null; }
  slow(t0, t1, v, ramp) { this.slows.push({ t0, t1, v, ramp: ramp === undefined ? 0.12 : ramp }); }
  hold(t, dur) { this.holds.push({ t, dur }); }
  speed(s) {
    let v = 1;
    for (const w of this.slows) {
      const inK = smooth(w.t0 - w.ramp, w.t0, s), outK = 1 - smooth(w.t1, w.t1 + w.ramp, s);
      const k = Math.min(inK, outK);
      if (k > 0) v = Math.min(v, lerp(1, w.v, k));
    }
    return v;
  }
  build(total) {
    const ds = 1 / 960, o = [0], s = [0];
    const holds = this.holds.slice().sort((a, b) => a.t - b.t);
    let hi = 0, ot = 0;
    for (let st = 0; st < total; st += ds) {
      while (hi < holds.length && holds[hi].t <= st) { ot += holds[hi].dur; o.push(ot); s.push(st); hi++; }
      ot += ds / this.speed(st + ds / 2);
      o.push(ot); s.push(st + ds);
    }
    this.o = o; this.s = s; this.dur = ot;
  }
  s2o(t) { // story -> output (first occurrence)
    const S = this.s; let lo = 0, hi = S.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (S[m] < t) lo = m; else hi = m; }
    return this.o[hi];
  }
  o2s(ot) {
    const O = this.o, S = this.s;
    if (ot <= 0) return 0;
    if (ot >= O[O.length - 1]) return S[S.length - 1];
    let lo = 0, hi = O.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (O[m] <= ot) lo = m; else hi = m; }
    const d = O[hi] - O[lo];
    return d < 1e-9 ? S[lo] : lerp(S[lo], S[hi], (ot - O[lo]) / d);
  }
}

root.CORE = { D2R, clamp, lerp, smooth, EASE, rng, hash, vnoise, BODY, FIELDS, BASE, POSE, defPose, resolvePose, ik2, solveLocal, Track, groundY, depthScale, toWorld, Warp, GAIT };
})(typeof window !== 'undefined' ? window : globalThis);

// story.js — ASHFALL choreography (story time, seconds). Green vs Blue vs Yellow; Yellow beats both.
(function () {
'use strict';
const { F, cam, ev, txt, warp } = SIM;
const { G, B, Y } = F;
const C = CORE;
const SC = SIM.colors;
SIM.total = 62;
SIM.wind = s => 1 + 0.45 * Math.sin(s * 0.55) + (s > 52 ? 0.3 : 0);
SIM.fades = [
  { t0: 0, t1: 1.4, from: 1, to: 0 },
  { t0: 59.2, t1: 61.8, from: 0, to: 1 },
];
SIM.setpieces = [{ x: 560, z: 0.3, w: 70, h: 250, topple: 17.95, dir: 1 }, { x: -760, z: 0.2, w: 60, h: 190, col: '#55504a' }];

// ================================================================= helpers
const SGN = v => (v >= 0 ? 1 : -1);
function boot(f, x, z, pose) { F[f].k(0, pose || 'idle', { x, z, on: 0 }); }
// ignite: hilt up -> blade extends (on 0->1)
function ignite(f, t, big) {
  F[f].k(t, 'draw', { on: 0 });
  F[f].k(t + 0.17, 'draw', { on: 1, ease: 'out' });
  ev(t + 0.02, 'ignite', { f, big: big || 1, shk: 3 * (big || 1) });
  ev(t + 0.02, 'sfx', { name: 'ignite', f, big: big || 1 });
}

// ================================================================= ACT 0 — title (0 - 4.2)
boot('G', -470, 0.5, 'idle'); boot('B', 470, 0.5, 'idle'); boot('Y', 0, 0.78, 'idle');
G.k(2.4, 'idleLook', { x: -470 }); B.k(2.4, 'idleLook', { x: 470 }); Y.k(3.4, 'idleLook', { x: 0 });
cam(0, { x: 0, y: 112, zoom: 0.58, tau: 0.6 });
cam(4.0, { x: 0, y: 100, zoom: 0.78, tau: 0.6 });
txt(0.9, 3.9, { kind: 'title', text: 'ASHFALL', sub: 'GREEN VS BLUE VS YELLOW', fi: 0.7, fo: 0.6 });
ev(0.2, 'embers', { x: -500, y: -20, w: 900, n: 28, dur: 6 });
ev(0.2, 'cue', { name: 'title' });

// ================================================================= ACT 1 — ignition close-ups
// GREEN
const tg = 4.2;
G.k(tg, 'idleLook', { x: -470 });
G.k(tg + 0.5, 'draw', { x: -470, on: 0, ease: 'out' });
ignite('G', tg + 0.62);
G.k(tg + 1.35, 'stance', { x: -470, on: 1, ease: 'out' });
cam(tg, { x: -440, y: 118, zoom: 2.3, cut: true, tau: 0.3 });
cam(tg + 1.7, { x: -420, y: 118, zoom: 2.5, tau: 0.3 });
txt(tg + 0.2, tg + 1.65, { kind: 'name', who: 'G', sub: 'THE RAGE' });
// BLUE
const tb = 5.95;
B.k(tb, 'idleLook', { x: 470 });
B.k(tb + 0.5, 'draw', { x: 470, on: 0, ease: 'out' });
ignite('B', tb + 0.62);
B.k(tb + 1.35, 'stance', { x: 470, on: 1, ease: 'out' });
cam(tb, { x: 440, y: 118, zoom: 2.3, cut: true, tau: 0.3 });
cam(tb + 1.7, { x: 420, y: 118, zoom: 2.5, tau: 0.3 });
txt(tb + 0.2, tb + 1.65, { kind: 'name', who: 'B', sub: 'THE DISCIPLINE' });
// YELLOW
const ty = 7.7;
SIM.fix('Y', 7.6, 10.2, 1);
Y.k(ty, 'idleLook', { x: 0 });
Y.k(ty + 0.7, 'draw', { x: 0, on: 0, ease: 'out' });
ignite('Y', ty + 0.84, 1.6);
Y.k(ty + 1.7, 'stance', { x: 0, on: 1, ease: 'out' });
cam(ty, { x: 40, y: 84, zoom: 2.15, cut: true, tau: 0.3 });
cam(ty + 1.9, { x: 20, y: 86, zoom: 2.4, tau: 0.35 });
txt(ty + 0.3, ty + 1.9, { kind: 'name', who: 'Y', sub: 'THE INSTINCT' });
ev(ty + 0.84, 'flash', { rgb: '255,236,140', amp: 0.55, dur: 0.35 });

// standoff wide shot
const ts = 9.7;
cam(ts, { x: 0, y: 96, zoom: 0.8, cut: true, tau: 0.5 });
cam(10.9, { x: 0, y: 100, zoom: 0.95, tau: 0.5 });
for (const f of ['G', 'B']) F[f].k(ts, 'stance', {});
Y.k(ts, 'stance', {});
G.k(10.8, 'stanceB', { x: -470 }); B.k(10.8, 'stanceB', { x: 470 }); Y.k(10.8, 'stanceB', { x: 0 });
txt(10.0, 11.6, { kind: 'vs', text: '1  VS  1  VS  1', fi: 0.2, fo: 0.3 });
ev(9.7, 'cue', { name: 'standoff' });
ev(10.7, 'cue', { name: 'go' });


// ================================================================= exchange helper (blades are locked at the contact point)
const KIND = {
  hi:  { wa: 'windHi',  sa: 'strikeHi',  da: 'blockHi',  dp: 'stanceB',   la: { cy: 155, ang: 60 },  ld: { cy: 155, ang: 86 } },
  lo:  { wa: 'windLow', sa: 'strikeLow', da: 'blockLow', dp: 'stanceLow', la: { cy: 48,  ang: -34 }, ld: { cy: 48,  ang: -60 } },
  mid: { wa: 'coil',    sa: 'thrust',    da: 'blockMid', dp: 'stanceB',   la: { cy: 108, ang: 24 },  ld: { cy: 108, ang: 52 } },
  up:  { wa: 'windUp',  sa: 'strikeUp',  da: 'blockHi',  dp: 'stance',    la: { cy: 128, ang: 40 },  ld: { cy: 128, ang: 108 } },
};
function exch(t, a, d, kind, xa, xd, o) {
  o = o || {};
  const K = KIND[kind], dir = SGN(xd - xa), pwr = o.pwr || 1;
  const lk = (w, L) => Object.assign({ with: w }, L, o.cx !== undefined ? { cx: o.cx } : {});
  F[a].k(t - 0.2, K.wa, { x: xa - dir * (o.pre || 34), z: o.z, on: 1, ease: 'out' });
  F[d].k(t - 0.2, K.dp, { x: xd + dir * (o.dpre || 14), z: o.z, on: 1, ease: 'out' });
  F[a].k(t, K.sa, { x: xa, z: o.z, ease: 'inq', ex: 'out', lock: lk(d, K.la) });
  F[d].k(t, K.da, { x: xd, z: o.z, ease: 'snap', lock: lk(a, K.ld) });
  ev(t, 'clash', { a, b: d, pwr, shk: 3.2 * pwr });
  if (pwr >= 2) { warp.hold(t, 0.05); }
  if (o.dust) ev(t, 'dust', { x: (xa + xd) / 2, z: 0.5, n: 7, pwr: 0.6 });
}
// sustained blade lock: trickle of sparks between t0..t1
function sparkle(t0, t1, a, b, every) {
  for (let t = t0; t < t1; t += every || 0.09) ev(t, 'clash', { a, b, pwr: 0.45, shk: 0.8 });
}

// ================================================================= ACT 2 — green vs blue duel (10.8 - 15.7)
G.k(10.8, 'stanceB', { x: -470, on: 1 }); B.k(10.8, 'stanceB', { x: 470, on: 1 });
G.k(11.0, 'runFwd', { x: -445, ease: 'in' }); B.k(11.0, 'runFwd', { x: 445, ease: 'in' });
// run in; exch() supplies the windup at 11.7 so stop slightly short
exch(11.9, 'G', 'B', 'hi', -85, 75, { pwr: 2, dust: true });
G.k(11.7, 'windHi', { x: -125, on: 1, ease: 'out', ex: 'lin' }); // overrides the pre key with the run distance
B.k(11.7, 'stanceB', { x: 120, on: 1, ease: 'out', ex: 'lin' });
exch(12.35, 'B', 'G', 'lo', 55, -105);
exch(12.8, 'G', 'B', 'hi', -75, 85);
exch(13.25, 'B', 'G', 'mid', 45, -115);
exch(13.7, 'G', 'B', 'up', -70, 90, { pwr: 1.5 });
// Blue kicks Green in the gut
B.k(13.95, 'coil', { x: 62, ease: 'out' });
B.k(14.22, 'kickF', { x: 0, ease: 'in', ex: 'out' });
G.k(13.95, 'stanceB', { x: -88, ease: 'out' });
G.k(14.22, 'stanceB', { x: -88, ease: 'lin' });
G.k(14.3, 'hurt', { x: -96, ease: 'snap' });
G.k(14.72, 'crouch', { x: -240, ease: 'out', ex: 'out' });
ev(14.25, 'hit', { f: 'G', at: [14, 46], pwr: 1.4, shk: 7 });
ev(14.25, 'sfx', { name: 'kick' });
warp.hold(14.25, 0.07);
ev(14.3, 'dust', { x: -170, z: 0.5, n: 16, pwr: 1, spread: 1.2 });
B.k(14.62, 'stanceB', { x: -4, ease: 'out' });
// Green's flip over Blue
SIM.fix('G', 14.6, 15.6, 1);
G.k(14.82, 'leap', { x: -232, h: 0, rot: 0, ease: 'out' });
G.k(15.17, 'tuck', { x: -10, h: 190, rot: 180, ease: 'lin', eh: 'out', ex: 'lin', er: 'lin' });
G.k(15.55, 'airStrike', { x: 150, h: 0, rot: 360, ease: 'lin', eh: 'in', ex: 'lin', er: 'lin' });
ev(14.82, 'dust', { x: -230, z: 0.5, n: 9, pwr: 0.8 });
ev(15.55, 'dust', { x: 150, z: 0.5, n: 12, pwr: 1 });
B.k(15.4, 'stanceB', { x: -8 });
// clash 'hi' with G now on the right
G.k(15.75, 'strikeHi', { x: 150, rot: 360, ease: 'inq', lock: { with: 'B', cy: 155, ang: 60 } });
B.k(15.75, 'blockHi', { x: -5, ease: 'snap', lock: { with: 'G', cy: 155, ang: 86 } });
ev(15.75, 'clash', { a: 'G', b: 'B', pwr: 2, shk: 6 });
G.k(16.0, 'strikeHi', { x: 142, lock: { with: 'B', cy: 155, ang: 60 } });
B.k(16.0, 'blockHi', { x: 2, lock: { with: 'G', cy: 155, ang: 86 } });
sparkle(15.8, 16.4, 'G', 'B', 0.07);

// ---- Yellow's leap
Y.k(10.8, 'stanceB', { x: 0, z: 0.78 });
Y.k(11.6, 'walkSab', { x: 250, z: 0.3 });
Y.k(15.3, 'walkSab', { x: 335, z: 0.26 });
Y.k(15.5, 'stanceLow', { x: 335, z: 0.26, ease: 'out' });
Y.k(15.62, 'leap', { x: 330, z: 0.26, h: 0, ease: 'out' });
Y.k(16.02, 'airWind', { x: 190, z: 0.4, h: 185, rot: 0, ease: 'lin', eh: 'out', ex: 'lin' });
Y.k(16.42, 'airStrike', { x: 72, z: 0.5, h: 108, ease: 'lin', eh: 'in', ex: 'lin', lock: { with: 'B', cx: 72, cy: 150, ang: -78, d: 58 } });
SIM.fix('Y', 15.5, 17.0, -1);
// triple lock
G.k(16.42, 'strikeHi', { x: 138, lock: { with: 'B', cx: 72, cy: 150, ang: 60 } });
B.k(16.42, 'blockHi', { x: 6, lock: { with: 'G', cx: 72, cy: 150, ang: 90 } });
ev(16.42, 'clash', { a: 'G', b: 'Y', pwr: 3, shk: 9 });
ev(16.44, 'clash', { a: 'B', b: 'Y', pwr: 3, shk: 9 });
sparkle(16.5, 16.72, 'G', 'B', 0.04);
warp.slow(16.2, 16.72, 0.2, 0.12);

// ================================================================= BOOM (16.72)
const tb2 = 16.72;
G.k(tb2, 'strikeHi', { x: 138, lock: { with: 'B', cx: 72, cy: 150, ang: 60 } });
B.k(tb2, 'blockHi', { x: 6, lock: { with: 'G', cx: 72, cy: 150, ang: 90 } });
Y.k(tb2, 'airStrike', { x: 72, z: 0.5, h: 108, lock: { with: 'B', cx: 72, cy: 150, ang: -78, d: 58 } });
ev(tb2, 'boom', { pos: [72, 150], pwr: 1.2, shk: 26, decay: 0.3, z: 0.5 });
ev(tb2, 'impact', { pos: [72, 150], od: 0.12 });
ev(tb2, 'flash', { amp: 0.5, dur: 0.35 });
ev(tb2, 'cue', { name: 'boom' });
ev(tb2, 'sfx', { name: 'boom' });
ev(tb2, 'rubble', { x: 72, y: 20, n: 26, pwr: 1.2, z: 0.5 });
ev(tb2, 'dust', { x: 72, z: 0.5, n: 26, pwr: 2.2, spread: 3 });
// Green flung right into the column
SIM.fix('G', 16.7, 18.4, -1);
G.k(tb2 + 0.04, 'hurt', { x: 150, ease: 'out' });
G.k(17.0, 'hurt', { x: 330, h: 100, rot: -80, ease: 'out', ex: 'out', eh: 'out' });
G.k(17.5, 'fall', { x: 470, h: 70, rot: -170, ease: 'lin', eh: 'in', ex: 'lin' });
G.k(17.92, 'fall', { x: 552, h: 46, rot: -230, ease: 'lin', eh: 'in', ex: 'lin' });
G.k(18.3, 'fall', { x: 560, h: -58, rot: -270, ease: 'out', eh: 'in', ex: 'out', on: 0 });
ev(17.92, 'hit', { f: 'G', at: [0, 20], pwr: 2, shk: 14 });
ev(17.95, 'rubble', { x: 560, y: 120, n: 26, pwr: 1.1, z: 0.3, ang0: 1.4, spreadA: 1.8, dirx: -1 });
ev(17.95, 'dust', { x: 560, z: 0.3, n: 22, pwr: 1.6 });
ev(18.9, 'dust', { x: 640, z: 0.3, n: 18, pwr: 2 });   // column lands
ev(18.88, 'shake', { shk: 12, decay: 0.3 });
ev(17.92, 'sfx', { name: 'crash' });
ev(18.88, 'sfx', { name: 'crash' });
// Blue backflips away
SIM.fix('B', 16.7, 17.5, 1);
B.k(tb2 + 0.04, 'hurt', { x: 6, ease: 'out' });
B.k(17.05, 'tuck', { x: -150, h: 120, rot: -200, ease: 'lin', eh: 'out', ex: 'lin', er: 'lin' });
B.k(17.5, 'crouch', { x: -330, h: 0, rot: -360, ease: 'lin', eh: 'in', ex: 'out', er: 'lin' });
B.k(17.9, 'stance', { x: -345, rot: -360, ease: 'out', on: 1 });
ev(17.5, 'dust', { x: -330, z: 0.5, n: 14, pwr: 1.2, spread: 1.6 });
// Yellow flips out of it
Y.k(tb2 + 0.04, 'tuck', { x: 72, z: 0.5, h: 130, rot: 0, ease: 'out', eh: 'out' });
Y.k(17.1, 'tuck', { x: 60, z: 0.55, h: 250, rot: -200, ease: 'lin', eh: 'out', ex: 'lin', er: 'lin' });
Y.k(17.58, 'crouch', { x: 20, z: 0.55, h: 0, rot: -360, ease: 'lin', eh: 'in', ex: 'lin', er: 'lin' });
Y.k(17.95, 'stance', { x: 20, z: 0.55, rot: -360, ease: 'out' });
ev(17.58, 'dust', { x: 20, z: 0.55, n: 12, pwr: 1 });
SIM.fix('Y', 17.0, 18.2, -1);

// ---- camera for the duel
cam(10.8, { fol: ['G', 'B'], zm: 1.05, cut: true, tau: 0.35 });
cam(11.8, { fol: ['G', 'B'], zm: 1.2, tau: 0.3 });
cam(15.5, { fol: ['G', 'B'], zm: 0.95, dy: 70, tau: 0.3 });
cam(16.3, { x: 72, y: 128, zoom: 1.9, tau: 0.18 });
cam(16.72, { x: 72, y: 130, zoom: 2.2, tau: 0.2 });
cam(17.0, { x: 80, y: 130, zoom: 0.95, tau: 0.35 });
cam(17.5, { x: 440, y: 110, zoom: 1.2, tau: 0.25 });
cam(18.5, { x: 540, y: 104, zoom: 1.15, tau: 0.3 });
cam(19.6, { fol: ['G', 'B', 'Y'], zm: 0.8, tau: 0.4 });


// ================================================================= ACT 3 — yellow vs blue (18.3 - 22.9)
const EO = C.EASE.out;
G.k(18.3, 'fall', { x: 560, h: -58, rot: -270, on: 0 });
G.k(22.45, 'fall', { x: 560, h: -58, rot: -270, on: 0 });
Y.k(18.4, 'stance', { x: 20, z: 0.5, rot: -360 });
B.k(18.4, 'stance', { x: -335, on: 1 });
B.k(18.55, 'runFwd', { x: -320, ease: 'in' });
exch(19.25, 'B', 'Y', 'hi', -95, 65, { pwr: 1.5, dust: true });
exch(19.7, 'Y', 'B', 'lo', 45, -115);
exch(20.15, 'B', 'Y', 'mid', -80, 80);
exch(20.6, 'Y', 'B', 'up', 35, -125, { pwr: 1.5 });
// Blue's force push
B.k(20.85, 'pushWind', { x: -128, ease: 'out' });
B.k(21.1, 'pushP', { x: -112, ease: 'snap' });
Y.k(20.85, 'stanceB', { x: 40, ease: 'out' });
Y.k(21.1, 'blockMid', { x: 42, ease: 'lin' });
Y.k(21.2, 'blockMid', { x: 70, ease: 'snap' });
Y.k(22.05, 'blockMid', { x: 335, ease: 'out', ex: 'out' });
ev(21.1, 'push', { f: 'B', pwr: 1.3, shk: 10 });
ev(21.1, 'sfx', { name: 'push' });
warp.hold(21.1, 0.05);
for (let t = 21.25; t < 22.0; t += 0.085) { const u = (t - 21.25) / 0.8; ev(t, 'dust', { x: 70 + 265 * EO(clamp01(u)), z: 0.5, n: 4, pwr: 0.55, spread: 0.6 }); }
function clamp01(v) { return Math.max(0, Math.min(1, v)); }
SIM.fix('Y', 20.9, 22.9, -1);
// Blue leaps after him
B.k(21.45, 'crouch', { x: -112, ease: 'out' });
B.k(21.58, 'leap', { x: -105, h: 0, ease: 'out' });
B.k(21.97, 'airWind', { x: 50, h: 190, ease: 'lin', eh: 'out', ex: 'lin' });
B.k(22.38, 'airStrike', { x: 178, h: 36, ease: 'lin', eh: 'in', ex: 'lin', lock: { with: 'Y', cy: 150, ang: 52 } });
Y.k(22.38, 'blockHi', { x: 335, ease: 'snap', lock: { with: 'B', cy: 150, ang: 90 } });
ev(22.38, 'clash', { a: 'B', b: 'Y', pwr: 2, shk: 8 });
B.k(22.55, 'strikeHi', { x: 180, h: 0, ease: 'lin', lock: { with: 'Y', cy: 150, ang: 52 } });
Y.k(22.55, 'blockHi', { x: 335, lock: { with: 'B', cy: 150, ang: 90 } });
ev(22.55, 'dust', { x: 180, z: 0.5, n: 10, pwr: 1 });
sparkle(22.45, 22.85, 'B', 'Y', 0.07);
// Yellow kicks Blue away
Y.k(22.78, 'stanceB', { x: 335, ease: 'out' });
Y.k(22.88, 'kickF', { x: 268, ease: 'in', ex: 'out' });
B.k(22.78, 'blockHi', { x: 180, ease: 'lin' });
B.k(22.9, 'hurt', { x: 176, ease: 'snap' });
B.k(23.32, 'crouch', { x: -40, ease: 'out', ex: 'out' });
ev(22.88, 'hit', { f: 'B', at: [14, 46], pwr: 1.4, shk: 7 });
ev(22.88, 'sfx', { name: 'kick' });
warp.hold(22.88, 0.06);
ev(22.95, 'dust', { x: 100, z: 0.5, n: 14, pwr: 1, spread: 1.2 });

// ---- Green rises from the rubble (22.4 - 23.2)
G.k(22.65, 'kneel', { x: 560, h: 0, rot: -360, ease: 'out', eh: 'out', er: 'out' });
G.k(23.0, 'draw', { x: 560, ease: 'out' });
ignite('G', 23.0, 1.3);
G.k(23.35, 'stance', { x: 560, on: 1, ease: 'out' });
ev(22.55, 'rubble', { x: 560, y: 40, n: 22, pwr: 0.9, z: 0.3 });
ev(22.55, 'dust', { x: 580, z: 0.3, n: 16, pwr: 1.4 });
SIM.fix('G', 22.4, 24.2, -1);
txt(22.6, 23.9, { kind: 'small', text: 'GREEN IS BACK', x: 640, y: 560, size: 26, sp: 12, color: '#f2eee6' });

// ================================================================= ACT 4 — three-way melee (23.4 - 30.4)
// Yellow presses Blue while Green charges in
Y.k(23.0, 'runFwd', { x: 262, ease: 'out' });
Y.k(23.4, 'windHi', { x: 144, ease: 'out', ex: 'lin' });
B.k(23.4, 'stanceB', { x: -64, ease: 'out' });
exch(23.62, 'Y', 'B', 'hi', 110, -50, { pwr: 1.5 });
exch(24.05, 'B', 'Y', 'lo', -70, 90);
G.k(23.5, 'runFwd', { x: 545, ease: 'in' });
G.k(24.55, 'runFwd', { x: 250, ease: 'lin' });
// Green stabs at Yellow's back; Blue lunges from the front -> Yellow flips out of the sandwich
Y.k(24.45, 'stanceB', { x: 90, ease: 'out' });
B.k(24.45, 'stanceB', { x: -70, ease: 'out' });
Y.k(24.6, 'crouch', { x: 90 });
Y.k(24.72, 'leap', { x: 90, h: 0, ease: 'out' });
Y.k(25.0, 'tuck', { x: 90, h: 175, rot: -560, ease: 'lin', eh: 'out', er: 'lin' });
Y.k(25.38, 'crouch', { x: 90, z: 0.85, h: 0, rot: -720, ease: 'lin', eh: 'in', er: 'lin' });
Y.k(25.65, 'stanceB', { x: 70, z: 0.85, rot: -720, ease: 'out' });
Y.k(26.0, 'walkSab', { x: -150, z: 0.86, rot: -720, ease: 'io' });
Y.k(26.9, 'walkSab', { x: -230, z: 0.86, rot: -720 });
SIM.fix('Y', 24.5, 25.5, 1);
// the two blades meet exactly where Yellow was standing
exch(25.0, 'G', 'B', 'hi', 170, 10, { cx: 90, pwr: 2.5 });
sparkle(25.1, 25.5, 'G', 'B', 0.07);
ev(25.38, 'dust', { x: 90, z: 0.85, n: 12, pwr: 1 });
// green vs blue exchanges, yellow watches from the front
exch(25.8, 'B', 'G', 'lo', 25, 185);
exch(26.25, 'G', 'B', 'hi', 160, 0);
exch(26.7, 'B', 'G', 'mid', 38, 198);
exch(27.15, 'G', 'B', 'up', 150, -12, { pwr: 1.5 });
B.k(27.3, 'hurt', { x: -40, ease: 'snap' });
B.k(27.75, 'crouch', { x: -175, ease: 'out', ex: 'out' });
B.k(28.3, 'stance', { x: -178, ease: 'out' });
ev(27.3, 'dust', { x: -90, z: 0.5, n: 12, pwr: 1, spread: 1.2 });
Y.k(27.2, 'stanceB', { x: -230, z: 0.86 });
Y.k(27.55, 'runFwd', { x: -150, z: 0.86, ease: 'in' });
Y.k(27.92, 'windHi', { x: -45, z: 0.5, ease: 'out' });
SIM.fix('Y', 27.3, 28.2, 1);
G.k(27.5, 'stanceB', { x: 160, ease: 'out' });
G.k(27.92, 'stanceB', { x: 160 });
exch(28.15, 'Y', 'G', 'hi', 0, 160, { pwr: 2 });
exch(28.58, 'G', 'Y', 'lo', 168, 8);
// Green's last leap
G.k(28.78, 'crouch', { x: 170 });
G.k(28.9, 'leap', { x: 168, h: 0, ease: 'out' });
G.k(29.2, 'airWind', { x: 110, h: 140, ease: 'lin', eh: 'out', ex: 'lin' });
G.k(29.5, 'airStrike', { x: 62, h: 62, ease: 'lin', eh: 'in', ex: 'lin', lock: { with: 'Y', cy: 140, ang: 56 } });
Y.k(28.95, 'stanceB', { x: 10, ease: 'out' });
Y.k(29.5, 'blockHi', { x: 6, ease: 'snap', lock: { with: 'G', cy: 140, ang: 90 } });
ev(29.5, 'clash', { a: 'G', b: 'Y', pwr: 2.5, shk: 9 });
warp.hold(29.5, 0.06);
// Yellow sidesteps and cuts Green down
Y.k(29.64, 'spin', { x: -34, ease: 'out' });
G.k(29.72, 'hurtB', { x: 48, h: 0, rot: 0, ease: 'in', eh: 'in', ex: 'out' });
Y.k(29.9, 'strikeUp', { x: 128, ease: 'snap' });
ev(29.9, 'slice', { f: 'G', ang: 28, len: 200, shk: 14, pwr: 2 });
ev(29.9, 'impact', { pos: [48, 100], od: 0.12 });
ev(29.9, 'sfx', { name: 'slice' });
ev(29.9, 'flash', { amp: 0.4, dur: 0.25 });
G.k(29.92, 'hurtB', { x: 50, on: 1 });
G.k(30.0, 'hurtB', { x: 52, on: 0 });
G.k(30.5, 'kneelFist', { x: 40, ease: 'out' });
G.k(31.8, 'kneelFist', { x: 40 });
SIM.die('G', 30.1);
Y.k(30.5, 'stanceB', { x: 134, ease: 'out' });
warp.slow(29.78, 30.45, 0.22, 0.1);
SIM.fix('Y', 28.2, 30.3, 1);

// ---- camera (acts 3-4)
cam(18.4, { fol: ['B', 'Y'], zm: 1.0, tau: 0.4 });
cam(19.7, { fol: ['B', 'Y'], zm: 1.2, tau: 0.3 });
cam(21.0, { fol: ['B', 'Y'], zm: 1.0, tau: 0.3 });
cam(21.7, { fol: ['B', 'Y'], zm: 0.85, dy: 60, tau: 0.3 });
cam(22.35, { fol: ['B', 'Y'], zm: 1.1, tau: 0.25 });
cam(22.6, { x: 560, y: 96, zoom: 1.9, cut: true, tau: 0.3 });
cam(23.35, { fol: ['Y', 'B'], zm: 1.0, cut: true, tau: 0.3 });
cam(24.3, { fol: ['Y', 'B', 'G'], zm: 1.0, tau: 0.35 });
cam(24.95, { fol: ['G', 'B'], zm: 1.05, dy: 60, tau: 0.25 });
cam(25.6, { fol: ['G', 'B'], zm: 1.25, tau: 0.3 });
cam(27.4, { fol: ['Y', 'G'], zm: 1.2, tau: 0.35 });
cam(29.0, { fol: ['Y', 'G'], zm: 1.0, dy: 50, tau: 0.25 });
cam(29.7, { x: 56, y: 104, zoom: 1.8, tau: 0.12 });
cam(30.35, { x: 60, y: 100, zoom: 1.5, cut: true, tau: 0.4 });
cam(31.0, { fol: ['Y', 'G', 'B'], zm: 0.95, tau: 0.5 });

// ================================================================= ACT 5 — the final duel, yellow vs blue (30.6 - 43)
const ROT = { G: -360, B: -360, Y: -720 };
function flip(f, t0, t1, t2, x0, x1, x2, h, dir, o) {
  o = o || {};
  const r0 = ROT[f]; ROT[f] = r0 + dir * 360;
  F[f].k(t0, 'leap', { x: x0, h: 0, rot: r0, ease: 'out', z: o.z });
  F[f].k(t1, 'tuck', { x: x1, h, rot: r0 + dir * 180, ease: 'lin', eh: 'out', ex: 'lin', er: 'lin', z: o.z });
  F[f].k(t2, 'crouch', { x: x2, h: 0, rot: r0 + dir * 360, ease: 'lin', eh: 'in', ex: 'lin', er: 'lin', z: o.z });
  ev(t2, 'dust', { x: x2, z: o.z || 0.5, n: 10, pwr: 0.9 });
}
B.k(28.3, 'stance', { x: -178, on: 1 });
B.k(30.8, 'stance', { x: -178 });
B.k(31.0, 'runFwd', { x: -172, ease: 'in' });
Y.k(30.5, 'stanceB', { x: 134 });
// Blue's rage combo
exch(31.55, 'B', 'Y', 'hi', -10, 150, { pwr: 1.5 });
exch(31.95, 'B', 'Y', 'lo', 12, 172);
exch(32.35, 'B', 'Y', 'mid', 32, 192);
exch(32.75, 'B', 'Y', 'up', 56, 216, { pwr: 1.5 });
// Yellow turns it around
exch(33.15, 'Y', 'B', 'hi', 218, 58, { pwr: 1.5 });
exch(33.55, 'Y', 'B', 'lo', 195, 36);
exch(33.95, 'Y', 'B', 'mid', 172, 14, { pwr: 1.5 });
// both leap: aerial clash
B.k(34.2, 'crouch', { x: 12 }); Y.k(34.2, 'crouch', { x: 172 });
B.k(34.3, 'leap', { x: 12, h: 0, ease: 'out' }); Y.k(34.3, 'leap', { x: 170, h: 0, ease: 'out' });
B.k(34.64, 'airStrike', { x: 26, h: 125, ease: 'lin', eh: 'out', ex: 'lin', lock: { with: 'Y', cx: 98, cy: 238, ang: 52, d: 60 } });
Y.k(34.64, 'airStrike', { x: 164, h: 125, ease: 'lin', eh: 'out', ex: 'lin', lock: { with: 'B', cx: 98, cy: 238, ang: 76, d: 60 } });
ev(34.64, 'clash', { a: 'B', b: 'Y', pwr: 2.5, shk: 9 });
warp.hold(34.64, 0.06);
sparkle(34.7, 34.92, 'B', 'Y', 0.055);
// flip apart
{ ROT.B = -360; ROT.Y = -720; }
B.k(34.95, 'tuck', { x: 6, h: 160, rot: -540, ease: 'lin', eh: 'out', ex: 'lin', er: 'lin' });
B.k(35.4, 'crouch', { x: -70, h: 0, rot: -720, ease: 'lin', eh: 'in', ex: 'lin', er: 'lin' });
Y.k(34.95, 'tuck', { x: 176, h: 160, rot: -900, ease: 'lin', eh: 'out', ex: 'lin', er: 'lin' });
Y.k(35.4, 'crouch', { x: 250, h: 0, rot: -1080, ease: 'lin', eh: 'in', ex: 'lin', er: 'lin' });
ROT.B = -720; ROT.Y = -1080;
ev(35.4, 'dust', { x: -70, z: 0.5, n: 10, pwr: 0.9 }); ev(35.4, 'dust', { x: 250, z: 0.5, n: 10, pwr: 0.9 });
SIM.fix('B', 34.3, 35.5, 1); SIM.fix('Y', 34.3, 35.5, -1);
// Blue charges and overpowers: Yellow's saber is knocked away
B.k(35.52, 'runFwd', { x: -60, ease: 'out' });
B.k(35.95, 'windHi', { x: 62, ease: 'lin', ex: 'lin' });
Y.k(35.58, 'stanceB', { x: 250, ease: 'out' });
exch(36.15, 'B', 'Y', 'hi', 96, 252, { pwr: 3 });
Y.k(36.3, 'hurt', { x: 258, held: 0, on: 0, ease: 'snap' });
Y.k(36.7, 'spread', { x: 285, ease: 'out', ex: 'out' });
B.k(36.3, 'strikeHi', { x: 112, ease: 'out' });
ev(36.18, 'sabre', { f: 'Y', tl: 36.9, lx: -250, lz: 0.4, a0: 0.4, tp: 39.0, tc: 39.22, rest: 0.12, spinDir: -1 });
ev(36.3, 'sfx', { name: 'disarm' });
// unarmed evasion
B.k(36.62, 'stanceB', { x: 140, on: 1, ease: 'out' });
B.k(36.78, 'windHi', { x: 128, ease: 'out' });
B.k(36.98, 'strikeHi', { x: 196, ease: 'inq', ex: 'out' });
ev(36.98, 'spark', { f: 'B', pwr: 1.4, shk: 6 }); ev(36.98, 'rubble', { x: 330, y: 8, n: 12, pwr: 0.7, z: 0.5, ang0: 0.5, spreadA: 2 });
Y.k(36.82, 'spread', { x: 290 });
Y.k(37.0, 'crouch', { x: 296, ease: 'out' });
// Yellow cartwheels clear of the blow
Y.k(37.08, 'leap', { x: 296, h: 0, ease: 'out' });
Y.k(37.3, 'tuck', { x: 360, h: 120, rot: -1260, ease: 'lin', eh: 'out', ex: 'lin', er: 'lin' });
Y.k(37.6, 'crouch', { x: 420, h: 0, rot: -1440, ease: 'lin', eh: 'in', ex: 'lin', er: 'lin' });
ROT.Y = -1440;
ev(37.6, 'dust', { x: 420, z: 0.5, n: 10, pwr: 1 });
SIM.fix('Y', 36.9, 37.7, -1);
B.k(37.25, 'stanceB', { x: 205 });
B.k(37.45, 'runFwd', { x: 210, ease: 'in' });
B.k(37.8, 'thrust', { x: 370, ease: 'inq' });
ev(37.8, 'spark', { f: 'B', pwr: 1.2, shk: 5 });
// Yellow vaults over Blue and runs for the saber
Y.k(37.65, 'stanceLow', { x: 420, ease: 'out' });
Y.k(37.78, 'leap', { x: 420, h: 0, ease: 'out' });
Y.k(38.05, 'tuck', { x: 280, h: 190, rot: -1620, ease: 'lin', eh: 'out', ex: 'lin', er: 'lin' });
Y.k(38.38, 'crouch', { x: 110, h: 0, rot: -1800, ease: 'lin', eh: 'in', ex: 'lin', er: 'lin' });
ROT.Y = -1800;
ev(38.38, 'dust', { x: 110, z: 0.5, n: 10, pwr: 1 });
SIM.fix('Y', 37.7, 38.4, -1);
Y.k(38.5, 'runFwd', { x: 105, ease: 'in' });
Y.k(38.95, 'runFwd', { x: -150, ease: 'lin' });
B.k(38.1, 'stanceB', { x: 372, ease: 'out' });
B.k(38.25, 'runFwd', { x: 360, ease: 'in' });
B.k(39.2, 'windHi', { x: -62, ease: 'lin', ex: 'lin' });
// Yellow reaches the saber and calls it
Y.k(39.0, 'pullP', { x: -205, ease: 'out', ex: 'out' });
Y.k(39.22, 'stanceB', { x: -208, held: 1, on: 0, ease: 'snap' });
Y.k(39.4, 'stanceB', { x: -208, on: 1, ease: 'out' });
ev(39.22, 'ignite', { f: 'Y', big: 1.5, shk: 6 });
ev(39.22, 'sfx', { name: 'ignite', f: 'Y', big: 1.5 });
ev(38.98, 'sfx', { name: 'pull' });
ev(39.22, 'flash', { rgb: '255,238,150', amp: 0.2, dur: 0.25 });
warp.slow(38.9, 39.3, 0.35, 0.08);
// the comeback
exch(39.7, 'B', 'Y', 'hi', -62, -214, { pwr: 2.5 });
exch(40.1, 'Y', 'B', 'lo', -198, -44, { pwr: 1.5 });
exch(40.45, 'Y', 'B', 'hi', -160, -2);
exch(40.8, 'Y', 'B', 'mid', -118, 40, { pwr: 1.5 });
exch(41.15, 'Y', 'B', 'up', -70, 88, { pwr: 2 });
exch(41.5, 'Y', 'B', 'hi', -26, 134, { pwr: 3 });
B.k(41.62, 'hurt', { x: 150, ease: 'snap' });
B.k(41.95, 'stanceB', { x: 230, ease: 'out', ex: 'out' });
Y.k(41.62, 'strikeHi', { x: -20 });
Y.k(41.95, 'stanceB', { x: -20, ease: 'out' });
// final: Blue's desperate leap, Yellow meets him in the air
B.k(42.05, 'crouch', { x: 230 });
B.k(42.15, 'leap', { x: 228, h: 0, ease: 'out' });
B.k(42.5, 'airWind', { x: 160, h: 150, ease: 'lin', eh: 'out', ex: 'lin' });
B.k(42.84, 'airStrike', { x: 104, h: 112, ease: 'lin', eh: 'in', ex: 'lin' });
Y.k(42.15, 'crouch', { x: -20 });
Y.k(42.28, 'leap', { x: -20, h: 0, ease: 'out' });
Y.k(42.6, 'airStrike', { x: -8, h: 120, ease: 'out', eh: 'out', ex: 'out' });
Y.k(42.84, 'thrust', { x: -4, h: 108, ease: 'snap', eh: 'lin', ex: 'out' });
Y.k(43.02, 'thrust', { x: 40, h: 96, ease: 'out', eh: 'lin', ex: 'out' });
Y.k(43.4, 'crouch', { x: 168, h: 0, ease: 'lin', eh: 'in', ex: 'out' });
ev(42.86, 'slice', { f: 'B', ang: 40, len: 200, shk: 18, pwr: 2 });
ev(42.86, 'impact', { pos: [104, 200], od: 0.14 });
ev(42.86, 'flash', { amp: 0.5, dur: 0.3 });
ev(42.86, 'sfx', { name: 'slice' });
ev(42.86, 'cue', { name: 'kill2' });
warp.slow(42.6, 43.5, 0.2, 0.15);
B.k(42.9, 'hurtB', { x: 104, h: 112, on: 1 });
B.k(42.98, 'hurtB', { x: 108, h: 104, on: 0 });
B.k(43.4, 'hurtB', { x: 92, h: 20, ease: 'in', eh: 'in' });
B.k(43.75, 'kneelFist', { x: 90, h: 0, ease: 'out', eh: 'out' });
B.k(46, 'kneelFist', { x: 90 });
SIM.die('B', 43.1);
SIM.fix('Y', 41.5, 43.4, 1); SIM.fix('B', 41.5, 43.4, -1);
ev(43.4, 'dust', { x: 90, z: 0.5, n: 12, pwr: 1 });
ev(43.4, 'dust', { x: 168, z: 0.5, n: 12, pwr: 1 });

// ================================================================= ACT 6 — aftermath
Y.k(43.9, 'stanceB', { x: 168, ease: 'out', on: 1 });
Y.k(45.2, 'lowered', { x: 170, ease: 'io', on: 1 });
Y.k(46.0, 'lowered', { x: 174, on: 0, ease: 'out' });
Y.k(47.0, 'idleLook', { x: 178, ease: 'io' });
Y.k(48.0, 'walkP', { x: 230, ease: 'io' });
Y.k(56.5, 'walkP', { x: 760, z: 0.16, ease: 'lin', ex: 'lin' });
ev(43.4, 'embers', { x: -200, y: -20, w: 900, n: 36, dur: 16 });
txt(43.9, 46.4, { kind: 'small', text: 'YELLOW  ×  BLUE', x: 640, y: 560, size: 24, sp: 10, color: '#f2eee6', fi: 0.3, fo: 0.4 });
txt(30.7, 33.0, { kind: 'small', text: 'YELLOW  ×  GREEN', x: 640, y: 560, size: 24, sp: 10, color: '#f2eee6', fi: 0.3, fo: 0.4 });
txt(46.6, 52.6, { kind: 'end', text: 'YELLOW WINS', sub: 'ONE LEFT STANDING', fi: 0.9, fo: 1.0 });
txt(53.8, 58.0, { kind: 'small', text: 'A S H F A L L', x: 640, y: 262, size: 34, sp: 22, color: '#1b1814', fi: 1.0, fo: 1.2 });
SIM.fades = [
  { t0: 0, t1: 1.4, from: 1, to: 0 },
  { t0: 57.6, t1: 59.6, from: 0, to: 1 },
];
SIM.setpieces.push({ x: 640, z: 0.2, w: 54, h: 160, col: '#4b4741' });

// ---- camera (acts 5-6)
cam(31.15, { fol: ['B', 'Y'], zm: 1.15, tau: 0.4 });
cam(33.0, { fol: ['B', 'Y'], zm: 1.25, tau: 0.3 });
cam(34.0, { fol: ['B', 'Y'], zm: 1.0, dy: 70, tau: 0.2 });
cam(35.2, { fol: ['B', 'Y'], zm: 1.05, tau: 0.3 });
cam(36.1, { x: 175, y: 112, zoom: 1.95, cut: true, tau: 0.2 });
cam(36.55, { x: -210, y: 70, zoom: 1.7, cut: true, tau: 0.2 });
cam(37.1, { fol: ['Y', 'B'], zm: 1.1, cut: true, tau: 0.25 });
cam(38.1, { fol: ['Y', 'B'], zm: 0.8, tau: 0.3 });
cam(38.7, { x: -190, y: 105, zoom: 2.3, cut: true, tau: 0.15 });
cam(39.45, { fol: ['Y', 'B'], zm: 1.25, cut: true, tau: 0.25 });
cam(41.4, { fol: ['Y', 'B'], zm: 1.3, tau: 0.25 });
cam(41.95, { fol: ['Y', 'B'], zm: 0.95, dy: 70, tau: 0.3 });
cam(42.45, { x: 60, y: 138, zoom: 1.4, tau: 0.14 });
cam(42.86, { x: 60, y: 150, zoom: 1.8, tau: 0.1 });
cam(43.9, { x: 120, y: 112, zoom: 1.15, tau: 0.5 });
cam(45.5, { x: 140, y: 115, zoom: 1.0, tau: 0.8 });
cam(48.0, { fol: ['Y'], zm: 0.9, dy: 10, tau: 0.8 });
cam(52.0, { x: 420, y: 112, zoom: 0.62, tau: 0.9 });
cam(58.5, { x: 430, y: 112, zoom: 0.52, tau: 0.9 });

SIM.total = 60;
SIM.build();
})();

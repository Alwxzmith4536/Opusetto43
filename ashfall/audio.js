// audio.js — synthesises the whole soundtrack (score + sfx) from the story's event list.
// usage: node audio.js out.wav
const fs = require('fs');
global.window = undefined;
for (const f of ['core.js', 'poses.js', 'sim.js', 'story.js']) require('./' + f);
const C = CORE, SR = 44100, TAU = Math.PI * 2;
const o2 = t => SIM.warp.s2o(t);
const DUR = o2(SIM.total) + 0.1, N = Math.floor(DUR * SR);
const mk = () => new Float32Array(N);
const dry = { L: mk(), R: mk() }, wet = { L: mk(), R: mk() };
const rnd = C.rng(4242);
const clamp = C.clamp, lerp = C.lerp;
const midi = m => 440 * Math.pow(2, (m - 69) / 12);

// ------------------------------------------------------------ helpers
function place(sig, t, o) {
  o = o || {};
  const g = o.g === undefined ? 1 : o.g, pan = clamp(o.pan || 0, -1, 1), send = o.send === undefined ? 0.25 : o.send;
  const gl = g * Math.cos((pan + 1) * Math.PI / 4), gr = g * Math.sin((pan + 1) * Math.PI / 4);
  const s0 = Math.floor(t * SR);
  for (let i = 0; i < sig.length; i++) {
    const k = s0 + i; if (k < 0 || k >= N) continue;
    const v = sig[i];
    dry.L[k] += v * gl; dry.R[k] += v * gr;
    wet.L[k] += v * gl * send; wet.R[k] += v * gr * send;
  }
}
function lp(x, fc, passes) { const a = 1 - Math.exp(-TAU * fc / SR); for (let p = 0; p < (passes || 1); p++) { let y = 0; for (let i = 0; i < x.length; i++) { y += a * (x[i] - y); x[i] = y; } } return x; }
function hp(x, fc) { const a = 1 - Math.exp(-TAU * fc / SR); let y = 0; for (let i = 0; i < x.length; i++) { y += a * (x[i] - y); x[i] -= y; } return x; }
function noise(n) { const x = new Float32Array(n); for (let i = 0; i < n; i++) x[i] = rnd() * 2 - 1; return x; }
function env(x, a, d, curve) { // attack a seconds, exponential decay with time-constant d
  for (let i = 0; i < x.length; i++) { const t = i / SR; const e = (t < a ? t / a : 1) * Math.exp(-Math.max(0, t - a) / d); x[i] *= e; } return x;
}
function svfSweep(x, f0, f1, q, mode) { // band/low pass with exponential cutoff sweep
  let lo = 0, bp = 0; const n = x.length;
  for (let i = 0; i < n; i++) {
    const fc = f0 * Math.pow(f1 / f0, i / n), f = 2 * Math.sin(Math.PI * Math.min(fc, 9000) / SR);
    lo += f * bp; const hi = x[i] - lo - bp / q; bp += f * hi; x[i] = mode === 'lp' ? lo : bp;
  }
  return x;
}
const saw = ph => 2 * (ph - Math.floor(ph)) - 1;
const tri = ph => 4 * Math.abs(ph - Math.floor(ph + 0.5)) - 1;

// ------------------------------------------------------------ instruments
function taiko(pw) {
  const n = Math.floor(0.7 * SR), x = new Float32Array(n); let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR, f = 48 + 62 * Math.exp(-t / 0.045); ph += f / SR; x[i] = Math.sin(TAU * ph) * Math.exp(-t / 0.2) * 0.9; }
  const nz = lp(noise(n), 700, 2); for (let i = 0; i < n; i++) x[i] += nz[i] * Math.exp(-i / SR / 0.05) * 0.6;
  for (let i = 0; i < x.length; i++) x[i] *= pw; return x;
}
function rim(pw) { const n = Math.floor(0.2 * SR); const x = hp(noise(n), 1800); svfSweep(x, 3200, 2600, 3, 'bp'); env(x, 0.001, 0.035); for (let i = 0; i < n; i++) x[i] *= 2.2 * pw; return x; }
function hat(pw) { const n = Math.floor(0.08 * SR); const x = hp(noise(n), 6000); env(x, 0.001, 0.015); for (let i = 0; i < n; i++) x[i] *= pw; return x; }
function snare(pw) { const n = Math.floor(0.45 * SR); const x = noise(n); svfSweep(x, 1800, 900, 1.2, 'bp'); env(x, 0.001, 0.09); const b = new Float32Array(n); let ph = 0; for (let i = 0; i < n; i++) { const t = i / SR; ph += (180 - 70 * Math.min(t / 0.05, 1)) / SR; b[i] = Math.sin(TAU * ph) * Math.exp(-t / 0.07) * 0.5 + x[i] * 1.2; } for (let i = 0; i < n; i++) b[i] *= pw; return b; }
function brass(freqs, dur, bright) {
  const n = Math.floor(dur * SR), x = new Float32Array(n);
  for (const f of freqs) for (const det of [-0.006, 0, 0.006]) { let ph = rnd(); const fr = f * (1 + det); for (let i = 0; i < n; i++) { ph += fr / SR; x[i] += saw(ph); } }
  // swell filter: opens quickly then closes
  let y = 0; for (let i = 0; i < n; i++) { const t = i / SR, fc = (400 + (bright || 1800) * Math.exp(-t / 0.35) + 300) * 1, a = 1 - Math.exp(-TAU * fc / SR); y += a * (x[i] - y); const e = Math.min(t / 0.03, 1) * Math.exp(-t / (dur * 0.5)); x[i] = y * e / (freqs.length * 2.4); }
  return x;
}
function strings(freq, dur, g) {
  const n = Math.floor(dur * SR), x = new Float32Array(n);
  for (const det of [-0.004, 0.0, 0.005]) { let ph = rnd(); for (let i = 0; i < n; i++) { const t = i / SR; ph += freq * (1 + det) * (1 + 0.003 * Math.sin(TAU * 5.2 * t)) / SR; x[i] += saw(ph); } }
  lp(x, 1500 + freq, 2); for (let i = 0; i < n; i++) { const t = i / SR; x[i] *= Math.min(t / 0.3, 1) * Math.min((dur - t) / 0.4, 1) * (g || 0.2) / 3; } return x;
}
function bassNote(freq, dur, g) {
  const n = Math.floor(dur * SR), x = new Float32Array(n); let ph = 0, ph2 = 0;
  for (let i = 0; i < n; i++) { ph += freq / SR; ph2 += freq * 0.5 / SR; x[i] = saw(ph) * 0.6 + Math.sin(TAU * ph2) * 0.7; }
  lp(x, 380, 2); for (let i = 0; i < n; i++) { const t = i / SR; x[i] *= Math.min(t / 0.01, 1) * Math.exp(-t / (dur * 0.6)) * (g || 0.5); } return x;
}
function pad(freqs, dur, g, att, rel) {
  const n = Math.floor(dur * SR), x = new Float32Array(n);
  for (const f of freqs) for (const det of [-0.0035, 0.004]) { let ph = rnd(); for (let i = 0; i < n; i++) { ph += f * (1 + det) / SR; x[i] += saw(ph) * 0.5 + Math.sin(TAU * ph) * 0.5; } }
  lp(x, 900, 2); const k = (g || 0.2) / (freqs.length * 2);
  for (let i = 0; i < n; i++) { const t = i / SR; x[i] *= Math.min(t / att, 1) * Math.min((dur - t) / rel, 1) * k; } return x;
}
function choir(freqs, dur, g, att) {
  const n = Math.floor(dur * SR), x = new Float32Array(n);
  const form = [[1, 1.0], [2, 0.6], [3, 0.55], [4, 0.35], [5, 0.28], [6, 0.12], [7, 0.1]];
  for (const f of freqs) for (const det of [-0.004, 0.0, 0.004]) { let ph = rnd(); for (let i = 0; i < n; i++) { const t = i / SR; ph += f * (1 + det) * (1 + 0.004 * Math.sin(TAU * 5.4 * t + det * 300)) / SR; let v = 0; for (const [h, a] of form) v += Math.sin(TAU * ph * h) * a; x[i] += v; } }
  const k = (g || 0.2) / (freqs.length * 3 * 2);
  for (let i = 0; i < n; i++) { const t = i / SR; x[i] *= Math.min(t / (att || 1.2), 1) * Math.min((dur - t) / 1.4, 1) * k; } return x;
}
function lead(freq, dur, g) {
  const n = Math.floor(dur * SR), x = new Float32Array(n); let ph = 0;
  const br = noise(n); lp(br, 2400, 1);
  for (let i = 0; i < n; i++) { const t = i / SR; const vib = 1 + 0.006 * Math.sin(TAU * 5 * t) * Math.min(t / 0.5, 1); ph += freq * vib / SR; x[i] = (tri(ph) * 0.6 + Math.sin(TAU * ph * 2) * 0.12 + br[i] * 0.08) * Math.min(t / 0.18, 1) * Math.min((dur - t) / 0.35, 1) * (g || 0.2); }
  return x;
}
function riser(dur, f0, f1, g) {
  const n = Math.floor(dur * SR), x = noise(n); svfSweep(x, f0, f1, 2.5, 'bp');
  for (let i = 0; i < n; i++) { const u = i / n; x[i] *= u * u * (g || 0.5); } return x;
}
function revSwell(dur, g) { const n = Math.floor(dur * SR), x = hp(noise(n), 600); lp(x, 5000, 1); for (let i = 0; i < n; i++) { const u = i / n; x[i] *= Math.pow(u, 2.5) * (g || 0.4); } return x; }

// ------------------------------------------------------------ sfx
function sub(dur, f0, f1, g, tc) { const n = Math.floor(dur * SR), x = new Float32Array(n); let ph = 0; for (let i = 0; i < n; i++) { const t = i / SR; ph += (f1 + (f0 - f1) * Math.exp(-t / (tc || dur * 0.3))) / SR; x[i] = Math.sin(TAU * ph) * Math.exp(-t / (dur * 0.38)) * g; } return x; }
function clashSfx(pw) {
  const n = Math.floor((0.35 + 0.6 * Math.min(pw, 3) / 3) * SR), x = new Float32Array(n);
  const f0 = 900 + rnd() * 500, parts = [[1, 1], [2.76, 0.6], [5.4, 0.4], [8.9, 0.22]];
  for (const [r, a] of parts) { let ph = rnd(); const dec = (0.09 + 0.14 * pw) / (1 + r * 0.25); for (let i = 0; i < n; i++) { ph += f0 * r / SR; x[i] += Math.sin(TAU * ph) * a * Math.exp(-i / SR / dec) * 0.18; } }
  const c = hp(noise(n), 1500); for (let i = 0; i < n; i++) x[i] += c[i] * Math.exp(-i / SR / 0.025) * 0.9;
  const b = lp(noise(n), 3200, 1); for (let i = 0; i < n; i++) x[i] += b[i] * Math.exp(-i / SR / 0.11) * 0.45;
  const th = sub(0.25, 160, 70, 0.55 * Math.min(pw, 2.5) / 2, 0.04); for (let i = 0; i < th.length && i < n; i++) x[i] += th[i];
  const g = 0.55 + 0.3 * Math.min(pw, 3); for (let i = 0; i < n; i++) x[i] *= g; return x;
}
function crackle(pw) { const n = Math.floor(0.12 * SR), x = hp(noise(n), 2500); env(x, 0.001, 0.02); for (let i = 0; i < n; i++) x[i] *= 0.5 * pw; return x; }
function whoosh(dur, f0, f1, g) { const n = Math.floor(dur * SR), x = noise(n); svfSweep(x, f0, f1, 1.6, 'bp'); for (let i = 0; i < n; i++) { const u = i / n; x[i] *= Math.pow(Math.sin(Math.PI * u), 1.6) * g; } return x; }
function boomSfx() {
  const n = Math.floor(3.2 * SR), x = new Float32Array(n);
  const s = sub(3.0, 95, 26, 1.1, 0.5); for (let i = 0; i < s.length; i++) x[i] += s[i];
  const nz = lp(noise(n), 900, 2); for (let i = 0; i < n; i++) x[i] += nz[i] * Math.exp(-i / SR / 0.7) * 1.4;
  const c = hp(noise(n), 1200); for (let i = 0; i < n; i++) x[i] += c[i] * Math.exp(-i / SR / 0.09) * 0.9;
  const rb = lp(noise(n), 400, 1); for (let i = 0; i < n; i++) x[i] += rb[i] * Math.exp(-i / SR / 1.3) * 0.6;
  return x;
}
function crashSfx() { const n = Math.floor(1.8 * SR), x = new Float32Array(n); const nz = lp(noise(n), 1800, 1); for (let i = 0; i < n; i++) x[i] += nz[i] * Math.exp(-i / SR / 0.3) * 0.9; const s = sub(0.8, 80, 34, 0.9, 0.12); for (let i = 0; i < s.length; i++) x[i] += s[i]; for (let k = 0; k < 40; k++) { const t0 = Math.floor((0.1 + rnd() * 1.4) * SR), cl = hp(noise(900), 800); for (let i = 0; i < 900 && t0 + i < n; i++) x[t0 + i] += cl[i] * Math.exp(-i / SR / 0.012) * 0.28 * Math.exp(-t0 / SR / 0.8); } return x; }
function igniteSfx(f0, big) {
  const n = Math.floor(0.9 * SR), x = new Float32Array(n); let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR, f = f0 * (0.4 + 0.6 * Math.min(t / 0.22, 1)); ph += f / SR; const a = Math.min(t / 0.05, 1) * Math.exp(-Math.max(0, t - 0.25) / 0.5); x[i] = (Math.sin(TAU * ph) + 0.5 * Math.sin(TAU * ph * 2) + 0.3 * saw(ph * 3)) * a * 0.22; }
  const sn = hp(noise(n), 2000); for (let i = 0; i < n; i++) x[i] += sn[i] * Math.exp(-i / SR / 0.05) * 0.8;
  const w = whoosh(0.3, 400, 3500, 0.6); for (let i = 0; i < w.length; i++) x[i] += w[i];
  const s = sub(0.8, 120 * big, 45, 0.5 * big, 0.1); for (let i = 0; i < s.length; i++) x[i] += s[i];
  return x;
}
function sliceSfx() {
  const n = Math.floor(1.6 * SR), x = new Float32Array(n);
  const c = hp(noise(n), 3000); for (let i = 0; i < n; i++) x[i] += c[i] * Math.exp(-i / SR / 0.06) * 1.1;
  let ph = 0; for (let i = 0; i < n; i++) { const t = i / SR; ph += 2400 / SR; x[i] += Math.sin(TAU * ph) * Math.exp(-t / 0.6) * 0.18 + Math.sin(TAU * ph * 1.51) * Math.exp(-t / 0.4) * 0.1; }
  const s = sub(1.2, 70, 30, 0.8, 0.2); for (let i = 0; i < s.length; i++) x[i] += s[i];
  return x;
}
function dieSfx() { const n = Math.floor(3.4 * SR), x = new Float32Array(n); for (let k = 0; k < 220; k++) { const t0 = Math.floor(Math.pow(rnd(), 1.4) * 2.6 * SR), len = 300 + Math.floor(rnd() * 500), cl = hp(noise(len), 1500); for (let i = 0; i < len; i++) x[t0 + i] += cl[i] * Math.exp(-i / len * 5) * 0.12 * (1 - t0 / n); } const hs = lp(hp(noise(n), 700), 4200, 1); for (let i = 0; i < n; i++) { const t = i / SR; x[i] += hs[i] * 0.16 * Math.min(t / 0.3, 1) * Math.exp(-t / 1.1); } return x; }

// ------------------------------------------------------------ sfx from events
const camAtO = o => SIM.camAt(SIM.warp.o2s(o));
function panAt(wx, o) { const c = SIM.camAt(SIM.warp.o2s(o)); return clamp((wx - c.x) * c.zoom / 640, -1, 1) * 0.8; }
let nHit = 0;
for (const e of SIM.evs) {
  const to = o2(e.t);
  if (e.type === 'clash' || e.type === 'spark') {
    const pw = e.pwr || 1; const pan = e.pos ? panAt(e.pos[0], to) : 0;
    if (pw < 0.9) place(crackle(pw * 1.4), to, { g: 0.5, pan, send: 0.1 });
    else place(clashSfx(pw), to, { g: 0.75, pan, send: 0.22 });
    nHit++;
  } else if (e.type === 'sfx') {
    const pan = 0;
    if (e.name === 'ignite') place(igniteSfx({ G: 112, B: 124, Y: 140 }[e.f] || 120, e.big || 1), to, { g: 0.8, send: 0.3 });
    else if (e.name === 'kick') place(sub(0.35, 190, 60, 0.9, 0.05), to, { g: 0.9 }), place(crackle(1.2), to, { g: 0.6 });
    else if (e.name === 'push') { place(whoosh(0.7, 150, 900, 1.2), to - 0.05, { g: 0.9, send: 0.35 }); place(sub(1.4, 110, 32, 1.1, 0.3), to, { g: 0.9, send: 0.3 }); }
    else if (e.name === 'boom') place(boomSfx(), to, { g: 1.0, send: 0.45 });
    else if (e.name === 'crash') place(crashSfx(), to, { g: 0.9, send: 0.3 });
    else if (e.name === 'slice') place(sliceSfx(), to, { g: 0.9, send: 0.45 });
    else if (e.name === 'disarm') { place(clashSfx(3), to - 0.12, { g: 0.6 }); }
    else if (e.name === 'pull') place(whoosh(0.28, 500, 5200, 1.3), to - 0.05, { g: 0.85, send: 0.3 });
  } else if (e.type === 'push') { /* handled by sfx */ }
  else if (e.type === 'hit') { place(sub(0.4, 170, 55, 1.0, 0.05), to, { g: 0.8, pan: e.pos ? panAt(e.pos[0], to) : 0 }); }
  else if (e.type === 'die') { place(dieSfx(), to, { g: 0.6, send: 0.5 }); }
  else if (e.type === 'dust' && (e.pwr || 1) >= 0.95) { const x = lp(noise(Math.floor(0.4 * SR)), 500, 2); env(x, 0.005, 0.1); place(x, to, { g: 0.5 * Math.min(e.pwr || 1, 1.8), pan: panAt(e.x, to), send: 0.15 }); }
  else if (e.type === 'rubble') { for (let k = 0; k < 8; k++) { const cl = hp(noise(700), 700); env(cl, 0.001, 0.015); place(cl, to + 0.05 + rnd() * 0.9, { g: 0.22, pan: panAt(e.x, to), send: 0.15 }); } }
  else if (e.type === 'sabre') { // thrown saber whirr, then a clink when it lands
    const tl = o2(e.tl), t0 = to, n = Math.floor((tl - t0) * SR), x = new Float32Array(n); let ph = 0;
    for (let i = 0; i < n; i++) { const t = i / SR; ph += (150 + 40 * Math.sin(TAU * 11 * t)) / SR; x[i] = (Math.sin(TAU * ph) + 0.4 * Math.sin(TAU * ph * 2)) * 0.18 * Math.min(t / 0.05, 1) * (1 - 0.5 * t / ((tl - t0))); }
    place(x, t0, { g: 0.7, pan: 0.2, send: 0.3 });
    const cl = clashSfx(0.8); place(cl, tl, { g: 0.35, pan: panAt(e.lx, tl) });
  }
}
console.log('clash sounds', nHit);

// ------------------------------------------------------------ saber hum + whooshes (from the animation itself)
const HUM = { G: 112, B: 124, Y: 138 };
const BLK = 1 / 100;
const speedTrack = { G: [], B: [], Y: [] }, bodyTrack = { G: [], B: [], Y: [] };
for (const f of SIM.names) {
  let prevTip = null, prevPel = null, ph = 0, ph2 = 0, sm = 0;
  const steps = Math.floor(DUR / BLK);
  for (let k = 0; k < steps; k++) {
    const o = k * BLK, s = SIM.warp.o2s(o);
    const st = SIM.stateAt(f, s), bl = SIM.blade(st), pel = SIM.pelvis(st);
    const tip = bl[1];
    let sp = 0, bp = 0;
    if (prevTip) { sp = Math.hypot(tip[0] - prevTip[0], tip[1] - prevTip[1]) / BLK; bp = Math.hypot(pel[0] - prevPel[0], pel[1] - prevPel[1]) / BLK; }
    // worlds speeds measured in OUTPUT time (so slow-mo is quiet)
    prevTip = tip; prevPel = pel;
    speedTrack[f].push(st.on > 0.2 ? sp : 0); bodyTrack[f].push(bp);
    const on = clamp(st.on, 0, 1) * (st.held ? 1 : 0.0) + ((!st.held && s > 0) ? 0 : 0);
    const spn = clamp(sp / 3500, 0, 1); sm += (spn - sm) * 0.2;
    const a = Math.pow(on, 1.4) * (0.024 + 0.04 * sm);
    const pan = panAt(pel[0], o);
    const f0 = HUM[f] * (1 + 0.14 * sm);
    const gl = Math.cos((pan + 1) * Math.PI / 4), gr = Math.sin((pan + 1) * Math.PI / 4);
    const s0 = Math.floor(o * SR), s1 = Math.min(N, s0 + Math.floor(BLK * SR));
    for (let i = s0; i < s1; i++) {
      ph += f0 / SR; ph2 += 38 / SR;
      const v = (Math.sin(TAU * ph) + 0.55 * Math.sin(TAU * ph * 2 + 0.7) + 0.28 * Math.sin(TAU * ph * 3) + 0.12 * saw(ph * 5)) * (1 + 0.18 * Math.sin(TAU * ph2)) * a;
      dry.L[i] += v * gl; dry.R[i] += v * gr; wet.L[i] += v * gl * 0.1; wet.R[i] += v * gr * 0.1;
    }
  }
}
// whooshes at speed peaks
for (const f of SIM.names) {
  const sp = speedTrack[f], bp = bodyTrack[f];
  let last = -1;
  for (let k = 3; k < sp.length - 3; k++) {
    const v = sp[k];
    if (v > 1700 && v >= sp[k - 1] && v >= sp[k + 1] && v >= sp[k - 2] && v >= sp[k + 2] && k - last > 11) {
      last = k; const g = clamp((v - 1500) / 3500, 0.12, 1) * 0.55;
      place(whoosh(0.2 + 0.06 * g, 500, 1800 + 3200 * g, 1), k * BLK - 0.08, { g, pan: 0, send: 0.12 });
    }
  }
  last = -1;
  for (let k = 3; k < bp.length - 3; k++) {
    const v = bp[k];
    if (v > 750 && v >= bp[k - 1] && v >= bp[k + 1] && v >= bp[k - 2] && v >= bp[k + 2] && k - last > 25) { last = k; place(whoosh(0.36, 200, 900, 1), k * BLK - 0.15, { g: clamp(v / 2000, 0.15, 0.6) * 0.5, send: 0.2 }); }
  }
}

// ------------------------------------------------------------ wind bed
{
  const x = new Float32Array(N), y = noise(N); let a = 0, b = 0;
  for (let i = 0; i < N; i++) {
    const t = i / SR, lfo = 0.5 + 0.5 * Math.sin(TAU * 0.07 * t + 1) * Math.sin(TAU * 0.031 * t + 2);
    const fc = 260 + 900 * lfo, k = 1 - Math.exp(-TAU * fc / SR); a += k * (y[i] - a); b += k * (a - b);
    const gain = 0.35 + 0.65 * lfo; x[i] = b * gain;
  }
  const secs = [[0, 0.55], [1.2, 0.9], [9.7, 0.5], [10.8, 0.28], [29.9, 0.25], [45, 0.6], [57, 0.8]];
  const gf = t => { let g = secs[0][1]; for (let i = 0; i < secs.length - 1; i++) if (t >= secs[i][0] && t < secs[i + 1][0]) g = lerp(secs[i][1], secs[i + 1][1], (t - secs[i][0]) / (secs[i + 1][0] - secs[i][0])); return g; };
  const L = new Float32Array(N), Rr = new Float32Array(N), y2 = noise(N); let c = 0, d = 0;
  for (let i = 0; i < N; i++) { const t = i / SR, lfo = 0.5 + 0.5 * Math.sin(TAU * 0.05 * t + 3) * Math.sin(TAU * 0.037 * t); const fc = 300 + 800 * lfo, k = 1 - Math.exp(-TAU * fc / SR); c += k * (y2[i] - c); d += k * (c - d); Rr[i] = d * (0.35 + 0.65 * lfo); }
  for (let i = 0; i < N; i++) { const g = gf(SIM.warp.o2s(i / SR)) * 0.9; dry.L[i] += x[i] * g * 0.5; dry.R[i] += Rr[i] * g * 0.5; }
}

// ------------------------------------------------------------ score
const T = { title: o2(0.2), standoff: o2(9.7), go: o2(10.8), lock: o2(16.2), boom: o2(16.72), rise: o2(22.4), melee: o2(23.4), kill1: o2(29.9), duel: o2(31.2), disarm: o2(36.3), pullUp: o2(38.4), pull: o2(39.22), kill2: o2(42.86), end: o2(46.6), fadeOut: o2(57.6) };
const BPM = 126, BEAT = 60 / BPM, BAR = BEAT * 4;
// drone: continuous bed D1/D2/A2 with a gain curve
{
  const gainPts = [[0, 0], [1.5, 0.12], [T.standoff, 0.2], [T.go, 0.2], [T.lock, 0.2], [T.lock + 0.4, 0.34], [T.boom, 0.1], [T.boom + 3, 0.2], [T.kill1, 0.2], [T.kill1 + 0.2, 0.34], [T.kill1 + 3, 0.2], [T.disarm, 0.34], [T.pull, 0.14], [T.kill2 - 0.2, 0.18], [T.kill2, 0.04], [T.kill2 + 2, 0.2], [T.end, 0.18], [T.fadeOut, 0.14], [DUR, 0.0]];
  const gf = t => { for (let i = 0; i < gainPts.length - 1; i++) { const a = gainPts[i], b = gainPts[i + 1]; if (t >= a[0] && t < b[0]) return lerp(a[1], b[1], (t - a[0]) / (b[0] - a[0])); } return 0; };
  const x = new Float32Array(N); let p1 = 0, p2 = 0, p3 = 0, p4 = 0;
  const notes = [[0, 36], [T.disarm - 0.1, 34], [T.pull, 36], [T.end - 0.5, 38]]; // D2 … Bb1 … D2 … D3?
  for (let i = 0; i < N; i++) {
    const t = i / SR; let m = 38; for (const [nt, mm] of notes) if (t >= nt) m = mm + 2; // D2=38
    const f = midi(m - 12 + 12);
    p1 += f / SR; p2 += f * 1.5 * 1.002 / SR; p3 += f * 0.5 / SR; p4 += f * 1.004 / SR;
    x[i] = (saw(p1) * 0.35 + saw(p2) * 0.22 + Math.sin(TAU * p3) * 0.8 + saw(p4) * 0.3) * gf(t);
  }
  lp(x, 320, 2);
  for (let i = 0; i < N; i++) { dry.L[i] += x[i] * 0.9; dry.R[i] += x[i] * 0.9; wet.L[i] += x[i] * 0.2; wet.R[i] += x[i] * 0.2; }
}
// lonely lead motif (title + ending)
const D4 = 62, F4 = 65, A4 = 69, C5 = 72, D5 = 74, E4 = 64, G4 = 67;
place(lead(midi(D4 + 0), 2.2, 0.16), T.title + 1.4, { send: 0.55, pan: -0.1 });
place(lead(midi(F4), 1.6, 0.15), T.title + 3.7, { send: 0.55, pan: 0.1 });
place(lead(midi(A4), 2.6, 0.15), T.title + 5.4, { send: 0.55, pan: -0.1 });
place(lead(midi(G4), 1.2, 0.13), T.title + 8.2, { send: 0.55 });
// intro hits on each ignition
for (const e of SIM.evs) if (e.type === 'sfx' && e.name === 'ignite') { const t = o2(e.t); place(taiko(0.9), t, { g: 0.7, send: 0.4 }); }
place(taiko(1.0), o2(0.9), { g: 0.8, send: 0.5 });
// standoff: heartbeat + riser
for (let t = T.standoff; t < T.go - 0.2; t += 0.5) { place(taiko(0.55), t, { g: 0.7 }); place(taiko(0.38), t + 0.17, { g: 0.6 }); }
place(riser(T.go - T.standoff, 300, 5200, 0.6), T.standoff, { g: 0.6, send: 0.3 });
place(taiko(1.2), T.go, { g: 1.0, send: 0.35 });
// rhythm sections
function rhythm(t0, t1, level, opt) {
  opt = opt || {};
  let bar = 0;
  const roots = [38, 38, 34, 36]; // D2 D2 Bb1 C2 (+12)
  for (let t = t0; t < t1 - 0.05; t += BEAT) {
    const bi = Math.round((t - t0) / BEAT), beat = bi % 4, barNo = Math.floor(bi / 4);
    if (beat === 0 || beat === 2) place(taiko(0.8 + 0.2 * level), t, { g: 0.85, send: 0.18 });
    if (beat === 1 || beat === 3) place(snare(0.5 * level), t, { g: 0.6, send: 0.2 });
    if (opt.double) place(taiko(0.4 * level), t + BEAT * 0.5, { g: 0.6 }); else place(rim(0.6 * level), t + BEAT * 0.5, { g: 0.5 });
    place(hat(0.35 * level), t + BEAT * 0.25, { g: 0.3 }); place(hat(0.5 * level), t + BEAT * 0.75, { g: 0.3 });
    // bass ostinato 8ths
    const r = roots[barNo % 4];
    place(bassNote(midi(r), BEAT * 0.5, 0.5 * level), t, { g: 0.55, send: 0.08 });
    place(bassNote(midi(r + (beat % 2 ? 7 : 0)), BEAT * 0.5, 0.45 * level), t + BEAT * 0.5, { g: 0.5, send: 0.08 });
    // brass stab on bar starts
    if (beat === 0) {
      const ch = barNo % 4 === 2 ? [r + 24, r + 28, r + 31] : barNo % 4 === 3 ? [r + 24, r + 28, r + 31] : [r + 24, r + 27, r + 31];
      place(brass(ch.map(m => midi(m)), BEAT * 1.6, 1900), t, { g: 0.62 * level, send: 0.3 });
      place(strings(midi(r + 24), BAR, 0.22 * level), t, { g: 0.6, send: 0.3 });
    }
    if (opt.motif && beat === 2 && barNo % 2 === 1) { // rising brass motif D F A D
      [0, 3, 7, 12].forEach((iv, k) => place(brass([midi(62 + iv), midi(50 + iv)], BEAT * 0.5, 2200), t + k * BEAT * 0.25 + BEAT * 0.0, { g: 0.55 * level, send: 0.3 }));
    }
  }
}
rhythm(T.go, T.lock - 0.1, 0.9, {});
place(riser(T.boom - T.lock, 500, 7000, 0.9), T.lock, { g: 0.8, send: 0.4 });
place(strings(midi(86), T.boom - T.lock + 0.2, 0.5), T.lock, { g: 0.5, send: 0.5 });
place(strings(midi(81), T.boom - T.lock + 0.2, 0.5), T.lock, { g: 0.5, send: 0.5 });
place(taiko(1.5), T.boom, { g: 1.1, send: 0.5 });
rhythm(T.boom + 0.9, T.rise - 0.1, 1.0, { motif: true });
// Green rises: sparse + ominous
for (let t = T.rise; t < T.melee - 0.2; t += BEAT * 2) place(taiko(0.7), t, { g: 0.7, send: 0.4 });
place(brass([midi(38), midi(45), midi(50)], 1.4, 900), T.rise + 0.3, { g: 0.5, send: 0.5 });
rhythm(T.melee, T.kill1 - 0.15, 1.1, { double: true, motif: true });
// kill 1
place(taiko(1.4), T.kill1, { g: 1.0, send: 0.6 });
place(choir([midi(50), midi(57), midi(62)], 3.0, 0.5, 0.3), T.kill1 + 0.1, { g: 0.5, send: 0.6 });
rhythm(T.duel, T.disarm - 0.05, 1.15, { double: true, motif: true });
// disarmed: dread
for (let t = T.disarm + 0.2; t < T.pull - 0.4; t += 0.75) place(taiko(0.5), t, { g: 0.6, send: 0.5 });
place(pad([midi(46), midi(53), midi(58), midi(65)], T.pull - T.disarm, 0.35, 0.5, 0.4), T.disarm, { g: 0.55, send: 0.5 });
place(riser(T.pull - T.pullUp, 400, 6000, 0.8), T.pullUp, { g: 0.7, send: 0.4 });
// the comeback
place(choir([midi(50), midi(57), midi(62), midi(66)], T.kill2 - T.pull - 0.6, 0.6, 0.5), T.pull + 0.1, { g: 0.6, send: 0.6 });
place(taiko(1.4), T.pull + 0.05, { g: 1.0, send: 0.5 });
rhythm(T.pull + 0.4, T.kill2 - 1.4, 1.25, { double: true, motif: true });
place(riser(1.3, 500, 8000, 0.9), T.kill2 - 1.3, { g: 0.8, send: 0.4 });
// kill 2: everything stops, then the hit
place(taiko(1.6), T.kill2, { g: 1.1, send: 0.7 });
place(sub(3.0, 80, 24, 1.0, 0.6), T.kill2, { g: 0.9, send: 0.4 });
place(revSwell(1.0, 0.5), T.kill2 - 1.0, { g: 0.6 });
// ending
place(choir([midi(50), midi(57), midi(62), midi(66), midi(69)], DUR - T.kill2 - 2.0, 0.55, 2.6), T.kill2 + 1.6, { g: 0.55, send: 0.7 });
place(pad([midi(38), midi(45), midi(50), midi(54)], DUR - T.end, 0.45, 2.5, 2.5), T.end - 0.5, { g: 0.55, send: 0.6 });
place(lead(midi(D5), 2.8, 0.18), T.end + 0.4, { send: 0.65, pan: 0.1 });
place(lead(midi(A4), 2.4, 0.16), T.end + 3.6, { send: 0.65, pan: -0.1 });
place(lead(midi(F4 + 1), 3.6, 0.16), T.end + 6.2, { send: 0.65 });

// ------------------------------------------------------------ reverb (Schroeder) on the wet bus
function reverb(inp, delays, fb, damp) {
  const out = new Float32Array(N);
  for (const d0 of delays) {
    const d = Math.floor(d0 * SR / 44100), buf = new Float32Array(d); let idx = 0, lpv = 0;
    for (let i = 0; i < N; i++) { const y = buf[idx]; lpv += damp * (y - lpv); buf[idx] = inp[i] + lpv * fb; idx = (idx + 1) % d; out[i] += y; }
  }
  for (const [d0, g] of [[556, 0.5], [441, 0.5], [341, 0.5]]) {
    const d = Math.floor(d0 * SR / 44100), buf = new Float32Array(d); let idx = 0;
    for (let i = 0; i < N; i++) { const y = buf[idx], v = out[i] + g * y; buf[idx] = v; out[i] = y - g * v; idx = (idx + 1) % d; }
  }
  return out;
}
const rvL = reverb(wet.L, [1557, 1617, 1491, 1422, 1277, 1356, 2011, 2203], 0.86, 0.35);
const rvR = reverb(wet.R, [1580, 1640, 1513, 1445, 1300, 1379, 2037, 2231], 0.86, 0.35);
const outL = mk(), outR = mk();
for (let i = 0; i < N; i++) { outL[i] = dry.L[i] + rvL[i] * 0.2; outR[i] = dry.R[i] + rvR[i] * 0.2; }

// ------------------------------------------------------------ master
let peak = 0; for (let i = 0; i < N; i++) peak = Math.max(peak, Math.abs(outL[i]), Math.abs(outR[i]));
const norm = 0.9 / peak;
const fi = 1.2, fo0 = T.fadeOut + 0.2;
for (let i = 0; i < N; i++) {
  const t = i / SR; let g = norm * Math.min(t / fi, 1) * (t > fo0 ? Math.max(0, 1 - (t - fo0) / (DUR - fo0)) : 1);
  outL[i] = Math.tanh(outL[i] * g * 1.15) / 1.0; outR[i] = Math.tanh(outR[i] * g * 1.15) / 1.0;
}
const buf = Buffer.alloc(44 + N * 4);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write('WAVEfmt ', 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write('data', 36); buf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) { buf.writeInt16LE(Math.round(clamp(outL[i], -1, 1) * 32767), 44 + i * 4); buf.writeInt16LE(Math.round(clamp(outR[i], -1, 1) * 32767), 46 + i * 4); }
fs.writeFileSync(process.argv[2] || 'ashfall.wav', buf);
console.log('audio written', DUR.toFixed(2) + 's', 'peak(pre-norm)', peak.toFixed(3));

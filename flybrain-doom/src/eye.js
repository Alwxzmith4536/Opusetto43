// Compound eyes and optic lobe.
//
// Each eye is a strip of ommatidial columns (azimuth only). Left eye spans
// -10..130 degrees, right eye mirrors it, so the fly sees 260 degrees with a
// 20 degree binocular zone in front. The optic lobe is modelled as rate
// filters; its outputs become Poisson spike rates for the visual projection
// neurons (VPNs) that enter the spiking central brain:
//
//   LC10a   small-object detector, retinotopic        -> AOTU (pursuit)
//   LC4     looming speed (1/time-to-contact)          -> giant fiber
//   LPLC2   angular size of an approaching object      -> giant fiber
//   HS      horizontal optic flow (Reichardt, T4/T5)   -> steering (optomotor)
//   vPN     color channels to the mushroom body calyx  -> Kenyon cells
//   MECH    wall contact ahead (bristles / legs)       -> steering, backing
//   MECHb   wall contact behind                        -> forward walking
//
// Looming cells only respond to objects that move toward the fly; expansion
// caused by the fly's own walking is cancelled (efference copy).

import { DEG, wrapAngle } from './world.js';
import { WALL_STYLE } from './maps.js';

export const EYE = { cols: 16, span: 140 * DEG, inner: -10 * DEG, range: 22 };
export const COLOR_CHANNELS = ['blue', 'green', 'red', 'dark'];

// How each thing looks to the fly's photoreceptors.
const LOOK = {
  imp: { blue: 0, green: 0, red: 0.55, dark: 0.9, contrast: 0.85, lum: 0.25 },
  fireball: { blue: 0, green: 0, red: 1, dark: 0, contrast: 1, lum: 1 },
  orb_blue: { blue: 1, green: 0, red: 0, dark: 0, contrast: 0.9, lum: 0.85 },
  orb_green: { blue: 0, green: 1, red: 0, dark: 0, contrast: 0.9, lum: 0.85 },
};
export const lookOf = (e) => (e.kind === 'orb' ? LOOK['orb_' + e.color] : LOOK[e.kind]);

const WALL_LUM = {};
for (const [ch, s] of Object.entries(WALL_STYLE)) WALL_LUM[ch.charCodeAt(0)] = s.lum;

const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

// Column azimuths for one eye (bearing, positive = left).
export function columnAzimuths(side) {
  const out = new Float32Array(EYE.cols), w = EYE.span / EYE.cols;
  for (let c = 0; c < EYE.cols; c++) {
    const b = EYE.inner + (c + 0.5) * w;
    out[c] = side === 0 ? b : -b;
  }
  return out;
}
const AZ = [columnAzimuths(0), columnAzimuths(1)];
const COLW = EYE.span / EYE.cols;

// Small-object size tuning of LC10a (full angular width, degrees).
function sizeTuning(widthDeg) {
  const l = Math.log(Math.max(widthDeg, 0.2) / 10);
  return Math.exp(-(l * l) / (2 * 0.9 * 0.9));
}

export class OpticLobe {
  constructor() {
    const n = EYE.cols;
    this.lum = [new Float32Array(n), new Float32Array(n)];
    this.prevLum = [new Float32Array(n), new Float32Array(n)];
    this.out = {
      lc10a: [new Float32Array(n), new Float32Array(n)],
      lc4: [new Float32Array(n), new Float32Array(n)],
      lplc2: [new Float32Array(n), new Float32Array(n)],
      hs: [0, 0],
      vpn: [new Float32Array(COLOR_CHANNELS.length), new Float32Array(COLOR_CHANNELS.length)],
      mech: [0, 0],
      mechBack: [0, 0],
      // for display: per-column color the eye saw
      view: { rgb: [new Float32Array(n * 3), new Float32Array(n * 3)], lum: this.lum },
    };
    this.primed = false;
  }

  reset() { this.primed = false; }

  process(world) {
    const p = world.player, n = EYE.cols, o = this.out;
    // swap luminance buffers
    const t = this.prevLum; this.prevLum = this.lum; this.lum = t; o.view.lum = this.lum;

    // 1. Wall luminance per column (R1-6 photoreceptors)
    for (let s = 0; s < 2; s++) {
      const lum = this.lum[s], rgb = o.view.rgb[s];
      for (let c = 0; c < n; c++) {
        const r = world.castRay(p.x, p.y, p.angle - AZ[s][c], EYE.range);
        let b = 0.08;
        if (r.cell) {
          const base = WALL_LUM[r.cell] ?? 0.5;
          const stripe = 0.8 + 0.2 * Math.sin(r.u * Math.PI * 6 + r.mx * 1.7 + r.my * 2.3);
          b = base * stripe * (r.side ? 0.85 : 1) / (1 + 0.12 * r.dist);
        }
        lum[c] = b;
        rgb[c * 3] = rgb[c * 3 + 1] = rgb[c * 3 + 2] = b;
        o.lc10a[s][c] = 0; o.lc4[s][c] = 0; o.lplc2[s][c] = 0;
      }
      o.vpn[s].fill(0);
    }

    // 2. Objects
    for (const e of world.entities) {
      if (e.alive === false) continue;
      const dx = e.x - p.x, dy = e.y - p.y, dist = Math.hypot(dx, dy);
      if (dist > EYE.range || dist < 1e-3) continue;
      const beta = wrapAngle(p.angle - Math.atan2(dy, dx));
      if (Math.abs(beta) > EYE.span + EYE.inner + 0.3) continue; // behind the fly
      if (!world.lineOfSight(p.x, p.y, e.x, e.y)) continue;
      const alpha = Math.atan(e.radius / Math.max(dist, e.radius * 1.05)); // half width
      const look = lookOf(e);
      const tune = sizeTuning((2 * alpha) / DEG) * look.contrast;
      // object-generated approach speed (efference copy removes self-motion)
      const ux = -dx / dist, uy = -dy / dist;
      const approach = (e.vx || 0) * ux + (e.vy || 0) * uy;
      const invTTC = approach > 0 ? approach / dist : 0; // 1/s
      const loomSpeed = clamp01((invTTC - 0.8) / 2.5);
      const loomSize = approach > 0.5 ? clamp01((2 * alpha / DEG - 10) / 30) : 0;
      for (let s = 0; s < 2; s++) {
        const az = AZ[s], rgb = o.view.rgb[s];
        for (let c = 0; c < n; c++) {
          const lo = Math.max(beta - alpha, az[c] - COLW / 2), hi = Math.min(beta + alpha, az[c] + COLW / 2);
          if (hi <= lo) continue;
          const cov = (hi - lo) / COLW;
          o.lc10a[s][c] += cov * tune;
          o.lc4[s][c] += cov * loomSpeed;
          o.lplc2[s][c] += cov * loomSize;
          for (let k = 0; k < COLOR_CHANNELS.length; k++) o.vpn[s][k] += cov * look[COLOR_CHANNELS[k]];
          const mix = clamp01(cov);
          const col = e.kind === 'orb' ? (e.color === 'blue' ? [0.25, 0.45, 1] : [0.3, 1, 0.35]) : e.kind === 'fireball' ? [1, 0.6, 0.2] : [0.55, 0.25, 0.15];
          for (let j = 0; j < 3; j++) rgb[c * 3 + j] = rgb[c * 3 + j] * (1 - mix) + col[j] * mix;
          this.lum[s][c] = this.lum[s][c] * (1 - mix) + look.lum * mix;
        }
      }
    }

    // 3. Convert to firing rates (Hz)
    for (let s = 0; s < 2; s++) {
      for (let c = 0; c < n; c++) {
        o.lc10a[s][c] = 140 * clamp01(o.lc10a[s][c]);
        o.lc4[s][c] = 180 * clamp01(o.lc4[s][c]);
        o.lplc2[s][c] = 200 * clamp01(o.lplc2[s][c]);
      }
      // Color PNs need a sizeable image: far-away objects barely drive them, so the
      // mushroom body mostly sees what is close.
      for (let k = 0; k < COLOR_CHANNELS.length; k++) o.vpn[s][k] = 160 * clamp01((o.vpn[s][k] - 0.3) / 1.5);
    }

    // 4. Horizontal optic flow: Hassenstein-Reichardt correlators between
    // neighbouring columns. Columns run front to back, so a positive sum is
    // front-to-back (progressive) motion, which HS cells of that eye prefer.
    for (let s = 0; s < 2; s++) {
      if (!this.primed) { o.hs[s] = 0; continue; }
      const a = this.prevLum[s], b = this.lum[s];
      let m = 0;
      for (let c = 0; c < n - 1; c++) m += a[c] * b[c + 1] - b[c] * a[c + 1];
      o.hs[s] = 120 * clamp01(m * 6);
    }
    this.primed = true;

    // 5. Mechanosensory wall contact, front-left and front-right
    for (let s = 0; s < 2; s++) {
      let near = 9;
      for (const deg of [15, 40, 65]) {
        const b = (s === 0 ? deg : -deg) * DEG;
        near = Math.min(near, world.castRay(p.x, p.y, p.angle - b, 2).dist);
      }
      o.mech[s] = near < 0.6 ? 220 : near < 0.9 ? 90 : 0;
      let back = 9;
      for (const deg of [110, 150]) {
        const b = (s === 0 ? deg : -deg) * DEG;
        back = Math.min(back, world.castRay(p.x, p.y, p.angle - b, 2).dist);
      }
      o.mechBack[s] = back < 0.45 ? 220 : 0;
    }
    return o;
  }
}

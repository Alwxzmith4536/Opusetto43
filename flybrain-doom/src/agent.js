// Agents that play the world. FlyAgent closes the loop:
//   world -> compound eye / optic lobe -> spiking brain -> descending neurons -> action
// Game events reach the brain the way they would reach a fly: damage drives
// nociceptors (-> PPL1 dopamine), healing and kills drive sweet-taste neurons
// (-> PAM dopamine).

import { OpticLobe, COLOR_CHANNELS } from './eye.js';
import { buildConnectome, scrambleConnectome, SIDES } from './connectome.js';
import { FlyBrain } from './brain.js';
import { RNG, hashSeed } from './rng.js';
import { TIC } from './world.js';

// Descending-neuron rates (Hz, smoothed) to game controls.
export const READOUT = {
  tau: 0.08, // s, smoothing of DN rates
  turnGain: 1 / 70, // turn = gain x (left steering DNs - right steering DNs)
  fwdGain: 1 / 28, // forward from P9
  backGain: 1 / 18, // backward from MDN
  strafeGain: 1 / 25, // sidestep away from the giant fiber that fired
  fireMin: 12, // fire when both AOTU019 populations exceed this (target in the binocular zone)
  fireSum: 40, // ... and together exceed this (Hz)
};

const MOTOR_GROUPS = ['DNa02', 'DNa01', 'P9', 'MDN', 'DNp01', 'AOTU019', 'AOTU025', 'MBON11', 'MBON01', 'LALi', 'PPL101', 'PAM', 'KC', 'APL'];

export class FlyAgent {
  constructor({ seed = 1, silence = [], scramble = false, plasticity = true, dt = 0.5, learning = {}, readout = {} } = {}) {
    this.kind = 'fly';
    this.seed = seed;
    // Each fly gets its own random Kenyon cell claws, like real flies.
    let conn = buildConnectome(new RNG(hashSeed(seed, 'wiring')));
    if (scramble) conn = scrambleConnectome(conn, new RNG(hashSeed(seed, 'scramble')));
    this.conn = conn;
    const silenced = conn.neurons.filter((n) => silence.includes(n.type)).map((n) => n.id);
    this.brain = new FlyBrain(conn, { rng: new RNG(hashSeed(seed, 'noise')), dt, plasticity, silenced, learning });
    this.eye = new OpticLobe();
    this.R = { ...READOUT, ...readout };
    this.ema = {};
    for (const g of MOTOR_GROUPS) for (const s of SIDES) this.ema[`${g}_${s}`] = 0;
    // per-input-neuron lookup into the optic lobe output
    const col = (key) => Int32Array.from(this.brain.groups[key], (id) => conn.neurons[id].col);
    const ch = (key) => Int32Array.from(this.brain.groups[key], (id) => conn.neurons[id].channel);
    this.map = SIDES.map((s) => ({ lc10a: col(`LC10a_${s}`), lc4: col(`LC4_${s}`), lplc2: col(`LPLC2_${s}`), vpn: ch(`vPN_${s}`) }));
    this.buf = {};
    for (const [k, ids] of Object.entries(this.brain.groups)) this.buf[k] = new Float32Array(ids.length);
    this.beginEpisode();
  }

  beginEpisode() {
    this.brain.resetState();
    this.eye.reset();
    this.pain = 0;
    this.sugar = 0;
    for (const k in this.ema) this.ema[k] = 0;
    this.lastAction = { forward: 0, turn: 0, strafe: 0, fire: false };
  }

  // ev: events returned by the previous world.step (or null)
  act(world, ev) {
    if (ev) {
      this.pain += ev.damage / 10;
      this.sugar += (ev.heal > 0 ? 1.2 : 0) + ev.kill * 1.0;
    }
    const o = this.eye.process(world);
    const b = this.brain, buf = this.buf;
    for (let s = 0; s < 2; s++) {
      const S = SIDES[s], m = this.map[s];
      const fillCols = (key, src, idx) => { const a = buf[key]; for (let i = 0; i < a.length; i++) a[i] = src[idx[i]]; b.setRate(key, a); };
      fillCols(`LC10a_${S}`, o.lc10a[s], m.lc10a);
      fillCols(`LC4_${S}`, o.lc4[s], m.lc4);
      fillCols(`LPLC2_${S}`, o.lplc2[s], m.lplc2);
      fillCols(`vPN_${S}`, o.vpn[s], m.vpn);
      b.setRate(`HS_${S}`, o.hs[s]);
      b.setRate(`MECH_${S}`, o.mech[s]);
      b.setRate(`MECHb_${S}`, o.mechBack[s]);
      b.setRate(`NOCI_${S}`, 250 * Math.min(1, this.pain));
      b.setRate(`GRN_${S}`, 250 * Math.min(1, this.sugar));
    }
    b.run(TIC * 1000);
    b.learn(TIC);
    const decay = Math.exp(-TIC / 0.25);
    this.pain *= decay;
    this.sugar *= decay;

    // smoothed firing rates of the motor-side populations
    const a = 1 - Math.exp(-TIC / this.R.tau);
    for (const k in this.ema) {
      const n = b.groups[k].length;
      this.ema[k] += a * (b.groupCount(k) / n / TIC - this.ema[k]);
    }
    const r = this.ema, R = this.R;
    const turn = R.turnGain * (r.DNa02_L + r.DNa01_L - r.DNa02_R - r.DNa01_R);
    const forward = R.fwdGain * (r.P9_L + r.P9_R) / 2 - R.backGain * (r.MDN_L + r.MDN_R) / 2;
    const strafe = R.strafeGain * (r.DNp01_R - r.DNp01_L);
    const fire = r.AOTU019_L > R.fireMin && r.AOTU019_R > R.fireMin && r.AOTU019_L + r.AOTU019_R > R.fireSum;
    this.lastAction = { turn, forward, strafe, fire };
    this.lastOptics = o;
    return this.lastAction;
  }

  memory() { return this.brain.memory(); }
}

// Baseline: random walk with random trigger pulls. No brain, no learning.
export class RandomAgent {
  constructor({ seed = 1 } = {}) {
    this.kind = 'random';
    this.rng = new RNG(hashSeed(seed, 'random-agent'));
    this.beginEpisode();
  }
  beginEpisode() { this.turn = 0; this.hold = 0; }
  act() {
    const rng = this.rng;
    if (--this.hold <= 0) { this.turn = rng.range(-1, 1); this.hold = 5 + rng.int(25); }
    return { turn: this.turn, forward: rng.range(0.2, 1), strafe: 0, fire: rng.chance(0.08) };
  }
  memory() { return Object.fromEntries(COLOR_CHANNELS.map((c) => [c, { approach: 1, avoid: 1, valence: 0 }])); }
}

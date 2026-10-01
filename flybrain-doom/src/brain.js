// Spiking simulator for the connectome.
//
// Neuron model: leaky integrate-and-fire with exponential synaptic current,
// parameters from Shiu et al. 2024 (Nature 634:210):
//   dv/dt = (v_rest - v + g) / tau_m,   dg/dt = -g / tau_syn
//   a presynaptic spike adds  count x sign x 0.275 mV  to g after a 1.8 ms delay.
//
// Learning: three-factor rule at Kenyon cell -> MBON synapses. A KC keeps an
// eligibility trace of its recent spikes; a compartment's dopamine neuron keeps a
// dopamine trace. Dopamine plus an eligible KC depresses that KC's synapse
// (LTD, Hige et al. 2015). Dopamine onto a silent KC's synapse lets it recover
// toward baseline, and all synapses drift back slowly (forgetting).

import { BACKGROUND } from './connectome.js';
import { COLOR_CHANNELS } from './eye.js';

export const LIF = { vRest: -52, vReset: -52, vTh: -45, tauM: 20, tauSyn: 5, tRef: 2.2, wSyn: 0.275, delay: 1.8 };

export const LEARNING = {
  tauElig: 0.6, // s
  tauDA: 0.3, // s
  ltd: 0.12, // fractional depression per (dopamine spike x second) at full eligibility
  eligCap: 8, // spikes in the trace that count as full eligibility
  eligMin: 1.5, // below this a KC counts as silent
  recover: 0.01, // dopamine-driven recovery of silent KCs' synapses, per (spike x second)
  tauForget: 600, // s, passive return to baseline
};

export class FlyBrain {
  constructor(conn, { rng, dt = 0.5, plasticity = true, silenced = [], learning = {} } = {}) {
    this.conn = conn;
    this.rng = rng;
    this.dt = dt;
    this.plasticity = plasticity;
    this.L = { ...LEARNING, ...learning };
    const N = conn.N, E = conn.pre.length;
    this.N = N;
    this.nInput = conn.nInput;

    // CSR adjacency by presynaptic neuron
    const start = new Int32Array(N + 1);
    for (let k = 0; k < E; k++) start[conn.pre[k] + 1]++;
    for (let i = 0; i < N; i++) start[i + 1] += start[i];
    const fill = start.slice(0, N);
    this.outStart = start;
    this.outPost = new Int32Array(E);
    this.outW = new Float32Array(E);
    const slotOf = new Int32Array(E);
    for (let k = 0; k < E; k++) {
      const i = conn.pre[k], s = fill[i]++;
      this.outPost[s] = conn.post[k];
      this.outW[s] = conn.count[k] * conn.sign[i] * LIF.wSyn;
      slotOf[k] = s;
    }

    // Groups
    this.groups = {};
    for (const [k, ids] of Object.entries(conn.groups)) this.groups[k] = Int32Array.from(ids);
    this.kcIds = Int32Array.from([...conn.groups.KC_L, ...conn.groups.KC_R]);
    this.kcLocal = new Int32Array(N).fill(-1);
    this.kcIds.forEach((id, j) => { this.kcLocal[id] = j; });

    // Plastic synapses: KC -> MBON-11 gated by PPL1-γ1pedc, KC -> MBON-01 gated by PAM-γ5,
    // using the dopamine neurons on the MBON's side. (Recomputed from the actual
    // wiring, so a scrambled brain learns wherever such synapses happen to exist.)
    const pl = { slot: [], kc: [], comp: [] };
    for (let k = 0; k < E; k++) {
      const a = conn.neurons[conn.pre[k]], b = conn.neurons[conn.post[k]];
      if (a.type !== 'KC') continue;
      if (b.type === 'MBON11') { pl.slot.push(slotOf[k]); pl.kc.push(this.kcLocal[a.id]); pl.comp.push(0 + b.side); }
      else if (b.type === 'MBON01') { pl.slot.push(slotOf[k]); pl.kc.push(this.kcLocal[a.id]); pl.comp.push(2 + b.side); }
    }
    this.plSlot = Int32Array.from(pl.slot);
    this.plKC = Int32Array.from(pl.kc);
    this.plComp = Uint8Array.from(pl.comp);
    this.plW0 = new Float32Array(this.plSlot.length);
    for (let p = 0; p < this.plSlot.length; p++) this.plW0[p] = this.outW[this.plSlot[p]];
    this.danGroups = [this.groups.PPL101_L, this.groups.PPL101_R, this.groups.PAM_L, this.groups.PAM_R];

    // Which color each KC listens to (from its claws), for the memory readout
    this.kcChannel = Array.from({ length: COLOR_CHANNELS.length }, () => new Float32Array(this.kcIds.length));
    for (let k = 0; k < E; k++) {
      const a = conn.neurons[conn.pre[k]], j = this.kcLocal[conn.post[k]];
      if (a.type === 'vPN' && j >= 0) this.kcChannel[a.channel][j] += conn.count[k];
    }

    // Background drive and silencing
    this.bgLambda = new Float32Array(N);
    this.bgP0 = new Float32Array(N); // exp(-lambda)
    this.bgW = new Float32Array(N);
    this.silent = new Uint8Array(N);
    for (const n of conn.neurons) {
      const bg = BACKGROUND[n.type];
      if (bg) { this.bgLambda[n.id] = bg.rate * dt / 1000; this.bgP0[n.id] = Math.exp(-this.bgLambda[n.id]); this.bgW[n.id] = bg.w; }
    }
    for (const id of silenced) this.silent[id] = 1;

    // State
    this.v = new Float32Array(N);
    this.g = new Float32Array(N);
    this.refr = new Float32Array(N);
    this.rate = new Float32Array(N); // Hz, input neurons only
    this.D = Math.max(1, Math.round(LIF.delay / dt));
    this.R = this.D + 1;
    this.ring = new Float32Array(this.R * N);
    this.counts = new Uint16Array(N);
    this.elig = new Float32Array(this.kcIds.length);
    this.da = new Float32Array(4);
    this.step = 0;
    this.resetState();
  }

  resetState() {
    this.v.fill(LIF.vRest);
    this.g.fill(0);
    this.refr.fill(0);
    this.ring.fill(0);
    this.rate.fill(0);
    this.elig.fill(0);
    this.da.fill(0);
  }

  resetWeights() {
    for (let p = 0; p < this.plSlot.length; p++) this.outW[this.plSlot[p]] = this.plW0[p];
  }

  // Simulate `ms` milliseconds. Spike counts for the window end up in this.counts.
  run(ms) {
    const N = this.N, nIn = this.nInput, dt = this.dt, R = this.R, D = this.D;
    const v = this.v, g = this.g, refr = this.refr, ring = this.ring, rate = this.rate;
    const silent = this.silent, bgL = this.bgLambda, bgP0 = this.bgP0, bgW = this.bgW, counts = this.counts;
    const outStart = this.outStart, outPost = this.outPost, outW = this.outW;
    const rng = this.rng;
    const { vRest, vReset, vTh, tRef } = LIF;
    const kM = dt / LIF.tauM, decayG = Math.exp(-dt / LIF.tauSyn), pScale = dt / 1000;
    counts.fill(0);
    const steps = Math.max(1, Math.round(ms / dt));
    for (let t = 0; t < steps; t++) {
      const cur = (this.step % R) * N;
      const fut = ((this.step + D) % R) * N;
      // Poisson input neurons
      for (let i = 0; i < nIn; i++) {
        const r = rate[i];
        if (r <= 0 || silent[i] || rng.next() >= r * pScale) continue;
        counts[i]++;
        for (let k = outStart[i], e = outStart[i + 1]; k < e; k++) ring[fut + outPost[k]] += outW[k];
      }
      // LIF neurons
      for (let i = nIn; i < N; i++) {
        let gi = g[i] + ring[cur + i];
        ring[cur + i] = 0;
        const lam = bgL[i];
        if (lam > 0) {
          // Poisson count by inversion (lambda < ~2 here)
          let u = rng.next(), p = bgP0[i], s = p, n = 0;
          while (u > s && n < 8) { n++; p *= lam / n; s += p; }
          gi += n * bgW[i];
        }
        if (silent[i]) { g[i] = gi * decayG; v[i] = vRest; continue; }
        if (refr[i] > 0) { refr[i] -= dt; v[i] = vReset; }
        else {
          let vi = v[i] + (vRest - v[i] + gi) * kM;
          if (vi >= vTh) {
            vi = vReset; refr[i] = tRef; counts[i]++;
            for (let k = outStart[i], e = outStart[i + 1]; k < e; k++) ring[fut + outPost[k]] += outW[k];
          }
          v[i] = vi;
        }
        g[i] = gi * decayG;
      }
      this.step++;
    }
    return counts;
  }

  // Update traces and plastic weights after a window of `sec` seconds.
  learn(sec) {
    const L = this.L, counts = this.counts, elig = this.elig, da = this.da;
    const dE = Math.exp(-sec / L.tauElig), dD = Math.exp(-sec / L.tauDA);
    const kc = this.kcIds;
    for (let j = 0; j < kc.length; j++) elig[j] = elig[j] * dE + counts[kc[j]];
    for (let c = 0; c < 4; c++) {
      const ids = this.danGroups[c];
      let s = 0;
      for (let k = 0; k < ids.length; k++) s += counts[ids[k]];
      da[c] = da[c] * dD + s / ids.length;
    }
    if (!this.plasticity) return;
    const outW = this.outW, slot = this.plSlot, pk = this.plKC, pc = this.plComp, w0 = this.plW0;
    const fr = sec / L.tauForget, ltd = L.ltd, cap = L.eligCap, emin = L.eligMin, rec = L.recover;
    for (let p = 0; p < slot.length; p++) {
      let w = outW[slot[p]];
      const D = da[pc[p]];
      if (D > 0.02) {
        const e = elig[pk[p]];
        if (e > emin) w -= ltd * D * (e < cap ? (e - emin) / (cap - emin) : 1) * w * sec;
        else if (w < w0[p]) w += rec * D * (w0[p] - w) * sec;
      }
      w += (w0[p] - w) * fr;
      outW[slot[p]] = w;
    }
  }

  setRate(key, values) {
    const ids = this.groups[key];
    if (typeof values === 'number') for (let k = 0; k < ids.length; k++) this.rate[ids[k]] = values;
    else for (let k = 0; k < ids.length; k++) this.rate[ids[k]] = values[k];
  }

  groupCount(key) {
    const ids = this.groups[key];
    let s = 0;
    for (let k = 0; k < ids.length; k++) s += this.counts[ids[k]];
    return s;
  }

  // Learned value of each color channel per hemisphere: how strongly the KCs
  // that listen to that color still drive MBON-11 (approach) and MBON-01
  // (avoidance), relative to the naive weights. 1 = untouched.
  memory() {
    const out = {};
    const n = this.kcIds.length, half = n / 2;
    const sums = {};
    for (let p = 0; p < this.plSlot.length; p++) {
      const comp = this.plComp[p] < 2 ? 'approach' : 'avoid';
      const j = this.plKC[p];
      const side = j < half ? 0 : 1;
      const ratio = this.outW[this.plSlot[p]] / this.plW0[p];
      for (let c = 0; c < COLOR_CHANNELS.length; c++) {
        const wgt = this.kcChannel[c][j];
        if (wgt <= 0) continue;
        const key = `${COLOR_CHANNELS[c]}|${comp}|${side}`;
        const s = sums[key] || (sums[key] = [0, 0]);
        s[0] += wgt * wgt * ratio; s[1] += wgt * wgt;
      }
    }
    for (const c of COLOR_CHANNELS) {
      out[c] = {};
      for (const comp of ['approach', 'avoid']) {
        const v = [0, 1].map((side) => { const s = sums[`${c}|${comp}|${side}`]; return s && s[1] > 0 ? s[0] / s[1] : 1; });
        out[c][comp] = (v[0] + v[1]) / 2;
      }
      // positive = learned attraction, negative = learned aversion
      out[c].valence = out[c].approach - out[c].avoid;
    }
    return out;
  }
}


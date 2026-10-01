// A reduced, connectome-inspired wiring diagram of the fly circuits the game
// needs. Cell types and their wiring motifs follow the published FlyWire /
// MaleCNS literature; the neuron counts are scaled down and synapse counts are
// set by hand so the network runs in a browser. This is not the 140k-neuron
// connectome.
//
//   Pursuit   LC10a -> AOTU019 (GABA, central field, contralateral DNs)
//                   -> AOTU025 (ACh, peripheral field, ipsilateral DNs)
//                   -> DNa02 / DNa01 steering
//   Escape    LC4, LPLC2 -> DNp01 giant fiber; LC4 -> contralateral DNa02
//   Learning  vPN -> Kenyon cells (6 claws each) <-> APL (global inhibition)
//             KC -> MBON-11 (γ1pedc, GABA, approach)  plastic, gated by PPL1-γ1pedc
//             KC -> MBON-01 (γ5β'2a, Glu, avoidance) plastic, gated by PAM-γ5
//             MBON-11 -| MBON-01 (feedforward inhibition)
//             MBON-11 -| contralateral steering DNs     (turn toward)
//             MBON-01 -> contralateral steering DNs, MDN (turn away, back off)
//             MBON-01 -> LALi (GABA) -| ipsilateral AOTU, P9 (gate off pursuit)
//   Reinforcement  nociceptors -> PPL1-γ1pedc (punishment)
//                  sweet GRNs  -> PAM-γ5      (reward)

import { columnAzimuths, COLOR_CHANNELS, EYE } from './eye.js';
import { DEG } from './world.js';

export const NT_SIGN = { ACh: 1, GABA: -1, Glu: -1, DA: 0 };
export const SIDES = ['L', 'R'];

// input: Poisson-driven sensory/VPN populations. Others are LIF neurons.
export const CELL_TYPES = {
  LC10a: { input: true, nt: 'ACh', perSide: EYE.cols * 2, region: 'Lobula', role: 'Small moving object detector' },
  LC4: { input: true, nt: 'ACh', perSide: EYE.cols, region: 'Lobula', role: 'Looming speed' },
  LPLC2: { input: true, nt: 'ACh', perSide: EYE.cols, region: 'Lobula plate', role: 'Looming size' },
  HS: { input: true, nt: 'ACh', perSide: 3, region: 'Lobula plate', role: 'Horizontal optic flow' },
  vPN: { input: true, nt: 'ACh', perSide: COLOR_CHANNELS.length * 6, region: 'Medulla', role: 'Color input to mushroom body' },
  MECH: { input: true, nt: 'ACh', perSide: 4, region: 'VNC', role: 'Wall contact ahead' },
  MECHb: { input: true, nt: 'ACh', perSide: 4, region: 'VNC', role: 'Wall contact behind' },
  NOCI: { input: true, nt: 'ACh', perSide: 3, region: 'VNC', role: 'Pain (damage)' },
  GRN: { input: true, nt: 'ACh', perSide: 3, region: 'SEZ', role: 'Sweet taste (reward)' },

  AOTU019: { nt: 'GABA', perSide: 4, region: 'AOTU', role: 'Central-field pursuit, inhibits contralateral DNs' },
  AOTU025: { nt: 'ACh', perSide: 4, region: 'AOTU', role: 'Peripheral-field pursuit, excites ipsilateral DNs' },
  KC: { nt: 'ACh', perSide: 300, region: 'Mushroom body', role: 'Sparse visual code' },
  APL: { nt: 'GABA', perSide: 2, region: 'Mushroom body', role: 'Global feedback inhibition' },
  MBON11: { nt: 'GABA', perSide: 2, region: 'MB γ1pedc', role: 'Approach output (MBON-γ1pedc>α/β)' },
  MBON01: { nt: 'Glu', sign: 1, perSide: 2, region: 'MB γ5β′2a', role: 'Avoidance output (MBON-γ5β′2a); excitatory (iGluR) in this model' },
  LALi: { nt: 'GABA', perSide: 2, region: 'LAL', role: 'Premotor interneuron that gates off pursuit' },
  PPL101: { nt: 'DA', perSide: 1, region: 'MB γ1pedc', role: 'Punishment dopamine (PPL1-γ1pedc)' },
  PAM: { nt: 'DA', perSide: 3, region: 'MB γ5', role: 'Reward dopamine (PAM-γ5)' },
  DNa02: { nt: 'ACh', perSide: 1, region: 'Descending', role: 'Steering (ipsilateral turn)' },
  DNa01: { nt: 'ACh', perSide: 1, region: 'Descending', role: 'Steering (ipsilateral turn)' },
  P9: { nt: 'ACh', perSide: 1, region: 'Descending', role: 'Forward walking' },
  MDN: { nt: 'ACh', perSide: 2, region: 'Descending', role: 'Backward walking (moonwalker)' },
  DNp01: { nt: 'ACh', perSide: 1, region: 'Descending', role: 'Giant fiber escape' },
};

// Spontaneous drive from outside the modelled circuit: Poisson events of
// `w` mV at `rate` Hz onto every neuron of the type.
export const BACKGROUND = {
  DNa02: { rate: 1500, w: 1.1 },
  DNa01: { rate: 1500, w: 1.1 },
  P9: { rate: 1700, w: 1.1 },
  MBON11: { rate: 900, w: 1.0 },
  MBON01: { rate: 900, w: 1.0 },
};

// Synapse counts per connection (weight = count x 0.275 mV, Shiu et al. 2024).
export const WIRING = {
  lc10aTo019: 40, lc10aTo025: 45, lc10aToP9: 4,
  aotu025ToDN: 14, aotu019ToDN: 22,
  lc4ToGF: 30, lplc2ToGF: 30, lc4ToContraDN: 5,
  hsToDN: 6,
  mechToContraDN: 30, mechToMDN: 22, mechbToP9: 30,
  pnToKC: 18, claws: 6,
  kcToAPL: 10, aplToKC: 60,
  kcToMBON: 10,
  mbon11To01: 130, mbon11ToDN: 14,
  mbon01ToLALi: 100, laliToAOTU: 200, laliToP9: 80, mbon01ToDN: 40, mbon01ToMDN: 110,
  gfToMDN: 12,
  nociToPPL: 30, grnToPAM: 30,
};

// Field profiles on the ipsilateral eccentricity e (degrees, 0 = straight ahead,
// negative = across the midline into the binocular zone).
const prof019 = (e) => (e < 10 ? Math.max(0, (e + 20) / 30) : e < 30 ? 1 : Math.max(0, 1 - (e - 30) / 20));
const prof025 = (e) => Math.min(1, Math.max(0, (e - 25) / 25));

export function buildConnectome(rng, wiring = WIRING) {
  const neurons = [];
  const groups = {};
  const typeNames = Object.keys(CELL_TYPES);
  // inputs first so the simulator can skip their membrane equations
  const order = [...typeNames.filter((t) => CELL_TYPES[t].input), ...typeNames.filter((t) => !CELL_TYPES[t].input)];
  for (const type of order) {
    const def = CELL_TYPES[type];
    for (let s = 0; s < 2; s++) {
      const key = `${type}_${SIDES[s]}`;
      groups[key] = [];
      for (let i = 0; i < def.perSide; i++) {
        const n = { id: neurons.length, type, side: s, idx: i };
        if (type === 'LC10a') n.col = Math.floor(i / 2);
        if (type === 'LC4' || type === 'LPLC2') n.col = i;
        if (type === 'vPN') n.channel = Math.floor(i / 6);
        neurons.push(n);
        groups[key].push(n.id);
      }
    }
  }
  const nInput = neurons.filter((n) => CELL_TYPES[n.type].input).length;

  const pre = [], post = [], count = [];
  const add = (a, b, c) => { if (c > 0) { pre.push(a); post.push(b); count.push(Math.round(c)); } };
  const G = (type, s) => groups[`${type}_${SIDES[s]}`];
  const W = wiring;

  for (let s = 0; s < 2; s++) {
    const o = 1 - s;
    const az = columnAzimuths(s);
    // Pursuit
    for (const id of G('LC10a', s)) {
      const a = az[neurons[id].col];
      const e = (s === 0 ? a : -a) / DEG; // ipsilateral eccentricity
      for (const t of G('AOTU019', s)) add(id, t, W.lc10aTo019 * prof019(e));
      for (const t of G('AOTU025', s)) add(id, t, W.lc10aTo025 * prof025(e));
      for (const t of G('P9', s)) add(id, t, W.lc10aToP9);
    }
    for (const id of G('AOTU025', s)) for (const t of [...G('DNa02', s), ...G('DNa01', s)]) add(id, t, W.aotu025ToDN);
    for (const id of G('AOTU019', s)) for (const t of [...G('DNa02', o), ...G('DNa01', o)]) add(id, t, W.aotu019ToDN);
    // Escape
    for (const id of G('LC4', s)) {
      for (const t of G('DNp01', s)) add(id, t, W.lc4ToGF);
      for (const t of G('DNa02', o)) add(id, t, W.lc4ToContraDN);
    }
    for (const id of G('LPLC2', s)) for (const t of G('DNp01', s)) add(id, t, W.lplc2ToGF);
    for (const id of G('DNp01', s)) for (const t of G('MDN', s)) add(id, t, W.gfToMDN);
    // Optomotor
    for (const id of G('HS', s)) for (const t of G('DNa02', s)) add(id, t, W.hsToDN);
    // Wall contact
    for (const id of G('MECH', s)) {
      for (const t of [...G('DNa02', o), ...G('DNa01', o)]) add(id, t, W.mechToContraDN);
      for (const t of G('MDN', s)) add(id, t, W.mechToMDN);
    }
    for (const id of G('MECHb', s)) for (const t of [...G('P9', 0), ...G('P9', 1)]) add(id, t, W.mechbToP9);
    // Mushroom body: random claws, one hemisphere per eye
    const pns = G('vPN', s);
    for (const kc of G('KC', s)) {
      for (let k = 0; k < W.claws; k++) add(pns[rng.int(pns.length)], kc, W.pnToKC * (0.7 + 0.6 * rng.next()));
      for (const a of G('APL', s)) { add(kc, a, W.kcToAPL); add(a, kc, W.aplToKC); }
      for (const m of G('MBON11', s)) add(kc, m, W.kcToMBON);
      for (const m of G('MBON01', s)) add(kc, m, W.kcToMBON);
    }
    for (const m of G('MBON11', s)) {
      for (const t of G('MBON01', s)) add(m, t, W.mbon11To01);
      for (const t of [...G('DNa02', o), ...G('DNa01', o)]) add(m, t, W.mbon11ToDN);
    }
    for (const m of G('MBON01', s)) {
      for (const t of G('LALi', s)) add(m, t, W.mbon01ToLALi);
      for (const t of [...G('DNa02', o), ...G('DNa01', o)]) add(m, t, W.mbon01ToDN);
      for (const t of G('MDN', s)) add(m, t, W.mbon01ToMDN);
    }
    for (const id of G('LALi', s)) {
      for (const t of [...G('AOTU019', s), ...G('AOTU025', s)]) add(id, t, W.laliToAOTU);
      for (const t of G('P9', s)) add(id, t, W.laliToP9);
    }
    // Reinforcement pathways reach both hemispheres
    for (const id of G('NOCI', s)) for (const t of [...G('PPL101', 0), ...G('PPL101', 1)]) add(id, t, W.nociToPPL);
    for (const id of G('GRN', s)) for (const t of [...G('PAM', 0), ...G('PAM', 1)]) add(id, t, W.grnToPAM);
  }

  return finalize({ neurons, groups, nInput, pre, post, count, scrambled: false });
}

function finalize(c) {
  const N = c.neurons.length;
  const sign = new Int8Array(N), isInput = new Uint8Array(N), typeIdx = new Uint8Array(N);
  const typeNames = Object.keys(CELL_TYPES);
  c.neurons.forEach((n, i) => {
    const d = CELL_TYPES[n.type];
    sign[i] = d.sign ?? NT_SIGN[d.nt];
    isInput[i] = d.input ? 1 : 0;
    typeIdx[i] = typeNames.indexOf(n.type);
  });
  return {
    ...c, N, sign, isInput, typeIdx, typeNames,
    pre: Int32Array.from(c.pre), post: Int32Array.from(c.post), count: Float32Array.from(c.count),
  };
}

// Degree- and sign-preserving shuffle: every neuron keeps its number of input
// and output synapses and its transmitter (Dale's law), but who talks to whom
// is randomized. Sensory inputs and motor readouts stay where they are.
export function scrambleConnectome(conn, rng) {
  const E = conn.pre.length;
  const perm = rng.shuffle(Array.from({ length: E }, (_, i) => i));
  const post = new Int32Array(E);
  for (let i = 0; i < E; i++) post[i] = conn.post[perm[i]];
  // remove self-loops by swapping with a random partner
  for (let i = 0; i < E; i++) {
    if (post[i] !== conn.pre[i]) continue;
    for (let tries = 0; tries < 20; tries++) {
      const j = rng.int(E);
      if (post[j] !== conn.pre[i] && post[i] !== conn.pre[j]) { const t = post[i]; post[i] = post[j]; post[j] = t; break; }
    }
  }
  return { ...conn, post, scrambled: true };
}

export function connectomeSummary(conn) {
  const byType = {};
  for (const n of conn.neurons) byType[n.type] = (byType[n.type] || 0) + 1;
  let syn = 0;
  for (let i = 0; i < conn.count.length; i++) syn += conn.count[i];
  return { neurons: conn.N, connections: conn.pre.length, synapses: syn, byType };
}

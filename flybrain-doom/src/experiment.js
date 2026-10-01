// The test engine: run flies through protocols, with controls, and decide who learned.
//
// Design (classic fly conditioning, adapted to the game):
//  * Each subject is one fly: its own random Kenyon-cell wiring and noise seed.
//  * Which orb color heals is counterbalanced across subjects (even = blue,
//    odd = green). Any innate color bias cancels in the group mean, so a group
//    preference for the healing color can only come from learning.
//  * Every condition sees the same flies and the same worlds; only the
//    manipulation differs, so comparisons are paired by subject.
//  * Reversal: after acquisition the colors swap meaning. A fly that learned
//    has to unlearn and relearn; fixed wiring cannot follow the swap.

import { World, otherColor } from './world.js';
import { FlyAgent, RandomAgent } from './agent.js';
import { hashSeed } from './rng.js';
import { mean, sem, oneSampleT, signFlipTest, bootstrapCI, cohenD, fmtP, pEq } from './stats.js';

export const CONDITIONS = {
  intact: { label: 'Intact fly', about: 'Full model with dopamine-gated plasticity.' },
  'no-dopamine': { label: 'Dopamine blocked', silence: ['PPL101', 'PAM'], about: 'PPL1 and PAM dopamine neurons silenced, so reinforcement never reaches the mushroom body.' },
  'kc-block': { label: 'Kenyon cells blocked', silence: ['KC'], about: 'Mushroom body intrinsic neurons silenced: no learned output at all.' },
  scrambled: { label: 'Scrambled wiring', scramble: true, about: 'Every synapse rewired at random, keeping each neuron’s in/out degree and transmitter.' },
  'lc10a-lesion': { label: 'LC10a lesion', silence: ['LC10a'], about: 'Small-object detectors silenced: no innate pursuit or aiming.' },
  random: { label: 'Random policy', random: true, about: 'No brain. Random turns, random trigger pulls.' },
};

export const PROTOCOLS = {
  learning: {
    label: 'Valence learning + reversal', scenario: 'forage', subjects: 16, acquisition: 12, reversal: 6, block: 3,
    conditions: ['intact', 'no-dopamine', 'kc-block', 'scrambled', 'random'],
  },
  combat: {
    label: 'Imp combat', scenario: 'combat', subjects: 12, acquisition: 10, reversal: 0, block: 3,
    conditions: ['intact', 'no-dopamine', 'lc10a-lesion', 'scrambled', 'random'],
  },
  quick: {
    label: 'Quick learning check', scenario: 'forage', subjects: 6, acquisition: 6, reversal: 3, block: 3,
    conditions: ['intact', 'no-dopamine', 'random'],
  },
};

export function makeAgent(condition, seed) {
  const c = CONDITIONS[condition];
  if (!c) throw new Error(`unknown condition ${condition}`);
  if (c.random) return new RandomAgent({ seed });
  return new FlyAgent({ seed, silence: c.silence || [], scramble: !!c.scramble });
}

export function subjectSeed(baseSeed, subject) { return hashSeed(baseSeed, 'fly', subject); }
export function worldSeed(baseSeed, subject, ep) { return hashSeed(baseSeed, 'world', subject, ep); }
export const goodColorFor = (subject) => (subject % 2 === 0 ? 'blue' : 'green');

export function runEpisode(agent, world, onTic) {
  agent.beginEpisode();
  let ev = null;
  while (!world.done) {
    const action = agent.act(world, ev);
    ev = world.step(action);
    if (onTic) onTic(world, agent, action, ev);
  }
  const s = world.stats;
  const n = s.good + s.bad;
  return {
    good: s.good, bad: s.bad, pi: n ? (s.good - s.bad) / n : 0,
    kills: s.kills, shots: s.shots, hits: s.hits, damage: s.damage, healed: s.healed,
    survived: +world.time.toFixed(2), died: !world.player.alive, distance: +s.distance.toFixed(1), bumps: s.bumps,
    touches: s.touches,
  };
}

// Run every episode of one subject under one condition.
export function runSubject({ protocol, condition, subject, baseSeed = 1, onEpisode }) {
  const P = typeof protocol === 'string' ? PROTOCOLS[protocol] : protocol;
  const agent = makeAgent(condition, subjectSeed(baseSeed, subject));
  const firstGood = goodColorFor(subject);
  const total = P.acquisition + P.reversal;
  const episodes = [];
  for (let ep = 0; ep < total; ep++) {
    const phase = ep < P.acquisition ? 'acq' : 'rev';
    const goodColor = phase === 'acq' ? firstGood : otherColor(firstGood);
    const world = new World({ scenario: P.scenario, seed: worldSeed(baseSeed, subject, ep), goodColor });
    const m = runEpisode(agent, world);
    const mem = agent.memory();
    m.ep = ep; m.phase = phase; m.goodColor = goodColor;
    m.memory = Object.fromEntries(Object.entries(mem).map(([k, v]) => [k, +v.valence.toFixed(3)]));
    episodes.push(m);
    if (onEpisode) onEpisode(m);
  }
  return { condition, subject, firstGood, episodes };
}

export function* tasksFor(P) {
  for (const condition of P.conditions) for (let subject = 0; subject < P.subjects; subject++) yield { condition, subject };
}

// ---------- analysis ----------

// Encounter-level analysis: every orb touch in order, binned.
export const TOUCH_BIN = 4;
export const TOUCH_BINS = 10;
function piOfTouches(str) {
  let g = 0, b = 0;
  for (const ch of str) (ch === 'g' ? g++ : b++);
  return g + b ? (g - b) / (g + b) : null;
}
function touchCurve(seqs) {
  const out = [];
  for (let k = 0; k < TOUCH_BINS; k++) {
    const v = seqs.map((q) => piOfTouches(q.slice(k * TOUCH_BIN, (k + 1) * TOUCH_BIN))).filter((x) => x !== null);
    out.push({ bin: k, from: k * TOUCH_BIN + 1, to: (k + 1) * TOUCH_BIN, mean: mean(v), sem: sem(v), n: v.length });
  }
  return out;
}
// paired values where both exist
function pairs(a, b) {
  const d = [];
  for (let i = 0; i < Math.min(a.length, b.length); i++) if (a[i] !== null && b[i] !== null) d.push(a[i] - b[i]);
  return d;
}

// Pooled preference index over a set of episodes: (good - bad) / (good + bad)
function blockPI(eps) {
  let g = 0, b = 0;
  for (const e of eps) { g += e.good; b += e.bad; }
  return g + b ? (g - b) / (g + b) : 0;
}
const per = (eps, f) => mean(eps.map(f));

export function analyze(P, results, { alpha = 0.05 } = {}) {
  const B = P.block;
  const byCond = {};
  for (const r of results) (byCond[r.condition] ||= []).push(r);
  for (const k in byCond) byCond[k].sort((a, b) => a.subject - b.subject);
  const total = P.acquisition + P.reversal;
  const out = { protocol: P, conditions: {}, comparisons: [], verdicts: [] };

  for (const cond of P.conditions) {
    const subs = byCond[cond] || [];
    if (!subs.length) continue;
    const curve = [];
    for (let ep = 0; ep < total; ep++) {
      const v = subs.map((s) => s.episodes[ep]?.pi).filter((x) => x !== undefined);
      curve.push({ ep, mean: mean(v), sem: sem(v) });
    }
    const acq = (s) => s.episodes.slice(0, P.acquisition);
    const rev = (s) => s.episodes.slice(P.acquisition);
    const seqAcq = subs.map((s) => acq(s).map((e) => e.touches || '').join(''));
    const seqRev = subs.map((s) => rev(s).map((e) => e.touches || '').join(''));
    const early = subs.map((s) => blockPI(acq(s).slice(0, B)));
    const late = subs.map((s) => blockPI(acq(s).slice(-B)));
    const all = subs.map((s) => blockPI(acq(s)));
    const c = {
      label: CONDITIONS[cond].label, about: CONDITIONS[cond].about, n: subs.length, curve,
      early: { mean: mean(early), sem: sem(early), values: early },
      late: { mean: mean(late), sem: sem(late), values: late, ci: bootstrapCI(late), perm: signFlipTest(late), t: oneSampleT(late) },
      overall: { mean: mean(all), sem: sem(all), values: all },
      learningIndex: (() => { const d = late.map((x, i) => x - early[i]); return { mean: mean(d), sem: sem(d), perm: signFlipTest(d) }; })(),
      pickups: per(subs.flatMap(acq), (e) => e.good + e.bad),
      kills: per(subs.flatMap(acq), (e) => e.kills),
      accuracy: (() => { const sh = subs.flatMap(acq).reduce((s, e) => s + e.shots, 0); const h = subs.flatMap(acq).reduce((s, e) => s + e.hits, 0); return sh ? h / sh : 0; })(),
      damage: per(subs.flatMap(acq), (e) => e.damage),
      survived: per(subs.flatMap(acq), (e) => e.survived),
      deaths: per(subs.flatMap(acq), (e) => (e.died ? 1 : 0)),
      killsEarly: mean(subs.map((s) => per(acq(s).slice(0, B), (e) => e.kills))),
      killsLate: mean(subs.map((s) => per(acq(s).slice(-B), (e) => e.kills))),
      damageEarly: mean(subs.map((s) => per(acq(s).slice(0, B), (e) => e.damage))),
      damageLate: mean(subs.map((s) => per(acq(s).slice(-B), (e) => e.damage))),
      damageLateValues: subs.map((s) => per(acq(s).slice(-B), (e) => e.damage)),
      killsLateValues: subs.map((s) => per(acq(s).slice(-B), (e) => e.kills)),
    };
    const naive = seqAcq.map((q) => piOfTouches(q.slice(0, TOUCH_BIN)));
    const naiveV = naive.filter((x) => x !== null);
    c.naive = { mean: mean(naiveV), sem: sem(naiveV), n: naiveV.length, values: naive, perm: signFlipTest(naiveV) };
    c.touchCurve = { acq: touchCurve(seqAcq) };
    if (P.reversal > 0) {
      c.touchCurve.rev = touchCurve(seqRev);
      const swapT = seqRev.map((q) => piOfTouches(q.slice(0, TOUCH_BIN)));
      const swapV = swapT.filter((x) => x !== null);
      const carry = pairs(late, swapT);
      const revFirst = subs.map((s) => blockPI(rev(s).slice(0, Math.min(B, P.reversal))));
      const revLast = subs.map((s) => blockPI(rev(s).slice(-Math.min(B, P.reversal))));
      const drop = revFirst.map((x, i) => late[i] - x);
      c.reversal = {
        firstTouches: { mean: mean(swapV), sem: sem(swapV), n: swapV.length, values: swapT, perm: signFlipTest(swapV) },
        carryOver: { mean: mean(carry), sem: sem(carry), n: carry.length, perm: signFlipTest(carry) },
        first: { mean: mean(revFirst), sem: sem(revFirst), values: revFirst },
        last: { mean: mean(revLast), sem: sem(revLast), values: revLast, perm: signFlipTest(revLast) },
        drop: { mean: mean(drop), sem: sem(drop), perm: signFlipTest(drop) },
      };
    }
    out.conditions[cond] = c;
  }

  // Compare every condition with the intact fly, paired by subject.
  const ref = out.conditions.intact;
  if (ref) {
    for (const cond of P.conditions) {
      if (cond === 'intact' || !out.conditions[cond]) continue;
      const o = out.conditions[cond];
      const n = Math.min(ref.late.values.length, o.late.values.length);
      const d = ref.late.values.slice(0, n).map((x, i) => x - o.late.values[i]);
      const dmg = ref.damageLateValues.slice(0, n).map((x, i) => x - o.damageLateValues[i]);
      const kil = ref.killsLateValues.slice(0, n).map((x, i) => x - o.killsLateValues[i]);
      out.comparisons.push({
        a: 'intact', b: cond, metric: 'late PI', diff: mean(d), sem: sem(d), perm: signFlipTest(d),
        d: cohenD(ref.late.values, o.late.values),
        damageDiff: mean(dmg), damagePerm: signFlipTest(dmg), killsDiff: mean(kil), killsPerm: signFlipTest(kil),
      });
    }
  }

  // Verdict per condition
  for (const cond of P.conditions) {
    const c = out.conditions[cond];
    if (!c) continue;
    let verdict, why;
    if (P.scenario === 'combat') {
      const cmp = out.comparisons.find((x) => x.b === cond);
      verdict = c.kills > 0.5 ? 'Fights' : 'Does not fight';
      why = `${c.kills.toFixed(2)} kills/episode at ${(c.accuracy * 100).toFixed(0)}% accuracy, ${c.damage.toFixed(0)} damage taken`;
      if (cmp) { const d = -cmp.killsDiff; why += `; ${d >= 0 ? '+' : '−'}${Math.abs(d).toFixed(2)} kills/episode vs intact (${pEq(cmp.killsPerm.p)})`; }
    } else {
      const learned = c.late.mean > 0 && c.late.perm.p < alpha;
      // Re-learning: the old memory shows up right after the swap (preference
      // falls below the trained level) and the new preference is in place by the end.
      const reverses = c.reversal ? c.reversal.carryOver.mean > 0 && c.reversal.carryOver.perm.p < alpha
        && c.reversal.last.mean > 0 && c.reversal.last.perm.p < alpha : null;
      if (learned && reverses) verdict = 'Learns and re-learns';
      else if (learned) verdict = 'Learns';
      else verdict = 'No evidence of learning';
      why = `late PI ${c.late.mean.toFixed(2)} ± ${c.late.sem.toFixed(2)} (${pEq(c.late.perm.p)})`;
      if (c.reversal) why += `; first ${TOUCH_BIN} touches after the swap ${c.reversal.firstTouches.mean.toFixed(2)} (drop ${pEq(c.reversal.carryOver.perm.p)}), last block ${c.reversal.last.mean.toFixed(2)} (${pEq(c.reversal.last.perm.p)})`;
    }
    out.verdicts.push({ condition: cond, label: c.label, verdict, why });
  }
  return out;
}

// Drop per-fly arrays so the analysis is small enough to embed in the web page.
export function slimAnalysis(A) {
  return JSON.parse(JSON.stringify(A, (k, v) => (k === 'values' || k.endsWith('Values') ? undefined : typeof v === 'number' ? +v.toPrecision(4) : v)));
}

const SPARK = ' ▁▂▃▄▅▆▇█';
function sparkline(values, lo = -1, hi = 1) {
  return values.map((v) => SPARK[Math.max(0, Math.min(8, Math.round(((v - lo) / (hi - lo)) * 8)))]).join('');
}
const f2 = (x) => (isFinite(x) ? (x >= 0 ? ' ' : '') + x.toFixed(2) : ' n/a');

export function reportMarkdown(A, meta = {}) {
  const P = A.protocol, L = [];
  L.push(`## ${P.label}`);
  L.push('');
  L.push(`Scenario \`${P.scenario}\`, ${P.subjects} flies per condition, ${P.acquisition} acquisition episodes` + (P.reversal ? ` then ${P.reversal} reversal episodes` : '') + `, blocks of ${P.block}.` + (meta.seed !== undefined ? ` Base seed ${meta.seed}.` : ''));
  L.push('');
  L.push('| Condition | Verdict | Evidence |');
  L.push('|---|---|---|');
  for (const v of A.verdicts) L.push(`| ${v.label} | **${v.verdict}** | ${v.why} |`);
  L.push('');
  if (P.scenario !== 'combat') {
    L.push('Preference index PI = (healing orbs − burning orbs) / all orbs touched, scored against whichever color currently heals. 0 = no preference, 1 = only healing orbs.');
    L.push('');
    L.push(`| Condition | First ${TOUCH_BIN} touches | Late PI | 95% CI | Orbs/episode` + (P.reversal ? ` | First ${TOUCH_BIN} touches after swap | Last block after swap` : '') + ' |');
    L.push('|---|---|---|---|---|' + (P.reversal ? '---|---|' : ''));
    const pm = (x) => `${f2(x.mean)} ± ${(x.sem || 0).toFixed(2)}`;
    for (const c of Object.values(A.conditions)) {
      L.push(`| ${c.label} | ${pm(c.naive)} | ${pm(c.late)} | [${c.late.ci[0].toFixed(2)}, ${c.late.ci[1].toFixed(2)}] | ${c.pickups.toFixed(1)}` + (c.reversal ? ` | ${pm(c.reversal.firstTouches)} | ${pm(c.reversal.last)}` : '') + ' |');
    }
    L.push('');
    L.push(`Learning curves by encounter (mean PI over successive bins of ${TOUCH_BIN} orb touches, −1 to +1` + (P.reversal ? '; | marks the color swap' : '') + '):');
    L.push('');
    L.push('```');
    for (const c of Object.values(A.conditions)) {
      const line = (cv) => sparkline(cv.map((x) => (isFinite(x.mean) ? x.mean : 0)));
      L.push(`${c.label.padEnd(22)} ${line(c.touchCurve.acq)}${c.touchCurve.rev ? '|' + line(c.touchCurve.rev) : ''}`);
    }
    L.push('```');
    L.push('');
    L.push('Learning curves by episode:');
    L.push('');
    L.push('```');
    for (const c of Object.values(A.conditions)) {
      const sp = sparkline(c.curve.map((x) => x.mean));
      L.push(`${c.label.padEnd(22)} ${P.reversal ? sp.slice(0, P.acquisition) + '|' + sp.slice(P.acquisition) : sp}`);
    }
    L.push('```');
    L.push('');
    if (A.comparisons.length) {
      L.push('Intact vs each control (late PI, paired by fly):');
      L.push('');
      L.push('| Comparison | Δ late PI | p (permutation) | Cohen’s d |');
      L.push('|---|---|---|---|');
      for (const c of A.comparisons) L.push(`| intact − ${A.conditions[c.b].label} | ${f2(c.diff)} ± ${c.sem.toFixed(2)} | ${fmtP(c.perm.p)} | ${c.d.toFixed(2)} |`);
      L.push('');
    }
  } else {
    L.push('| Condition | Kills/episode | Accuracy | Damage/episode | Survival (s) | Deaths/episode | Kills early→late | Damage early→late |');
    L.push('|---|---|---|---|---|---|---|---|');
    for (const c of Object.values(A.conditions)) {
      L.push(`| ${c.label} | ${c.kills.toFixed(2)} | ${(c.accuracy * 100).toFixed(0)}% | ${c.damage.toFixed(1)} | ${c.survived.toFixed(1)} | ${c.deaths.toFixed(2)} | ${c.killsEarly.toFixed(2)} → ${c.killsLate.toFixed(2)} | ${c.damageEarly.toFixed(0)} → ${c.damageLate.toFixed(0)} |`);
    }
    L.push('');
    if (A.comparisons.length) {
      L.push('Intact vs each control in the last block (paired by fly):');
      L.push('');
      L.push('| Comparison | Δ kills/episode | p | Δ damage/episode | p |');
      L.push('|---|---|---|---|---|');
      for (const c of A.comparisons) L.push(`| intact − ${A.conditions[c.b].label} | ${f2(c.killsDiff)} | ${fmtP(c.killsPerm.p)} | ${f2(c.damageDiff)} | ${fmtP(c.damagePerm.p)} |`);
      L.push('');
    }
  }
  return L.join('\n');
}

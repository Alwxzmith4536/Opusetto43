#!/usr/bin/env node
/*
 * FlyDoom test engine: runs controlled learning experiments and reports whether the
 * fly brain actually learns, compared with the same brain frozen, scrambled, lesioned,
 * and a random agent.
 *
 *   node flydoom/test-engine.js                     # default experiment
 *   node flydoom/test-engine.js --quick             # fast smoke run
 *   node flydoom/test-engine.js --episodes 60 --seeds 1,2,3,4,5 --conditions learning,frozen
 *   node flydoom/test-engine.js --out results.json  # also save raw per-episode data
 */
'use strict';
const fs = require('fs');
const F = require('./flydoom.js');
const { mean, sem, welch, slope } = F.stats;

function parseArgs(argv) {
  const args = { episodes: 30, seeds: [1, 2, 3], conditions: Object.keys(F.CONDITIONS), window: 10, out: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i], next = () => argv[++i];
    if (a === '--quick') { args.episodes = 8; args.seeds = [1, 2]; args.window = 4; }
    else if (a === '--episodes') args.episodes = +next();
    else if (a === '--seeds') args.seeds = next().split(',').map(Number);
    else if (a === '--conditions') args.conditions = next().split(',');
    else if (a === '--window') args.window = +next();
    else if (a === '--out') args.out = next();
    else if (a === '--help' || a === '-h') { console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0]); process.exit(0); }
    else throw new Error('Unknown argument: ' + a);
  }
  for (const c of args.conditions) if (!F.CONDITIONS[c]) throw new Error('Unknown condition: ' + c);
  args.window = Math.max(1, Math.min(args.window, Math.floor(args.episodes / 2) || 1));
  return args;
}

function runExperiment({ episodes, seeds, conditions, onEpisode }) {
  const results = {};
  for (const condition of conditions) {
    results[condition] = [];
    for (const seed of seeds) {
      const sim = new F.Simulation({ condition, seed });
      const runs = [];
      for (let e = 0; e < episodes; e++) {
        runs.push(sim.runEpisode());
        if (onEpisode) onEpisode(condition, seed, e);
      }
      results[condition].push({ seed, episodes: runs, brain: sim.agent.stats ? sim.agent.stats() : null,
        mbon: sim.agent.mbonWeights ? sim.agent.mbonWeights() : null });
    }
  }
  return results;
}

/** Per condition: first/last-window means per seed, curve slope, accuracy and survival. */
function summarize(results, window) {
  const summary = {};
  for (const [condition, seedRuns] of Object.entries(results)) {
    const first = [], last = [], slopes = [], acc = [], surv = [], lastAll = [];
    for (const r of seedRuns) {
      const kills = r.episodes.map((e) => e.kills);
      first.push(mean(kills.slice(0, window)));
      last.push(mean(kills.slice(-window)));
      lastAll.push(...kills.slice(-window));
      slopes.push(slope(kills));
      acc.push(mean(r.episodes.slice(-window).map((e) => e.accuracy)));
      surv.push(mean(r.episodes.slice(-window).map((e) => (e.survived ? 1 : 0))));
    }
    const n = seedRuns[0].episodes.length;
    const curve = [];
    for (let e = 0; e < n; e++) curve.push(mean(seedRuns.map((r) => r.episodes[e].kills)));
    summary[condition] = {
      label: F.CONDITIONS[condition].label,
      firstKills: mean(first), lastKills: mean(last), lastSem: sem(lastAll), lastAll,
      improvement: mean(last) - mean(first), slope: mean(slopes),
      accuracy: mean(acc), survival: mean(surv), curve,
      neurons: seedRuns[0].brain ? seedRuns[0].brain.neurons : 0,
      synapses: seedRuns[0].brain ? seedRuns[0].brain.synapses : 0,
    };
  }
  return summary;
}

/** Pass/fail checks — the claims the experiment is supposed to support. */
function verdicts(summary) {
  const out = [];
  const L = summary.learning;
  const check = (name, pass, detail) => out.push({ name, pass, detail });
  if (L && summary.frozen) {
    const w = welch(L.lastAll, summary.frozen.lastAll);
    check('Learning beats the same brain with plasticity off', L.lastKills > summary.frozen.lastKills && w.p < 0.05,
      `${L.lastKills.toFixed(2)} vs ${summary.frozen.lastKills.toFixed(2)} kills/ep, t=${w.t.toFixed(2)}, p≈${w.p.toFixed(4)}`);
  }
  if (L) check('Learning curve trends upward', L.improvement > 0 && L.slope > 0,
    `first→last ${L.firstKills.toFixed(2)}→${L.lastKills.toFixed(2)}, slope ${L.slope.toFixed(3)} kills/ep²`);
  if (summary.frozen && summary.random) {
    const w = welch(summary.frozen.lastAll, summary.random.lastAll);
    check('Innate fly wiring alone beats random play', summary.frozen.lastKills > summary.random.lastKills && w.p < 0.05,
      `${summary.frozen.lastKills.toFixed(2)} vs ${summary.random.lastKills.toFixed(2)}, p≈${w.p.toFixed(4)}`);
  }
  if (L && summary.scrambled) {
    const w = welch(L.lastAll, summary.scrambled.lastAll);
    check('Real (structured) wiring beats scrambled wiring', L.lastKills > summary.scrambled.lastKills && w.p < 0.05,
      `${L.lastKills.toFixed(2)} vs ${summary.scrambled.lastKills.toFixed(2)}, p≈${w.p.toFixed(4)}`);
  }
  if (L && summary['mb-lesion']) {
    check('Mushroom-body lesion removes the learning benefit', summary['mb-lesion'].lastKills < L.lastKills,
      `${summary['mb-lesion'].lastKills.toFixed(2)} vs ${L.lastKills.toFixed(2)}`);
  }
  return out;
}

const SPARK = '▁▂▃▄▅▆▇█';
function sparkline(ys, max) {
  return ys.map((y) => SPARK[Math.max(0, Math.min(7, Math.round((y / (max || 1)) * 7)))]).join('');
}

function report(summary, checks, args) {
  const pad = (s, n) => String(s).padEnd(n);
  const lines = [];
  lines.push(`FlyDoom test engine — ${args.episodes} episodes × ${args.seeds.length} seeds, window ${args.window}`);
  const any = Object.values(summary).find((s) => s.neurons);
  if (any) lines.push(`Brain: ${any.neurons} LIF neurons, ${any.synapses} synapses`);
  lines.push('');
  lines.push(pad('condition', 12) + pad('first', 7) + pad('last ± sem', 14) + pad('Δ', 7) + pad('acc', 6) + pad('surv', 6) + 'kills per episode');
  const max = Math.max(...Object.values(summary).flatMap((s) => s.curve));
  for (const [c, s] of Object.entries(summary)) {
    lines.push(pad(c, 12) + pad(s.firstKills.toFixed(2), 7) + pad(`${s.lastKills.toFixed(2)} ± ${s.lastSem.toFixed(2)}`, 14) +
      pad((s.improvement >= 0 ? '+' : '') + s.improvement.toFixed(2), 7) + pad(s.accuracy.toFixed(2), 6) +
      pad(s.survival.toFixed(2), 6) + sparkline(s.curve, max));
  }
  lines.push('');
  for (const v of checks) lines.push(`${v.pass ? 'PASS' : 'FAIL'}  ${v.name}\n      ${v.detail}`);
  return lines.join('\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const total = args.conditions.length * args.seeds.length * args.episodes;
  let done = 0;
  const t0 = Date.now();
  const results = runExperiment(Object.assign({}, args, {
    onEpisode: () => {
      done++;
      if (process.stderr.isTTY) process.stderr.write(`\r  running ${done}/${total} episodes…`);
    },
  }));
  if (process.stderr.isTTY) process.stderr.write('\r\x1b[K');
  const summary = summarize(results, args.window);
  const checks = verdicts(summary);
  console.log(report(summary, checks, args));
  console.log(`\n(${((Date.now() - t0) / 1000).toFixed(1)} s)`);
  if (args.out) {
    fs.writeFileSync(args.out, JSON.stringify({ args, summary, checks, results }, null, 1));
    console.log('Saved', args.out);
  }
  process.exitCode = checks.every((c) => c.pass) ? 0 : 1;
}

if (require.main === module) main();
module.exports = { parseArgs, runExperiment, summarize, verdicts, report };

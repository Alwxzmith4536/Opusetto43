#!/usr/bin/env node
// Run test-engine protocols from the command line, in parallel worker threads.
//
//   node cli/run.mjs                         # learning + combat protocols
//   node cli/run.mjs --protocol quick        # fast smoke test
//   node cli/run.mjs --protocol learning --subjects 24 --workers 8 --seed 42
//
// Writes results/<protocol>.json and results/REPORT.md.

import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';
import { availableParallelism } from 'node:os';
import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { PROTOCOLS, runSubject, tasksFor, analyze, reportMarkdown, slimAnalysis } from '../src/experiment.js';

const here = dirname(fileURLToPath(import.meta.url));

if (!isMainThread) {
  const { protocol, baseSeed } = workerData;
  parentPort.on('message', (task) => {
    if (task === null) { process.exit(0); }
    const r = runSubject({ protocol, condition: task.condition, subject: task.subject, baseSeed });
    parentPort.postMessage(r);
  });
} else {
  main().catch((e) => { console.error(e); process.exit(1); });
}

function parseArgs(argv) {
  const a = { protocol: 'all', seed: 1, workers: Math.max(1, availableParallelism() - 0), out: join(here, '..', 'results') };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i].replace(/^--/, ''), v = argv[i + 1];
    if (['protocol', 'out'].includes(k)) { a[k] = v; i++; }
    else if (['seed', 'workers', 'subjects', 'acquisition', 'reversal'].includes(k)) { a[k] = Number(v); i++; }
    else if (k === 'conditions') { a.conditions = v.split(','); i++; }
    else if (k === 'help' || k === 'h') { a.help = true; }
  }
  return a;
}

async function runProtocol(name, args) {
  const P = { ...PROTOCOLS[name] };
  if (!P.scenario) throw new Error(`unknown protocol ${name}; choose from ${Object.keys(PROTOCOLS).join(', ')}`);
  for (const k of ['subjects', 'acquisition', 'reversal', 'conditions']) if (args[k] !== undefined) P[k] = args[k];
  const tasks = [...tasksFor(P)];
  const nW = Math.min(args.workers, tasks.length);
  const t0 = Date.now();
  console.log(`\n${P.label}: ${tasks.length} fly runs (${P.conditions.length} conditions x ${P.subjects} flies x ${P.acquisition + P.reversal} episodes) on ${nW} workers`);
  const results = [];
  await new Promise((resolve, reject) => {
    let next = 0, done = 0;
    for (let w = 0; w < nW; w++) {
      const worker = new Worker(fileURLToPath(import.meta.url), { workerData: { protocol: P, baseSeed: args.seed } });
      const feed = () => worker.postMessage(next < tasks.length ? tasks[next++] : null);
      worker.on('message', (r) => {
        results.push(r);
        done++;
        const pct = ((done / tasks.length) * 100).toFixed(0).padStart(3);
        process.stdout.write(`\r  ${pct}%  ${done}/${tasks.length}  ${((Date.now() - t0) / 1000).toFixed(0)}s   `);
        if (done === tasks.length) resolve();
        feed();
      });
      worker.on('error', reject);
      feed();
    }
  });
  process.stdout.write('\n');
  const A = analyze(P, results);
  const md = reportMarkdown(A, { seed: args.seed });
  mkdirSync(args.out, { recursive: true });
  writeFileSync(join(args.out, `${name}.json`), JSON.stringify({ protocol: P, seed: args.seed, results }, null, 0));
  // compact analysis that the web app shows before you run anything
  const refPath = join(args.out, 'reference.json');
  let ref = {};
  try { if (existsSync(refPath)) ref = JSON.parse(readFileSync(refPath, 'utf8')); } catch (e) { ref = {}; }
  if (name !== 'quick') { ref[name] = slimAnalysis(A); ref.seed = args.seed; ref.generated = new Date().toISOString(); }
  writeFileSync(refPath, JSON.stringify(ref));
  console.log('\n' + md);
  return { name, md, seconds: (Date.now() - t0) / 1000 };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log('usage: node cli/run.mjs [--protocol learning|combat|quick|all] [--subjects n] [--acquisition n] [--reversal n] [--conditions a,b] [--workers n] [--seed n] [--out dir]');
    return;
  }
  const names = args.protocol === 'all' ? ['learning', 'combat'] : [args.protocol];
  const parts = [];
  for (const n of names) parts.push(await runProtocol(n, args));
  const header = [
    '# Fly brain test engine report',
    '',
    `Generated ${new Date().toISOString()} with \`node cli/run.mjs --protocol ${args.protocol} --seed ${args.seed}\`.`,
    'Inference: two-sided permutation tests (exact sign-flip when n <= 16). Values are mean ± SEM across flies.',
    '',
  ];
  writeFileSync(join(args.out, 'REPORT.md'), header.join('\n') + parts.map((p) => p.md).join('\n\n') + '\n');
  console.log(`\nWrote ${join(args.out, 'REPORT.md')}`);
}

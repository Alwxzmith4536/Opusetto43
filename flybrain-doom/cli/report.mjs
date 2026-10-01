#!/usr/bin/env node
// Re-analyze saved results without re-running the simulation.
//   node cli/report.mjs results/learning.json results/combat.json
//   node cli/report.mjs --write results/learning.json results/combat.json
// With --write it also regenerates results/REPORT.md and results/reference.json.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { analyze, reportMarkdown, slimAnalysis } from '../src/experiment.js';

const args = process.argv.slice(2);
const write = args.includes('--write');
const files = args.filter((a) => !a.startsWith('--'));
if (!files.length) { console.error('usage: node cli/report.mjs [--write] <results.json> [...]'); process.exit(1); }
const parts = [], ref = {};
let seed;
for (const f of files) {
  const data = JSON.parse(readFileSync(f, 'utf8'));
  seed = data.seed;
  const A = analyze(data.protocol, data.results);
  parts.push(reportMarkdown(A, { seed }));
  const name = f.replace(/^.*\//, '').replace(/\.json$/, '');
  if (name !== 'quick') ref[name] = slimAnalysis(A);
}
const md = parts.join('\n\n');
console.log(md);
if (write) {
  const dir = dirname(files[0]);
  const header = [
    '# Fly brain test engine report',
    '',
    `Generated ${new Date().toISOString()} from saved runs (base seed ${seed}). Reproduce with \`node cli/run.mjs --seed ${seed}\`.`,
    'Inference: two-sided permutation tests (exact sign-flip when n <= 16). Values are mean ± SEM across flies.',
    '',
  ];
  writeFileSync(join(dir, 'REPORT.md'), header.join('\n') + md + '\n');
  writeFileSync(join(dir, 'reference.json'), JSON.stringify({ ...ref, seed, generated: new Date().toISOString() }));
  console.error(`\nWrote ${join(dir, 'REPORT.md')} and ${join(dir, 'reference.json')}`);
}

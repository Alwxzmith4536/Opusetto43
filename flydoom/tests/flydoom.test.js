// Run with: node --test flydoom/tests
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const F = require('../flydoom.js');
const engine = require('../test-engine.js');

test('map is rectangular and walled in', () => {
  const m = F.DEFAULT_MAP;
  for (const row of m) assert.equal(row.length, m[0].length);
  assert.ok(/^#+$/.test(m[0]) && /^#+$/.test(m[m.length - 1]));
  for (const row of m) assert.ok(row[0] === '#' && row[row.length - 1] === '#');
});

test('RNG is deterministic per seed', () => {
  const a = new F.Rng(42), b = new F.Rng(42), c = new F.Rng(43);
  const xs = Array.from({ length: 5 }, () => a.float());
  assert.deepEqual(xs, Array.from({ length: 5 }, () => b.float()));
  assert.notDeepEqual(xs, Array.from({ length: 5 }, () => c.float()));
});

test('raycast hits the wall at the expected distance', () => {
  const w = new F.DoomWorld({ seed: 1 });
  w.player.x = 1.5; w.player.y = 1.5; w.player.a = Math.PI; // facing west, wall at x=1
  assert.ok(Math.abs(w.castRay(Math.PI).dist - 0.5) < 1e-6);
});

test('firing at a centred, visible enemy hits it and kills after enemyHp shots', () => {
  const w = new F.DoomWorld({ seed: 1, enemySpeed: 0 });
  w.player.x = 8.5; w.player.y = 6.5; w.player.a = 0;
  w.enemies = [{ id: 1, x: 11.5, y: 6.5, hp: 2, cooldown: 99, flash: 0 }];
  let r = w.step({ fire: true });
  assert.ok(r.events.includes('hit'));
  for (let i = 0; i < w.opts.fireCooldown; i++) w.step({});
  r = w.step({ fire: true });
  assert.ok(r.events.includes('kill'));
  assert.equal(w.kills, 1);
  assert.ok(r.reward > 0.9);
});

test('firing at empty space is a miss with negative reward', () => {
  const w = new F.DoomWorld({ seed: 1 });
  w.enemies = [];
  const r = w.step({ fire: true });
  assert.deepEqual(r.events, ['miss']);
  assert.ok(r.reward < 0);
});

test('enemies path around walls toward the player and hurt on contact', () => {
  const w = new F.DoomWorld({ seed: 3, spawnEvery: 1e9 });
  w.player.x = 8.5; w.player.y = 6.5;
  w.enemies = [{ id: 1, x: 2.5, y: 12.5, hp: 2, cooldown: 0, flash: 0 }]; // other side of the dividing wall
  let hurt = false;
  for (let t = 0; t < 1000 && !hurt; t++) hurt = w.step({}).events.includes('hurt');
  assert.ok(hurt, 'enemy should reach the player');
});

test('compound eye sees an enemy on the correct side', () => {
  const w = new F.DoomWorld({ seed: 1 });
  w.player.x = 8.5; w.player.y = 6.5; w.player.a = 0;
  const eye = new F.CompoundEye();
  w.enemies = [{ id: 1, x: 10.5, y: 4.5, hp: 2, cooldown: 0, flash: 0 }];
  const rel = w.relativeEnemies()[0];
  const obs = eye.sample(w);
  const C = eye.columns;
  const left = obs.object.slice(0, C / 2).reduce((a, b) => a + b, 0);
  const right = obs.object.slice(C / 2).reduce((a, b) => a + b, 0);
  if (rel.angle > 0) assert.ok(left > right); else assert.ok(right > left);
});

test('LIF neuron fires under constant drive and stays silent without it', () => {
  const net = new F.SpikingNetwork(new F.Rng(1));
  net.addPop('A', 2, { noise: 0 });
  net.finalize();
  net.ext[0] = 0.2;
  for (let t = 0; t < 100; t++) net.step();
  assert.ok(net.counts[0] > 5);
  assert.equal(net.counts[1], 0);
});

test('excitatory synapse propagates spikes, inhibitory blocks them', () => {
  const build = (w) => {
    const net = new F.SpikingNetwork(new F.Rng(1));
    net.addPop('A', 1, { noise: 0 }); net.addPop('B', 1, { noise: 0 });
    net.connect('A', 0, 'B', 0, w);
    net.finalize();
    net.ext[0] = 0.3; net.ext[1] = 0.05;
    for (let t = 0; t < 200; t++) net.step();
    return net.counts[1];
  };
  assert.ok(build(0.5) > build(0) && build(-0.5) <= build(0));
});

test('brain has the expected cell types and lesion silences them', () => {
  const b = new F.FlyBrain({ lesion: ['KC'] });
  for (const p of ['R_obj', 'L2', 'LC11', 'LC4', 'LPTC', 'KC', 'APL', 'MBON', 'PAM', 'PPL1', 'GF', 'DN_fire']) assert.ok(b.net.pops[p], p);
  const w = new F.DoomWorld({ seed: 1 });
  for (let t = 0; t < 50; t++) b.think(w);
  assert.equal(b.net.popCounts('KC').reduce((a, x) => a + x, 0), 0);
});

test('reward potentiates and punishment depresses eligible KC→MBON synapses', () => {
  const run = (reward) => {
    const b = new F.FlyBrain({ seed: 5, weightDecay: 0 });
    b.elig.fill(1);
    const before = b.W.reduce((a, x) => a + x, 0);
    b.feedback(reward);
    b.think(new F.DoomWorld({ seed: 1 }));
    return b.W.reduce((a, x) => a + x, 0) - before;
  };
  assert.ok(run(1) > 0);
  assert.ok(run(-1) < 0);
});

test('frozen brain does not change its weights', () => {
  const sim = new F.Simulation({ condition: 'frozen', seed: 2, world: { maxTicks: 200 } });
  const w0 = Float32Array.from(sim.agent.W);
  sim.runEpisode();
  assert.deepEqual(sim.agent.W, w0);
});

test('scrambled control preserves synapse count but changes wiring', () => {
  const a = new F.FlyBrain({ seed: 9 }), b = new F.FlyBrain({ seed: 9, scrambleInnate: true });
  assert.equal(a.net.targets.length, b.net.targets.length);
  assert.notDeepEqual(Array.from(a.net.targets), Array.from(b.net.targets));
});

test('simulation is reproducible for a given seed', () => {
  const run = () => new F.Simulation({ condition: 'learning', seed: 4, world: { maxTicks: 300 } }).runEpisode();
  assert.deepEqual(run(), run());
});

test('statistics helpers', () => {
  assert.equal(F.stats.mean([1, 2, 3]), 2);
  assert.equal(F.stats.slope([1, 2, 3, 4]), 1);
  const w = F.stats.welch([10, 11, 12, 10, 11, 12], [1, 2, 1, 2, 1, 2]);
  assert.ok(w.t > 5 && w.p < 0.001);
});

test('test engine smoke run produces a summary and verdicts', () => {
  const results = engine.runExperiment({ episodes: 2, seeds: [1], conditions: ['frozen', 'random'] });
  const summary = engine.summarize(results, 1);
  assert.ok(summary.frozen.curve.length === 2);
  const checks = engine.verdicts(summary);
  assert.ok(checks.some((c) => c.name.includes('random')));
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RNG, hashSeed } from '../src/rng.js';
import { MAPS } from '../src/maps.js';
import { World, TIC, DEG, ORB } from '../src/world.js';
import { buildConnectome, scrambleConnectome, CELL_TYPES } from '../src/connectome.js';
import { FlyBrain, LIF } from '../src/brain.js';
import { FlyAgent } from '../src/agent.js';
import { tPValue, signFlipTest, welchT, mean } from '../src/stats.js';
import { runSubject, analyze, PROTOCOLS } from '../src/experiment.js';

test('rng is deterministic per seed', () => {
  const a = new RNG(42), b = new RNG(42), c = new RNG(43);
  const sa = Array.from({ length: 5 }, () => a.next());
  assert.deepEqual(sa, Array.from({ length: 5 }, () => b.next()));
  assert.notDeepEqual(sa, Array.from({ length: 5 }, () => c.next()));
  assert.equal(hashSeed('fly', 1), hashSeed('fly', 1));
  assert.notEqual(hashSeed('fly', 1), hashSeed('fly', 2));
});

test('maps are rectangular and closed', () => {
  for (const m of Object.values(MAPS)) {
    assert.ok(m.open.length > 20);
    for (let x = 0; x < m.width; x++) { assert.ok(m.cells[x]); assert.ok(m.cells[(m.height - 1) * m.width + x]); }
    for (let y = 0; y < m.height; y++) { assert.ok(m.cells[y * m.width]); assert.ok(m.cells[y * m.width + m.width - 1]); }
  }
});

test('ray cast hits the arena wall at the right distance', () => {
  const w = new World({ scenario: 'forage', seed: 1 });
  // the arena's west wall occupies x in [0,1); from x=5.5 looking west the hit is 4.5 away
  const r = w.castRay(5.5, 5.5, Math.PI);
  assert.ok(Math.abs(r.dist - 4.5) < 1e-9, `got ${r.dist}`);
});

test('world is deterministic for a seed and action sequence', () => {
  const run = () => {
    const w = new World({ scenario: 'doom', seed: 9 });
    for (let i = 0; i < 300; i++) w.step({ forward: Math.sin(i / 20), turn: Math.cos(i / 31), fire: i % 9 === 0 });
    return JSON.stringify([w.player, w.stats, w.entities.map((e) => [e.kind, e.x, e.y])]);
  };
  assert.equal(run(), run());
});

test('healing orbs heal, burning orbs burn', () => {
  for (const goodColor of ['blue', 'green']) {
    const w = new World({ scenario: 'forage', seed: 3, goodColor });
    const p = w.player;
    const good = w.entities.find((e) => e.kind === 'orb' && e.color === goodColor);
    good.x = p.x + 0.2; good.y = p.y;
    let ev = w.step({});
    assert.equal(ev.good, 1); assert.equal(ev.heal, ORB.heal); assert.equal(p.health, 100 + ORB.heal);
    const bad = w.entities.find((e) => e.kind === 'orb' && e.alive && e.color !== goodColor);
    bad.x = p.x + 0.2; bad.y = p.y;
    ev = w.step({});
    assert.equal(ev.bad, 1); assert.equal(ev.damage, ORB.burn);
    assert.equal(w.stats.touches, 'gb');
  }
});

test('connectome has the declared cell counts and Dale-consistent signs', () => {
  const c = buildConnectome(new RNG(1));
  for (const [type, def] of Object.entries(CELL_TYPES)) {
    assert.equal(c.neurons.filter((n) => n.type === type).length, def.perSide * 2, type);
  }
  // every outgoing synapse of a neuron carries that neuron's sign
  for (let k = 0; k < c.pre.length; k++) assert.ok(c.count[k] > 0);
  assert.equal(c.sign[c.groups.KC_L[0]], 1);
  assert.equal(c.sign[c.groups.APL_L[0]], -1);
  assert.equal(c.sign[c.groups.MBON11_L[0]], -1);
});

test('scrambling keeps every neuron’s in- and out-degree', () => {
  const c = buildConnectome(new RNG(2));
  const s = scrambleConnectome(c, new RNG(3));
  const deg = (arr) => { const d = new Map(); for (const x of arr) d.set(x, (d.get(x) || 0) + 1); return d; };
  assert.deepEqual(deg(s.pre), deg(c.pre));
  assert.deepEqual(deg(s.post), deg(c.post));
  let changed = 0;
  for (let k = 0; k < c.post.length; k++) if (c.post[k] !== s.post[k]) changed++;
  assert.ok(changed / c.post.length > 0.9, 'most synapses should be rewired');
});

test('LIF neuron rests without input and fires near the analytic rate under constant drive', () => {
  const c = buildConnectome(new RNG(4));
  const b = new FlyBrain(c, { rng: new RNG(5), dt: 0.5 });
  b.bgLambda.fill(0);
  const id = c.groups.AOTU019_L[0];
  b.run(200);
  assert.equal(b.counts[id], 0);
  // clamp g at 14 mV (2x the 7 mV threshold gap): T = tauM ln(g/(g-7)) + tRef
  let spikes = 0;
  for (let t = 0; t < 1000; t++) { b.g[id] = 14 / Math.exp(-0.5 / LIF.tauSyn); b.run(1); spikes += b.counts[id]; }
  const expected = 1000 / (LIF.tauM * Math.log(14 / 7) + LIF.tRef);
  assert.ok(Math.abs(spikes - expected) / expected < 0.15, `rate ${spikes} Hz vs ${expected.toFixed(1)} Hz`);
});

test('punishment paired with blue depresses blue KC→MBON-11 synapses, not green', () => {
  for (const silence of [[], ['PPL101', 'PAM']]) {
    const c = buildConnectome(new RNG(6));
    const silenced = c.neurons.filter((n) => silence.includes(n.type)).map((n) => n.id);
    const b = new FlyBrain(c, { rng: new RNG(7), silenced });
    for (let t = 0; t < 35; t++) {
      b.setRate('vPN_L', Float32Array.from(c.groups.vPN_L, (id) => (c.neurons[id].channel === 0 ? 140 : 0)));
      b.setRate('NOCI_L', t > 10 ? 250 : 0);
      b.setRate('NOCI_R', t > 10 ? 250 : 0);
      b.run(TIC * 1000);
      b.learn(TIC);
    }
    const m = b.memory();
    if (silence.length) {
      assert.equal(m.blue.approach, 1);
      assert.equal(m.green.approach, 1);
    } else {
      assert.ok(m.blue.approach < 0.9, `blue approach ${m.blue.approach}`);
      assert.ok(m.blue.approach < m.green.approach - 0.05, `blue ${m.blue.approach} vs green ${m.green.approach}`);
      assert.ok(m.blue.valence < 0);
    }
  }
});

test('innate pursuit turns the fly toward an object, left or right', () => {
  const summedTurn = (side) => {
    const w = new World({ scenario: 'forage', seed: 11 });
    const p = w.player;
    p.x = side > 0 ? 5.5 : 10.5; p.y = 11.5; p.angle = -Math.PI / 2; // facing north, clear line of sight
    w.entities = w.entities.filter((e) => e.kind === 'orb').slice(0, 1);
    const orb = w.entities[0];
    // 35 degrees to the given side at 3 units (bearing positive = left)
    const a = p.angle - side * 35 * DEG;
    orb.x = p.x + Math.cos(a) * 3; orb.y = p.y + Math.sin(a) * 3;
    assert.ok(w.lineOfSight(p.x, p.y, orb.x, orb.y));
    const agent = new FlyAgent({ seed: 12, silence: ['PPL101', 'PAM'] });
    let turn = 0;
    for (let i = 0; i < 10; i++) turn += agent.act(w, null).turn;
    return turn;
  };
  const left = summedTurn(1), right = summedTurn(-1);
  assert.ok(left > 0, `object on the left: summed turn ${left} should be positive`);
  assert.ok(right < 0, `object on the right: summed turn ${right} should be negative`);
});

test('statistics match known values', () => {
  assert.ok(Math.abs(tPValue(2.0, 10) - 0.07339) < 1e-4);
  assert.ok(Math.abs(tPValue(2.228, 10) - 0.05) < 1e-3);
  assert.equal(signFlipTest([1, 1, 1, 1, 1]).p, 2 / 32);
  assert.equal(signFlipTest([1, -1, 1, -1]).p, 1);
  const w = welchT([1, 2, 3, 4, 5], [3, 4, 5, 6, 7]);
  assert.ok(Math.abs(w.t + 2) < 1e-9 && Math.abs(w.df - 8) < 1e-9);
});

test('verdicts: a consistent preference counts as learning, noise does not', () => {
  const P = { ...PROTOCOLS.quick, subjects: 8, acquisition: 4, reversal: 2, conditions: ['intact', 'no-dopamine'] };
  const results = [];
  const rng = new RNG(1);
  for (const condition of P.conditions) {
    for (let subject = 0; subject < P.subjects; subject++) {
      const episodes = [];
      for (let ep = 0; ep < 6; ep++) {
        const rev = ep >= 4;
        let touches = '';
        for (let k = 0; k < 10; k++) {
          // intact: right most of the time, but the old memory wins the first touches after the swap
          const learned = condition === 'intact' ? (ep === 4 && k < 4 ? rng.chance(0.15) : rng.chance(0.85)) : rng.chance(0.5);
          touches += learned ? 'g' : 'b';
        }
        const good = [...touches].filter((t) => t === 'g').length;
        episodes.push({ ep, phase: rev ? 'rev' : 'acq', good, bad: 10 - good, pi: (2 * good - 10) / 10, touches, kills: 0, shots: 0, hits: 0, damage: 0, survived: 40, died: false });
      }
      results.push({ condition, subject, episodes });
    }
  }
  const A = analyze(P, results);
  const v = Object.fromEntries(A.verdicts.map((x) => [x.condition, x.verdict]));
  assert.equal(v.intact, 'Learns and re-learns');
  assert.equal(v['no-dopamine'], 'No evidence of learning');
});

test('a real fly run produces well-formed episode records', () => {
  const P = { ...PROTOCOLS.quick, acquisition: 1, reversal: 1 };
  const r = runSubject({ protocol: P, condition: 'intact', subject: 0, baseSeed: 5 });
  assert.equal(r.episodes.length, 2);
  for (const e of r.episodes) {
    assert.ok(e.survived > 0);
    assert.equal(e.good + e.bad, e.touches.length);
    assert.ok(e.pi >= -1 && e.pi <= 1);
    assert.ok('blue' in e.memory);
  }
  assert.notEqual(r.episodes[0].goodColor, r.episodes[1].goodColor);
  assert.ok(mean(r.episodes.map((e) => e.good + e.bad)) > 2, 'an intact fly forages');
});

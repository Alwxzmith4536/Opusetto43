# FlyDoom learning lab

A spiking fruit-fly brain model that plays a Doom-style shooter **and learns**, plus a test engine that checks the learning with controlled experiments.

Recent projects hooked real fly connectomes (FlyWire, MaleCNS v1.0) to Doom. Their authors note that the fly plays by **reflex, not learning**. This project adds what they leave out: dopamine-gated plasticity in the mushroom body, the fly's learning centre. It also tests the same controls they use: scrambled wiring and lesions.

No dependencies. Plain JavaScript that runs in the browser and in Node ≥ 18.

```bash
open flydoom/index.html                  # watch it play (or serve the folder)
cd flydoom && npm test                   # 16 unit tests
node test-engine.js                      # full experiment, ~90 s
node test-engine.js --quick              # smoke run
node test-engine.js --episodes 60 --seeds 1,2,3,4,5 --out results.json
```

## The brain (526 LIF neurons, ~4k synapses)

| Stage | Cell types | Role |
|---|---|---|
| Compound eye | 36 ommatidia over 270° | Raycasts the level: wall nearness, dark object, transient |
| Lamina | L2 | Centre-surround contrast for objects |
| Lobula / lobula plate | LC11, LC4, LPTC | Small-object detection, looming, near-wall optic flow |
| Mushroom body | 300 KC, APL, 5 MBON | Sparse scene code → learned action values |
| Dopamine | PAM, PPL1 | Reward (kill, hit, new ground) and punishment (miss, damage) |
| Descending | DNa02 L/R, DNp09, MDN, giant fiber, DN-fire | Steering, walking, backing off, shooting |

**Innate reflexes** (hardwired lobula → DN): turn toward objects, turn away from walls, and back off through the giant fiber and MDN when something looms. The fly has **no innate urge to shoot**: shooting comes from spontaneous activity and what the mushroom body learns.

**Learning rule** (KC → MBON synapses only): `Δw = η · DA · e`, where the eligibility trace `e` is Kenyon cell spikes × an efference copy of the chosen action, decaying over ~5 tics, and `DA` is PAM spikes − PPL1 spikes. Weights relax slowly back toward their starting value.

The cell types and projection logic follow the Drosophila literature. **The wiring is connectome-inspired. It is not the real FlyWire graph.** Swapping in real connectome edges is the obvious next step.

## The game

A 16×16 Doom-style level at 35 tics/s. Imps path around walls toward the player, take two hits, and claw at close range. Episodes last 30 s (1050 tics). The first-person view in the browser is a raycaster with a 90° screen. The fly's own eye sees 270°.

## Test engine results

`node test-engine.js --episodes 30 --seeds 1,2,3,4` (window = last 10 episodes):

```
condition   first  last ± sem    Δ      acc   surv
learning    8.95   9.32 ± 0.27   +0.38  0.26  1.00
frozen      7.73   7.97 ± 0.21   +0.25  0.30  1.00
scrambled   4.70   4.72 ± 0.40   +0.02  0.27  0.13
mb-lesion   0.00   0.00 ± 0.00   +0.00  0.00  0.00
random      0.75   0.80 ± 0.18   +0.05  0.05  0.00

PASS  Learning beats the same brain with plasticity off   9.32 vs 7.97, p≈0.0001
PASS  Learning curve trends upward
PASS  Innate fly wiring alone beats random play            7.97 vs 0.80
PASS  Real (structured) wiring beats scrambled wiring      9.32 vs 4.72
PASS  Mushroom-body lesion removes the learning benefit
```

What these numbers show:

- Learning gives about **+17% kills** over the same brain with plasticity off. Most of the gain comes in the first episode or two; after that the curve rises only slowly.
- The learner gets its extra kills by **shooting more, not more accurately** (accuracy 0.26 vs 0.30 frozen).
- The MB lesion scores 0 because, in this model, the shooting command passes through the MBONs. Silencing the KCs removes shooting entirely, not just the learned part.
- p-values come from Welch's t-test with a normal approximation, over episodes pooled across seeds.

The process exits non-zero if any check fails, so you can use it in CI.

## Files

- `flydoom.js`: world, compound eye, spiking network, fly brain, simulation, stats
- `test-engine.js`: experiment runner, summary table, pass/fail checks
- `index.html`: live view with the game, the fly's-eye strip, a population heatmap, DN and MBON readouts, dopamine trace, and learning curve
- `tests/flydoom.test.js`: unit tests

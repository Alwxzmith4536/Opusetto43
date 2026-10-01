# Fly brain plays Doom: vizdoom:basic

Brain: **synthetic-fly** (1,936 neurons, 165,900 synapses, 1,500 Kenyon cells). Training: 300 episodes. Evaluation: frozen weights on 50 fixed seeds.

## Evaluation

| condition | episodes | mean return | 95% CI | median | episodes with a kill |
|---|---:|---:|---|---:|---:|
| Random play | 50 | -177.5 | [-232.4, -125.0] | -184.5 | 54% |
| Fly brain, untrained | 50 | -134.4 | [-190.3, -80.5] | -65.5 | 62% |
| Fly brain, trained | 50 | 49.9 | [38.2, 60.0] | 62.5 | 100% |
| Trained, Kenyon cells silenced | 50 | -175.2 | [-224.7, -124.9] | -212.5 | 60% |
| Trained with dopamine neurons silenced | 50 | -200.3 | [-254.0, -145.9] | -352.5 | 48% |

## Validation gates

| gate | verdict | criterion |
|---|---|---|
| G1 learning | PASS | trained > untrained and trained > random on the same evaluation seeds (one-sided Mann-Whitney, p < 0.01) |
| G2 learning curve | PASS | returns rise over training: Spearman rho > 0 with p < 0.01, and last third > first third |
| G3 dopamine necessity | PASS | a brain trained with its PAM/PPL1 dopamine neurons silenced does not improve over the untrained brain (p > 0.05) and is beaten by the intact trained brain (p < 0.01) |
| G4 mushroom-body necessity | PASS | silencing Kenyon cells after training degrades play (one-sided Mann-Whitney, p < 0.01) |
| G5 visual aiming (untrained control) | INFO | steers towards the monster: both one-sided Fisher tests p < 0.01; fires more when the monster is centred (control: reported, not judged) |
| G5 visual aiming (trained) | PASS | steers towards the monster: both one-sided Fisher tests p < 0.01; fires more when the monster is centred |
| G6 aversive visual conditioning | PASS | after CS+ x punishment pairing, value(CS+) falls relative to value(CS-) (p < 0.01); no significant effect when dopamine neurons are silenced |

## Where the fly steers (share of actions by monster azimuth)

**untrained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 824 | 32% | 34% | 34% |
| -20…-10° | 232 | 31% | 34% | 35% |
| -10…-3° | 130 | 28% | 28% | 45% |
| -3…3° | 61 | 23% | 39% | 38% |
| 3…10° | 101 | 26% | 37% | 38% |
| 10…20° | 230 | 33% | 34% | 33% |
| > 20° | 453 | 33% | 33% | 34% |

**trained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 129 | 56% | 25% | 19% |
| -20…-10° | 101 | 59% | 17% | 24% |
| -10…-3° | 96 | 42% | 20% | 39% |
| -3…3° | 93 | 11% | 24% | 66% |
| 3…10° | 86 | 10% | 52% | 37% |
| 10…20° | 66 | 12% | 76% | 12% |
| > 20° | 17 | 12% | 82% | 6% |


Training wall time: 87 s (0.29 s per episode).

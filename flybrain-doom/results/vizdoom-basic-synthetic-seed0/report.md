# Fly brain plays Doom: vizdoom:basic

Brain: **synthetic-fly** (1,936 neurons, 165,900 synapses, 1,500 Kenyon cells). Training: 300 episodes. Evaluation: frozen weights on 50 fixed seeds.

## Evaluation

| condition | episodes | mean return | 95% CI | median | episodes with a kill |
|---|---:|---:|---|---:|---:|
| Random play | 50 | -134.5 | [-187.1, -81.9] | -79.5 | 66% |
| Fly brain, untrained | 50 | -103.4 | [-152.0, -55.5] | -68.5 | 74% |
| Fly brain, trained | 50 | 36.7 | [14.1, 54.8] | 57.0 | 98% |
| Trained, Kenyon cells silenced | 50 | -149.6 | [-202.5, -97.2] | -119.0 | 60% |
| Trained with dopamine neurons silenced | 50 | -100.2 | [-152.6, -50.8] | -13.0 | 74% |

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
| < -20° | 596 | 34% | 35% | 31% |
| -20…-10° | 189 | 39% | 30% | 31% |
| -10…-3° | 91 | 40% | 27% | 33% |
| -3…3° | 99 | 38% | 32% | 29% |
| 3…10° | 216 | 32% | 34% | 33% |
| 10…20° | 400 | 30% | 36% | 34% |
| > 20° | 268 | 32% | 36% | 32% |

**trained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 61 | 57% | 13% | 30% |
| -20…-10° | 100 | 66% | 10% | 24% |
| -10…-3° | 80 | 50% | 16% | 34% |
| -3…3° | 107 | 21% | 14% | 65% |
| 3…10° | 92 | 11% | 48% | 41% |
| 10…20° | 138 | 23% | 46% | 30% |
| > 20° | 110 | 34% | 37% | 29% |


Training wall time: 84 s (0.28 s per episode).

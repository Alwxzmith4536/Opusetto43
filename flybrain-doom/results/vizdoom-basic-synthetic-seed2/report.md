# Fly brain plays Doom: vizdoom:basic

Brain: **synthetic-fly** (1,936 neurons, 165,900 synapses, 1,500 Kenyon cells). Training: 300 episodes. Evaluation: frozen weights on 50 fixed seeds.

## Evaluation

| condition | episodes | mean return | 95% CI | median | episodes with a kill |
|---|---:|---:|---|---:|---:|
| Random play | 50 | -155.0 | [-209.0, -99.4] | -88.0 | 58% |
| Fly brain, untrained | 50 | -133.5 | [-185.4, -82.4] | -114.0 | 66% |
| Fly brain, trained | 50 | -5.2 | [-46.5, 29.7] | 46.0 | 88% |
| Trained, Kenyon cells silenced | 50 | -147.3 | [-201.3, -93.5] | -136.0 | 64% |
| Trained with dopamine neurons silenced | 50 | -155.0 | [-214.5, -100.7] | -114.5 | 56% |

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
| < -20° | 727 | 35% | 34% | 32% |
| -20…-10° | 250 | 34% | 31% | 35% |
| -10…-3° | 173 | 35% | 37% | 28% |
| -3…3° | 77 | 32% | 40% | 27% |
| 3…10° | 142 | 27% | 40% | 32% |
| 10…20° | 296 | 35% | 32% | 32% |
| > 20° | 413 | 32% | 34% | 34% |

**trained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 63 | 65% | 14% | 21% |
| -20…-10° | 94 | 68% | 14% | 18% |
| -10…-3° | 99 | 35% | 8% | 57% |
| -3…3° | 72 | 11% | 24% | 65% |
| 3…10° | 92 | 29% | 41% | 29% |
| 10…20° | 153 | 34% | 44% | 22% |
| > 20° | 442 | 38% | 37% | 26% |


Training wall time: 106 s (0.35 s per episode).

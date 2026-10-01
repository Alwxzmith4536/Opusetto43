# Fly brain plays Doom: vizdoom:defend_the_center

Brain: **synthetic-fly** (1,936 neurons, 165,900 synapses; 1,500 Kenyon cells feed the plastic synapses). Training: 200 episodes. Evaluation: frozen weights on 30 fixed seeds.

## Evaluation

| condition | episodes | mean return | 95% CI | median | episodes with a kill |
|---|---:|---:|---|---:|---:|
| Scripted aimer (cheats: reads true monster positions) | 30 | 10.2 | [8.4, 12.0] | 8.0 | 100% |
| Random play | 30 | 0.5 | [0.1, 0.8] | 0.0 | 80% |
| Fly brain, untrained | 30 | 0.3 | [-0.1, 0.7] | 0.0 | 77% |
| Fly brain, trained | 30 | 3.9 | [3.3, 4.5] | 4.0 | 100% |
| Trained, Kenyon cells silenced | 30 | 0.7 | [0.1, 1.4] | 0.5 | 77% |
| Trained with dopamine neurons silenced | 30 | 0.4 | [0.1, 0.7] | 0.0 | 83% |

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
| < -20° | 455 | 32% | 37% | 31% |
| -20…-10° | 219 | 37% | 31% | 32% |
| -10…-3° | 175 | 32% | 38% | 30% |
| -3…3° | 198 | 32% | 36% | 32% |
| 3…10° | 199 | 33% | 29% | 39% |
| 10…20° | 244 | 35% | 32% | 32% |
| > 20° | 661 | 33% | 31% | 36% |

**trained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 464 | 69% | 12% | 19% |
| -20…-10° | 261 | 69% | 10% | 21% |
| -10…-3° | 403 | 38% | 9% | 53% |
| -3…3° | 561 | 25% | 12% | 63% |
| 3…10° | 360 | 34% | 19% | 47% |
| 10…20° | 208 | 47% | 25% | 28% |
| > 20° | 360 | 64% | 15% | 21% |


Training wall time: 207 s (1.04 s per episode).

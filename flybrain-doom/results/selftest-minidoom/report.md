# Fly brain plays Doom: minidoom:basic

Brain: **synthetic-fly** (1,936 neurons, 165,900 synapses; 1,500 Kenyon cells feed the plastic synapses). Training: 150 episodes. Evaluation: frozen weights on 30 fixed seeds.

## Evaluation

| condition | episodes | mean return | 95% CI | median | episodes with a kill |
|---|---:|---:|---|---:|---:|
| Scripted aimer (cheats: reads true monster positions) | 30 | -14.4 | [-79.3, 49.5] | 86.0 | 73% |
| Random play | 30 | -219.7 | [-298.0, -143.0] | -309.5 | 53% |
| Fly brain, untrained | 30 | -177.0 | [-251.1, -105.6] | -145.5 | 67% |
| Fly brain, trained | 30 | -0.8 | [-59.7, 48.4] | 61.5 | 87% |
| Trained, Kenyon cells silenced | 30 | -202.2 | [-278.6, -128.5] | -172.0 | 53% |
| Trained with dopamine neurons silenced | 30 | -134.3 | [-201.3, -68.9] | -75.0 | 73% |

## Validation gates

| gate | verdict | criterion |
|---|---|---|
| G1 learning | PASS | trained > untrained and trained > random on the same evaluation seeds (one-sided Mann-Whitney, p < 0.01) |
| G2 learning curve | PASS | returns rise over training: Spearman rho > 0 with p < 0.01, and last third > first third |
| G3 dopamine necessity | PASS | a brain trained with its PAM/PPL1 dopamine neurons silenced does not improve over the untrained brain (p > 0.05) and is beaten by the intact trained brain (p < 0.01) |
| G4 mushroom-body necessity | PASS | silencing Kenyon cells after training degrades play (one-sided Mann-Whitney, p < 0.01) |
| G5 visual aiming (untrained control) | INFO | steers towards the monster: both one-sided Fisher tests p < 0.01; fires more when the monster is centred (control: reported, not judged) |
| G5 visual aiming (trained) | FAIL | steers towards the monster: both one-sided Fisher tests p < 0.01; fires more when the monster is centred |
| G6 aversive visual conditioning | PASS | after CS+ x punishment pairing, value(CS+) falls relative to value(CS-) (p < 0.01); no significant effect when dopamine neurons are silenced |

## Where the fly steers (share of actions by monster azimuth)

**untrained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 457 | 34% | 32% | 33% |
| -20…-10° | 150 | 40% | 30% | 30% |
| -10…-3° | 105 | 29% | 30% | 41% |
| -3…3° | 52 | 27% | 44% | 29% |
| 3…10° | 61 | 34% | 34% | 31% |
| 10…20° | 111 | 35% | 43% | 22% |
| > 20° | 393 | 33% | 33% | 35% |

**trained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 296 | 28% | 53% | 19% |
| -20…-10° | 38 | 45% | 34% | 21% |
| -10…-3° | 44 | 50% | 18% | 32% |
| -3…3° | 42 | 14% | 31% | 55% |
| 3…10° | 46 | 11% | 39% | 50% |
| 10…20° | 24 | 17% | 83% | 0% |
| > 20° | 47 | 17% | 47% | 36% |


Training wall time: 53 s (0.35 s per episode).

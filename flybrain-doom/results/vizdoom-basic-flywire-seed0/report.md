# Fly brain plays Doom: vizdoom:basic

Brain: **FlyWire v783 (central)** (50,601 neurons, 6,727,577 synapses; 1,299 descending neurons feed the plastic synapses). Training: 150 episodes. Evaluation: frozen weights on 30 fixed seeds.

## Evaluation

| condition | episodes | mean return | 95% CI | median | episodes with a kill |
|---|---:|---:|---|---:|---:|
| Scripted aimer (cheats: reads true monster positions) | 30 | 76.6 | [72.3, 80.6] | 77.0 | 100% |
| Random play | 30 | -83.0 | [-145.8, -23.1] | 2.0 | 77% |
| Fly brain, untrained | 30 | -168.3 | [-237.0, -97.8] | -126.5 | 57% |
| Fly brain, trained | 30 | -153.5 | [-221.8, -84.2] | -110.0 | 53% |
| Trained, Kenyon cells silenced | 30 | -165.6 | [-237.7, -98.1] | -173.5 | 53% |
| Trained with dopamine neurons silenced | 30 | -154.0 | [-223.3, -85.3] | -183.0 | 63% |

## Validation gates

| gate | verdict | criterion |
|---|---|---|
| G1 learning | FAIL | trained > untrained and trained > random on the same evaluation seeds (one-sided Mann-Whitney, p < 0.01) |
| G2 learning curve | FAIL | returns rise over training: Spearman rho > 0 with p < 0.01, and last third > first third |
| G3 dopamine necessity | FAIL | a brain trained with its PAM/PPL1 dopamine neurons silenced does not improve over the untrained brain (p > 0.05) and is beaten by the intact trained brain (p < 0.01) |
| G4 mushroom-body necessity | FAIL | silencing Kenyon cells after training degrades play (one-sided Mann-Whitney, p < 0.01) |
| G5 visual aiming (untrained control) | INFO | steers towards the monster: both one-sided Fisher tests p < 0.01; fires more when the monster is centred (control: reported, not judged) |
| G5 visual aiming (trained) | FAIL | steers towards the monster: both one-sided Fisher tests p < 0.01; fires more when the monster is centred |
| G6 aversive visual conditioning | FAIL | after CS+ x punishment pairing, value(CS+) falls relative to value(CS-) (p < 0.01); no significant effect when dopamine neurons are silenced |

## Where the fly steers (share of actions by monster azimuth)

**untrained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 192 | 32% | 19% | 48% |
| -20…-10° | 127 | 29% | 19% | 52% |
| -10…-3° | 90 | 26% | 23% | 51% |
| -3…3° | 40 | 38% | 22% | 40% |
| 3…10° | 85 | 34% | 27% | 39% |
| 10…20° | 234 | 29% | 16% | 55% |
| > 20° | 575 | 23% | 27% | 50% |

**trained**

| monster azimuth | steps | left | right | attack |
|---|---:|---:|---:|---:|
| < -20° | 401 | 42% | 34% | 24% |
| -20…-10° | 195 | 34% | 38% | 28% |
| -10…-3° | 91 | 36% | 41% | 23% |
| -3…3° | 69 | 45% | 36% | 19% |
| 3…10° | 103 | 33% | 45% | 22% |
| 10…20° | 210 | 44% | 34% | 22% |
| > 20° | 262 | 30% | 48% | 21% |


Training wall time: 1166 s (7.77 s per episode).

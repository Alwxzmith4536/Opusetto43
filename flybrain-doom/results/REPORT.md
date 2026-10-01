# Fly brain test engine report

Generated 2026-10-01T15:02:08.089Z from saved runs (base seed 1). Reproduce with `node cli/run.mjs --seed 1`.
Inference: two-sided permutation tests (exact sign-flip when n <= 16). Values are mean ± SEM across flies.
## Valence learning + reversal

Scenario `forage`, 16 flies per condition, 12 acquisition episodes then 6 reversal episodes, blocks of 3. Base seed 1.

| Condition | Verdict | Evidence |
|---|---|---|
| Intact fly | **Learns and re-learns** | late PI 0.29 ± 0.04 (p<0.001); first 4 touches after the swap -0.31 (drop p<0.001), last block 0.36 (p<0.001) |
| Dopamine blocked | **No evidence of learning** | late PI -0.02 ± 0.03 (p=0.573); first 4 touches after the swap 0.00 (drop p=0.901), last block 0.07 (p=0.020) |
| Kenyon cells blocked | **No evidence of learning** | late PI 0.03 ± 0.03 (p=0.212); first 4 touches after the swap -0.09 (drop p=0.385), last block 0.03 (p=0.236) |
| Scrambled wiring | **No evidence of learning** | late PI 0.10 ± 0.15 (p=0.609); first 4 touches after the swap 0.00 (drop p=0.912), last block -0.08 (p=0.658) |
| Random policy | **No evidence of learning** | late PI 0.02 ± 0.18 (p=0.907); first 4 touches after the swap 0.00 (drop p=0.913), last block 0.17 (p=0.265) |

Preference index PI = (healing orbs − burning orbs) / all orbs touched, scored against whichever color currently heals. 0 = no preference, 1 = only healing orbs.

| Condition | First 4 touches | Late PI | 95% CI | Orbs/episode | First 4 touches after swap | Last block after swap |
|---|---|---|---|---|---|---|
| Intact fly |  0.25 ± 0.06 |  0.29 ± 0.04 | [0.20, 0.36] | 11.3 | -0.31 ± 0.11 |  0.36 ± 0.04 |
| Dopamine blocked |  0.00 ± 0.10 | -0.02 ± 0.03 | [-0.07, 0.03] | 17.1 |  0.00 ± 0.12 |  0.07 ± 0.03 |
| Kenyon cells blocked |  0.03 ± 0.11 |  0.03 ± 0.03 | [-0.02, 0.08] | 17.4 | -0.09 ± 0.13 |  0.03 ± 0.03 |
| Scrambled wiring | -0.01 ± 0.20 |  0.10 ± 0.15 | [-0.18, 0.40] | 0.7 |  0.00 ± 0.25 | -0.08 ± 0.18 |
| Random policy |  0.16 ± 0.11 |  0.02 ± 0.18 | [-0.32, 0.36] | 1.4 |  0.00 ± 0.11 |  0.17 ± 0.14 |

Learning curves by encounter (mean PI over successive bins of 4 orb touches, −1 to +1; | marks the color swap):

```
Intact fly             ▅▅▅▅▄▅▅▆▆▅|▃▄▆▅▅▄▅▅▆▆
Dopamine blocked       ▄▄▄▄▅▄▄▄▄▄|▄▄▄▄▄▄▄▄▄▄
Kenyon cells blocked   ▄▄▅▄▄▅▅▄▄▄|▄▄▄▄▄▄▄▄▄▄
Scrambled wiring       ▄▃▄▃▃▅▄ ▄▄|▄▃▃▄▄▄▄▄▄▄
Random policy          ▅▄▄▅▂▂▄▄▄▄|▄▄▄ ▄▄▄▄▄▄
```

Learning curves by episode:

```
Intact fly             ▅▅▅▅▅▅▅▅▅▆▅▅|▄▅▅▆▆▅
Dopamine blocked       ▄▄▄▄▄▄▄▄▄▄▄▄|▄▄▄▄▄▄
Kenyon cells blocked   ▄▅▄▄▄▄▄▄▄▄▄▄|▄▄▄▄▄▄
Scrambled wiring       ▄▄▄▄▄▄▅▄▄▅▄▄|▅▃▄▄▄▄
Random policy          ▆▄▄▃▃▄▃▅▅▅▃▄|▃▄▄▄▅▃
```

Intact vs each control (late PI, paired by fly):

| Comparison | Δ late PI | p (permutation) | Cohen’s d |
|---|---|---|---|
| intact − Dopamine blocked |  0.30 ± 0.03 | <0.001 | 2.15 |
| intact − Kenyon cells blocked |  0.25 ± 0.05 | <0.001 | 1.85 |
| intact − Scrambled wiring |  0.19 ± 0.14 | 0.193 | 0.42 |
| intact − Random policy |  0.26 ± 0.18 | 0.165 | 0.51 |


## Imp combat

Scenario `combat`, 12 flies per condition, 10 acquisition episodes, blocks of 3. Base seed 1.

| Condition | Verdict | Evidence |
|---|---|---|
| Intact fly | **Does not fight** | 0.24 kills/episode at 58% accuracy, 89 damage taken |
| Dopamine blocked | **Fights** | 1.97 kills/episode at 71% accuracy, 89 damage taken; +1.94 kills/episode vs intact (p=0.001) |
| LC10a lesion | **Does not fight** | 0.00 kills/episode at 0% accuracy, 89 damage taken; −0.22 kills/episode vs intact (p=1.000) |
| Scrambled wiring | **Does not fight** | 0.07 kills/episode at 29% accuracy, 93 damage taken; −0.11 kills/episode vs intact (p=1.000) |
| Random policy | **Does not fight** | 0.10 kills/episode at 4% accuracy, 93 damage taken; −0.14 kills/episode vs intact (p=1.000) |

| Condition | Kills/episode | Accuracy | Damage/episode | Survival (s) | Deaths/episode | Kills early→late | Damage early→late |
|---|---|---|---|---|---|---|---|
| Intact fly | 0.24 | 58% | 89.1 | 34.4 | 0.63 | 0.36 → 0.22 | 85 → 94 |
| Dopamine blocked | 1.97 | 71% | 88.7 | 34.9 | 0.55 | 1.92 → 2.17 | 86 → 89 |
| LC10a lesion | 0.00 | 0% | 89.1 | 33.8 | 0.65 | 0.00 → 0.00 | 91 → 86 |
| Scrambled wiring | 0.07 | 29% | 92.8 | 31.7 | 0.68 | 0.11 → 0.11 | 91 → 96 |
| Random policy | 0.10 | 4% | 92.7 | 32.5 | 0.73 | 0.11 → 0.08 | 91 → 96 |

Intact vs each control in the last block (paired by fly):

| Comparison | Δ kills/episode | p | Δ damage/episode | p |
|---|---|---|---|---|
| intact − Dopamine blocked | -1.94 | 0.001 |  4.53 | 0.446 |
| intact − LC10a lesion |  0.22 | 1.000 |  8.03 | 0.177 |
| intact − Scrambled wiring |  0.11 | 1.000 | -1.92 | 0.657 |
| intact − Random policy |  0.14 | 1.000 | -1.83 | 0.835 |


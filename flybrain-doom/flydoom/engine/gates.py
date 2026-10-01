"""Validation gates: falsifiable checks that the fly brain sees, learns, and learns *because of* dopamine.

Each gate states a criterion up front and returns PASS/FAIL with the statistics behind it,
so "it learned" is a tested claim rather than an impression from a few lucky episodes.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field

import numpy as np

from . import stats

ALPHA = 0.01


@dataclass
class GateResult:
    name: str
    passed: bool | None  # None: informative only (no pass/fail claim)
    criterion: str
    metrics: dict = field(default_factory=dict)
    detail: str = ""

    def to_dict(self) -> dict:
        return asdict(self)

    @property
    def verdict(self) -> str:
        return {True: "PASS", False: "FAIL", None: "INFO"}[self.passed]


def _returns(episodes: list[dict]) -> np.ndarray:
    return np.array([e["raw_return"] for e in episodes], dtype=float)


# --------------------------------------------------------------- behaviour
def learning_gate(trained: list[dict], untrained: list[dict], random: list[dict]) -> GateResult:
    t, u, r = _returns(trained), _returns(untrained), _returns(random)
    vs_untrained = stats.compare(t, u)
    vs_random = stats.compare(t, r)
    passed = vs_untrained["p"] < ALPHA and vs_random["p"] < ALPHA
    return GateResult(
        "G1 learning", passed,
        f"trained > untrained and trained > random on the same evaluation seeds "
        f"(one-sided Mann-Whitney, p < {ALPHA})",
        {"trained": stats.summary(t), "untrained": stats.summary(u), "random": stats.summary(r),
         "trained_vs_untrained": vs_untrained, "trained_vs_random": vs_random})


def trend_gate(curve: list[dict]) -> GateResult:
    y = _returns(curve)
    tr = stats.trend(y)
    third = max(1, len(y) // 3)
    early, late = y[:third], y[-third:]
    cmp = stats.compare(late, early)
    passed = tr["rho"] > 0 and tr["p"] < ALPHA and cmp["p"] < ALPHA
    return GateResult(
        "G2 learning curve", passed,
        f"returns rise over training: Spearman rho > 0 with p < {ALPHA}, and last third > first third",
        {"spearman": tr, "first_third": stats.summary(early), "last_third": stats.summary(late),
         "late_vs_early": cmp})


def dopamine_gate(trained: list[dict], dan_lesioned_trained: list[dict], untrained: list[dict]) -> GateResult:
    t, d, u = _returns(trained), _returns(dan_lesioned_trained), _returns(untrained)
    intact_vs_lesion = stats.compare(t, d)
    lesion_vs_naive = stats.compare(d, u)
    passed = intact_vs_lesion["p"] < ALPHA and lesion_vs_naive["p"] > 0.05
    return GateResult(
        "G3 dopamine necessity", passed,
        "a brain trained with its PAM/PPL1 dopamine neurons silenced does not improve over the "
        f"untrained brain (p > 0.05) and is beaten by the intact trained brain (p < {ALPHA})",
        {"dan_lesioned_trained": stats.summary(d), "intact_vs_lesioned": intact_vs_lesion,
         "lesioned_vs_untrained": lesion_vs_naive})


def mushroom_body_gate(trained: list[dict], kc_lesioned: list[dict]) -> GateResult:
    t, k = _returns(trained), _returns(kc_lesioned)
    cmp = stats.compare(t, k)
    passed = cmp["p"] < ALPHA
    return GateResult(
        "G4 mushroom-body necessity", passed,
        f"silencing Kenyon cells after training degrades play (one-sided Mann-Whitney, p < {ALPHA})",
        {"kc_lesioned": stats.summary(k), "trained_vs_kc_lesioned": cmp})


def aiming_gate(episodes: list[dict], available: list[str], label: str = "",
                informative: bool = False) -> GateResult:
    """Does the chosen action depend on where the nearest monster is (ground truth from the game)?

    ``informative=True`` reports the same statistics without a pass/fail claim (used for the
    untrained brain, which is a control that is expected *not* to aim).
    """
    pairs = [p for e in episodes for p in e.get("aim", [])]
    az = np.array([p[0] for p in pairs], dtype=float)
    act = np.array([p[1] for p in pairs])
    left, right, centre = az < -5.0, az > 5.0, np.abs(az) <= 2.5
    metrics: dict = {"n_steps": int(az.size), "n_left": int(left.sum()), "n_right": int(right.sum()),
                     "n_centre": int(centre.sum())}
    if az.size == 0 or left.sum() < 5 or right.sum() < 5:
        return GateResult(f"G5 visual aiming{label}", None, "needs frames with monsters on both sides",
                          metrics, "not enough data")
    steer_l = stats.fisher_greater(int((act[left] == "left").sum()), int(left.sum()),
                                   int((act[right] == "left").sum()), int(right.sum()))
    steer_r = stats.fisher_greater(int((act[right] == "right").sum()), int(right.sum()),
                                   int((act[left] == "right").sum()), int(left.sum()))
    metrics.update({"P(left|monster left) vs P(left|monster right)": steer_l,
                    "P(right|monster right) vs P(right|monster left)": steer_r})
    passed = steer_l["p"] < ALPHA and steer_r["p"] < ALPHA
    crit = f"steers towards the monster: both one-sided Fisher tests p < {ALPHA}"
    if "attack" in available and centre.sum() >= 5:
        off = np.abs(az) > 5.0
        fire = stats.fisher_greater(int((act[centre] == "attack").sum()), int(centre.sum()),
                                    int((act[off] == "attack").sum()), int(off.sum()))
        metrics["P(attack|centred) vs P(attack|off-centre)"] = fire
        passed = passed and fire["p"] < ALPHA
        crit += "; fires more when the monster is centred"
    if informative:
        metrics["meets_criterion"] = bool(passed)
        return GateResult(f"G5 visual aiming{label}", None, crit + " (control: reported, not judged)", metrics)
    return GateResult(f"G5 visual aiming{label}", passed, crit, metrics)


# ------------------------------------------------------------- conditioning
def conditioning_gate(make_agent, cs_plus: list[np.ndarray], cs_minus: list[np.ndarray],
                      trials: int = 12, seed: int = 0) -> GateResult:
    """Aversive visual conditioning, the fly's classic paradigm transposed to vision.

    CS+ frames (monster on the left) are paired with punishment, CS- frames (monster on the
    right) with nothing; dopamine neurons signal the prediction error (PPL1 when punishment
    is worse than expected, PAM when an expected punishment fails to come). The
    appetitive-minus-aversive MBON value of held-out CS+ frames should drop relative to CS-
    frames. The same protocol in a brain with silenced dopamine neurons is the control.
    """
    rng = np.random.default_rng(seed)
    out = {}
    for label, lesion in (("intact", None), ("dopamine_lesioned", "dopamine")):
        agent = make_agent(lesion)
        train_p, test_p = cs_plus[::2], cs_plus[1::2]
        train_m, test_m = cs_minus[::2], cs_minus[1::2]
        pre_p = [agent.value(agent.present(f), agent.cfg.window_ms) for f in test_p]
        pre_m = [agent.value(agent.present(f), agent.cfg.window_ms) for f in test_m]
        for _ in range(trials):
            agent.condition(train_p[rng.integers(len(train_p))], us=-1.0)
            agent.condition(train_m[rng.integers(len(train_m))], us=0.0)
        post_p = [agent.value(agent.present(f), agent.cfg.window_ms) for f in test_p]
        post_m = [agent.value(agent.present(f), agent.cfg.window_ms) for f in test_m]
        d_p = np.array(post_p) - np.array(pre_p)
        d_m = np.array(post_m) - np.array(pre_m)
        out[label] = {"delta_value_cs_plus": stats.summary(d_p), "delta_value_cs_minus": stats.summary(d_m),
                      "learning_index": float(d_m.mean() - d_p.mean()),
                      "cs_minus_vs_cs_plus": stats.compare(d_m, d_p)}
    passed = (out["intact"]["cs_minus_vs_cs_plus"]["p"] < ALPHA and out["intact"]["learning_index"] > 0
              and not out["dopamine_lesioned"]["cs_minus_vs_cs_plus"]["p"] < 0.05)
    return GateResult(
        "G6 aversive visual conditioning", passed,
        f"after CS+ x punishment pairing, value(CS+) falls relative to value(CS-) (p < {ALPHA}); "
        "no significant effect when dopamine neurons are silenced",
        out)

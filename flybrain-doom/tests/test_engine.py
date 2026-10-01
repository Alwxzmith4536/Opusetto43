import json
import os

import numpy as np

from flydoom.engine import gates as G
from flydoom.engine import stats
from flydoom.engine.report import write_report


def eps(returns, kills=None, aim=None):
    out = []
    for i, r in enumerate(returns):
        e = {"raw_return": float(r), "kills": float(r > 0 if kills is None else kills[i]), "seed": i}
        if aim is not None:
            e["aim"] = aim[i]
        out.append(e)
    return out


def test_stats_compare_and_trend():
    rng = np.random.default_rng(0)
    a, b = rng.normal(10, 1, 40), rng.normal(0, 1, 40)
    c = stats.compare(a, b)
    assert c["p"] < 1e-6 and c["cliffs_delta"] > 0.9
    assert stats.trend(np.arange(30) + rng.normal(0, 1, 30))["rho"] > 0.8
    lo, hi = stats.bootstrap_ci(a)
    assert lo < 10 < hi
    assert stats.fisher_greater(18, 20, 2, 20)["p"] < 0.001


def test_learning_and_dopamine_gates():
    rng = np.random.default_rng(1)
    trained = eps(rng.normal(50, 10, 30))
    untrained = eps(rng.normal(-150, 30, 30))
    random = eps(rng.normal(-160, 30, 30))
    assert G.learning_gate(trained, untrained, random).passed
    assert not G.learning_gate(untrained, trained, random).passed
    dan = eps(rng.normal(-150, 30, 30))
    assert G.dopamine_gate(trained, dan, untrained).passed
    assert not G.dopamine_gate(trained, trained, untrained).passed
    curve = eps(np.linspace(-150, 50, 90) + rng.normal(0, 20, 90))
    assert G.trend_gate(curve).passed


def test_aiming_gate_detects_steering():
    aim_good = [[(-20.0, "left"), (20.0, "right"), (0.0, "attack")] * 10 for _ in range(3)]
    aim_bad = [[(-20.0, "right"), (20.0, "left"), (0.0, "left")] * 10 for _ in range(3)]
    acts = ["left", "right", "attack"]
    assert G.aiming_gate(eps([0, 0, 0], aim=aim_good), acts).passed
    assert not G.aiming_gate(eps([0, 0, 0], aim=aim_bad), acts).passed


def test_report_files(tmp_path):
    rng = np.random.default_rng(2)
    aim = [[(-25.0, "left"), (25.0, "right"), (0.0, "attack")] for _ in range(5)]
    results = {
        "config": {"eval_episodes": 5}, "env": "minidoom:basic",
        "motor_map": {"left": "MOVE_LEFT", "right": "MOVE_RIGHT", "attack": "ATTACK"},
        "brain": {"name": "synthetic-fly", "neurons": 10, "synapses": 20, "vpns": 2, "state_neurons": 4,
                  "state_label": "Kenyon cells", "notes": ""},
        "calibration": {"w_ref_mv": 0.5}, "curve": eps(rng.normal(0, 10, 40)),
        "eval": {"random": eps(rng.normal(-100, 5, 5), aim=aim), "untrained": eps(rng.normal(-90, 5, 5), aim=aim),
                 "trained": eps(rng.normal(40, 5, 5), aim=aim)},
        "gates": [G.learning_gate(eps([1, 2]), eps([0, 0]), eps([0, 0])).to_dict()],
        "timing": {"train_s": 10.0, "total_s": 12.0, "train_s_per_episode": 0.25},
    }
    s = write_report(results, str(tmp_path))
    for name in ("results.json", "report.md", "report.html"):
        assert os.path.getsize(tmp_path / name) > 200
    data = json.loads((tmp_path / "results.json").read_text())
    assert data["eval"]["trained"]["summary"]["n"] == 5
    assert s["aim"]["trained"]["rows"][0]["p"]["left"] == 1.0
    html = (tmp_path / "report.html").read_text()
    assert "const D=" in html and "</script>" in html

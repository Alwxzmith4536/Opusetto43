"""Small statistics toolkit used by the validation gates."""
from __future__ import annotations

import numpy as np
from scipy import stats as st


def summary(x) -> dict:
    x = np.asarray(x, dtype=float)
    if x.size == 0:
        return {"n": 0}
    lo, hi = bootstrap_ci(x)
    return {"n": int(x.size), "mean": float(x.mean()), "median": float(np.median(x)),
            "std": float(x.std(ddof=1)) if x.size > 1 else 0.0, "ci95": [lo, hi]}


def bootstrap_ci(x, stat=np.mean, n_boot: int = 2000, alpha: float = 0.05, seed: int = 0) -> tuple[float, float]:
    x = np.asarray(x, dtype=float)
    if x.size < 2:
        v = float(stat(x)) if x.size else float("nan")
        return v, v
    rng = np.random.default_rng(seed)
    boots = stat(x[rng.integers(0, x.size, size=(n_boot, x.size))], axis=1)
    return float(np.quantile(boots, alpha / 2)), float(np.quantile(boots, 1 - alpha / 2))


def compare(a, b, alternative: str = "greater") -> dict:
    """Mann-Whitney U test of ``a`` vs ``b`` plus Cliff's delta effect size (-1..1)."""
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    if a.size == 0 or b.size == 0:
        return {"p": float("nan"), "cliffs_delta": float("nan")}
    u, p = st.mannwhitneyu(a, b, alternative=alternative)
    delta = 2.0 * u / (a.size * b.size) - 1.0
    return {"U": float(u), "p": float(p), "cliffs_delta": float(delta),
            "mean_diff": float(a.mean() - b.mean())}


def trend(y) -> dict:
    """Spearman correlation between episode index and ``y`` (learning-curve trend)."""
    y = np.asarray(y, dtype=float)
    if y.size < 3:
        return {"rho": float("nan"), "p": float("nan")}
    rho, p = st.spearmanr(np.arange(y.size), y)
    return {"rho": float(rho), "p": float(p)}


def fisher_greater(k1: int, n1: int, k2: int, n2: int) -> dict:
    """One-sided Fisher exact test that proportion k1/n1 exceeds k2/n2."""
    table = [[k1, n1 - k1], [k2, n2 - k2]]
    _, p = st.fisher_exact(table, alternative="greater")
    return {"p1": k1 / n1 if n1 else float("nan"), "p2": k2 / n2 if n2 else float("nan"), "p": float(p)}


def moving_average(y, k: int = 20) -> np.ndarray:
    y = np.asarray(y, dtype=float)
    if y.size == 0:
        return y
    k = max(1, min(k, y.size))
    c = np.cumsum(np.insert(y, 0, 0.0))
    out = (c[k:] - c[:-k]) / k
    return np.concatenate([np.full(k - 1, np.nan), out])

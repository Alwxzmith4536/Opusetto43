"""Graded (non-spiking) model of the fly optic lobe: lamina -> medulla -> lobula/lobula plate.

Early fly vision is carried by graded potentials, which the LIF whole-brain model cannot
propagate (driving FlyWire photoreceptors in the Shiu et al. model activates the lamina but
dies out in the medulla; see ``flydoom.engine.gates.photoreceptor_propagation_gate``).
So the optic lobe is modelled functionally, per ommatidium, and its outputs drive the
spiking visual projection neurons (VPNs) of the central brain.

Feature channels (all >= 0, saturating to ~1):

=============  ========================================  ===========================
channel        computation                               fly analogue
=============  ========================================  ===========================
``bright``     centre-surround luminance increment       Mi1/Tm3 ON contrast
``dark``       centre-surround luminance decrement       Tm1/Tm2/Tm9 OFF contrast
``on``/``off`` temporal increment / decrement            L1 / L2 transients
``color``      short-vs-middle wavelength opponency       R7/R8 -> Dm8/Tm5 colour
``motion_l``   Hassenstein-Reichardt correlator on       T4/T5 back-to-front, LPTCs
               high-passed inputs, one-frame delay
``motion_r``   ditto, opposite direction                 T4/T5 front-to-back
``figure``     local motion minus wide-field motion      figure-detection (FD) cells
``object``     small-target contrast, size-tuned         LC10a / LC11
``loom``       growth of pooled contrast energy          LC4 / LPLC2
=============  ========================================  ===========================
"""
from __future__ import annotations

import numpy as np
import scipy.sparse as sp

from .eye import CompoundEye

FEATURES = ("bright", "dark", "on", "off", "color", "motion_l", "motion_r", "figure", "object", "loom")


def _sat(x: np.ndarray, gain: float) -> np.ndarray:
    return 1.0 - np.exp(-gain * np.maximum(x, 0.0))


class OpticLobe:
    """Stateful per-frame feature extractor on a :class:`CompoundEye` lattice."""

    GAINS = {"bright": 4.0, "dark": 4.0, "on": 6.0, "off": 6.0, "color": 4.0,
             "motion": 12.0, "figure": 12.0, "object": 3.5, "loom": 8.0}

    def __init__(self, eye: CompoundEye, temporal_alpha: float = 0.5):
        self.eye = eye
        self.alpha = temporal_alpha  # low-pass coefficient per frame (1 = no memory)
        self.N = eye.neighbors
        # two-ring neighbourhood for size tuning and looming pooling
        n2 = (self.N @ self.N).tocsr()
        n2.setdiag(0)
        n2.eliminate_zeros()
        deg = np.asarray(n2.sum(axis=1)).ravel()
        deg[deg == 0] = 1
        self.N2 = sp.diags(1.0 / deg) @ n2
        self.has_right = eye.right_neighbor >= 0
        self.right = np.where(self.has_right, eye.right_neighbor, 0)
        self.left_eye = eye.eye == "L"
        self.reset()

    def reset(self) -> None:
        self._lp = None
        self._hp_prev = None
        self._energy_lp = None

    def process(self, frame: np.ndarray) -> dict[str, np.ndarray]:
        """Return the feature channels for one RGB frame (dict of per-ommatidium arrays)."""
        ph = self.eye.sample(frame)
        lum = ph["lum"]
        out: dict[str, np.ndarray] = {}
        # photoreceptor gain control: divisive normalisation by each eye's mean
        adapted = np.empty_like(lum)
        for m in (self.left_eye, ~self.left_eye):
            adapted[m] = lum[m] / (lum[m].mean() + 0.05)
        surround = self.N @ adapted
        contrast = (adapted - surround) / (surround + 0.1)
        out["bright"] = _sat(contrast, self.GAINS["bright"])
        out["dark"] = _sat(-contrast, self.GAINS["dark"])
        opp = (ph["short"] - ph["middle"]) / (ph["short"] + ph["middle"] + 0.05)
        col_contrast = np.abs(opp - self.N @ opp)
        out["color"] = _sat(col_contrast, self.GAINS["color"])

        lp = adapted if self._lp is None else self._lp
        d = adapted - lp
        out["on"] = _sat(d, self.GAINS["on"])
        out["off"] = _sat(-d, self.GAINS["off"])
        # Hassenstein-Reichardt correlator between horizontal neighbours i -> j (j right of i)
        # on high-passed inputs (as T4/T5 receive from band-pass Mi1/Tm3), delay = one frame
        hp = d
        hp_prev = np.zeros_like(hp) if self._hp_prev is None else self._hp_prev
        j = self.right
        emd = np.where(self.has_right, hp_prev * hp[j] - hp * hp_prev[j], 0.0)
        out["motion_r"] = _sat(emd, self.GAINS["motion"])
        out["motion_l"] = _sat(-emd, self.GAINS["motion"])
        wide = np.where(self.left_eye, emd[self.left_eye].mean(), emd[~self.left_eye].mean())
        out["figure"] = _sat(np.abs(emd - wide), self.GAINS["figure"])
        self.wide_field = (float(emd[self.left_eye].mean()), float(emd[~self.left_eye].mean()))

        energy = np.abs(contrast) + 2.0 * col_contrast
        obj = energy - 0.8 * (self.N2 @ energy)
        out["object"] = _sat(obj, self.GAINS["object"])
        pooled = self.N2 @ energy + energy
        prev = pooled if self._energy_lp is None else self._energy_lp
        out["loom"] = _sat(pooled - prev, self.GAINS["loom"])

        self._lp = self.alpha * adapted + (1 - self.alpha) * lp
        self._hp_prev = hp
        self._energy_lp = self.alpha * pooled + (1 - self.alpha) * prev
        return out

    def stack(self, feats: dict[str, np.ndarray]) -> np.ndarray:
        """Features as an array of shape ``(len(FEATURES), n_ommatidia)``."""
        return np.stack([feats[f] for f in FEATURES])

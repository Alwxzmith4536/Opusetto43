"""Visual projection neurons (VPNs): pool optic-lobe channels into spiking input rates.

Each VPN has a feature channel, an eye and a receptive-field centre (azimuth). It pools
its channel over the ommatidia of that eye with a Gaussian azimuth profile spanning the
whole elevation band, using a soft-max (generalised mean, p=4) so that a small target
anywhere in the field drives it, as lobula columnar (LC) neurons do. The pooled value
(0..1) becomes a Poisson rate ``max_rate * value``.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .eye import CompoundEye
from .optic_lobe import FEATURES


@dataclass
class VPNLayout:
    feature: np.ndarray  # int index into FEATURES, per VPN
    eye: np.ndarray  # "L"/"R" per VPN
    azimuth: np.ndarray  # receptive-field centre (deg) per VPN

    @property
    def n(self) -> int:
        return int(self.feature.size)

    @staticmethod
    def columnar(eye: CompoundEye, features: tuple[str, ...] = FEATURES, step: float | None = None,
                 copies: int = 1) -> "VPNLayout":
        """One VPN per (feature, eye, azimuth column) tiling each eye's field."""
        step = step or eye.cfg.spacing
        feats, eyes, azs = [], [], []
        for side in ("L", "R"):
            az = eye.azimuth[eye.eye == side]
            centres = np.arange(az.min(), az.max() + 1e-6, step)
            for f in features:
                for c in centres:
                    for _ in range(copies):
                        feats.append(FEATURES.index(f))
                        eyes.append(side)
                        azs.append(c)
        return VPNLayout(np.asarray(feats), np.asarray(eyes), np.asarray(azs, dtype=float))


class VPNEncoder:
    """Turn optic-lobe features into VPN firing rates."""

    def __init__(self, eye: CompoundEye, layout: VPNLayout, rf_sigma: float | None = None,
                 max_rate: float = 150.0, power: float = 4.0, suppression: float = 1.0,
                 adapt_tau: float = 50.0, threshold: float = 1.0, headroom: float = 2.0):
        self.layout = layout
        self.max_rate = max_rate
        self.power = power
        # wide-field suppression: each VPN is inhibited by the mean of its own channel across
        # the eye, so uniform texture is ignored and odd-one-out targets pop out (LC11-like)
        self.suppression = suppression
        self._gid = layout.feature * 2 + (layout.eye == "R")
        self._gcount = np.maximum(np.bincount(self._gid), 1)
        # contrast gain control: each channel is divided by its running RMS (time constant
        # adapt_tau frames); responses below `threshold` x RMS are silent and the rate
        # saturates `headroom` RMS above that, so only outstanding columns fire strongly
        self.adapt_rate = 1.0 / adapt_tau if adapt_tau else 0.0
        self.threshold = threshold
        self.headroom = headroom
        self._feat_count = np.maximum(np.bincount(layout.feature, minlength=len(FEATURES)), 1)
        sigma = rf_sigma or eye.cfg.spacing * 0.8
        same_eye = layout.eye[:, None] == eye.eye[None, :]
        d = layout.azimuth[:, None] - eye.azimuth[None, :]
        w = np.exp(-0.5 * (d / sigma) ** 2) * same_eye
        w[w < 1e-3] = 0.0
        w /= np.maximum(w.sum(axis=1, keepdims=True), 1e-9)
        self.W = w  # (n_vpn, n_ommatidia)
        self.reset()

    def reset(self) -> None:
        """Forget the adapted channel gains."""
        self._ms = None

    def pooled(self, feats: dict[str, np.ndarray]) -> np.ndarray:
        """Pooled feature value (0..1) per VPN."""
        stack = np.stack([feats[f] for f in FEATURES])  # (n_feat, n_omm)
        p = self.power
        per_vpn = stack[self.layout.feature]  # (n_vpn, n_omm)
        val = (np.einsum("vo,vo->v", self.W, per_vpn ** p)) ** (1.0 / p)
        if self.suppression:
            mean = (np.bincount(self._gid, weights=val, minlength=self._gcount.size) / self._gcount)[self._gid]
            val = np.maximum(val - self.suppression * mean, 0.0)
        if self.adapt_rate:
            ms = np.bincount(self.layout.feature, weights=val ** 2, minlength=len(FEATURES)) / self._feat_count
            self._ms = ms if self._ms is None else self._ms + self.adapt_rate * (ms - self._ms)
            rms = np.sqrt(np.maximum(self._ms, 1e-6))
            val = (val / rms[self.layout.feature] - self.threshold) / self.headroom
        return np.clip(val, 0.0, 1.0)

    def rates(self, feats: dict[str, np.ndarray]) -> np.ndarray:
        return self.max_rate * self.pooled(feats)

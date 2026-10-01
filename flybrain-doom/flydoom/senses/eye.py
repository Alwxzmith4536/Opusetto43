"""Compound eyes: sample a game frame with two hexagonal ommatidia lattices.

Each ommatidium looks along a direction (azimuth, elevation) and integrates the image
through a Gaussian acceptance function (fly: inter-ommatidial angle ~5 deg, acceptance
angle ~5 deg). The frame is treated as a pinhole projection with Doom's 90 deg
horizontal field of view. The left eye covers the left part of the frame plus a
binocular overlap zone around the midline, the right eye the mirror image.

Spectral channels follow the fly rather than the monitor: R1-6 (broadband, green
peak) give luminance, and an R7/R8-like opponent channel compares the short (blue)
and middle (green) wavelength bands. Flies have no red receptor.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import scipy.sparse as sp


@dataclass(frozen=True)
class EyeConfig:
    fov_h: float = 90.0  # horizontal field of view of the frame (deg)
    spacing: float = 5.0  # inter-ommatidial angle (deg)
    acceptance: float = 5.5  # acceptance angle, FWHM (deg)
    overlap: float = 10.0  # binocular overlap: each eye sees this far past the midline (deg)
    elev_min: float = -20.0  # ventral limit (deg) - below this the frame shows the weapon/floor
    elev_max: float = 25.0  # dorsal limit (deg)


class CompoundEye:
    """Pair of compound eyes for frames of a fixed size ``(height, width)``."""

    def __init__(self, frame_shape: tuple[int, int], config: EyeConfig | None = None):
        self.cfg = config or EyeConfig()
        self.h, self.w = int(frame_shape[0]), int(frame_shape[1])
        cfg = self.cfg
        self.focal = (self.w / 2) / math.tan(math.radians(cfg.fov_h / 2))
        half_v = math.degrees(math.atan((self.h / 2) / self.focal))
        el_lo, el_hi = max(cfg.elev_min, -half_v + 1), min(cfg.elev_max, half_v - 1)
        az, el, eye = [], [], []
        row_step = cfg.spacing * math.sqrt(3) / 2
        half_h = cfg.fov_h / 2 - 1
        for side, (lo, hi) in (("L", (-half_h, cfg.overlap)), ("R", (-cfg.overlap, half_h))):
            r = 0
            e = el_lo
            while e <= el_hi + 1e-9:
                shift = (cfg.spacing / 2) if (r % 2) else 0.0
                a = lo + shift
                while a <= hi + 1e-9:
                    az.append(a)
                    el.append(e)
                    eye.append(side)
                    a += cfg.spacing
                e += row_step
                r += 1
        self.azimuth = np.asarray(az)  # deg, negative = left of midline
        self.elevation = np.asarray(el)  # deg, positive = up
        self.eye = np.asarray(eye)
        self.n = self.azimuth.size
        self.S = self._sampling_matrix()
        self.neighbors = self._neighbor_matrix()
        self.right_neighbor = self._right_neighbor()

    # ----------------------------------------------------------- construction
    def _pixel(self, az: np.ndarray, el: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        x = self.w / 2 + self.focal * np.tan(np.radians(az))
        y = self.h / 2 - self.focal * np.tan(np.radians(el)) / np.cos(np.radians(az))
        return x, y

    def _sampling_matrix(self) -> sp.csr_matrix:
        x0, y0 = self._pixel(self.azimuth, self.elevation)
        sigma_deg = self.cfg.acceptance / 2.355
        rows, cols, vals = [], [], []
        for i in range(self.n):
            sig = self.focal * math.radians(sigma_deg) / math.cos(math.radians(self.azimuth[i]))
            sig = max(sig, 0.5)
            rad = int(math.ceil(2.5 * sig))
            xs = np.arange(int(x0[i]) - rad, int(x0[i]) + rad + 2)
            ys = np.arange(int(y0[i]) - rad, int(y0[i]) + rad + 2)
            xs = xs[(xs >= 0) & (xs < self.w)]
            ys = ys[(ys >= 0) & (ys < self.h)]
            if xs.size == 0 or ys.size == 0:
                continue
            gx = np.exp(-0.5 * ((xs + 0.5 - x0[i]) / sig) ** 2)
            gy = np.exp(-0.5 * ((ys + 0.5 - y0[i]) / sig) ** 2)
            wgt = np.outer(gy, gx)
            wgt /= wgt.sum()
            yy, xx = np.meshgrid(ys, xs, indexing="ij")
            rows.append(np.full(wgt.size, i))
            cols.append((yy * self.w + xx).ravel())
            vals.append(wgt.ravel())
        return sp.csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))),
                             shape=(self.n, self.h * self.w))

    def _neighbor_matrix(self) -> sp.csr_matrix:
        """Row-normalised adjacency to the (up to 6) nearest ommatidia of the same eye."""
        rows, cols = [], []
        lim = 1.25 * self.cfg.spacing
        for side in ("L", "R"):
            idx = np.flatnonzero(self.eye == side)
            da = self.azimuth[idx, None] - self.azimuth[None, idx]
            de = self.elevation[idx, None] - self.elevation[None, idx]
            close = (np.hypot(da, de) < lim) & (np.hypot(da, de) > 1e-6)
            i, j = np.nonzero(close)
            rows.append(idx[i])
            cols.append(idx[j])
        rows, cols = np.concatenate(rows), np.concatenate(cols)
        m = sp.csr_matrix((np.ones(rows.size), (rows, cols)), shape=(self.n, self.n))
        deg = np.asarray(m.sum(axis=1)).ravel()
        deg[deg == 0] = 1
        return sp.diags(1.0 / deg) @ m

    def _right_neighbor(self) -> np.ndarray:
        """Index of the horizontal neighbour one spacing to the right (or -1)."""
        out = np.full(self.n, -1, dtype=np.int64)
        for i in range(self.n):
            same = (self.eye == self.eye[i]) & (np.abs(self.elevation - self.elevation[i]) < 1e-6)
            cand = np.flatnonzero(same & (self.azimuth > self.azimuth[i] + 1e-6))
            if cand.size:
                j = cand[np.argmin(self.azimuth[cand])]
                if self.azimuth[j] - self.azimuth[i] < 1.5 * self.cfg.spacing:
                    out[i] = j
        return out

    # ---------------------------------------------------------------- sampling
    def sample(self, frame: np.ndarray) -> dict[str, np.ndarray]:
        """Photoreceptor signals for an ``(H, W, 3)`` uint8 RGB frame, each in [0, 1].

        Returns ``lum`` (R1-6) and ``short``/``middle`` (R7/R8-like spectral bands).
        """
        if frame.shape[:2] != (self.h, self.w):
            raise ValueError(f"frame shape {frame.shape[:2]} != eye shape {(self.h, self.w)}")
        f = frame.reshape(-1, frame.shape[-1]).astype(np.float32) / 255.0
        r, g, b = f[:, 0], f[:, 1], f[:, 2]
        lum = self.S @ (0.15 * r + 0.55 * g + 0.30 * b)
        short = self.S @ b
        middle = self.S @ g
        return {"lum": lum, "short": short, "middle": middle}

    def render(self, values: np.ndarray, scale: int = 4) -> np.ndarray:
        """Debug image: paint each ommatidium's value (0..1) at its pixel position."""
        img = np.zeros((self.h, self.w), dtype=np.float32)
        x, y = self._pixel(self.azimuth, self.elevation)
        for xi, yi, val in zip(x.astype(int), y.astype(int), values):
            img[max(0, yi - scale // 2):yi + scale // 2 + 1, max(0, xi - scale // 2):xi + scale // 2 + 1] = val
        return img

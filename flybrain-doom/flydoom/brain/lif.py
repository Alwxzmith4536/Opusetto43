"""Leaky integrate-and-fire network with the whole-brain parameters of Shiu et al. (2024).

Model (Shiu et al., Nature 634:210, 2024; github.com/philshiu/Drosophila_brain_model)::

    dv/dt = (v_0 - v + g) / t_mbr        (unless refractory)
    dg/dt = -g / tau                     (unless refractory)
    on presynaptic spike (after t_dly):  g_post += w   with  w = signed_synapse_count * w_syn
    on v > v_th:                         v = v_rst, g = 0, refractory for t_rfc
    Poisson "optogenetic" drive:         v += w_syn * f_poi  at rate r

    v_0 = v_rst = -52 mV, v_th = -45 mV, t_mbr = 20 ms, tau = 5 ms,
    t_rfc = 2.2 ms, t_dly = 1.8 ms, w_syn = 0.275 mV, f_poi = 250

Between spikes the linear system is integrated exactly (exponential propagator), so a
coarser ``dt`` than Brian2's 0.1 ms default stays stable; the synaptic delay is
rounded to whole steps. Spike propagation gathers only the CSR rows of neurons that
spiked, so cost scales with activity rather than with the number of synapses.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

from .connectome import Connectome


@dataclass(frozen=True)
class LIFParams:
    dt: float = 0.5  # ms
    v_rest: float = -52.0  # mV (v_0)
    v_reset: float = -52.0  # mV (v_rst)
    v_thresh: float = -45.0  # mV (v_th)
    tau_m: float = 20.0  # ms (t_mbr)
    tau_syn: float = 5.0  # ms (tau)
    t_ref: float = 2.2  # ms (t_rfc)
    delay: float = 1.8  # ms (t_dly)
    w_syn: float = 0.275  # mV per synapse
    poisson_weight: float = 0.275 * 250  # mV per Poisson event (w_syn * f_poi)

    @property
    def delay_steps(self) -> int:
        return max(1, int(round(self.delay / self.dt)))

    @property
    def ref_steps(self) -> int:
        return max(1, int(math.ceil(self.t_ref / self.dt - 1e-9)))

    def propagator(self) -> tuple[float, float, float]:
        """Exact one-step update ``v' = v0 + (v - v0)*a + g*b``, ``g' = g*c``."""
        a = math.exp(-self.dt / self.tau_m)
        c = math.exp(-self.dt / self.tau_syn)
        if abs(self.tau_syn - self.tau_m) < 1e-12:
            b = (self.dt / self.tau_m) * a
        else:
            b = self.tau_syn / (self.tau_syn - self.tau_m) * (c - a)
        return a, b, c


class LIFNetwork:
    """Vectorised LIF simulator over a :class:`Connectome`."""

    def __init__(self, connectome: Connectome, params: LIFParams | None = None, seed: int | None = None):
        self.connectome = connectome
        self.p = params or LIFParams()
        self.n = connectome.n
        self.rng = np.random.default_rng(seed)
        self.csr, pos = connectome.to_csr()
        pre, post, _ = connectome.edges()
        self.plastic: dict[str, dict[str, np.ndarray]] = {}
        for name, eids in connectome.plastic_sets.items():
            self.plastic[name] = {"pos": pos[eids], "pre": pre[eids], "post": post[eids]}
        self.D = self.p.delay_steps
        self.n_ref = self.p.ref_steps
        self._a, self._b, self._c = self.p.propagator()
        self.alive = np.ones(self.n, dtype=bool)
        self.rate_hz = np.zeros(self.n, dtype=np.float32)
        self._drive_dirty = True
        self._drive_idx = np.zeros(0, dtype=np.int64)
        self._drive_p = np.zeros(0)
        self.reset_state()

    # ------------------------------------------------------------------ state
    def reset_state(self) -> None:
        """Return every neuron to rest and drop in-flight spikes (weights are kept)."""
        p = self.p
        self.v = np.full(self.n, p.v_rest, dtype=np.float32)
        self.g = np.zeros(self.n, dtype=np.float32)
        self.ref_until = np.zeros(self.n, dtype=np.int64)
        self.buf = np.zeros((self.D + 1, self.n), dtype=np.float32)
        self.t = 0  # global step counter

    # ------------------------------------------------------------------ drive
    def set_rate(self, idx: np.ndarray, rate_hz: np.ndarray | float) -> None:
        """Poisson drive (Hz) for neurons ``idx``; each event kicks v by ``poisson_weight``."""
        self.rate_hz[np.asarray(idx, dtype=np.int64)] = rate_hz
        self._drive_dirty = True

    def clear_rates(self, idx: np.ndarray | None = None) -> None:
        if idx is None:
            self.rate_hz[:] = 0.0
        else:
            self.rate_hz[np.asarray(idx, dtype=np.int64)] = 0.0
        self._drive_dirty = True

    def silence(self, idx: np.ndarray) -> None:
        """Optogenetic-style silencing: the neurons never spike (their synapses go quiet)."""
        self.alive[np.asarray(idx, dtype=np.int64)] = False
        self._drive_dirty = True

    def unsilence(self, idx: np.ndarray | None = None) -> None:
        if idx is None:
            self.alive[:] = True
        else:
            self.alive[np.asarray(idx, dtype=np.int64)] = True
        self._drive_dirty = True

    def _refresh_drive(self) -> None:
        idx = np.flatnonzero((self.rate_hz > 0) & self.alive)
        self._drive_idx = idx
        self._drive_p = np.minimum(self.rate_hz[idx].astype(np.float64) * self.p.dt * 1e-3, 1.0)
        self._drive_dirty = False

    # ---------------------------------------------------------------- weights
    def get_weights(self, plastic_set: str) -> np.ndarray:
        return self.csr.data[self.plastic[plastic_set]["pos"]].copy()

    def set_weights(self, plastic_set: str, w: np.ndarray) -> None:
        self.csr.data[self.plastic[plastic_set]["pos"]] = np.asarray(w, dtype=np.float32)

    # ------------------------------------------------------------- simulation
    def run(self, duration_ms: float, record: np.ndarray | None = None):
        """Simulate ``duration_ms``. Returns per-neuron spike counts (int32).

        With ``record`` (bool mask or indices), also returns ``(steps, neurons)`` arrays of
        every spike from the recorded neurons, with ``steps`` relative to the run start.
        """
        if self._drive_dirty:
            self._refresh_drive()
        n_steps = int(round(duration_ms / self.p.dt))
        counts = np.zeros(self.n, dtype=np.int32)
        rec_mask = None
        if record is not None:
            record = np.asarray(record)
            rec_mask = record if record.dtype == bool else np.isin(np.arange(self.n), record)
            rec_steps: list[np.ndarray] = []
            rec_ids: list[np.ndarray] = []
        p = self.p
        a, b, c = self._a, self._b, self._c
        v, g, buf = self.v, self.g, self.buf
        indptr, indices, data = self.csr.indptr, self.csr.indices, self.csr.data
        drive_idx, drive_p = self._drive_idx, self._drive_p
        alive = self.alive
        ring = self.D + 1
        v_rest = np.float32(p.v_rest)
        for k in range(n_steps):
            t = self.t
            slot = t % ring
            g += buf[slot]
            buf[slot] = 0.0
            active = self.ref_until <= t
            # exact integration for non-refractory neurons; refractory ones are frozen
            v_new = (v - v_rest) * np.float32(a) + g * np.float32(b) + v_rest
            np.copyto(v, v_new, where=active)
            np.multiply(g, np.float32(c), out=g, where=active)
            if drive_idx.size:
                hit = drive_idx[self.rng.random(drive_idx.size) < drive_p]
                if hit.size:
                    v[hit] += np.float32(p.poisson_weight)
            spk = np.flatnonzero((v > p.v_thresh) & active & alive)
            if spk.size:
                v[spk] = p.v_reset
                g[spk] = 0.0
                self.ref_until[spk] = t + self.n_ref
                counts[spk] += 1
                if rec_mask is not None:
                    r = spk[rec_mask[spk]]
                    if r.size:
                        rec_steps.append(np.full(r.size, k, dtype=np.int32))
                        rec_ids.append(r.astype(np.int32))
                st = indptr[spk]
                ln = indptr[spk + 1] - st
                tot = int(ln.sum())
                if tot:
                    if spk.size == 1:
                        off = np.arange(st[0], st[0] + tot)
                    else:
                        ends = np.cumsum(ln)
                        off = np.arange(tot, dtype=np.int64) + np.repeat(st - (ends - ln), ln)
                    inc = np.bincount(indices[off], weights=data[off], minlength=self.n)
                    buf[(t + self.D) % ring] += inc.astype(np.float32)
            self.t += 1
        if rec_mask is not None:
            steps = np.concatenate(rec_steps) if rec_steps else np.zeros(0, dtype=np.int32)
            ids = np.concatenate(rec_ids) if rec_ids else np.zeros(0, dtype=np.int32)
            return counts, (steps, ids)
        return counts

    def rates_hz(self, counts: np.ndarray, duration_ms: float) -> np.ndarray:
        return counts.astype(np.float64) / (duration_ms * 1e-3)

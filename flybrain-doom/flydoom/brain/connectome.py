"""Connectome container: neurons, signed weighted edges, named groups, plastic edge sets.

A :class:`Connectome` is the wiring diagram the LIF simulator runs on. It can come
from real data (FlyWire v783, see :mod:`flydoom.brain.flywire`) or be generated
procedurally (see :mod:`flydoom.brain.synthetic`). Weights are stored in mV of
synaptic drive per presynaptic spike (Shiu et al. 2024 use
``signed synapse count x 0.275 mV``).
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np


@dataclass
class CSR:
    """Row-compressed weight matrix: row = presynaptic neuron, column = postsynaptic."""

    indptr: np.ndarray  # int64, shape (n + 1,)
    indices: np.ndarray  # int32, postsynaptic neuron of each stored edge
    data: np.ndarray  # float32, weight (mV) of each stored edge
    n: int

    @property
    def nnz(self) -> int:
        return int(self.indices.size)


@dataclass
class Connectome:
    """Neurons + signed edges + named neuron groups + named plastic edge sets."""

    n: int = 0
    cell_type: list[str] = field(default_factory=list)
    side: list[str] = field(default_factory=list)
    groups: dict[str, np.ndarray] = field(default_factory=dict)
    plastic_sets: dict[str, np.ndarray] = field(default_factory=dict)
    neuron_ids: np.ndarray | None = None
    meta: dict = field(default_factory=dict)
    _pre: list[np.ndarray] = field(default_factory=list, repr=False)
    _post: list[np.ndarray] = field(default_factory=list, repr=False)
    _w: list[np.ndarray] = field(default_factory=list, repr=False)
    _n_edges: int = field(default=0, repr=False)

    # ------------------------------------------------------------------ neurons
    def add_neurons(self, group: str, count: int, cell_type: str | None = None,
                    side: str = "") -> np.ndarray:
        """Append ``count`` neurons, register them under ``group`` and return their indices."""
        idx = np.arange(self.n, self.n + count, dtype=np.int64)
        self.n += count
        self.cell_type.extend([cell_type or group] * count)
        self.side.extend([side] * count)
        if group in self.groups:
            self.groups[group] = np.concatenate([self.groups[group], idx])
        else:
            self.groups[group] = idx
        return idx

    def group(self, name: str) -> np.ndarray:
        return self.groups[name]

    def groups_matching(self, prefix: str) -> list[str]:
        return [g for g in self.groups if g.startswith(prefix)]

    def select(self, cell_type: str | list[str] | None = None, side: str | None = None) -> np.ndarray:
        """Indices of neurons whose cell type (exact match or list) and side match."""
        types = np.asarray(self.cell_type, dtype=object)
        mask = np.ones(self.n, dtype=bool)
        if cell_type is not None:
            wanted = [cell_type] if isinstance(cell_type, str) else list(cell_type)
            mask &= np.isin(types, wanted)
        if side is not None:
            mask &= np.asarray(self.side, dtype=object) == side
        return np.flatnonzero(mask)

    # -------------------------------------------------------------------- edges
    @property
    def n_edges(self) -> int:
        return self._n_edges

    def add_edges(self, pre: np.ndarray, post: np.ndarray, weight_mv: np.ndarray | float,
                  plastic: str | None = None) -> np.ndarray:
        """Append edges ``pre -> post`` (weights in mV). Returns their edge ids.

        If ``plastic`` is given, the edges are registered in that plastic set so a
        learning rule can rewrite their weights at run time.
        """
        pre = np.asarray(pre, dtype=np.int64).ravel()
        post = np.asarray(post, dtype=np.int64).ravel()
        if pre.shape != post.shape:
            raise ValueError("pre and post must have the same length")
        w = np.broadcast_to(np.asarray(weight_mv, dtype=np.float32), pre.shape).copy()
        if pre.size and (pre.min() < 0 or post.min() < 0 or pre.max() >= self.n or post.max() >= self.n):
            raise IndexError("edge endpoint outside neuron range")
        ids = np.arange(self._n_edges, self._n_edges + pre.size, dtype=np.int64)
        self._pre.append(pre)
        self._post.append(post)
        self._w.append(w)
        self._n_edges += pre.size
        if plastic is not None:
            prev = self.plastic_sets.get(plastic)
            self.plastic_sets[plastic] = ids if prev is None else np.concatenate([prev, ids])
        return ids

    def connect_random(self, pre_idx: np.ndarray, post_idx: np.ndarray, p: float, weight_mv: float,
                       rng: np.random.Generator, jitter: float = 0.0, plastic: str | None = None) -> np.ndarray:
        """Bernoulli(p) connections between two populations (no self-loops)."""
        pre_idx = np.asarray(pre_idx)
        post_idx = np.asarray(post_idx)
        mask = rng.random((pre_idx.size, post_idx.size)) < p
        i, j = np.nonzero(mask)
        pre, post = pre_idx[i], post_idx[j]
        keep = pre != post
        pre, post = pre[keep], post[keep]
        w = np.full(pre.size, weight_mv, dtype=np.float32)
        if jitter:
            w *= rng.lognormal(0.0, jitter, size=pre.size).astype(np.float32)
        return self.add_edges(pre, post, w, plastic=plastic)

    def connect_all(self, pre_idx: np.ndarray, post_idx: np.ndarray, weight_mv: float,
                    plastic: str | None = None) -> np.ndarray:
        pre, post = np.meshgrid(np.asarray(pre_idx), np.asarray(post_idx), indexing="ij")
        keep = pre.ravel() != post.ravel()
        return self.add_edges(pre.ravel()[keep], post.ravel()[keep], weight_mv, plastic=plastic)

    def edges(self) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """All edges as ``(pre, post, weight_mv)`` arrays (concatenated, in insertion order)."""
        if len(self._pre) > 1:  # consolidate so repeated calls are cheap
            self._pre = [np.concatenate(self._pre)]
            self._post = [np.concatenate(self._post)]
            self._w = [np.concatenate(self._w)]
        if not self._pre:
            empty = np.zeros(0, dtype=np.int64)
            return empty, empty, np.zeros(0, dtype=np.float32)
        return self._pre[0], self._post[0], self._w[0]

    # ---------------------------------------------------------------- compiling
    def to_csr(self) -> tuple[CSR, np.ndarray]:
        """Compile to CSR. Returns the matrix and ``pos``: CSR data position of every edge id.

        Duplicate ``pre -> post`` pairs are kept as separate stored entries (their effects
        add up), which keeps a one-to-one mapping between edge ids and CSR positions.
        """
        pre, post, w = self.edges()
        order = np.argsort(pre, kind="stable")
        counts = np.bincount(pre, minlength=self.n) if pre.size else np.zeros(self.n, dtype=np.int64)
        indptr = np.zeros(self.n + 1, dtype=np.int64)
        np.cumsum(counts, out=indptr[1:])
        pos = np.empty(pre.size, dtype=np.int64)
        pos[order] = np.arange(pre.size, dtype=np.int64)
        csr = CSR(indptr=indptr, indices=post[order].astype(np.int32),
                  data=w[order].astype(np.float32), n=self.n)
        return csr, pos

    # ------------------------------------------------------------------ helpers
    def subgraph(self, keep: np.ndarray) -> "Connectome":
        """Return the induced subgraph on neurons ``keep`` (bool mask or indices).

        Groups are remapped; plastic sets keep only edges that survive.
        """
        keep = np.asarray(keep)
        mask = keep if keep.dtype == bool else np.isin(np.arange(self.n), keep)
        new_index = np.full(self.n, -1, dtype=np.int64)
        new_index[mask] = np.arange(int(mask.sum()))
        out = Connectome(meta=dict(self.meta))
        out.n = int(mask.sum())
        out.cell_type = [t for t, k in zip(self.cell_type, mask) if k]
        out.side = [s for s, k in zip(self.side, mask) if k]
        if self.neuron_ids is not None:
            out.neuron_ids = self.neuron_ids[mask]
        for name, idx in self.groups.items():
            remapped = new_index[idx]
            out.groups[name] = remapped[remapped >= 0]
        pre, post, w = self.edges()
        ok = mask[pre] & mask[post] if pre.size else np.zeros(0, dtype=bool)
        new_edge = np.full(pre.size, -1, dtype=np.int64)
        new_edge[ok] = np.arange(int(ok.sum()))
        out.add_edges(new_index[pre[ok]], new_index[post[ok]], w[ok])
        for name, eids in self.plastic_sets.items():
            remapped = new_edge[eids]
            out.plastic_sets[name] = remapped[remapped >= 0]
        return out

    def summary(self) -> str:
        pre, post, w = self.edges()
        lines = [f"Connectome: {self.n:,} neurons, {pre.size:,} edges "
                 f"({(w > 0).sum():,} excitatory / {(w < 0).sum():,} inhibitory)"]
        for name, idx in list(self.groups.items())[:40]:
            lines.append(f"  group {name:<28s} {idx.size:>7,d} neurons")
        if len(self.groups) > 40:
            lines.append(f"  ... {len(self.groups) - 40} more groups")
        for name, eids in self.plastic_sets.items():
            lines.append(f"  plastic {name:<26s} {eids.size:>7,d} edges")
        return "\n".join(lines)

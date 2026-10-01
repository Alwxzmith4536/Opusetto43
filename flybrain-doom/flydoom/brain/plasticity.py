"""Dopamine-gated three-factor plasticity (eligibility trace x dopamine) at KC -> MBON synapses.

Mushroom-body output synapses are rewired by dopamine: a Kenyon cell that was active
shortly before a dopamine neuron fires has its synapse onto that compartment's MBON
changed (Hige et al. 2015; Cohn et al. 2015). Here that "shortly before" is an
eligibility trace, and the dopamine signal is a reward prediction error carried by the
spike counts of reward (PAM) and punishment (PPL1) dopamine neurons, so the rule is
actor-critic TD(lambda) learning written as a three-factor rule:

    critic synapse KC_i -> MBON+/- :  e_i  = phi_i * (+1 / -1)
    actor synapse  KC_i -> MBON_a  :  e_ia = phi_i * (1[a chosen] - p_a)
    traces                         :  E <- gamma * lambda * E + e
    weight change                  :  dw = lr * w_ref * dopamine * E,  clipped to [0, w_max]

``phi_i`` is the (capped) spike count of KC i in the decision window and ``p_a`` the share
of descending-neuron spikes voting for action a. Silencing the dopamine neurons makes
``dopamine`` zero, so the lesion abolishes learning; that is one of the engine's controls.
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .lif import LIFNetwork


@dataclass
class PlasticityConfig:
    gamma: float = 0.95
    lam: float = 0.8
    lr_actor: float = 0.5  # weight change per unit eligibility per unit dopamine, as a fraction of w_ref
    lr_critic: float = 0.2
    phi_cap: int = 3  # KC spike count that counts as "fully active"
    ref_active: float = 60.0  # eligibility is normalised to this many fully active KCs


class ActorCriticPlasticity:
    """Bookkeeping for the plastic sets ``actor`` and ``critic`` of a network."""

    def __init__(self, net: LIFNetwork, state_idx: np.ndarray, actor: dict[str, np.ndarray],
                 critic_pos: np.ndarray, critic_neg: np.ndarray, weight_max: dict[str, float],
                 config: PlasticityConfig | None = None):
        self.net = net
        self.cfg = config or PlasticityConfig()
        self.state_idx = np.asarray(state_idx)
        state_pos = np.full(net.n, -1, dtype=np.int64)
        state_pos[self.state_idx] = np.arange(self.state_idx.size)
        self.actions = list(actor)
        post_action = np.full(net.n, -1, dtype=np.int64)
        for k, name in enumerate(self.actions):
            post_action[actor[name]] = k
        post_sign = np.zeros(net.n)
        post_sign[critic_pos] = 1.0
        post_sign[critic_neg] = -1.0

        self.sets = {}
        if "actor" in net.plastic:
            a = net.plastic["actor"]
            self.sets["actor"] = {"pre": state_pos[a["pre"]], "act": post_action[a["post"]]}
        if "critic" in net.plastic:
            cset = net.plastic["critic"]
            sign = post_sign[cset["post"]]
            self.sets["critic"] = {"pre": state_pos[cset["pre"]], "sign": sign,
                                   "n_pos": max(np.unique(cset["post"][sign > 0]).size, 1),
                                   "n_neg": max(np.unique(cset["post"][sign < 0]).size, 1)}
        for s in self.sets.values():
            if (s["pre"] < 0).any():
                raise ValueError("plastic synapse whose presynaptic neuron is not in state_idx")
        self.w_max = weight_max
        self.w_ref = 1.0  # reference weight (mV); set by FlyAgent.calibrate
        self.enabled_actions = np.ones(len(self.actions), dtype=bool)
        self.reset_traces()

    def reset_traces(self) -> None:
        self.E = {name: np.zeros(s["pre"].size) for name, s in self.sets.items()}

    def critic_drive(self, counts: np.ndarray, value_mv: float = 0.5) -> float:
        """Value from the critic MBONs' synaptic drive: spike-weighted KC input to MBON+
        minus MBON-, per MBON, in units of ``ref_active`` KCs x ``value_mv``."""
        s = self.sets["critic"]
        x, _ = self.phi(counts)
        w = self.net.get_weights("critic")
        contrib = x[s["pre"]] * w
        pos = s["sign"] > 0
        drive = contrib[pos].sum() / s["n_pos"] - contrib[~pos].sum() / s["n_neg"]
        return float(drive / (self.cfg.ref_active * value_mv))

    def phi(self, counts: np.ndarray) -> tuple[np.ndarray, float]:
        """Capped, normalised KC activity and the number of fully active KC equivalents."""
        x = np.minimum(counts[self.state_idx], self.cfg.phi_cap) / self.cfg.phi_cap
        total = float(x.sum())
        return x * (self.cfg.ref_active / max(total, self.cfg.ref_active * 0.25)), total

    def accumulate(self, counts: np.ndarray, action: int | None, probs: np.ndarray) -> None:
        """Decay the traces and add this decision's eligibility."""
        x, _ = self.phi(counts)
        decay = self.cfg.gamma * self.cfg.lam
        if "actor" in self.sets:
            s = self.sets["actor"]
            target = np.zeros(len(self.actions))
            if action is not None:
                target[action] = 1.0
            factor = np.where(self.enabled_actions, target - probs, 0.0)
            act = s["act"]
            self.E["actor"] = decay * self.E["actor"] + x[s["pre"]] * factor[act]
        if "critic" in self.sets:
            s = self.sets["critic"]
            self.E["critic"] = decay * self.E["critic"] + x[s["pre"]] * s["sign"]

    def apply_dopamine(self, dopamine: float, only: tuple[str, ...] | None = None) -> dict[str, float]:
        """Rewrite plastic weights by ``lr * w_ref * dopamine * E``; returns mean |dw| per set."""
        names = [n for n in self.sets if only is None or n in only]
        out = {}
        if dopamine == 0.0:
            return {name: 0.0 for name in names}
        for name in names:
            lr = (self.cfg.lr_actor if name == "actor" else self.cfg.lr_critic) * self.w_ref
            w = self.net.get_weights(name)
            dw = lr * dopamine * self.E[name]
            w_new = np.clip(w + dw, 0.0, self.w_max.get(name, np.inf))
            self.net.set_weights(name, w_new)
            out[name] = float(np.abs(w_new - w).mean())
        return out

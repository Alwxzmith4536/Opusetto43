"""The sensorimotor loop: Doom frame -> compound eye -> optic lobe -> spiking brain -> motor command.

One game step (``frame_skip`` Doom tics, ~114 ms of game time) corresponds to:

1. **perception window** (``window_ms`` of brain time): the frame's VPN rates drive the
   LIF network; spike counts of KCs, MBONs and descending neurons are collected;
2. **value readout**: appetitive minus aversive critic-MBON synaptic drive (or, with
   ``value_readout="spikes"``, spike rate) gives V(s_t);
3. **dopamine burst** (``dopamine_ms``): the reward prediction error of the previous
   step, ``delta = r + gamma*V(s_t) - V(s_{t-1})``, is delivered as Poisson drive to PAM
   (delta > 0) or PPL1 (delta < 0) dopamine neurons; their spike counts are the third
   factor that rewires KC -> MBON synapses;
4. **action**: the descending-neuron group with the most spikes wins.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from ..brain.blueprint import BrainBlueprint
from ..brain.lif import LIFNetwork, LIFParams
from ..brain.plasticity import ActorCriticPlasticity, PlasticityConfig
from ..senses.eye import CompoundEye, EyeConfig
from ..senses.optic_lobe import OpticLobe
from ..senses.vpn import VPNEncoder


@dataclass
class AgentConfig:
    window_ms: float = 50.0
    dopamine_ms: float = 30.0
    dan_max_hz: float = 200.0
    value_hz: float = 40.0  # 'spikes' readout: critic rate difference (Hz) for a value of 1.0
    value_readout: str = "drive"  # 'drive' (MBON synaptic drive) or 'spikes' (MBON spike counts)
    value_frac: float = 0.5  # 'drive' readout: weight difference per active KC, as a fraction of
    #                          the reference weight, that encodes a value of 1.0
    learning: bool = True
    plasticity: PlasticityConfig = field(default_factory=PlasticityConfig)
    record: bool = False  # keep per-step traces (for reports and replays)


class FlyAgent:
    def __init__(self, blueprint: BrainBlueprint, frame_shape: tuple[int, int],
                 eye_config: EyeConfig | None = None, lif: LIFParams | None = None,
                 config: AgentConfig | None = None, encoder_kwargs: dict | None = None,
                 seed: int = 0):
        self.bp = blueprint
        self.cfg = config or AgentConfig()
        self.eye = CompoundEye(frame_shape, eye_config)
        self.optic_lobe = OpticLobe(self.eye)
        self.encoder = VPNEncoder(self.eye, blueprint.vpn_layout, **{**blueprint.encoder, **(encoder_kwargs or {})})
        self.net = LIFNetwork(blueprint.connectome, lif, seed=seed)
        self.rng = np.random.default_rng(seed + 1)
        for idx, hz in blueprint.tonic:
            self.net.set_rate(idx, hz)
        self.plasticity = ActorCriticPlasticity(
            self.net, blueprint.state_idx, blueprint.actor, blueprint.critic_pos,
            blueprint.critic_neg, blueprint.weight_max, self.cfg.plasticity)
        self.primitives = list(blueprint.actor)
        self.available = list(self.primitives)
        self.trace: list[dict] = []
        self.begin_episode()

    # ---------------------------------------------------------------- wiring
    def bind(self, motor_map: dict[str, str]) -> None:
        """Enable only the motor primitives the scenario supports; silence the rest."""
        self.available = [p for p in self.primitives if p in motor_map]
        if not self.available:
            raise ValueError("no motor primitive of the brain maps onto this scenario")
        self.net.unsilence()
        for p in self.primitives:
            if p not in self.available:
                self.net.silence(self.bp.motor[p])
                self.net.silence(self.bp.actor[p])
        self.plasticity.enabled_actions = np.array([p in self.available for p in self.primitives])

    def calibrate(self, frames: list[np.ndarray], target_drive_mv: float = 6.0, brain_frames: int = 60,
                  w_max_factor: float = 3.0) -> dict:
        """Developmental calibration before any learning.

        1. the VPN contrast-gain control adapts to the scene statistics of ``frames``;
        2. the brain watches up to ``brain_frames`` of them, and the mean rates of the
           presynaptic population (Kenyon cells; DNs in the FlyWire readout) set the initial
           plastic weights so that each MBON's mean synaptic drive is ``target_drive_mv``
           (just below the 7 mV spike threshold), uniformly across its inputs.

        Plasticity learning rates and the value scale are expressed relative to the resulting
        reference weight, so the same settings work for brains of different sizes.
        """
        learning, self.cfg.learning = self.cfg.learning, False
        self.optic_lobe.reset()
        for f in frames:
            self.encoder.pooled(self.optic_lobe.process(f))
        self.begin_episode()
        state_hz = np.zeros(self.bp.state_idx.size)  # Kenyon cells (or DNs for the FlyWire readout)
        n = min(brain_frames, len(frames))
        for f in frames[:n]:
            self.act(f)
            state_hz += self.last_counts[self.bp.state_idx] / (self.cfg.window_ms * 1e-3)
        state_hz /= max(n, 1)
        tau = self.net.p.tau_syn
        ref = []
        for name, sp in self.plasticity.sets.items():
            post = self.net.plastic[name]["post"]
            drive_per_mv = np.bincount(post, weights=state_hz[sp["pre"]] * 1e-3 * tau, minlength=self.net.n)
            w0 = target_drive_mv / np.maximum(drive_per_mv[post], 1e-3)
            w0 = np.minimum(w0, 50.0)
            self.net.set_weights(name, w0)
            self.bp.weight_max[name] = float(np.median(w0) * w_max_factor)
            ref.append(np.median(w0))
        self.plasticity.w_max = self.bp.weight_max
        self.plasticity.w_ref = float(np.mean(ref)) if ref else 1.0
        self.cfg.learning = learning
        self.begin_episode()
        return {"state_rate_hz": float(state_hz.mean()), "state_active_frac": float((state_hz > 0).mean()),
                "w_ref_mv": self.plasticity.w_ref, "w_max_mv": dict(self.bp.weight_max)}

    def lesion(self, what: str) -> None:
        """Silence a population: ``dopamine``, ``kc``, ``dn``, ``vpn`` or ``critic``."""
        targets = {
            "dopamine": [self.bp.dan_reward, self.bp.dan_punish],
            "kc": [self.bp.state_idx],
            "dn": list(self.bp.motor.values()),
            "vpn": [self.bp.vpn_idx],
            "critic": [self.bp.critic_pos, self.bp.critic_neg],
        }[what]
        for idx in targets:
            self.net.silence(idx)

    # ---------------------------------------------------------------- episode
    def begin_episode(self) -> None:
        self.net.reset_state()
        self.optic_lobe.reset()
        self.plasticity.reset_traces()
        self._prev_value: float | None = None
        self._pending_reward = 0.0
        self.last: dict = {}

    def value(self, counts: np.ndarray, window_ms: float) -> float:
        if self.cfg.value_readout == "drive":
            return self.plasticity.critic_drive(counts, self.cfg.value_frac * self.plasticity.w_ref)
        s = window_ms * 1e-3
        pos = counts[self.bp.critic_pos].mean() / s
        neg = counts[self.bp.critic_neg].mean() / s
        return float((pos - neg) / self.cfg.value_hz)

    def _dopamine_burst(self, delta: float) -> float:
        """Drive PAM (delta>0) or PPL1 (delta<0); return the decoded dopamine signal."""
        cfg = self.cfg
        mag = float(np.clip(abs(delta), 0.0, 1.0))
        reward_hz = cfg.dan_max_hz * mag if delta > 0 else 0.0
        punish_hz = cfg.dan_max_hz * mag if delta < 0 else 0.0
        self.net.set_rate(self.bp.dan_reward, reward_hz)
        self.net.set_rate(self.bp.dan_punish, punish_hz)
        counts = self.net.run(cfg.dopamine_ms)
        self.net.set_rate(self.bp.dan_reward, 0.0)
        self.net.set_rate(self.bp.dan_punish, 0.0)
        full = cfg.dan_max_hz * cfg.dopamine_ms * 1e-3
        da = (counts[self.bp.dan_reward].mean() - counts[self.bp.dan_punish].mean()) / full
        return float(da)

    def _learn(self, delta: float) -> tuple[float, dict]:
        if not self.cfg.learning:
            return 0.0, {}
        da = self._dopamine_burst(delta)
        return da, self.plasticity.apply_dopamine(da)

    def act(self, frame: np.ndarray) -> str:
        cfg = self.cfg
        feats = self.optic_lobe.process(frame)
        self.net.set_rate(self.bp.vpn_idx, self.encoder.rates(feats))
        counts = self.net.run(cfg.window_ms)
        self.last_counts = counts
        v = self.value(counts, cfg.window_ms)
        delta = da = 0.0
        dw: dict = {}
        if self._prev_value is not None:
            delta = self._pending_reward + self.cfg.plasticity.gamma * v - self._prev_value
            da, dw = self._learn(delta)
        votes = np.array([counts[self.bp.motor[p]].sum() for p in self.primitives], dtype=float)
        avail = np.array([p in self.available for p in self.primitives])
        votes_av = np.where(avail, votes, -1.0)
        best = np.flatnonzero(votes_av == votes_av.max())
        choice = int(self.rng.choice(best))
        probs = np.where(avail, votes + 0.5, 0.0)
        probs /= probs.sum()
        self.plasticity.accumulate(counts, choice, probs)
        self._prev_value = v
        kc = counts[self.bp.state_idx]
        self.last = {"value": v, "delta": delta, "dopamine": da, "votes": votes, "action": self.primitives[choice],
                     "kc_active": float((kc > 0).mean()), "dw": dw}
        if cfg.record:
            self.last["counts"] = counts
            self.last["vpn_rates"] = self.net.rate_hz[self.bp.vpn_idx].copy()
            self.trace.append(self.last)
        return self.primitives[choice]

    def observe(self, reward: float, done: bool) -> None:
        """Feed back the (scaled) reward of the last action; closes the episode if ``done``."""
        self._pending_reward = reward
        if done and self._prev_value is not None:
            delta = reward - self._prev_value
            da, dw = self._learn(delta)
            self.last = dict(self.last, terminal_delta=delta, terminal_dopamine=da)
            self._prev_value = None

    # ------------------------------------------------- Pavlovian conditioning
    def present(self, frame: np.ndarray, windows: int = 2) -> np.ndarray:
        """Show a still frame from rest for ``windows`` perception windows; counts of the last."""
        self.begin_episode()
        counts = None
        for _ in range(windows):
            self.net.set_rate(self.bp.vpn_idx, self.encoder.rates(self.optic_lobe.process(frame)))
            counts = self.net.run(self.cfg.window_ms)
        return counts

    def condition(self, frame: np.ndarray, us: float) -> dict:
        """One conditioning trial: stimulus, then the unconditioned stimulus ``us``
        (e.g. -1 for punishment, 0 for nothing).

        Dopamine signals the prediction error ``us - V(stimulus)`` (Rescorla-Wagner), so an
        expected punishment that does not arrive drives the reward (PAM) neurons. Only the
        critic (valence) synapses are eligible, as in classical conditioning where no action
        is taken.
        """
        counts = self.present(frame)
        v = self.value(counts, self.cfg.window_ms)
        self.plasticity.reset_traces()
        n = len(self.primitives)
        self.plasticity.accumulate(counts, None, np.full(n, 1.0 / n))
        delta = us - v
        da = self._dopamine_burst(delta)
        self.plasticity.apply_dopamine(da, only=("critic",))
        return {"value": v, "delta": delta, "dopamine": da}

    # ------------------------------------------------------------- weights io
    def weights(self) -> dict[str, np.ndarray]:
        return {name: self.net.get_weights(name) for name in self.net.plastic}

    def load_weights(self, weights: dict[str, np.ndarray]) -> None:
        for name, w in weights.items():
            self.net.set_weights(name, w)

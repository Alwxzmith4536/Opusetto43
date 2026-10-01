"""What the agent needs to know about a brain: where to inject vision, what to read out, where to learn."""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .connectome import Connectome
from ..senses.vpn import VPNLayout

MOTOR_PRIMITIVES = ("left", "right", "forward", "backward", "attack")


@dataclass
class BrainBlueprint:
    """Connectome plus the named populations the sensorimotor loop uses.

    * ``vpn_idx[k]`` is the neuron driven by visual channel ``vpn_layout[k]``.
    * ``motor[name]`` are the neurons whose spikes vote for motor primitive ``name``
      (descending neurons, or VNC readout units in the real-connectome mode).
    * ``actor[name]`` are the plastic action units (postsynaptic in plastic set ``"actor"``).
    * ``critic_pos`` / ``critic_neg`` are appetitive / aversive value units
      (postsynaptic in plastic set ``"critic"``); value = their rate difference.
    * ``state_idx`` is the presynaptic population of the actor/critic sets (Kenyon cells).
    * ``dan_reward`` (PAM-like) and ``dan_punish`` (PPL1-like) carry the dopamine teaching signal.
    * ``tonic`` lists background Poisson drive ``(indices, rate_hz)``.
    """

    connectome: Connectome
    vpn_idx: np.ndarray
    vpn_layout: VPNLayout
    motor: dict[str, np.ndarray]
    actor: dict[str, np.ndarray]
    critic_pos: np.ndarray
    critic_neg: np.ndarray
    state_idx: np.ndarray
    dan_reward: np.ndarray
    dan_punish: np.ndarray
    tonic: list[tuple[np.ndarray, float]] = field(default_factory=list)
    weight_max: dict[str, float] = field(default_factory=dict)
    encoder: dict = field(default_factory=dict)  # VPNEncoder overrides for this brain (e.g. rf_sigma)
    state_label: str = "Kenyon cells"  # what the presynaptic population of the plastic synapses is
    name: str = "brain"
    notes: str = ""

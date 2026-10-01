"""Common interface for Doom-like environments driven by a fly brain."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol

import numpy as np


@dataclass
class StepResult:
    frame: np.ndarray | None  # next RGB frame (H, W, 3) uint8, None when the episode ended
    reward: float  # game reward divided by the scenario's reward_scale
    done: bool
    info: dict = field(default_factory=dict)  # raw_reward, health, damage, kills, ammo, ...


class DoomLikeEnv(Protocol):
    """Episode-based environment with a small discrete action set.

    ``motor_map`` maps the brain's motor primitives (``left``, ``right``, ``forward``,
    ``backward``, ``attack``) to the scenario's buttons; primitives absent from the map
    are not available in that scenario.
    """

    name: str
    frame_shape: tuple[int, int]
    motor_map: dict[str, str]
    reward_scale: float

    def reset(self, seed: int | None = None) -> np.ndarray: ...

    def step(self, primitive: str | None) -> StepResult: ...

    def episode_stats(self) -> dict: ...

    def close(self) -> None: ...

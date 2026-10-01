"""Real Doom through ViZDoom (bundled Freedoom assets and scenario WADs)."""
from __future__ import annotations

import os

import numpy as np

from .base import StepResult

# motor primitive -> ViZDoom button, plus the factor that maps game reward to ~[-1, 1]
SCENARIOS: dict[str, dict] = {
    "basic": {"motor": {"left": "MOVE_LEFT", "right": "MOVE_RIGHT", "attack": "ATTACK"},
              "reward_scale": 100.0},
    "defend_the_center": {"motor": {"left": "TURN_LEFT", "right": "TURN_RIGHT", "attack": "ATTACK"},
                          "reward_scale": 1.0},
    "defend_the_line": {"motor": {"left": "TURN_LEFT", "right": "TURN_RIGHT", "attack": "ATTACK"},
                        "reward_scale": 1.0},
    "health_gathering": {"motor": {"left": "TURN_LEFT", "right": "TURN_RIGHT", "forward": "MOVE_FORWARD"},
                         "reward_scale": 100.0},
    "take_cover": {"motor": {"left": "MOVE_LEFT", "right": "MOVE_RIGHT"}, "reward_scale": 100.0},
    "deadly_corridor": {"motor": {"left": "TURN_LEFT", "right": "TURN_RIGHT", "forward": "MOVE_FORWARD",
                                  "backward": "MOVE_BACKWARD", "attack": "ATTACK"},
                        "reward_scale": 100.0},
}


def vizdoom_available() -> bool:
    try:
        import vizdoom  # noqa: F401
    except ImportError:
        return False
    return True


class VizDoomEnv:
    """One ViZDoom scenario, rendered headless at 160x120 RGB, ``frame_skip`` tics per action."""

    def __init__(self, scenario: str = "basic", frame_skip: int = 4, render_weapon: bool = False,
                 seed: int | None = None, visible: bool = False, episode_timeout: int | None = None):
        import vizdoom as vzd

        if scenario not in SCENARIOS:
            raise ValueError(f"unknown scenario {scenario!r}; choose from {sorted(SCENARIOS)}")
        self.vzd = vzd
        self.name = f"vizdoom:{scenario}"
        self.scenario = scenario
        spec = SCENARIOS[scenario]
        self.reward_scale = float(spec["reward_scale"])
        self.frame_skip = frame_skip
        g = vzd.DoomGame()
        g.load_config(os.path.join(vzd.scenarios_path, f"{scenario}.cfg"))
        g.set_window_visible(visible)
        g.set_screen_resolution(vzd.ScreenResolution.RES_160X120)
        g.set_screen_format(vzd.ScreenFormat.RGB24)
        g.set_render_weapon(render_weapon)
        g.set_render_hud(False)
        g.set_render_crosshair(False)
        g.set_labels_buffer_enabled(True)
        for var in ("HEALTH", "KILLCOUNT", "AMMO2", "DAMAGE_TAKEN"):
            g.add_available_game_variable(getattr(vzd.GameVariable, var))
        if episode_timeout:
            g.set_episode_timeout(episode_timeout)
        if seed is not None:
            g.set_seed(int(seed))
        g.init()
        self.game = g
        self.buttons = [str(b).split(".")[-1].split(":")[0] for b in g.get_available_buttons()]
        self.motor_map = {k: v for k, v in spec["motor"].items() if v in self.buttons}
        self._button_index = {b: i for i, b in enumerate(self.buttons)}
        self.frame_shape = (120, 160)
        self._vars = [str(v).split(".")[-1] for v in g.get_available_game_variables()]
        self._stats: dict = {}

    def _variables(self) -> dict:
        st = self.game.get_state()
        if st is None or st.game_variables is None:
            return {}
        return {name.lower(): float(val) for name, val in zip(self._vars, st.game_variables)}

    def monster_azimuths(self) -> list[float]:
        """Ground-truth azimuth (deg) of visible monsters, for analysis only (never fed to the brain)."""
        st = self.game.get_state()
        if st is None:
            return []
        out = []
        focal = 80.0  # 160 px wide frame, 90 deg FOV
        for lab in st.labels:
            if lab.object_name in ("DoomPlayer",) or lab.object_name.endswith("Puff"):
                continue
            xc = lab.x + lab.width / 2
            out.append(float(np.degrees(np.arctan((xc - 80.0) / focal))))
        return out

    def reset(self, seed: int | None = None) -> np.ndarray:
        if seed is not None:
            self.game.set_seed(int(seed))
        self.game.new_episode()
        v = self._variables()
        self._stats = {"raw_return": 0.0, "steps": 0, "kills": 0.0, "damage_taken": 0.0,
                       "shots": 0, "start_health": v.get("health", 100.0)}
        self._last_vars = v
        return self.game.get_state().screen_buffer.copy()

    def step(self, primitive: str | None) -> StepResult:
        action = [0] * len(self.buttons)
        if primitive is not None and primitive in self.motor_map:
            action[self._button_index[self.motor_map[primitive]]] = 1
            if primitive == "attack":
                self._stats["shots"] += 1
        raw = float(self.game.make_action(action, self.frame_skip))
        done = self.game.is_episode_finished()
        self._stats["raw_return"] += raw
        self._stats["steps"] += 1
        info = {"raw_reward": raw}
        if not done:
            v = self._variables()
            info.update(v)
            self._stats["kills"] = v.get("killcount", self._stats["kills"])
            self._stats["damage_taken"] = v.get("damage_taken", self._stats["damage_taken"])
            dmg = v.get("damage_taken", 0.0) - self._last_vars.get("damage_taken", 0.0)
            info["damage"] = max(dmg, 0.0)
            self._last_vars = v
            frame = self.game.get_state().screen_buffer.copy()
        else:
            frame = None
            info["damage"] = 0.0
            self._stats["kills"] = float(self.game.get_game_variable(self.vzd.GameVariable.KILLCOUNT))
        self._stats["died"] = bool(done and self.game.is_player_dead())
        return StepResult(frame=frame, reward=raw / self.reward_scale, done=done, info=info)

    def episode_stats(self) -> dict:
        s = dict(self._stats)
        s["tics"] = s.get("steps", 0) * self.frame_skip
        return s

    def close(self) -> None:
        self.game.close()

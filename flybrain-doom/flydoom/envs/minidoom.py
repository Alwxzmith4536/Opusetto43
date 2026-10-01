"""MiniDoom: a tiny dependency-free raycaster with two ViZDoom-like scenarios.

It exists so the engine and its tests run without ViZDoom and so stimuli can be fully
controlled. It renders 160x120 RGB frames of a textured room with billboard monsters.

* ``basic`` (after ViZDoom ``basic``): one monster at a random lateral position on the far
  wall; buttons MOVE_LEFT / MOVE_RIGHT / ATTACK; reward -1 per tic, -5 per missed shot,
  +101 for the kill (ends the episode); timeout 300 tics.
* ``defend`` (after ``defend_the_center``): the player stands in the middle of a square
  arena, monsters walk in from the walls and bite; buttons TURN_LEFT / TURN_RIGHT / ATTACK;
  +1 per kill, -1 for dying; 26 bullets; timeout 2100 tics.
"""
from __future__ import annotations

import math

import numpy as np

from .base import StepResult

W, H = 160, 120
FOV = math.radians(90.0)
FOCAL = (W / 2) / math.tan(FOV / 2)
WALL_HEIGHT = 1.6

SCENARIOS = {
    "basic": {"motor": {"left": "MOVE_LEFT", "right": "MOVE_RIGHT", "attack": "ATTACK"},
              "reward_scale": 100.0, "timeout": 300},
    "defend": {"motor": {"left": "TURN_LEFT", "right": "TURN_RIGHT", "attack": "ATTACK"},
               "reward_scale": 1.0, "timeout": 2100},
}


class MiniDoomEnv:
    def __init__(self, scenario: str = "basic", frame_skip: int = 4, seed: int | None = None):
        if scenario not in SCENARIOS:
            raise ValueError(f"unknown MiniDoom scenario {scenario!r}; choose from {sorted(SCENARIOS)}")
        self.scenario = scenario
        self.name = f"minidoom:{scenario}"
        spec = SCENARIOS[scenario]
        self.motor_map = dict(spec["motor"])
        self.reward_scale = float(spec["reward_scale"])
        self.timeout = spec["timeout"]
        self.frame_skip = frame_skip
        self.frame_shape = (H, W)
        self.rng = np.random.default_rng(seed)
        if scenario == "basic":
            self.grid = np.ones((7, 9), dtype=np.int8)
            self.grid[1:6, 1:8] = 0
        else:
            self.grid = np.ones((11, 11), dtype=np.int8)
            self.grid[1:10, 1:10] = 0
        self._ray_offsets = np.arctan((np.arange(W) + 0.5 - W / 2) / FOCAL)
        self._t = np.arange(0.03, 22.0, 0.03)
        yy = np.arange(H)[:, None]
        self._floor = np.where(yy > H / 2, 1.0, 0.0)
        self._stats: dict = {}

    # ------------------------------------------------------------------ world
    def reset(self, seed: int | None = None) -> np.ndarray:
        if seed is not None:
            self.rng = np.random.default_rng(seed)
        self.tic = 0
        self.health = 100.0
        self.ammo = 50 if self.scenario == "basic" else 26
        self.monsters: list[dict] = []
        if self.scenario == "basic":
            self.pos = np.array([4.5, 1.4])
            self.angle = math.pi / 2  # facing +y (towards the far wall)
            self.monsters.append({"pos": np.array([self.rng.uniform(1.6, 7.4), 5.4]), "hp": 1, "r": 0.35})
        else:
            self.pos = np.array([5.5, 5.5])
            self.angle = self.rng.uniform(0, 2 * math.pi)
            for _ in range(3):
                self._spawn()
        self._stats = {"raw_return": 0.0, "steps": 0, "kills": 0.0, "damage_taken": 0.0, "shots": 0,
                       "died": False}
        return self.render()

    def _spawn(self) -> None:
        a = self.rng.uniform(0, 2 * math.pi)
        p = self.pos + 3.9 * np.array([math.cos(a), math.sin(a)])
        self.monsters.append({"pos": p, "hp": 1, "r": 0.35, "cool": 0})

    def _wall(self, x: np.ndarray, y: np.ndarray) -> np.ndarray:
        xi = np.clip(x.astype(int), 0, self.grid.shape[1] - 1)
        yi = np.clip(y.astype(int), 0, self.grid.shape[0] - 1)
        return self.grid[yi, xi] > 0

    def _cast(self) -> tuple[np.ndarray, np.ndarray]:
        """Perpendicular wall distance and texture coordinate for every screen column."""
        ang = self.angle - self._ray_offsets  # screen x grows to the right = clockwise
        dx, dy = np.cos(ang), np.sin(ang)
        px = self.pos[0] + dx[:, None] * self._t[None, :]
        py = self.pos[1] + dy[:, None] * self._t[None, :]
        hit = self._wall(px, py)
        first = np.argmax(hit, axis=1)
        dist = self._t[first]
        hx, hy = px[np.arange(W), first], py[np.arange(W), first]
        u = np.where(np.abs(hx - np.round(hx)) < np.abs(hy - np.round(hy)), hy, hx) % 1.0
        return dist * np.cos(self._ray_offsets), u

    def _to_camera(self, p: np.ndarray) -> tuple[float, float]:
        d = p - self.pos
        fwd = np.array([math.cos(self.angle), math.sin(self.angle)])
        right = np.array([math.sin(self.angle), -math.cos(self.angle)])
        return float(d @ fwd), float(d @ right)

    def render(self) -> np.ndarray:
        depth, u = self._cast()
        img = np.empty((H, W, 3), dtype=np.float32)
        ys = np.arange(H)[:, None]
        # ceiling grey with a grid, floor brown with depth shading
        ceil = np.array([70, 70, 74], np.float32) * (0.6 + 0.4 * (ys / (H / 2)))
        floor = np.array([120, 90, 60], np.float32) * (0.35 + 0.65 * ((ys - H / 2) / (H / 2)))
        img[:] = np.where((ys < H / 2)[..., None], ceil[:, None, :], floor[:, None, :])
        half = (FOCAL * WALL_HEIGHT / np.maximum(depth, 0.05)) / 2
        top, bot = H / 2 - half, H / 2 + half
        in_wall = (ys >= top[None, :]) & (ys <= bot[None, :])
        v = (ys - top[None, :]) / np.maximum(bot - top, 1)[None, :]
        brick = ((np.floor(v * 6) % 2) * 0.5 + u[None, :] * 4) % 1.0
        mortar = (np.abs((v * 6) % 1.0 - 0.5) > 0.42) | (brick < 0.06)
        shade = np.clip(2.5 / (depth + 1.5), 0.3, 1.0)[None, :]
        wall = np.array([125, 85, 50], np.float32)[None, None, :] * np.where(mortar, 0.6, 1.0)[..., None]
        img = np.where(in_wall[..., None], wall * shade[..., None], img)
        # monsters: billboards drawn far to near, occluded by the wall depth buffer
        order = sorted(self.monsters, key=lambda m: -self._to_camera(m["pos"])[0])
        for m in order:
            z, x = self._to_camera(m["pos"])
            if z < 0.2:
                continue
            cx = W / 2 + FOCAL * x / z
            rad = FOCAL * m["r"] / z
            cy = H / 2 - FOCAL * 0.15 / z
            x0, x1 = int(max(cx - rad, 0)), int(min(cx + rad + 1, W))
            if x1 <= x0:
                continue
            cols = np.arange(x0, x1)
            vis = cols[depth[cols] > z]
            if vis.size == 0:
                continue
            yy, xx = np.mgrid[0:H, 0:W]
            body = ((xx - cx) / max(rad, 0.5)) ** 2 + ((yy - cy) / max(rad * 1.3, 0.5)) ** 2 <= 1.0
            eye = ((xx - cx) / max(rad * 0.35, 0.5)) ** 2 + ((yy - cy + rad * 0.3) / max(rad * 0.3, 0.5)) ** 2 <= 1.0
            mask = np.zeros((H, W), bool)
            mask[:, vis] = True
            sh = float(np.clip(2.5 / (z + 1.5), 0.35, 1.0))
            img[body & mask] = np.array([170, 40, 60], np.float32) * sh
            img[eye & body & mask] = np.array([60, 200, 90], np.float32) * sh
        return np.clip(img, 0, 255).astype(np.uint8)

    # ---------------------------------------------------------------- dynamics
    def _shoot(self) -> float:
        self._stats["shots"] += 1
        if self.ammo <= 0:
            return 0.0
        self.ammo -= 1
        depth, _ = self._cast()
        best = None
        for m in self.monsters:
            z, x = self._to_camera(m["pos"])
            if z > 0.2 and abs(x) < m["r"] * 0.9 and z < depth[W // 2] and (best is None or z < best[0]):
                best = (z, m)
        if best is None:
            return -5.0 if self.scenario == "basic" else 0.0
        m = best[1]
        m["hp"] -= 1
        if m["hp"] <= 0:
            self.monsters.remove(m)
            self._stats["kills"] += 1
            if self.scenario == "defend":
                self._spawn()
            return 101.0 if self.scenario == "basic" else 1.0
        return 0.0

    def _tic(self, button: str | None) -> float:
        r = -1.0 if self.scenario == "basic" else 0.0
        if button == "MOVE_LEFT" or button == "MOVE_RIGHT":
            right = np.array([math.sin(self.angle), -math.cos(self.angle)])
            step = 0.12 * (1 if button == "MOVE_RIGHT" else -1)
            new = self.pos + right * step
            probe = self.pos + right * (step + 0.35 * np.sign(step))  # keep 0.35 units off walls
            if not self._wall(np.array([probe[0]]), np.array([probe[1]]))[0]:
                self.pos = new
        elif button in ("TURN_LEFT", "TURN_RIGHT"):
            self.angle += math.radians(3.0) * (1 if button == "TURN_LEFT" else -1)
        if self.scenario == "defend":
            for m in self.monsters:
                d = self.pos - m["pos"]
                dist = float(np.hypot(*d))
                if dist > 0.9:
                    m["pos"] = m["pos"] + 0.03 * d / dist
                else:
                    m["cool"] = m.get("cool", 0) - 1
                    if m["cool"] <= 0:
                        self.health -= 8.0
                        self._stats["damage_taken"] += 8.0
                        m["cool"] = 20
        return r

    def step(self, primitive: str | None) -> StepResult:
        button = self.motor_map.get(primitive) if primitive else None
        raw = 0.0
        done = False
        damage0 = self._stats["damage_taken"]
        for k in range(self.frame_skip):
            if button == "ATTACK":
                raw += self._shoot() if k == 0 else 0.0
                raw += self._tic(None)
            else:
                raw += self._tic(button)
            self.tic += 1
            if self.scenario == "basic" and not self.monsters:
                done = True
            if self.health <= 0:
                raw -= 1.0
                self._stats["died"] = True
                done = True
            if self.tic >= self.timeout:
                done = True
            if done:
                break
        self._stats["raw_return"] += raw
        self._stats["steps"] += 1
        info = {"raw_reward": raw, "health": self.health, "ammo": self.ammo,
                "damage": self._stats["damage_taken"] - damage0, "killcount": self._stats["kills"]}
        return StepResult(frame=None if done else self.render(), reward=raw / self.reward_scale,
                          done=done, info=info)

    def monster_azimuths(self) -> list[float]:
        out = []
        for m in self.monsters:
            z, x = self._to_camera(m["pos"])
            if z > 0.2:
                out.append(math.degrees(math.atan2(x, z)))
        return out

    def episode_stats(self) -> dict:
        s = dict(self._stats)
        s["tics"] = self.tic
        return s

    def close(self) -> None:
        pass

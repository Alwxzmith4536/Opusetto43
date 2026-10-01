"""Experiment runner: build env + brain + agent, train, evaluate on fixed seeds."""
from __future__ import annotations

import time
from dataclasses import asdict, dataclass, field

import numpy as np

from ..agents.fly_agent import AgentConfig, FlyAgent
from ..brain.synthetic import SyntheticBrainConfig, build_synthetic_brain
from ..senses.eye import EyeConfig
from ..senses.vpn import VPNLayout

EVAL_SEED_BASE = 1_000_000  # evaluation episodes use seeds disjoint from training seeds


def make_env(spec: str, seed: int = 0, frame_skip: int = 4):
    """``vizdoom:<scenario>`` (real Doom via ViZDoom) or ``minidoom:<scenario>``."""
    kind, _, scenario = spec.partition(":")
    if kind == "vizdoom":
        from ..envs.vizdoom_env import VizDoomEnv
        return VizDoomEnv(scenario or "basic", frame_skip=frame_skip, seed=seed)
    if kind == "minidoom":
        from ..envs.minidoom import MiniDoomEnv
        return MiniDoomEnv(scenario or "basic", frame_skip=frame_skip, seed=seed)
    raise ValueError(f"unknown environment {spec!r} (use vizdoom:<scenario> or minidoom:<scenario>)")


@dataclass
class ExperimentConfig:
    env: str = "vizdoom:basic"
    brain: str = "synthetic"  # 'synthetic' or 'flywire'
    train_episodes: int = 300
    eval_episodes: int = 50
    seed: int = 0
    frame_skip: int = 4
    calibration_frames: int = 200
    flywire_dir: str | None = None  # folder with Connectivity_783.parquet + Completeness_783.csv
    flywire_annotations: str | None = None  # FlyWire Supplemental_file1_neuron_annotations.tsv
    flywire_region: str = "central"
    agent: AgentConfig = field(default_factory=AgentConfig)
    brain_config: SyntheticBrainConfig = field(default_factory=SyntheticBrainConfig)
    eye: EyeConfig = field(default_factory=lambda: EyeConfig(spacing=4.5, elev_min=-10.0, elev_max=12.0))

    def to_dict(self) -> dict:
        return asdict(self)


class RandomPolicy:
    """Baseline: uniformly random choice among the scenario's motor primitives."""

    name = "random"

    def __init__(self, motor_map: dict[str, str], seed: int = 0):
        self.actions = list(motor_map)
        self.rng = np.random.default_rng(seed)
        self.last: dict = {}

    def begin_episode(self) -> None:
        pass

    def act(self, frame: np.ndarray) -> str:
        a = self.actions[self.rng.integers(len(self.actions))]
        self.last = {"action": a}
        return a

    def observe(self, reward: float, done: bool) -> None:
        pass


def collect_frames(env, n: int, seed: int = 0) -> list[np.ndarray]:
    """Frames from random play, used for developmental calibration of the eye and brain."""
    rng = np.random.default_rng(seed)
    actions = list(env.motor_map)
    frames = []
    frame = env.reset(seed=seed)
    k = 0
    while len(frames) < n:
        frames.append(frame)
        res = env.step(actions[rng.integers(len(actions))])
        if res.done:
            k += 1
            frame = env.reset(seed=seed + k)
        else:
            frame = res.frame
    return frames


def build_brain(cfg: ExperimentConfig, eye):
    if cfg.brain == "synthetic":
        layout = VPNLayout.columnar(eye)
        return build_synthetic_brain(layout, cfg.brain_config, seed=cfg.seed)
    if cfg.brain == "flywire":
        from ..brain.flywire import build_flywire_brain, load_flywire
        if not cfg.flywire_dir:
            raise ValueError("brain='flywire' needs flywire_dir (see `flydoom fetch-flywire`)")
        conn = load_flywire(cfg.flywire_dir, cfg.flywire_annotations, region=cfg.flywire_region)
        return build_flywire_brain(conn, eye, seed=cfg.seed)
    raise ValueError(f"unknown brain {cfg.brain!r}")


def build_agent(cfg: ExperimentConfig, env, lesion: str | None = None, calibrate: bool = True,
                blueprint=None) -> FlyAgent:
    from ..senses.eye import CompoundEye
    eye = CompoundEye(env.frame_shape, cfg.eye)
    bp = blueprint if blueprint is not None else build_brain(cfg, eye)
    agent = FlyAgent(bp, env.frame_shape, cfg.eye, config=AgentConfig(**{
        **asdict(cfg.agent), "plasticity": cfg.agent.plasticity}), seed=cfg.seed)
    agent.bind(env.motor_map)
    if calibrate:
        agent.calibration = agent.calibrate(collect_frames(env, cfg.calibration_frames, seed=cfg.seed + 777))
    if lesion:
        agent.lesion(lesion)
    return agent


def run_episode(policy, env, seed: int | None = None, learn: bool | None = None,
                record_aim: bool = False) -> dict:
    """Play one episode. ``learn`` temporarily overrides the agent's learning switch."""
    prev = None
    if learn is not None and hasattr(policy, "cfg"):
        prev, policy.cfg.learning = policy.cfg.learning, learn
    frame = env.reset(seed=seed)
    policy.begin_episode()
    aim: list[tuple[float, str]] = []
    t0 = time.time()
    track = record_aim and hasattr(env, "monster_azimuths")
    while True:
        az = env.monster_azimuths() if track else []
        action = policy.act(frame)
        if az:
            aim.append((min(az, key=abs), action))
        res = env.step(action)
        policy.observe(res.reward, res.done)
        if res.done:
            break
        frame = res.frame
    if prev is not None:
        policy.cfg.learning = prev
    out = env.episode_stats()
    out["seed"] = seed
    out["wall_time_s"] = time.time() - t0
    if record_aim:
        out["aim"] = aim
    return out


def evaluate(policy, env, n: int, seed_base: int = EVAL_SEED_BASE, record_aim: bool = False) -> list[dict]:
    """Frozen-weight evaluation on episode seeds ``seed_base .. seed_base + n - 1``."""
    return [run_episode(policy, env, seed=seed_base + i, learn=False, record_aim=record_aim) for i in range(n)]


def train(agent: FlyAgent, env, n: int, seed_base: int = 0, log=None, log_every: int = 25) -> list[dict]:
    curve = []
    for i in range(n):
        ep = run_episode(agent, env, seed=seed_base + i, learn=True)
        curve.append(ep)
        if log and (i + 1) % log_every == 0:
            recent = [e["raw_return"] for e in curve[-log_every:]]
            kills = np.mean([e["kills"] > 0 for e in curve[-log_every:]])
            log(f"  train ep {i + 1:4d}/{n}: mean return {np.mean(recent):8.1f}  episodes with a kill {kills:.0%}")
    return curve

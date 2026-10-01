"""The full test protocol: baselines -> training -> evaluation -> lesion controls -> gates -> report."""
from __future__ import annotations

import os
import time

import numpy as np

from . import gates as G
from .runner import EVAL_SEED_BASE, ExperimentConfig, RandomPolicy, build_agent, evaluate, make_env, train


def _monster_frames(env, n_each: int, seed: int, side_deg: float = 10.0):
    """Frames with the nearest monster clearly left (CS+) or right (CS-) of the midline."""
    rng = np.random.default_rng(seed)
    actions = list(env.motor_map)
    left, right = [], []
    frame = env.reset(seed=seed)
    k = 0
    for _ in range(20000):
        az = env.monster_azimuths()
        if az:
            a = min(az, key=abs)
            if a < -side_deg and len(left) < n_each:
                left.append(frame)
            elif a > side_deg and len(right) < n_each:
                right.append(frame)
        if len(left) >= n_each and len(right) >= n_each:
            break
        res = env.step(actions[rng.integers(len(actions))])
        if res.done:
            k += 1
            frame = env.reset(seed=seed + k)
        else:
            frame = res.frame
    return left, right


def run_experiment(cfg: ExperimentConfig, controls: bool = True, log=print, out_dir: str | None = None,
                   replay: bool = True) -> dict:
    """Run the protocol. With ``out_dir``, also saves trained weights and a replay GIF there."""
    t_start = time.time()
    env = make_env(cfg.env, seed=cfg.seed, frame_skip=cfg.frame_skip)
    log(f"[flydoom] environment {cfg.env} | brain {cfg.brain} | seed {cfg.seed}")
    agent = build_agent(cfg, env)
    bp = agent.bp
    log(f"[flydoom] brain: {bp.name} - {bp.connectome.n:,} neurons, {bp.connectome.n_edges:,} synapses; "
        f"{bp.vpn_idx.size} visual projection neurons, {bp.state_idx.size} {bp.state_label} feed the plastic synapses")
    log(f"[flydoom] calibration: {agent.calibration}")
    n = cfg.eval_episodes
    log(f"[flydoom] evaluating baselines on {n} fixed seeds ...")
    ev = {"random": evaluate(RandomPolicy(env.motor_map, seed=cfg.seed), env, n, record_aim=True)}
    ev["untrained"] = evaluate(agent, env, n, record_aim=True)
    w0 = agent.weights()
    log(f"[flydoom] training for {cfg.train_episodes} episodes (dopamine-gated plasticity on) ...")
    t0 = time.time()
    curve = train(agent, env, cfg.train_episodes, seed_base=cfg.seed * 100_000, log=log)
    t_train = time.time() - t0
    ev["trained"] = evaluate(agent, env, n, record_aim=True)
    w1 = agent.weights()
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        np.savez_compressed(os.path.join(out_dir, "weights.npz"), **{f"trained_{k}": v for k, v in w1.items()},
                            **{f"initial_{k}": v for k, v in w0.items()})
        if replay:
            from .replay import record_episodes, render_gif
            steps = record_episodes(agent, env, [EVAL_SEED_BASE + k for k in range(3)])
            gif = render_gif(steps, agent, os.path.join(out_dir, "replay.gif"),
                             title=f"{bp.name} playing {cfg.env} after {cfg.train_episodes} training episodes")
            log(f"[flydoom] replay of a frozen evaluation episode: {gif}")

    results: dict = {"config": cfg.to_dict(), "env": env.name, "motor_map": env.motor_map,
                     "brain": {"name": bp.name, "neurons": bp.connectome.n, "synapses": bp.connectome.n_edges,
                               "vpns": int(bp.vpn_idx.size), "state_neurons": int(bp.state_idx.size),
                               "state_label": bp.state_label,
                               "notes": bp.notes},
                     "calibration": agent.calibration, "curve": curve,
                     "weight_change": {k: float(np.abs(w1[k] - w0[k]).mean()) for k in w0}}
    gates = [G.learning_gate(ev["trained"], ev["untrained"], ev["random"]), G.trend_gate(curve)]
    if controls:
        agent.lesion("kc")
        ev["kc_lesioned"] = evaluate(agent, env, n)
        agent.bind(env.motor_map)  # unsilences everything again
        log("[flydoom] control: training a brain whose dopamine neurons are silenced ...")
        dan_agent = build_agent(cfg, env, lesion="dopamine", blueprint=bp)
        ev["dan_lesioned_curve"] = train(dan_agent, env, cfg.train_episodes, seed_base=cfg.seed * 100_000)
        ev["dan_lesioned_trained"] = evaluate(dan_agent, env, n)
        gates.append(G.dopamine_gate(ev["trained"], ev["dan_lesioned_trained"], ev["untrained"]))
        gates.append(G.mushroom_body_gate(ev["trained"], ev["kc_lesioned"]))
    gates.append(G.aiming_gate(ev["untrained"], list(env.motor_map), " (untrained control)", informative=True))
    gates.append(G.aiming_gate(ev["trained"], list(env.motor_map), " (trained)"))
    if controls:
        log("[flydoom] control: aversive visual conditioning ...")
        cs_plus, cs_minus = _monster_frames(env, 16, seed=EVAL_SEED_BASE * 2)
        if len(cs_plus) >= 4 and len(cs_minus) >= 4:
            gates.append(G.conditioning_gate(
                lambda lesion: build_agent(cfg, env, lesion=lesion, blueprint=bp), cs_plus, cs_minus,
                seed=cfg.seed))
    results["eval"] = ev
    results["gates"] = [g.to_dict() for g in gates]
    results["timing"] = {"train_s": t_train, "total_s": time.time() - t_start,
                         "train_s_per_episode": t_train / max(cfg.train_episodes, 1)}
    env.close()
    for g in gates:
        log(f"[flydoom] {g.verdict:4s} {g.name}: {g.criterion}")
    return results

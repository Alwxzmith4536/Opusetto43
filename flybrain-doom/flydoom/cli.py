"""Command line: ``python -m flydoom <command>``."""
from __future__ import annotations

import argparse
import json
import os
import sys
import time


def _cmd_run(a) -> int:
    from .engine.experiment import run_experiment
    from .engine.report import write_report
    from .engine.runner import ExperimentConfig

    cfg = ExperimentConfig(env=a.env, brain=a.brain, train_episodes=a.train, eval_episodes=a.eval,
                           seed=a.seed, frame_skip=a.frame_skip, flywire_dir=a.flywire_dir,
                           flywire_annotations=a.annotations, flywire_region=a.region)
    out = a.out or os.path.join("results", f"{a.env.replace(':', '-')}-{a.brain}-seed{a.seed}")
    results = run_experiment(cfg, controls=not a.no_controls, out_dir=out, replay=not a.no_replay)
    s = write_report(results, out)
    print(f"[flydoom] report written to {out}/report.html (also report.md, results.json)")
    failed = [g["name"] for g in s["gates"] if g["passed"] is False]
    if failed:
        print(f"[flydoom] gates failed: {', '.join(failed)}")
    return 1 if (failed and a.strict) else 0


def _cmd_replay(a) -> int:
    """Rebuild a trained brain from a results folder (config + weights.npz) and record a GIF."""
    import numpy as np

    from .agents.fly_agent import AgentConfig
    from .brain.plasticity import PlasticityConfig
    from .brain.synthetic import SyntheticBrainConfig
    from .engine.replay import record_episodes, render_gif
    from .engine.runner import EVAL_SEED_BASE, ExperimentConfig, build_agent, make_env
    from .senses.eye import EyeConfig

    with open(os.path.join(a.results, "results.json")) as f:
        c = json.load(f)["config"]
    agent_cfg = dict(c["agent"])
    agent_cfg["plasticity"] = PlasticityConfig(**agent_cfg["plasticity"])
    cfg = ExperimentConfig(**{**c, "agent": AgentConfig(**agent_cfg),
                              "brain_config": SyntheticBrainConfig(**{k: tuple(v) if isinstance(v, list) else v
                                                                     for k, v in c["brain_config"].items()}),
                              "eye": EyeConfig(**c["eye"])})
    if a.flywire_dir:
        cfg.flywire_dir, cfg.flywire_annotations = a.flywire_dir, a.annotations
    env = make_env(cfg.env, seed=cfg.seed, frame_skip=cfg.frame_skip)
    agent = build_agent(cfg, env)
    w = np.load(os.path.join(a.results, "weights.npz"))
    agent.load_weights({k[len("trained_"):]: w[k] for k in w.files if k.startswith("trained_")})
    steps = record_episodes(agent, env, [EVAL_SEED_BASE + k for k in range(a.episodes)], max_steps=a.max_steps)
    out = a.out or os.path.join(a.results, "replay.gif")
    render_gif(steps, agent, out, title=f"{agent.bp.name} playing {cfg.env} (trained)")
    print(f"[flydoom] wrote {out} ({len(steps)} steps)")
    return 0


def _cmd_selftest(a) -> int:
    """Fast end-to-end battery on MiniDoom (no ViZDoom needed)."""
    from .engine.experiment import run_experiment
    from .engine.report import write_report
    from .engine.runner import ExperimentConfig

    cfg = ExperimentConfig(env="minidoom:basic", train_episodes=a.train, eval_episodes=a.eval, seed=a.seed,
                           calibration_frames=150)
    t0 = time.time()
    results = run_experiment(cfg, controls=True, out_dir=a.out, replay=False)
    s = write_report(results, a.out)
    core = ("G1", "G2", "G3", "G4", "G6")  # learning happens, depends on dopamine and the MB, conditioning works
    ok = all(g["passed"] is True for g in s["gates"] if g["name"].startswith(core))
    others = [f"{g['name']}: {'PASS' if g['passed'] else 'FAIL'}" for g in s["gates"]
              if not g["name"].startswith(core) and g["passed"] is not None]
    print(f"[flydoom] selftest {'PASSED' if ok else 'FAILED'} (core gates G1-G4, G6) in {time.time() - t0:.0f} s; "
          f"also reported: {'; '.join(others) or 'none'}; report: {a.out}/report.html")
    return 0 if ok else 1


def _cmd_oracle(a) -> int:
    """Add the scripted-aimer reference to an existing results folder (same evaluation seeds)."""
    import numpy as np

    from .engine import stats
    from .engine.report import CONDITIONS, rerender
    from .engine.runner import OraclePolicy, evaluate, make_env

    path = os.path.join(a.results, "results.json")
    with open(path) as f:
        s = json.load(f)
    c = s["config"]
    env = make_env(c["env"], seed=c["seed"], frame_skip=c["frame_skip"])
    seeds = s["eval"]["random"]["seeds"]
    eps = evaluate(OraclePolicy(env), env, len(seeds), seed_base=seeds[0])
    r = [e["raw_return"] for e in eps]
    entry = {"label": dict(CONDITIONS)["oracle"], "returns": r, "seeds": [e["seed"] for e in eps],
             "kill_rate": float(np.mean([e["kills"] > 0 for e in eps])), "summary": stats.summary(r)}
    s["eval"] = {"oracle": entry, **{k: v for k, v in s["eval"].items() if k != "oracle"}}
    with open(path, "w") as f:
        json.dump(s, f, indent=1)
    rerender(a.results)
    env.close()
    print(f"[flydoom] oracle on {len(r)} seeds: mean {np.mean(r):+.1f}, kills in {entry['kill_rate']:.0%} of episodes")
    return 0


def _cmd_summarize(a) -> int:
    """Markdown table of every results folder given (or found under ``results/``)."""
    import glob

    folders = a.folders or sorted(os.path.dirname(p) for p in glob.glob(os.path.join("results", "*", "results.json")))
    print("| run | scripted aimer (cheats) | random | untrained | trained | KCs silenced | dopamine silenced | gates passed |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|")
    for d in folders:
        with open(os.path.join(d, "results.json")) as f:
            s = json.load(f)

        def cell(key):
            e = s["eval"].get(key)
            return "–" if e is None else f"{e['summary']['mean']:+.1f} ({100 * e['kill_rate']:.0f}%)"

        judged = [g for g in s["gates"] if g["passed"] is not None]
        passed = sum(g["passed"] is True for g in judged)
        print(f"| {os.path.basename(d.rstrip('/'))} | {cell('oracle')} | {cell('random')} | {cell('untrained')} | **{cell('trained')}** | "
              f"{cell('kc_lesioned')} | {cell('dan_lesioned_trained')} | {passed} / {len(judged)} |")
    return 0


def _cmd_flywire_gates(a) -> int:
    from .brain.flywire import connectome_gates, load_flywire

    conn = load_flywire(a.flywire_dir, a.annotations, region="full" if a.full else "central")
    print(conn.summary().split("\n")[0])
    gates = connectome_gates(conn, duration_ms=a.duration, seed=a.seed)
    for g in gates:
        print(f"[flydoom] {g.verdict:4s} {g.name}: {g.criterion}")
        print("         " + json.dumps(g.metrics.get("summary", {}))[:400])
    if a.out:
        os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
        with open(a.out, "w") as f:
            json.dump([g.to_dict() for g in gates], f, indent=1, default=str)
        print(f"[flydoom] wrote {a.out}")
    return 0


def _cmd_info(a) -> int:
    from .envs.vizdoom_env import SCENARIOS, vizdoom_available

    print("flydoom: fly-brain (Drosophila connectome) learning engine for Doom")
    print(f"  ViZDoom installed: {vizdoom_available()}  scenarios: {', '.join(sorted(SCENARIOS))}")
    print("  MiniDoom scenarios: basic, defend")
    print("  brains: synthetic (procedural fly-like), flywire (FlyWire v783 via Shiu et al. 2024 files)")
    return 0


def _cmd_fetch(a) -> int:
    """Clone the public FlyWire v783 tables used by Shiu et al. (2024) and the FlyWire annotations."""
    import subprocess

    os.makedirs(a.dest, exist_ok=True)
    repos = {"Drosophila_brain_model": "https://github.com/philshiu/Drosophila_brain_model",
             "flywire_annotations": "https://github.com/flyconnectome/flywire_annotations"}
    for name, url in repos.items():
        path = os.path.join(a.dest, name)
        if os.path.exists(path):
            print(f"[flydoom] {path} exists, skipping")
            continue
        print(f"[flydoom] cloning {url} -> {path} (~200 MB) ...")
        subprocess.run(["git", "clone", "--depth", "1", url, path], check=True,
                       env={**os.environ, "GIT_LFS_SKIP_SMUDGE": "1"})
    print("[flydoom] use: --flywire-dir {0}/Drosophila_brain_model --annotations "
          "{0}/flywire_annotations/supplemental_files/Supplemental_file1_neuron_annotations.tsv".format(a.dest))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="flydoom", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="train + evaluate a fly brain on a Doom scenario and write a report")
    r.add_argument("--env", default="vizdoom:basic", help="vizdoom:<scenario> or minidoom:<scenario>")
    r.add_argument("--brain", default="synthetic", choices=["synthetic", "flywire"])
    r.add_argument("--train", type=int, default=300, help="training episodes")
    r.add_argument("--eval", type=int, default=50, help="evaluation episodes per condition")
    r.add_argument("--seed", type=int, default=0)
    r.add_argument("--frame-skip", type=int, default=4)
    r.add_argument("--out", default=None)
    r.add_argument("--no-controls", action="store_true", help="skip lesion and conditioning controls")
    r.add_argument("--no-replay", action="store_true", help="do not render replay.gif")
    r.add_argument("--strict", action="store_true", help="exit non-zero when a gate fails")
    r.add_argument("--flywire-dir", default=None)
    r.add_argument("--annotations", default=None)
    r.add_argument("--region", default="central", choices=["central", "full"])
    r.set_defaults(fn=_cmd_run)

    s = sub.add_parser("selftest", help="fast end-to-end battery on MiniDoom")
    s.add_argument("--train", type=int, default=150)
    s.add_argument("--eval", type=int, default=30)
    s.add_argument("--seed", type=int, default=0)
    s.add_argument("--out", default=os.path.join("results", "selftest"))
    s.set_defaults(fn=_cmd_selftest)

    g = sub.add_parser("flywire-gates", help="stimulus-response checks on the real FlyWire connectome")
    g.add_argument("--flywire-dir", required=True)
    g.add_argument("--annotations", required=True)
    g.add_argument("--full", action="store_true", help="keep optic-lobe neurons (138k neurons, slower)")
    g.add_argument("--duration", type=float, default=200.0)
    g.add_argument("--seed", type=int, default=0)
    g.add_argument("--out", default=None)
    g.set_defaults(fn=_cmd_flywire_gates)

    rp = sub.add_parser("replay", help="record a GIF of a trained brain from a results folder")
    rp.add_argument("--results", required=True, help="folder written by `run` (results.json + weights.npz)")
    rp.add_argument("--episodes", type=int, default=3)
    rp.add_argument("--max-steps", type=int, default=60, help="cap per episode (keeps the GIF small)")
    rp.add_argument("--out", default=None)
    rp.add_argument("--flywire-dir", default=None)
    rp.add_argument("--annotations", default=None)
    rp.set_defaults(fn=_cmd_replay)

    f = sub.add_parser("fetch-flywire", help="download the public FlyWire v783 connectome tables")
    f.add_argument("--dest", default="data")
    f.set_defaults(fn=_cmd_fetch)

    o = sub.add_parser("oracle", help="add the scripted-aimer reference to an existing results folder")
    o.add_argument("--results", required=True)
    o.set_defaults(fn=_cmd_oracle)

    sm = sub.add_parser("summarize", help="Markdown table comparing result folders")
    sm.add_argument("folders", nargs="*")
    sm.set_defaults(fn=_cmd_summarize)

    i = sub.add_parser("info", help="show what is installed")
    i.set_defaults(fn=_cmd_info)

    a = p.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())

"""Record an episode and render it as an animated GIF: game view, the fly's compound-eye view,
and the descending-neuron votes that chose each action."""
from __future__ import annotations

import numpy as np


def record_episodes(agent, env, seeds: list[int], max_steps: int | None = 60) -> list[dict]:
    steps = []
    for k, seed in enumerate(seeds):
        for st in record_episode(agent, env, seed, max_steps=max_steps):
            st["episode"] = k + 1
            steps.append(st)
    return steps


def record_episode(agent, env, seed: int, learn: bool = False, max_steps: int | None = None) -> list[dict]:
    prev, agent.cfg.learning = agent.cfg.learning, learn
    frame = env.reset(seed=seed)
    agent.begin_episode()
    steps = []
    total = 0.0
    while True:
        f = frame.reshape(-1, 3).astype(np.float32) / 255.0
        omm_rgb = np.stack([agent.eye.S @ f[:, k] for k in range(3)], axis=1)
        action = agent.act(frame)
        res = env.step(action)
        agent.observe(res.reward, res.done)
        total += res.info.get("raw_reward", 0.0)
        steps.append({"frame": frame, "omm_rgb": omm_rgb, "votes": agent.last["votes"].copy(),
                      "action": action, "value": agent.last["value"], "dopamine": agent.last.get("dopamine", 0.0),
                      "kc_active": agent.last["kc_active"], "return": total})
        if res.done or (max_steps and len(steps) >= max_steps):
            break
        frame = res.frame
    agent.cfg.learning = prev
    return steps


def render_gif(steps: list[dict], agent, path: str, title: str = "", fps: int = 8, scale: int = 2) -> str:
    from PIL import Image, ImageDraw

    eye = agent.eye
    h, w = steps[0]["frame"].shape[:2]
    gw, gh = w * scale, h * scale
    panel_h = 92
    W, H = gw * 2 + 12, gh + panel_h + 22
    # each compound eye drawn as its own hexagonal mosaic, left eye on the left
    x0 = gw + 12
    half = gw / 2
    px_deg = (half - 16) / max(np.ptp(eye.azimuth[eye.eye == "L"]), 1e-6)
    el_mid = (eye.elevation.max() + eye.elevation.min()) / 2
    yc = 22 + gh / 2
    xs = np.empty(eye.n)
    ys = yc - (eye.elevation - el_mid) * px_deg
    for k, side in enumerate(("L", "R")):
        m = eye.eye == side
        lo = eye.azimuth[m].min()
        xs[m] = x0 + k * half + 8 + (eye.azimuth[m] - lo) * px_deg
    rad = eye.cfg.spacing * px_deg * 0.48
    prims = agent.primitives
    avail = [p for p in prims if p in agent.available]
    frames = []
    for s in steps:
        img = Image.new("RGB", (W, H), (17, 17, 16))
        d = ImageDraw.Draw(img)
        d.text((6, 4), title + (f"  - episode {s['episode']}" if "episode" in s else ""), fill=(230, 230, 225))
        d.text((x0, 4), "what the fly sees: %d ommatidia, two eyes" % eye.n, fill=(195, 194, 183))
        img.paste(Image.fromarray(s["frame"]).resize((gw, gh), Image.NEAREST), (0, 22))
        for xi, yi, c in zip(xs, ys, s["omm_rgb"]):
            col = tuple(int(v) for v in np.clip(c * 255, 0, 255))
            hexagon = [(xi + rad * np.cos(a), yi + rad * np.sin(a)) for a in np.arange(6) * np.pi / 3 + np.pi / 6]
            d.polygon(hexagon, fill=col)
        d.text((x0 + 8, yc + 60), "left eye", fill=(137, 135, 129))
        d.text((x0 + half + 8, yc + 60), "right eye", fill=(137, 135, 129))
        # descending-neuron votes
        by = 22 + gh + 10
        votes = np.array([s["votes"][prims.index(p)] for p in avail], dtype=float)
        vmax = max(votes.max(), 1.0)
        bw = (W - 24) / max(len(avail), 1)
        for k, p in enumerate(avail):
            bx = 12 + k * bw
            frac = votes[k] / vmax
            colour = (57, 135, 229) if p != s["action"] else (217, 89, 38)
            d.rectangle([bx, by + 18, bx + (bw - 16) * frac, by + 34], fill=colour)
            d.text((bx, by), f"DN {p}: {int(votes[k])} spikes" + ("  <- chosen" if p == s["action"] else ""),
                   fill=(230, 230, 225))
        d.text((12, by + 44), f"value {s['value']:+.2f}   dopamine {s['dopamine']:+.2f}   "
                              f"Kenyon cells active {100 * s['kc_active']:.0f}%   return {s['return']:+.0f}",
               fill=(195, 194, 183))
        frames.append(img)
    frames += [frames[-1]] * fps  # hold the last frame
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0,
                   optimize=True)
    return path

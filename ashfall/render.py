"""ASHFALL — a 1 vs 1 vs 1 stickman energy-blade battle on a ruined ash planet.

Green vs Blue vs Yellow. Yellow wins twice.

Every frame is drawn procedurally with Pillow + numpy, the soundtrack is
synthesised with numpy, and ffmpeg muxes both into ashfall.mp4.

    python3 ashfall/render.py            # full render
    python3 ashfall/render.py --still 21.2   # one frame to ashfall/still.png
"""
import math, os, sys, random, wave, subprocess, shutil
from multiprocessing import Pool
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

W, H = 1280, 720
SS = 2                      # supersampling for anti-aliased line art
FPS = 30
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "/usr/share/fonts/truetype/liberation/LiberationSans-BoldItalic.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

COL = {
    "G": (40, 235, 90),
    "B": (40, 140, 255),
    "Y": (255, 214, 20),
}
INK = (14, 13, 16)

# ---------------------------------------------------------------- math utils
def lerp(a, b, u): return a + (b - a) * u
def clamp(v, a=0.0, b=1.0): return a if v < a else b if v > b else v
def ease(u, kind="io"):
    u = clamp(u)
    if kind == "lin": return u
    if kind == "in": return u * u * u
    if kind == "out": return 1 - (1 - u) ** 3
    if kind == "snap": return 1 - (1 - u) ** 5
    return u * u * (3 - 2 * u)
def pol(a, r): return (math.cos(math.radians(a)) * r, math.sin(math.radians(a)) * r)

# ---------------------------------------------------------------- time remap
# (story_start, story_end, speed) — slow motion and freeze-frames.
SLOW = [
    (11.42, 11.62, 0.25),     # three-way clash
    (21.05, 21.30, 0.18),     # yellow's counter on green
    (21.30, 21.34, 0.02),     # freeze on the cut
    (26.60, 27.20, 0.5),      # blade lock
    (29.30, 29.50, 0.25),     # air clash
    (30.05, 30.25, 0.15),     # final pass-through
]
def speed_at(s):
    for a, b, k in SLOW:
        if a <= s < b: return k
    return 1.0

STORY_END = 37.5
def build_timeline():
    ts, s = [], 0.0
    while s < STORY_END:
        ts.append(s)
        s += speed_at(s) / FPS
    return ts

# ---------------------------------------------------------------- poses
# angles in degrees, facing right, y up. arm/leg = (upper, lower) absolute.
P = {
    "idle":    dict(t=94, aF=(300, 15), aB=(250, 215), lF=(292, 268), lB=(246, 262), b=58),
    "ready":   dict(t=82, aF=(320, 40), aB=(290, 30), lF=(305, 265), lB=(235, 255), b=40),
    "guardhi": dict(t=88, aF=(20, 100), aB=(40, 110), lF=(300, 262), lB=(240, 262), b=150),
    "slashdn": dict(t=62, aF=(330, 320), aB=(300, 330), lF=(330, 272), lB=(210, 225), b=330),
    "slashup": dict(t=86, aF=(40, 75), aB=(250, 220), lF=(300, 268), lB=(235, 255), b=82),
    "slashac": dict(t=70, aF=(355, 5), aB=(220, 200), lF=(320, 268), lB=(215, 230), b=5),
    "wind":    dict(t=100, aF=(160, 120), aB=(250, 220), lF=(300, 268), lB=(240, 262), b=135),
    "thrust":  dict(t=58, aF=(355, 0), aB=(200, 185), lF=(335, 275), lB=(200, 210), b=0),
    "block":   dict(t=100, aF=(330, 70), aB=(300, 75), lF=(305, 270), lB=(230, 255), b=95),
    "blocklo": dict(t=92, aF=(300, 330), aB=(280, 320), lF=(310, 265), lB=(230, 255), b=290),
    "run":     None,
    "tuck":    dict(t=70, aF=(320, 30), aB=(220, 260), lF=(340, 230), lB=(300, 220), b=40),
    "leap":    dict(t=75, aF=(80, 110), aB=(200, 170), lF=(300, 250), lB=(220, 280), b=140),
    "land":    dict(t=55, aF=(300, 330), aB=(200, 250), lF=(355, 265), lB=(215, 290), b=340),
    "hit":     dict(t=125, aF=(130, 160), aB=(250, 300), lF=(300, 270), lB=(250, 265), b=160),
    "stagger": dict(t=70, aF=(260, 250), aB=(240, 260), lF=(290, 265), lB=(255, 275), b=250),
    "kneel":   dict(t=60, aF=(270, 265), aB=(250, 250), lF=(0, 270), lB=(270, 180), b=260),
    "fallen":  dict(t=176, aF=(190, 215), aB=(170, 150), lF=(352, 330), lB=(8, 345), b=200),
    "victory": dict(t=92, aF=(70, 95), aB=(250, 230), lF=(290, 268), lB=(248, 262), b=92),
    "rest":    dict(t=92, aF=(275, 265), aB=(255, 265), lF=(285, 270), lB=(255, 270), b=275),
    "push":    dict(t=80, aF=(240, 250), aB=(0, 0), lF=(320, 268), lB=(220, 245), b=255),
    "roar":    dict(t=105, aF=(330, 20), aB=(220, 190), lF=(300, 265), lB=(240, 265), b=50),
    "lockF":   dict(t=72, aF=(15, 45), aB=(10, 50), lF=(325, 270), lB=(205, 225), b=55),
    "passend": dict(t=60, aF=(190, 200), aB=(225, 240), lF=(335, 268), lB=(205, 225), b=180),
}
KEYS = ["t", "aF", "aB", "lF", "lB", "b"]

def run_pose(phase):
    s = math.sin(phase); c = math.cos(phase)
    return dict(t=68, aF=(330 + 20 * s, 10 + 20 * s), aB=(220 - 40 * s, 250 - 30 * s),
                lF=(285 + 45 * s, 250 + 35 * s - 25 * max(0, -c)),
                lB=(285 - 45 * s, 250 - 35 * s - 25 * max(0, c)), b=-10 + 15 * s)

def get_pose(name, t):
    if name == "run": return run_pose(t * 22)
    return P[name]

def lerp_pose(a, b, u):
    out = {}
    for k in KEYS:
        if isinstance(a[k], tuple):
            out[k] = (lerp(a[k][0], b[k][0], u), lerp(a[k][1], b[k][1], u))
        else:
            out[k] = lerp(a[k], b[k], u)
    return out

# ---------------------------------------------------------------- choreography
# key: (t, x, y, facing, pose, blade_len, extra)  extra: dict(arc=, spin=, e=)
def K(t, x, y, f, p, bl=1.0, **kw): return dict(t=t, x=x, y=y, f=f, p=p, bl=bl, **kw)

SLAB_X, SLAB_TOP = 30, 62

G = [
    K(0, -260, 900, 1, "tuck", 0), K(4.0, -260, 900, 1, "tuck", 0),
    K(4.2, -260, 0, 1, "land", 0, e="in"), K(4.7, -260, 0, 1, "ready", 0),
    K(6.3, -260, 0, 1, "ready", 0), K(6.5, -260, 0, 1, "idle", 1),
    K(10.5, -255, 0, 1, "idle", 1), K(10.6, -240, 0, 1, "run"),
    K(11.3, -70, 0, 1, "run"), K(11.42, -45, 0, 1, "wind"),
    K(11.6, -40, 0, 1, "slashac", e="snap"), K(11.85, -150, 0, 1, "block", e="out"),
    K(12.2, -150, 0, 1, "ready"),
    # green vs blue below the slab
    K(12.35, -60, 0, 1, "thrust", e="snap"), K(12.6, -70, 0, 1, "ready"),
    K(12.75, -70, 0, 1, "guardhi"), K(12.9, -75, 0, 1, "block", e="snap"),
    K(13.15, -60, 0, 1, "wind"), K(13.3, -40, 0, 1, "slashdn", e="snap"),
    K(13.55, -60, 0, 1, "ready"), K(14.0, -60, 0, 1, "ready"),
    K(14.12, -70, 0, 1, "block", e="snap"), K(14.4, -150, 0, 1, "stagger", e="out"),
    K(14.6, -140, 0, 1, "ready"),
    K(14.75, -60, 0, 1, "slashdn", e="snap"), K(15.0, -70, 0, 1, "ready"),
    K(15.35, -70, 0, 1, "guardhi"), K(15.5, -80, 0, 1, "block", e="snap"),
    K(15.75, -180, 0, 1, "stagger", e="out"), K(16.2, -170, 0, 1, "ready"),
    K(16.55, -170, 0, 1, "ready"), K(16.7, -190, 0, 1, "hit", e="snap"),
    K(17.3, -330, 30, 1, "hit", arc=60, spin=-360),
    K(17.55, -340, 0, 1, "kneel", e="out"), K(18.6, -340, 0, 1, "kneel"),
    # green vs yellow
    K(19.0, -330, 0, 1, "roar"), K(19.5, -330, 0, 1, "roar"),
    K(19.6, -300, 0, 1, "run"), K(19.9, -210, 0, 1, "run"),
    K(20.0, -200, 0, 1, "slashdn", e="snap"), K(20.2, -205, 0, 1, "ready"),
    K(20.3, -195, 0, 1, "slashup", e="snap"), K(20.5, -200, 0, 1, "ready"),
    K(20.62, -180, 0, 1, "wind"),
    K(20.85, -150, 0, 1, "thrust", e="snap"), K(21.3, -140, 0, 1, "thrust"),
    K(21.6, -130, 0, 1, "stagger", 0.0, e="out"),
    K(22.1, -125, 0, 1, "kneel", 0.0), K(22.6, -125, 0, 1, "fallen", 0.0, e="in"),
    K(STORY_END, -125, 0, 1, "fallen", 0.0),
]

B = [
    K(0, 260, 900, -1, "tuck", 0), K(4.6, 260, 900, -1, "tuck", 0),
    K(4.8, 260, 0, -1, "land", 0, e="in"), K(5.3, 260, 0, -1, "ready", 0),
    K(6.6, 260, 0, -1, "ready", 0), K(6.8, 260, 0, -1, "idle", 1),
    K(10.5, 255, 0, -1, "idle"), K(10.6, 240, 0, -1, "run"),
    K(11.3, 70, 0, -1, "run"), K(11.42, 45, 0, -1, "wind"),
    K(11.6, 40, 0, -1, "slashac", e="snap"), K(11.85, 120, 0, -1, "block", e="out"),
    K(12.2, 100, 0, -1, "ready"),
    K(12.3, 40, 0, -1, "ready"), K(12.37, 40, 0, -1, "block", e="snap"),
    K(12.6, 40, 0, -1, "ready"), K(12.75, 30, 0, -1, "wind"),
    K(12.9, 10, 0, -1, "slashdn", e="snap"), K(13.15, 20, 0, -1, "ready"),
    K(13.3, 20, 0, -1, "blocklo", e="snap"), K(13.55, 30, 0, -1, "ready"),
    K(14.0, 30, 0, -1, "ready"),
    K(14.12, 40, 0, -1, "block", e="snap"), K(14.4, 130, 0, -1, "stagger", e="out"),
    K(14.6, 120, 0, -1, "ready"), K(14.9, 120, 0, -1, "ready"),
    K(15.05, 50, 0, -1, "slashdn", e="snap"), K(15.3, 60, 0, -1, "ready"),
    K(15.5, 70, 0, -1, "block", e="snap"),
    K(15.75, 170, 0, -1, "stagger", e="out"), K(16.2, 170, 0, -1, "ready"),
    K(16.4, 170, 0, -1, "ready"), K(16.55, 160, 0, -1, "push", e="snap"),
    K(17.2, 160, 0, -1, "push"), K(17.6, 170, 0, -1, "ready"),
    K(19.5, 220, 0, -1, "ready"), K(22.6, 220, 0, -1, "ready"),
    # blue walks in angry, then attacks yellow
    K(23.2, 230, 0, -1, "roar"), K(23.8, 230, 0, -1, "roar"),
    K(24.0, 200, 0, -1, "run"), K(24.35, 20, 0, -1, "run"),
    K(24.45, 10, 0, -1, "leap"), K(24.7, -45, 0, -1, "slashdn", e="in", arc=90),
    K(24.95, -25, 0, -1, "ready"),
    K(25.1, -25, 0, -1, "slashac", e="snap"), K(25.25, 5, 0, -1, "ready"),
    K(25.4, 5, 0, -1, "blocklo", e="snap"), K(25.55, 35, 0, -1, "wind"),
    K(25.7, 25, 0, -1, "slashdn", e="snap"), K(25.85, 60, 0, -1, "ready"),
    K(26.0, 60, 0, -1, "block", e="snap"), K(26.15, 85, 0, -1, "wind"),
    K(26.3, 75, 0, -1, "slashac", e="snap"), K(26.45, 70, 0, -1, "ready"),
    K(26.6, 58, 0, -1, "lockF", e="snap"), K(28.0, 55, 0, -1, "lockF"),
    K(28.25, 170, 50, -1, "tuck", arc=40, spin=360), K(28.35, 180, 0, -1, "land"),
    K(28.45, 180, 0, -1, "push", e="snap"), K(28.9, 180, 0, -1, "push"),
    K(29.0, 160, 0, -1, "run"), K(29.15, 120, 0, -1, "leap"),
    K(29.4, 40, 120, -1, "slashac", e="out"), K(29.6, 60, 60, -1, "tuck", spin=360),
    K(29.8, 140, 0, -1, "land", e="in"), K(29.9, 140, 0, -1, "ready"),
    K(30.05, 100, 0, -1, "run"), K(30.25, -30, 0, -1, "passend", e="snap"),
    K(31.25, -30, 0, -1, "passend"),
    K(31.5, -30, 0, -1, "stagger", 0.0, e="out"), K(31.9, -35, 0, -1, "kneel", 0.0),
    K(32.4, -35, 0, -1, "fallen", 0.0, e="in"), K(STORY_END, -35, 0, -1, "fallen", 0.0),
]

Y = [
    K(0, SLAB_X, 900, -1, "tuck", 0), K(5.4, SLAB_X, 900, -1, "tuck", 0),
    K(5.6, SLAB_X, SLAB_TOP, -1, "land", 0, e="in"), K(6.2, SLAB_X, SLAB_TOP, -1, "rest", 0),
    K(6.9, SLAB_X, SLAB_TOP, -1, "rest", 0), K(7.1, SLAB_X, SLAB_TOP, -1, "idle", 1),
    K(10.5, SLAB_X, SLAB_TOP, -1, "idle"), K(10.6, SLAB_X, SLAB_TOP, -1, "tuck"),
    K(11.1, 0, 0, 1, "land", arc=70, spin=-360), K(11.25, 0, 0, 1, "ready"),
    K(11.42, 0, 0, 1, "guardhi"), K(11.6, 0, 0, 1, "slashdn", e="snap"),
    K(11.75, 0, 0, 1, "tuck"), K(12.15, SLAB_X, SLAB_TOP, -1, "land", arc=60, spin=360),
    K(12.4, SLAB_X, SLAB_TOP, -1, "rest"), K(13.6, SLAB_X, SLAB_TOP, -1, "rest"),
    K(13.75, SLAB_X, SLAB_TOP, 1, "tuck"),
    K(14.1, -10, 0, 1, "slashdn", e="in", arc=50, spin=360),
    K(14.4, -10, 0, 1, "ready"),
    K(14.75, -10, 0, -1, "block", e="snap"), K(14.9, -10, 0, -1, "ready"),
    K(15.05, -10, 0, 1, "block", e="snap"), K(15.25, -10, 0, 1, "wind"),
    K(15.5, -10, 0, 1, "slashac", e="snap", spin=-360),
    K(15.7, -10, 0, 1, "ready"), K(16.3, -10, 0, 1, "ready"),
    K(16.55, -10, 0, 1, "tuck"),
    K(17.2, -200, 0, 1, "land", arc=140, spin=-720), K(17.5, -200, 0, 1, "ready"),
    K(18.8, -200, 0, -1, "ready"),
    # yellow vs green
    K(19.5, -125, 0, -1, "ready"), K(19.95, -125, 0, -1, "guardhi"),
    K(20.0, -130, 0, -1, "block", e="snap"), K(20.25, -130, 0, -1, "ready"),
    K(20.3, -140, 0, -1, "blocklo", e="snap"), K(20.55, -135, 0, -1, "ready"),
    K(20.8, -140, 0, -1, "ready"),
    K(20.95, -120, 0, -1, "tuck", e="snap"),
    K(21.1, -100, 0, -1, "wind", e="out"),
    K(21.3, -60, 0, -1, "slashac", e="snap", spin=-360),
    K(22.0, -60, 0, -1, "slashac"), K(22.5, -60, 0, -1, "ready"),
    K(23.0, -60, 0, 1, "ready"), K(24.4, -60, 0, 1, "ready"),
    # yellow vs blue
    K(24.6, -70, 0, 1, "guardhi"), K(24.7, -80, 0, 1, "block", e="snap"),
    K(24.95, -80, 0, 1, "ready"),
    K(25.1, -80, 0, 1, "blocklo", e="snap"), K(25.25, -55, 0, 1, "wind"),
    K(25.4, -55, 0, 1, "slashdn", e="snap"), K(25.55, -45, 0, 1, "ready"),
    K(25.7, -35, 0, 1, "block", e="snap"), K(25.85, -10, 0, 1, "wind"),
    K(26.0, -5, 0, 1, "slashac", e="snap"), K(26.15, 0, 0, 1, "ready"),
    K(26.3, 0, 0, 1, "blocklo", e="snap"), K(26.45, 0, 0, 1, "ready"),
    K(26.6, -8, 0, 1, "lockF", e="snap"), K(28.0, -5, 0, 1, "lockF"),
    K(28.25, -110, 40, 1, "tuck", arc=40, spin=-360), K(28.35, -120, 0, 1, "land"),
    K(28.45, -120, 0, 1, "ready"),
    K(28.5, -110, 0, 1, "slashup", e="snap"), K(28.6, -110, 0, 1, "ready"),
    K(28.7, -105, 0, 1, "slashdn", e="snap"), K(28.9, -110, 0, 1, "ready"),
    K(29.0, -90, 0, 1, "run"), K(29.15, -60, 0, 1, "leap"),
    K(29.4, 20, 125, 1, "slashac", e="out"), K(29.6, -20, 60, 1, "tuck", spin=-360),
    K(29.8, -100, 0, 1, "land", e="in"), K(29.9, -100, 0, 1, "ready"),
    K(30.05, -60, 0, 1, "run"), K(30.25, 210, 0, 1, "passend", e="snap"),
    K(31.4, 210, 0, 1, "passend"), K(32.2, 210, 0, 1, "rest", e="io"),
    K(32.6, 210, 0, -1, "rest"), K(33.2, 210, 0, -1, "rest", 0.0),
    K(34.0, 210, 0, -1, "victory", 0.0), K(34.3, 210, 0, -1, "victory", 1.0, e="snap"),
    K(35.6, 210, 0, -1, "victory", 1.0), K(36.2, 210, 0, -1, "rest", 0.0),
    K(STORY_END, 210, 0, -1, "rest", 0.0),
]
FIGHTERS = [("G", G), ("B", B), ("Y", Y)]

def eval_track(track, t):
    if t <= track[0]["t"]: k0 = k1 = track[0]; u = 0
    elif t >= track[-1]["t"]: k0 = k1 = track[-1]; u = 0
    else:
        i = 0
        while track[i + 1]["t"] <= t: i += 1
        k0, k1 = track[i], track[i + 1]
        u = (t - k0["t"]) / (k1["t"] - k0["t"])
    e = ease(u, k1.get("e", "io"))
    pa, pb = get_pose(k0["p"], t), get_pose(k1["p"], t)
    pose = lerp_pose(pa, pb, e)
    x = lerp(k0["x"], k1["x"], e)
    y = lerp(k0["y"], k1["y"], e) + k1.get("arc", 0) * 4 * u * (1 - u)
    spin = k1.get("spin", 0) * e
    f = k0["f"] if e < 0.5 else k1["f"]
    bl = lerp(k0["bl"], k1["bl"], clamp(u * 1.6))
    return x, y, f, pose, spin, bl

L_T, L_NECK, R_HEAD, L_UA, L_FA, L_TH, L_SH, L_BLADE, L_HILT = 30, 12, 9.5, 17, 16, 21, 21, 64, 8

def skeleton(x, y, f, pose, spin):
    def A(a):  # apply spin + mirroring
        a = a + spin
        return a if f > 0 else 180 - a
    rel = {}
    hip = (0, 0)
    neck = tuple(map(sum, zip(hip, pol(A(pose["t"]), L_T))))
    head = tuple(map(sum, zip(neck, pol(A(pose["t"]), L_NECK))))
    def limb(base, ang, l1, l2):
        j = (base[0] + pol(A(ang[0]), l1)[0], base[1] + pol(A(ang[0]), l1)[1])
        e = (j[0] + pol(A(ang[1]), l2)[0], j[1] + pol(A(ang[1]), l2)[1])
        return j, e
    sh = (lerp(hip[0], neck[0], 0.88), lerp(hip[1], neck[1], 0.88))
    eF, hF = limb(sh, pose["aF"], L_UA, L_FA)
    eB, hB = limb(sh, pose["aB"], L_UA, L_FA)
    kF, fF = limb(hip, pose["lF"], L_TH, L_SH)
    kB, fB = limb(hip, pose["lB"], L_TH, L_SH)
    pts = dict(hip=hip, neck=neck, head=head, sh=sh, eF=eF, hF=hF, eB=eB, hB=hB,
               kF=kF, fF=fF, kB=kB, fB=fB)
    low = min(p[1] for k, p in pts.items())
    low = min(low, head[1] - R_HEAD)
    off = (x, y - low)
    out = {k: (p[0] + off[0], p[1] + off[1]) for k, p in pts.items()}
    ba = A(pose["b"])
    out["bdir"] = ba
    hx, hy = out["hF"]
    out["hilt0"] = (hx - pol(ba, L_HILT * 0.5)[0], hy - pol(ba, L_HILT * 0.5)[1])
    out["hilt1"] = (hx + pol(ba, L_HILT * 0.5)[0], hy + pol(ba, L_HILT * 0.5)[1])
    return out

def blade_tip(sk, bl):
    hx, hy = sk["hilt1"]
    d = pol(sk["bdir"], L_BLADE * bl)
    return (hx + d[0], hy + d[1])

def fighter_state(name, track, t):
    x, y, f, pose, spin, bl = eval_track(track, t)
    sk = skeleton(x, y, f, pose, spin)
    return sk, bl, f

# ---------------------------------------------------------------- camera
# (t, cx, cy, zoom, ease)  cut=True means jump instantly at t
CAM = [
    dict(t=0, x=0, y=170, z=1.25), dict(t=3.4, x=0, y=110, z=1.55),
    dict(t=3.9, x=0, y=80, z=1.7, e="io"), dict(t=7.6, x=0, y=70, z=1.95),
    dict(t=8.0, x=-260, y=55, z=4.0, cut=True), dict(t=8.8, x=-255, y=55, z=4.4),
    dict(t=8.8, x=260, y=55, z=4.0, cut=True), dict(t=9.6, x=255, y=55, z=4.4),
    dict(t=9.6, x=SLAB_X, y=SLAB_TOP + 55, z=4.0, cut=True), dict(t=10.45, x=SLAB_X, y=SLAB_TOP + 55, z=4.4),
    dict(t=10.45, x=0, y=80, z=1.9, cut=True), dict(t=11.3, x=0, y=70, z=2.3),
    dict(t=11.6, x=0, y=60, z=3.0, e="snap"), dict(t=12.0, x=-20, y=70, z=2.4),
    dict(t=13.6, x=-20, y=70, z=2.5), dict(t=14.1, x=-10, y=65, z=2.7),
    dict(t=16.2, x=-10, y=75, z=2.3), dict(t=17.5, x=-120, y=80, z=1.8),
    dict(t=18.8, x=-250, y=70, z=2.4),
    dict(t=19.4, x=-260, y=60, z=3.2, e="snap"), dict(t=19.6, x=-220, y=70, z=2.6),
    dict(t=20.8, x=-170, y=65, z=2.8), dict(t=21.05, x=-120, y=55, z=3.6, e="snap"),
    dict(t=21.4, x=-100, y=55, z=3.8), dict(t=22.4, x=-110, y=70, z=2.5),
    dict(t=23.2, x=60, y=75, z=2.0), dict(t=23.8, x=210, y=65, z=3.4, e="snap"),
    dict(t=24.0, x=80, y=80, z=2.0, e="out"), dict(t=24.7, x=-60, y=60, z=2.8),
    dict(t=26.4, x=10, y=65, z=2.7), dict(t=26.7, x=25, y=70, z=4.2, e="snap"),
    dict(t=28.0, x=25, y=70, z=4.6), dict(t=28.3, x=30, y=80, z=2.2, e="out"),
    dict(t=29.2, x=30, y=110, z=2.2), dict(t=29.5, x=30, y=120, z=2.8),
    dict(t=29.9, x=20, y=75, z=2.2), dict(t=30.25, x=20, y=70, z=2.0),
    dict(t=31.2, x=20, y=70, z=2.1), dict(t=31.3, x=-170, y=50, z=3.4, cut=True),
    dict(t=32.6, x=-170, y=50, z=3.6), dict(t=32.6, x=210, y=65, z=3.0, cut=True),
    dict(t=34.4, x=210, y=75, z=3.6), dict(t=36.0, x=60, y=130, z=1.6), dict(t=STORY_END, x=40, y=150, z=1.4),
]
def eval_cam(t):
    k0, k1 = CAM[0], CAM[0]
    for i, k in enumerate(CAM):
        if k["t"] <= t: k0 = k; k1 = CAM[i + 1] if i + 1 < len(CAM) else k
    if k1["t"] == k0["t"] or k1.get("cut"): return k0["x"], k0["y"], k0["z"]
    u = ease((t - k0["t"]) / (k1["t"] - k0["t"]), k1.get("e", "io"))
    return lerp(k0["x"], k1["x"], u), lerp(k0["y"], k1["y"], u), lerp(k0["z"], k1["z"], u)

# ---------------------------------------------------------------- events
# clash sparks: (t, x, y, colour-a, colour-b, size)
EVENTS = []
def ev(kind, t, **kw): EVENTS.append(dict(kind=kind, t=t, **kw))

for t, x, y in [(4.2, -260, 0), (4.8, 260, 0), (5.6, SLAB_X, SLAB_TOP), (11.1, 0, 0),
                (14.1, -10, 0), (17.2, -200, 0), (17.55, -340, 0), (24.7, -60, 0),
                (28.35, 180, 0), (28.35, -120, 0), (29.8, 140, 0), (29.8, -100, 0),
                (22.6, -125, 0), (32.4, -35, 0)]:
    ev("dust", t, x=x, y=y)
for t, n in [(6.5, "G"), (6.8, "B"), (7.1, "Y"), (34.3, "Y")]:
    ev("ignite", t, who=n)

def clash(t, x, y, a, b, big=1.0, shake=6, flash=0.0, invert=False):
    ev("spark", t, x=x, y=y, a=a, b=b, big=big)
    ev("shake", t, amp=shake * big, dur=0.25 + 0.15 * big)
    if flash: ev("flash", t, amt=flash, dur=0.25)
    if invert: ev("invert", t, dur=2.5 / FPS)
    ev("ring", t, x=x, y=y, big=big)

clash(11.6, 0, 82, "G", "B", big=2.2, shake=10, flash=0.9, invert=True)
ev("spark", 11.6, x=0, y=82, a="Y", b="Y", big=1.6)
clash(12.37, -5, 60, "G", "B")
clash(12.9, -25, 85, "B", "G")
clash(13.3, -15, 40, "G", "B")
clash(14.1, -20, 70, "Y", "G", big=1.6, shake=9, flash=0.4)
ev("spark", 14.1, x=0, y=70, a="Y", b="B", big=1.4)
clash(14.75, -35, 70, "G", "Y")
clash(15.05, 15, 75, "B", "Y")
clash(15.5, -40, 60, "Y", "G", big=1.2)
ev("spark", 15.5, x=25, y=60, a="Y", b="B", big=1.2)
ev("push", 16.55, x=150, y=60, d=-1)
ev("shake", 16.6, amp=9, dur=0.6)
clash(20.0, -165, 85, "G", "Y")
clash(20.3, -168, 45, "G", "Y")
clash(21.3, -120, 60, "Y", "G", big=2.0, shake=12, flash=1.0, invert=True)
ev("slash", 21.3, x=-120, y=62, ang=8, col="Y")
clash(24.7, -70, 90, "B", "Y", big=1.8, shake=12, flash=0.5)
ev("ring", 24.7, x=-70, y=0, big=2.5)
clash(25.1, -60, 45, "B", "Y")
clash(25.4, -35, 40, "Y", "B")
clash(25.7, -20, 80, "B", "Y")
clash(26.0, 15, 65, "Y", "B")
clash(26.3, 25, 40, "B", "Y")
for i in range(9):
    ev("spark", 26.6 + i * 0.15, x=25, y=95, a="Y", b="B", big=0.7)
ev("shake", 26.6, amp=4, dur=1.4)
clash(28.0, 25, 95, "Y", "B", big=1.5, shake=10, flash=0.6, invert=True)
ev("push", 28.45, x=160, y=50, d=-1)
clash(28.5, -95, 70, "Y", "Y", big=0.9)
clash(28.7, -90, 45, "Y", "Y", big=0.9)
clash(29.4, 30, 160, "Y", "B", big=2.0, shake=11, flash=0.8, invert=True)
ev("slash", 30.15, x=20, y=60, ang=0, col="Y", big=1.6)
ev("flash", 30.15, amt=0.6, dur=0.3)
ev("shake", 31.3, amp=8, dur=0.4)
ev("slash", 31.3, x=-30, y=60, ang=-30, col="Y", big=1.3)
ev("flash", 31.3, amt=1.0, dur=0.45)
ev("invert", 31.3, dur=3 / FPS)
ev("ring", 31.3, x=-30, y=60, big=2)

# text overlays: (t0, t1, text, kind)
TEXTS = [
    (0.4, 3.6, "ASHFALL", "title"),
    (1.2, 3.6, "1  VS  1  VS  1", "sub"),
    (8.0, 8.8, "GREEN", "G"), (8.8, 9.6, "BLUE", "B"), (9.6, 10.45, "YELLOW", "Y"),
    (22.7, 24.0, "YELLOW  WINS  —  1", "win1"),
    (32.6, 34.2, "YELLOW  WINS  —  2", "win2"),
    (34.6, STORY_END, "YELLOW  WINS  ×2", "final"),
]

# ---------------------------------------------------------------- background
def rng_shapes(seed, n, spread, hmin, hmax, wmin, wmax):
    r = random.Random(seed)
    out = []
    for i in range(n):
        x = lerp(-spread, spread, (i + r.random() * 0.8) / n)
        h = r.uniform(hmin, hmax); w = r.uniform(wmin, wmax)
        kind = r.choice(["tower", "tower", "arch", "spire", "broken"])
        jag = [r.uniform(-0.25, 0.25) for _ in range(5)]
        out.append((x, w, h, kind, jag))
    return out

FAR = rng_shapes(7, 26, 1500, 80, 260, 30, 90)
MID = rng_shapes(11, 16, 1300, 50, 170, 25, 70)
ASH_RNG = random.Random(3)
ASH = [(ASH_RNG.random(), ASH_RNG.random(), ASH_RNG.uniform(0.4, 1.4), ASH_RNG.random() * 6.28)
       for _ in range(220)]

def shape_poly(x, w, h, kind, jag):
    if kind == "arch":
        pts = [(x - w, 0), (x - w, h * 0.7)]
        for i in range(9):
            a = math.pi - math.pi * i / 8
            pts.append((x + math.cos(a) * w, h * 0.7 + math.sin(a) * h * 0.3))
        pts += [(x + w, 0), (x + w * 0.55, 0), (x + w * 0.55, h * 0.55)]
        for i in range(9):
            a = math.pi * i / 8
            pts.append((x + math.cos(a) * w * 0.55, h * 0.55 + math.sin(a) * h * 0.2))
        pts += [(x - w * 0.55, h * 0.55), (x - w * 0.55, 0)]
        # broken chunk
        return [p for i, p in enumerate(pts) if not (6 <= i <= 8)]
    if kind == "spire":
        return [(x - w * 0.5, 0), (x - w * 0.3, h * 0.6), (x - w * 0.05, h), (x + w * 0.1, h * (0.75 + jag[0])),
                (x + w * 0.3, h * 0.55), (x + w * 0.5, 0)]
    if kind == "broken":
        return [(x - w * 0.6, 0), (x - w * 0.6, h * 0.5), (x - w * 0.2, h * (0.62 + jag[1])),
                (x + w * 0.1, h * 0.45), (x + w * 0.6, h * (0.3 + jag[2] * 0.4)), (x + w * 0.6, 0)]
    # tower with jagged ruined top
    top = [(x - w * 0.5, h * (0.92 + jag[0] * 0.3)), (x - w * 0.2, h * (1 + jag[1] * 0.4)),
           (x, h * (0.8 + jag[2] * 0.3)), (x + w * 0.25, h * (0.95 + jag[3] * 0.4)),
           (x + w * 0.5, h * (0.7 + jag[4] * 0.3))]
    return [(x - w * 0.5, 0)] + top + [(x + w * 0.5, 0)]

class Cam:
    def __init__(self, cx, cy, z, sx=0, sy=0):
        self.cx, self.cy, self.z, self.sx, self.sy = cx, cy, z, sx, sy
    def to(self, wx, wy, s=SS):
        return ((W / 2 + (wx - self.cx) * self.z + self.sx) * s, (H / 2 - (wy - self.cy) * self.z + self.sy) * s)
    def ground(self, s=SS): return self.to(0, 0, s)[1]

def draw_background(d, cam, t):
    gy = cam.ground()
    # sky: clean white top half with a faint warm haze toward the horizon
    for i in range(0, int(gy) + 2, 4 * SS):
        v = clamp(1 - (gy - i) / (H * SS * 0.45))
        c = (int(lerp(246, 214, v ** 2)), int(lerp(244, 206, v ** 2)), int(lerp(240, 198, v ** 2)))
        d.rectangle([0, i, W * SS, i + 4 * SS], fill=c)
    # shattered moon
    mx = W * SS * 0.72 - cam.cx * cam.z * 0.04 * SS
    my = gy - 330 * SS * (cam.z / 2) ** 0.3
    r = 120 * SS * (cam.z / 2) ** 0.3
    d.ellipse([mx - r, my - r, mx + r, my + r], fill=(228, 224, 219))
    d.polygon([(mx + r * 0.2, my - r * 1.02), (mx + r * 1.05, my - r * 0.3), (mx + r * 0.65, my + r * 0.1),
               (mx + r * 0.35, my - r * 0.25)], fill=(244, 242, 238))
    for a in (200, 240, 300):
        p1 = (mx + math.cos(math.radians(a)) * r * 0.2, my + math.sin(math.radians(a)) * r * 0.2)
        p2 = (mx + math.cos(math.radians(a + 15)) * r * 0.95, my + math.sin(math.radians(a + 15)) * r * 0.95)
        d.line([p1, p2], fill=(214, 209, 203), width=2 * SS)
    for i, (frac, chunk) in enumerate([(0.15, 18), (0.3, 11), (0.42, 7)]):
        cx_ = mx + r * (1.25 + frac * 1.6); cy_ = my - r * (0.7 - frac)
        s = chunk * SS * (cam.z / 2) ** 0.3
        d.polygon([(cx_ - s, cy_), (cx_, cy_ - s * 0.8), (cx_ + s, cy_ + s * 0.2), (cx_ + s * 0.1, cy_ + s)], fill=(222, 218, 212))
    # parallax ruin layers
    for layer, p, col in ((FAR, 0.3, (205, 200, 193)), (MID, 0.6, (164, 157, 148))):
        for x, w, h, kind, jag in layer:
            poly = shape_poly(x, w, h, kind, jag)
            pts = [((W / 2 + (px - cam.cx * p) * cam.z * p * 1.3 + cam.sx) * SS, gy - py * cam.z * p * 1.3 * SS)
                   for px, py in poly]
            if max(q[0] for q in pts) < 0 or min(q[0] for q in pts) > W * SS: continue
            d.polygon(pts, fill=col)
    # crashed starship hull in the mid layer
    p = 0.6
    def mp(px, py): return ((W / 2 + (px - cam.cx * p) * cam.z * p * 1.3 + cam.sx) * SS, gy - py * cam.z * p * 1.3 * SS)
    hull = [(-640, 0), (-610, 70), (-520, 110), (-380, 96), (-300, 40), (-280, 0)]
    d.polygon([mp(*q) for q in hull], fill=(150, 143, 135))
    d.polygon([mp(*q) for q in [(-560, 100), (-600, 190), (-575, 195), (-500, 104)]], fill=(150, 143, 135))
    for k in range(4):
        d.line([mp(-600 + k * 70, 30 + k * 6), mp(-560 + k * 70, 80 + k * 4)], fill=(176, 170, 162), width=2 * SS)
    # ground: ash plain
    for i in range(int(gy), H * SS + 4, 4 * SS):
        v = clamp((i - gy) / (H * SS * 0.5))
        c = (int(lerp(150, 92, v)), int(lerp(144, 86, v)), int(lerp(137, 82, v)))
        d.rectangle([0, i, W * SS, i + 4 * SS], fill=c)
    d.line([(0, gy), (W * SS, gy)], fill=(120, 114, 108), width=2 * SS)
    # ground ripples (parallax 1)
    rr = random.Random(5)
    for k in range(40):
        wx = rr.uniform(-900, 900); dep = rr.uniform(0.05, 1.0)
        sy = gy + dep ** 1.6 * (H * SS - gy)
        sx = (W / 2 + (wx - cam.cx * (1 + dep)) * cam.z * (1 + dep * 0.5) + cam.sx) * SS
        ln = rr.uniform(20, 70) * cam.z * SS * (0.5 + dep)
        d.line([(sx - ln, sy), (sx + ln, sy)], fill=(112, 106, 100), width=max(1, int(SS * (1 + dep * 2))))
    # near props: the slab yellow perches on, and a fallen column
    def wp(x, y): return cam.to(x, y)
    d.polygon([wp(SLAB_X - 52, 0), wp(SLAB_X - 46, SLAB_TOP - 2), wp(SLAB_X - 30, SLAB_TOP + 4),
               wp(SLAB_X + 40, SLAB_TOP), wp(SLAB_X + 50, SLAB_TOP - 10), wp(SLAB_X + 58, 0)], fill=(62, 58, 56))
    d.line([wp(SLAB_X - 40, 30), wp(SLAB_X - 10, 22), wp(SLAB_X + 5, 40)], fill=(90, 85, 80), width=2 * SS)
    d.polygon([wp(-470, 0), wp(-465, 150), wp(-445, 165), wp(-430, 135), wp(-420, 0)], fill=(70, 66, 62))
    d.polygon([wp(-415, 0), wp(-380, 22), wp(-300, 30), wp(-290, 10), wp(-300, 0)], fill=(80, 76, 71))
    d.polygon([wp(420, 0), wp(430, 95), wp(470, 120), wp(480, 70), wp(500, 0)], fill=(70, 66, 62))
    # smoke columns (drawn opaque-ish light greys, rising)
    for sxw, base in ((-1500, 0), (1500, 0)):
        for j in range(7):
            ph = (t * 0.08 + j / 7) % 1
            px = (W / 2 + (sxw + ph * 60 - cam.cx * 0.3) * cam.z * 0.39 + cam.sx) * SS
            py = gy - (ph * 380) * cam.z * 0.39 * SS
            rad = (6 + ph * 22) * cam.z * 0.39 * SS
            g = int(lerp(170, 232, ph))
            d.ellipse([px - rad, py - rad, px + rad, py + rad], fill=(g, g - 3, g - 6))

# ---------------------------------------------------------------- fighters
def draw_fighter(d, cam, name, sk, t, f, alive=True):
    w = int(6.5 * cam.z / 2.2 * SS) + 1
    def P_(k): return cam.to(*sk[k])
    col = INK
    segs = [("hip", "neck"), ("sh", "eB"), ("eB", "hB"), ("hip", "kB"), ("kB", "fB"),
            ("hip", "kF"), ("kF", "fF"), ("sh", "eF"), ("eF", "hF")]
    # scarf in team colour, flowing behind
    nx, ny = sk["neck"]
    sc = COL[name]
    pts = [cam.to(nx, ny - 2)]
    for i in range(1, 6):
        wob = math.sin(t * 9 + i * 0.9 + hash(name) % 7) * (2 + i * 1.6)
        pts.append(cam.to(nx - f * i * 7, ny - 2 + wob - i * 0.6))
    d.line(pts, fill=sc, width=max(2, int(w * 0.75)), joint="curve")
    for a, b in segs:
        d.line([P_(a), P_(b)], fill=col, width=w)
    for k in ("hip", "neck", "sh", "eF", "eB", "kF", "kB", "hF", "hB", "fF", "fB"):
        x, y = P_(k); r = w / 2
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    hx, hy = P_("head"); r = R_HEAD * cam.z * SS
    d.ellipse([hx - r, hy - r, hx + r, hy + r], fill=col)
    # hilt
    d.line([cam.to(*sk["hilt0"]), cam.to(*sk["hilt1"])], fill=(70, 70, 76), width=int(w * 0.9))

def draw_blade(over, glow, cam, name, sk, bl, trail_sks):
    if bl <= 0.01: return
    c = COL[name]
    tip = blade_tip(sk, bl)
    base = sk["hilt1"]
    zz = cam.z
    # motion trail arc
    if trail_sks:
        poly_prev = (cam.to(*base), cam.to(*tip))
        for i, (tsk, tbl) in enumerate(trail_sks):
            tt = blade_tip(tsk, tbl); tb = tsk["hilt1"]
            a = int(85 * (1 - i / len(trail_sks)) ** 1.5)
            cur = (cam.to(*tb), cam.to(*tt))
            over.polygon([poly_prev[0], poly_prev[1], cur[1], cur[0]], fill=c + (a,))
            gp = [(p[0] / SS / 4, p[1] / SS / 4) for p in (poly_prev[0], poly_prev[1], cur[1], cur[0])]
            glow.polygon(gp, fill=tuple(int(v * 0.35 * (1 - i / len(trail_sks))) for v in c))
            poly_prev = cur
    b0, b1 = cam.to(*base), cam.to(*tip)
    wcore = max(3, int(4.2 * zz / 2.2 * SS))
    over.line([b0, b1], fill=c + (255,), width=int(wcore * 1.9))
    pale = tuple(int(lerp(v, 255, 0.78)) for v in c)
    over.line([b0, b1], fill=pale + (255,), width=wcore)
    for p in (b1,):
        r = wcore * 0.95
        over.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=pale + (255,))
    g0, g1 = (b0[0] / SS / 4, b0[1] / SS / 4), (b1[0] / SS / 4, b1[1] / SS / 4)
    glow.line([g0, g1], fill=c, width=max(2, int(3.2 * zz / 2.2)))

# ---------------------------------------------------------------- particles
def spark_parts(e):
    r = random.Random(int(e["t"] * 1000) + int(e["x"]))
    n = int(16 * e["big"]) + 6
    out = []
    for i in range(n):
        a = r.uniform(0, 360); s = r.uniform(120, 420) * (0.6 + 0.4 * e["big"])
        out.append((a, s, r.uniform(0.2, 0.5), e["a"] if i % 2 else e["b"]))
    return out

def debris_parts(e):
    r = random.Random(int(e["t"] * 77))
    return [(r.uniform(-20, 40), r.uniform(0, 90), r.uniform(250, 520) * e["d"], r.uniform(80, 260),
             r.uniform(4, 14), r.uniform(0, 360)) for _ in range(22)]

def draw_events(over, glow, cam, t):
    for e in EVENTS:
        dt = t - e["t"]
        if dt < 0: continue
        k = e["kind"]
        if k == "spark" and dt < 0.6:
            for a, s, life, who in spark_parts(e):
                if dt > life: continue
                u = dt / life
                d1 = s * dt; d0 = max(0, d1 - 30 - s * 0.05)
                p0 = (e["x"] + pol(a, d0)[0], e["y"] + pol(a, d0)[1] - 200 * dt * dt)
                p1 = (e["x"] + pol(a, d1)[0], e["y"] + pol(a, d1)[1] - 200 * dt * dt)
                c = COL[who]
                al = int(255 * (1 - u))
                over.line([cam.to(*p0), cam.to(*p1)], fill=c + (al,), width=max(2, int(2.2 * cam.z * SS / 2)))
                glow.line([(q[0] / SS / 4, q[1] / SS / 4) for q in (cam.to(*p0), cam.to(*p1))],
                          fill=tuple(int(v * (1 - u)) for v in c), width=2)
            if dt < 0.12:
                cx, cy = cam.to(e["x"], e["y"]); r = (40 + 260 * dt) * e["big"] * cam.z * SS / 2
                over.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, int(230 * (1 - dt / 0.12))))
                g = (cx / SS / 4, cy / SS / 4); gr = r / SS / 4 * 0.9
                cc = tuple(min(255, (COL[e["a"]][i] + COL[e["b"]][i]) // 2 + 40) for i in range(3))
                glow.ellipse([g[0] - gr, g[1] - gr, g[0] + gr, g[1] + gr], fill=cc)
        elif k == "ring" and dt < 0.45:
            u = dt / 0.45
            cx, cy = cam.to(e["x"], e["y"])
            rx = (20 + 180 * ease(u, "out")) * e["big"] * cam.z * SS / 2
            ry = rx * (0.35 if e["y"] < 5 else 1.0)
            over.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], outline=(255, 255, 255, int(220 * (1 - u))),
                         width=max(2, int(6 * (1 - u) * SS)))
        elif k == "dust" and dt < 1.0:
            r_ = random.Random(int(e["t"] * 100))
            for i in range(14):
                side = -1 if i % 2 else 1
                vx = side * r_.uniform(30, 140); vy = r_.uniform(5, 40)
                px = e["x"] + vx * ease(dt, "out") * 1.2; py = e["y"] + vy * ease(dt, "out")
                rr = (6 + 26 * ease(dt, "out")) * r_.uniform(0.7, 1.3)
                cx, cy = cam.to(px, py); rs = rr * cam.z * SS
                al = int(160 * (1 - dt))
                g = r_.randint(150, 185)
                over.ellipse([cx - rs, cy - rs, cx + rs, cy + rs], fill=(g, g - 4, g - 8, al))
        elif k == "push" and dt < 1.2:
            u = dt / 1.2
            # shock cone
            if dt < 0.35:
                cx, cy = cam.to(e["x"], e["y"])
                for j in range(3):
                    rr = (30 + 420 * (dt + j * 0.05)) * cam.z * SS
                    over.arc([cx - rr, cy - rr * 0.8, cx + rr, cy + rr * 0.8], 150, 210,
                             fill=(255, 255, 255, int(200 * (1 - dt / 0.35))), width=int(4 * SS))
            for ox, oy, vx, vy, sz, rot in debris_parts(e):
                px = e["x"] + ox * e["d"] + vx * dt; py = e["y"] + oy * 0.3 + vy * dt - 420 * dt * dt
                if py < -10: continue
                cx, cy = cam.to(px, py); s = sz * cam.z * SS
                a0 = rot + dt * 600
                poly = [(cx + math.cos(math.radians(a0 + q * 90 + (q * 23 % 30))) * s,
                         cy + math.sin(math.radians(a0 + q * 90 + (q * 23 % 30))) * s) for q in range(4)]
                over.polygon(poly, fill=(55, 52, 50, 255))
        elif k == "slash" and dt < 0.6:
            u = dt / 0.6
            cx, cy = cam.to(e["x"], e["y"])
            L = W * SS * 1.2 * ease(min(1, dt / 0.08), "out") * e.get("big", 1)
            d = pol(-e["ang"], 1)
            th = (26 * SS) * (1 - u) * e.get("big", 1)
            p0 = (cx - d[0] * L / 2, cy - d[1] * L / 2); p1 = (cx + d[0] * L / 2, cy + d[1] * L / 2)
            nx, ny = -d[1] * th / 2, d[0] * th / 2
            over.polygon([p0, (cx + nx, cy + ny), p1, (cx - nx, cy - ny)], fill=COL[e["col"]] + (int(255 * (1 - u)),))
            nx, ny = nx * 0.4, ny * 0.4
            over.polygon([p0, (cx + nx, cy + ny), p1, (cx - nx, cy - ny)], fill=(255, 255, 255, int(255 * (1 - u))))
        elif k == "ignite" and dt < 0.5:
            pass  # handled via blade length + sound

def shake_offset(t):
    sx = sy = 0.0
    for e in EVENTS:
        if e["kind"] != "shake": continue
        dt = t - e["t"]
        if 0 <= dt < e["dur"]:
            a = e["amp"] * (1 - dt / e["dur"]) ** 2
            sx += math.sin(dt * 91 + e["t"]) * a
            sy += math.cos(dt * 77 + e["t"] * 3) * a
    return sx, sy

def flash_amt(t):
    a = 0.0
    for e in EVENTS:
        if e["kind"] == "flash":
            dt = t - e["t"]
            if 0 <= dt < e["dur"]: a = max(a, e["amt"] * (1 - dt / e["dur"]))
    return a

def inverted(t):
    return any(e["kind"] == "invert" and 0 <= t - e["t"] < e["dur"] for e in EVENTS)

# ---------------------------------------------------------------- text
_fonts = {}
def font(sz, path=FONT):
    k = (sz, path)
    if k not in _fonts: _fonts[k] = ImageFont.truetype(path, sz)
    return _fonts[k]

def draw_texts(img, t):
    d = ImageDraw.Draw(img, "RGBA")
    for t0, t1, s, kind in TEXTS:
        if not (t0 <= t < t1): continue
        u = (t - t0); v = t1 - t
        fade = clamp(min(u, v) / 0.15)
        if kind == "title":
            sz = 150
            sl = ease(clamp(u / 0.5), "snap")
            x = lerp(-600, W / 2, sl)
            f = font(sz)
            tw = d.textlength(s, font=f)
            # ink brush band
            d.polygon([(0, 250), (W, 205), (W, 380), (0, 420)], fill=(14, 13, 16, int(235 * fade)))
            d.text((x - tw / 2 + 6, 222 + 6), s, font=f, fill=(255, 214, 20, int(255 * fade)))
            d.text((x - tw / 2, 222), s, font=f, fill=(250, 248, 244, int(255 * fade)))
        elif kind == "sub":
            f = font(40, FONT_B); tw = d.textlength(s, font=f)
            parts = [("1", COL["G"]), ("  VS  ", (250, 248, 244)), ("1", COL["B"]), ("  VS  ", (250, 248, 244)), ("1", COL["Y"])]
            x = W / 2 - tw / 2
            for p, c in parts:
                d.text((x, 432), p, font=f, fill=c + (int(255 * fade),)); x += d.textlength(p, font=f)
        elif kind in ("G", "B", "Y"):
            c = COL[kind]
            sl = ease(clamp(u / 0.25), "snap")
            right = kind == "B"
            band = [(0, 520), (W, 470), (W, 600), (0, 640)]
            d.polygon(band, fill=c + (int(220 * fade),))
            d.polygon([(0, 545), (W, 495), (W, 505), (0, 555)], fill=(14, 13, 16, int(200 * fade)))
            f = font(120)
            tw = d.textlength(s, font=f)
            x = lerp(W + 50, W - tw - 80, sl) if right else lerp(-tw - 50, 80, sl)
            d.text((x + 5, 480 + 5), s, font=f, fill=(14, 13, 16, int(255 * fade)))
            d.text((x, 480), s, font=f, fill=(255, 255, 255, int(255 * fade)))
            # speed lines
            r = random.Random(int(t * 30))
            for _ in range(26):
                yy = r.uniform(80, 660); xx = r.uniform(-200, W); ln = r.uniform(120, 420)
                d.line([(xx, yy), (xx + ln, yy)], fill=(14, 13, 16, int(90 * fade)), width=2)
        elif kind in ("win1", "win2", "final"):
            c = COL["Y"]
            big = kind == "final"
            sl = ease(clamp(u / 0.3), "snap")
            f = font(110 if big else 84)
            tw = d.textlength(s, font=f)
            y0 = 90 if big else 120
            d.polygon([(0, y0 - 10), (W, y0 - 40), (W, y0 + (130 if big else 100)), (0, y0 + (150 if big else 115))],
                      fill=(14, 13, 16, int(225 * fade)))
            x = lerp(W, W / 2 - tw / 2, sl)
            d.text((x + 5, y0 + 5), s, font=f, fill=c + (int(255 * fade),))
            d.text((x, y0), s, font=f, fill=(250, 248, 244, int(255 * fade)))

# ---------------------------------------------------------------- frame
STATE_DT = 0.014
def render_frame(t):
    cx, cy, z = eval_cam(t)
    sx, sy = shake_offset(t)
    cam = Cam(cx, cy, z, sx, sy)
    img = Image.new("RGB", (W * SS, H * SS))
    d = ImageDraw.Draw(img)
    draw_background(d, cam, t)
    over = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    od = ImageDraw.Draw(over, "RGBA")
    glow = Image.new("RGB", (W // 4, H // 4))
    gd = ImageDraw.Draw(glow)
    # dust & debris behind fighters? they read better in front; draw after fighters
    order = sorted(FIGHTERS, key=lambda n: {"Y": 2}.get(n[0], 0))
    for name, track in order:
        sk, bl, f = fighter_state(name, track, t)
        draw_fighter(d, cam, name, sk, t, f)
        trail = []
        tip_now = blade_tip(sk, bl)
        psk, pbl, _ = fighter_state(name, track, t - STATE_DT * 3)
        if bl > 0.05 and math.dist(tip_now, blade_tip(psk, pbl)) > 9:
            trail = [fighter_state(name, track, t - STATE_DT * i)[:2] for i in range(1, 6)]
        draw_blade(od, gd, cam, name, sk, bl, trail)
    draw_events(od, gd, cam, t)
    # ash flakes (screen space with parallax depth)
    for fx, fy, depth, ph in ASH:
        y = (fy * H + t * 40 * depth) % (H + 20) - 10
        x = (fx * W + math.sin(t * 1.3 + ph) * 18 * depth - cam.cx * cam.z * 0.25 * depth) % (W + 20) - 10
        s = 1.4 * depth * SS
        g = int(lerp(150, 70, depth / 1.4))
        od.ellipse([x * SS - s, y * SS - s, x * SS + s * 1.4, y * SS + s], fill=(g, g, g, int(150 + 60 * depth)))
    img = Image.alpha_composite(img.convert("RGBA"), over).convert("RGB")
    img = img.resize((W, H), Image.LANCZOS)
    # glow composite (alpha-tinted so it reads on white and on ash)
    gl = glow.filter(ImageFilter.GaussianBlur(3)).resize((W, H), Image.BILINEAR)
    G_ = np.asarray(gl, dtype=np.float32) / 255
    A = np.clip(G_.max(axis=2, keepdims=True) * 1.15, 0, 0.75)
    C = G_ / np.maximum(G_.max(axis=2, keepdims=True), 1e-3)
    base = np.asarray(img, dtype=np.float32) / 255
    out = base * (1 - A) + C * A
    fl = flash_amt(t)
    if fl > 0: out = out * (1 - fl) + fl
    # vignette + contrast
    out = np.clip(out * VIGNETTE, 0, 1)
    img = Image.fromarray((out * 255).astype(np.uint8))
    if inverted(t):
        img = ImageOps.invert(img)
    draw_texts(img, t)
    # cinematic letterbox
    d2 = ImageDraw.Draw(img)
    d2.rectangle([0, 0, W, 54], fill=(0, 0, 0)); d2.rectangle([0, H - 54, W, H], fill=(0, 0, 0))
    return img

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
VIGNETTE = (1 - 0.22 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) ** 1.5)[..., None]

# ---------------------------------------------------------------- audio
SR = 44100
def synth_audio(timeline, path):
    n = int(len(timeline) / FPS * SR) + SR
    out = np.zeros(n, dtype=np.float32)
    rng = np.random.default_rng(1)
    # story time -> video time
    def vt(s):
        for i, st in enumerate(timeline):
            if st >= s: return i / FPS
        return len(timeline) / FPS
    def add(sig, at, gain=1.0):
        i = int(at * SR)
        if i >= n: return
        j = min(n, i + len(sig))
        out[i:j] += sig[: j - i] * gain
    tt = np.arange(n) / SR
    # wind drone
    wind = rng.standard_normal(n).astype(np.float32)
    k = np.ones(400) / 400
    wind = np.convolve(wind, k, mode="same") * 6
    out += wind * (0.25 + 0.1 * np.sin(tt * 0.4)).astype(np.float32)
    # low cinematic pulse
    out += (0.08 * np.sin(2 * np.pi * 55 * tt) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * tt)) ** 4).astype(np.float32)
    def env(L, a=0.005, r=0.3):
        x = np.arange(int(L * SR)) / SR
        return np.minimum(x / a, 1) * np.exp(-x / r)
    def clang(big=1.0):
        L = 1.2
        x = np.arange(int(L * SR)) / SR
        s = np.zeros_like(x)
        for f, a in ((1180, 1), (1730, .7), (2630, .5), (3970, .35), (620, .6)):
            s += a * np.sin(2 * np.pi * f * x * (1 + 0.002 * big))
        s *= np.exp(-x / (0.18 * big))
        noise = rng.standard_normal(len(x)) * np.exp(-x / 0.04)
        boom = np.sin(2 * np.pi * 60 * x * np.exp(-x * 3)) * np.exp(-x / (0.25 * big)) * big
        return (0.25 * s + 0.5 * noise + 0.8 * boom).astype(np.float32)
    def thud():
        x = np.arange(int(0.6 * SR)) / SR
        return (np.sin(2 * np.pi * 50 * x * np.exp(-x * 4)) * np.exp(-x / 0.15) +
                0.3 * rng.standard_normal(len(x)) * np.exp(-x / 0.05)).astype(np.float32)
    def ignite():
        x = np.arange(int(0.7 * SR)) / SR
        f = 80 + 160 * np.minimum(x / 0.25, 1)
        ph = np.cumsum(2 * np.pi * f / SR)
        return ((np.sin(ph) + 0.5 * np.sin(2.01 * ph)) * np.minimum(x / 0.02, 1) * np.exp(-x / 0.35) * 0.6 +
                0.2 * rng.standard_normal(len(x)) * np.exp(-x / 0.08)).astype(np.float32)
    def whoosh():
        x = np.arange(int(0.25 * SR)) / SR
        nz = np.convolve(rng.standard_normal(len(x)), np.ones(30) / 30, mode="same") * 4
        hum = np.sin(2 * np.pi * (120 + 300 * x / 0.25) * x)
        return ((nz * 0.5 + hum * 0.4) * np.sin(np.pi * x / 0.25) ** 2).astype(np.float32)
    def boom():
        x = np.arange(int(2.0 * SR)) / SR
        nz = np.convolve(rng.standard_normal(len(x)), np.ones(60) / 60, mode="same") * 5
        return ((np.sin(2 * np.pi * 38 * x) + nz) * np.exp(-x / 0.6)).astype(np.float32)
    for e in EVENTS:
        at = vt(e["t"])
        if e["kind"] == "spark": add(clang(e["big"]), at, 0.35 * min(1.5, e["big"]))
        elif e["kind"] == "dust": add(thud(), at, 0.6)
        elif e["kind"] == "ignite": add(ignite(), at, 0.5)
        elif e["kind"] == "push": add(boom(), at, 0.5)
        elif e["kind"] == "slash": add(boom(), at, 0.6); add(whoosh(), at - 0.1, 0.8)
        elif e["kind"] == "invert": add(boom(), at, 0.35)
    # whooshes on fast swings
    for name, track in FIGHTERS:
        last = -1
        for k in track:
            if k.get("e") == "snap" and k["p"] in ("slashdn", "slashup", "slashac", "thrust") and k["t"] - last > 0.1:
                add(whoosh(), vt(k["t"]) - 0.12, 0.45); last = k["t"]
    # blade hum while lit
    hum = np.zeros(n, dtype=np.float32)
    for i, s in enumerate(timeline):
        lit = sum(eval_track(tr, s)[5] for _, tr in FIGHTERS)
        a, b = int(i / FPS * SR), int((i + 1) / FPS * SR)
        hum[a:b] = lit
    hum = np.convolve(hum, np.ones(2000) / 2000, mode="same")
    out += (hum * 0.03 * (np.sin(2 * np.pi * 92 * tt) + 0.5 * np.sin(2 * np.pi * 184.7 * tt))).astype(np.float32)
    out = np.tanh(out * 1.2) * 0.85
    fade = int(1.5 * SR)
    end = int(len(timeline) / FPS * SR)
    out[end - fade:end] *= np.linspace(1, 0, fade)
    out = out[:end]
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((out * 32767).astype(np.int16).tobytes())

# ---------------------------------------------------------------- main
def _job(args):
    i, t, d = args
    render_frame(t).save(os.path.join(d, f"f{i:05d}.png"), compress_level=1)
    return i

def main():
    if "--still" in sys.argv:
        t = float(sys.argv[sys.argv.index("--still") + 1])
        render_frame(t).save(os.path.join(HERE, "still.png")); return
    tmp = os.environ.get("ASHFALL_TMP", os.path.join(HERE, "_frames"))
    os.makedirs(tmp, exist_ok=True)
    tl = build_timeline()
    print(f"{len(tl)} frames ({len(tl) / FPS:.1f}s)")
    synth_audio(tl, os.path.join(tmp, "audio.wav"))
    with Pool(os.cpu_count()) as pool:
        for k, _ in enumerate(pool.imap_unordered(_job, [(i, t, tmp) for i, t in enumerate(tl)], chunksize=8)):
            if k % 100 == 0: print("frame", k, flush=True)
    out = os.path.join(HERE, "ashfall.mp4")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", os.path.join(tmp, "f%05d.png"),
                    "-i", os.path.join(tmp, "audio.wav"), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20",
                    "-preset", "medium", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", out],
                   check=True)
    shutil.rmtree(tmp)
    print("wrote", out)

if __name__ == "__main__":
    main()

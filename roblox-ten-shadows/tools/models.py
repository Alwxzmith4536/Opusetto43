"""Part-based geometry for every Ten Shadows model.

This file is the single source of truth for the models. It writes
assets/models.json, which is used twice:
  * tools/build.py turns it into ModelData.luau (what the game builds in Roblox)
  * preview/index.html renders it with three.js (the screenshots in media/)

Conventions (same as Roblox): Y is up, the model faces -Z, feet rest on y = 0.
Sizes and positions are in studs, rotations are CFrame.Angles order in degrees.
Shapes: Block, Ball, Cylinder (axis along X, like Roblox), Wedge (WedgePart).
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "models.json")


def _rx(a):
    c, s = math.cos(a), math.sin(a)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def _ry(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def _rz(a):
    c, s = math.cos(a), math.sin(a)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def _apply(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def euler_to_matrix(rot_deg):
    """Same convention as Roblox CFrame.Angles: R = Rx * Ry * Rz."""
    a, b, c = (math.radians(v) for v in rot_deg)
    return _mul(_mul(_rx(a), _ry(b)), _rz(c))


def matrix_to_euler(r):
    b = math.asin(max(-1.0, min(1.0, r[0][2])))
    a = math.atan2(-r[1][2], r[2][2])
    c = math.atan2(-r[0][1], r[0][0])
    return [math.degrees(a), math.degrees(b), math.degrees(c)]


class Model:
    def __init__(self, name, desc):
        self.name = name
        self.desc = desc
        self.parts = []
        self.joints = {}
        self.root = None

    def add(self, name, shape, size, pos, color, rot=(0, 0, 0), material="SmoothPlastic",
            group="Body", transparency=0.0):
        self.parts.append({
            "name": name, "shape": shape, "size": [round(v, 3) for v in size],
            "pos": [round(v, 3) for v in pos], "rot": [round(v, 3) for v in rot],
            "color": list(color), "material": material, "group": group,
            "transparency": transparency,
        })

    def pair(self, name, shape, size, pos, color, rot=(0, 0, 0), **kw):
        """Adds a left/right mirrored pair. pos/rot describe the RIGHT (+X) side."""
        x, y, z = pos
        rx, ry, rz = rot
        grp = kw.pop("group", "Body")
        lgrp = kw.pop("lgroup", grp)
        self.add(name + "R", shape, size, (x, y, z), color, (rx, ry, rz), group=grp, **kw)
        self.add(name + "L", shape, size, (-x, y, z), color, (rx, -ry, -rz), group=lgrp, **kw)

    def pose(self, group, pivot, rot_deg):
        """Bakes a rest pose: rotates every part of a group around a pivot."""
        r = euler_to_matrix(rot_deg)
        for p in self.parts:
            if p["group"] != group:
                continue
            rel = [p["pos"][i] - pivot[i] for i in range(3)]
            p["pos"] = [round(pivot[i] + v, 3) for i, v in enumerate(_apply(r, rel))]
            p["rot"] = [round(v, 3) for v in matrix_to_euler(_mul(r, euler_to_matrix(p["rot"])))]

    def joint(self, group, part0, pivot):
        self.joints[group] = {"part0": part0, "pivot": list(pivot)}

    def set_root(self, size, pos):
        self.root = {"size": list(size), "pos": list(pos)}

    def to_dict(self):
        min_y = min(p["pos"][1] - self._half_height(p) for p in self.parts)
        d = {"desc": self.desc, "parts": self.parts, "joints": self.joints, "minY": round(min_y, 3)}
        if self.root:
            d["root"] = self.root
            d["hipHeight"] = round(self.root["pos"][1] - self.root["size"][1] / 2 - max(min_y, 0), 3)
        return d

    @staticmethod
    def _half_height(p):
        sx, sy, sz = p["size"]
        if p["shape"] == "Ball":
            return min(p["size"]) / 2
        if p["shape"] == "Cylinder" and abs(p["rot"][2]) % 180 == 90:
            return sx / 2
        return sy / 2


# ---------------------------------------------------------------- palette
MAHO_SKIN = (236, 233, 225)
MAHO_SHADE = (205, 200, 190)
MAHO_CLOTH = (26, 24, 32)
GOLD = (214, 178, 74)
GOLD_DARK = (150, 116, 40)
BLADE = (255, 246, 222)
SHADOW = (18, 16, 24)
SHADOW_RIM = (120, 70, 200)


def ring(m, name, radius, count, seg_size, center, color, plane="XZ", material="SmoothPlastic",
         group="Body", phase=0.0):
    """A polygon ring of blocks. plane XZ = lying flat (segment long axis Z),
    XY = standing and facing -Z (segment long axis X)."""
    cx, cy, cz = center
    for i in range(count):
        a = 2 * math.pi * i / count + phase
        deg = math.degrees(a)
        if plane == "XZ":
            pos = (cx + radius * math.cos(a), cy, cz + radius * math.sin(a))
            rot = (0, -deg, 0)
        else:
            pos = (cx + radius * math.cos(a), cy + radius * math.sin(a), cz)
            rot = (0, 0, deg + 90)
        m.add(f"{name}{i}", "Block", seg_size, pos, color, rot, material=material, group=group)


# ---------------------------------------------------------------- Mahoraga
def mahoraga(name="Mahoraga", skin=MAHO_SKIN, shade=MAHO_SHADE, cloth=MAHO_CLOTH, tamed=False):
    m = Model(name, "Eight-Handled Sword Divergent Sila Divine General Mahoraga. ~20 studs tall, "
                    "adaptation wheel above the head, Sword of Extermination on the right arm.")
    # legs
    m.pair("Foot", "Block", (2.2, 0.8, 3.2), (1.8, 0.4, -0.4), shade)
    m.pair("Shin", "Block", (1.8, 4.2, 1.9), (1.8, 2.9, 0), skin)
    m.pair("Knee", "Ball", (2.1, 2.1, 2.1), (1.8, 5.0, -0.1), shade)
    m.pair("Thigh", "Block", (2.4, 4.0, 2.4), (1.8, 7.0, 0), skin)
    # waist cloth (dark hakama-like wrap) with gold rope
    m.add("Skirt", "Block", (5.8, 3.2, 3.6), (0, 8.1, 0), cloth)
    m.add("SkirtFlapF", "Block", (2.6, 4.6, 0.3), (0, 6.9, -1.9), cloth, (-6, 0, 0))
    m.add("SkirtFlapB", "Block", (3.4, 4.2, 0.3), (0, 7.0, 1.9), cloth, (6, 0, 0))
    m.add("Rope", "Block", (6.0, 0.5, 3.8), (0, 9.5, 0), GOLD, material="Metal")
    m.add("RopeKnot", "Ball", (1.0, 1.0, 1.0), (0, 9.4, -2.0), GOLD, material="Metal")
    # torso
    m.add("Abdomen", "Block", (4.6, 2.6, 2.9), (0, 11.0, 0), skin)
    for row in range(3):
        m.pair(f"Ab{row}", "Block", (1.2, 0.7, 0.25), (0.7, 10.3 + row * 0.85, -1.5), shade)
    m.add("Torso", "Block", (6.2, 4.4, 3.4), (0, 14.3, 0), skin)
    m.pair("Pec", "Block", (2.7, 1.9, 0.4), (1.45, 15.0, -1.75), shade)
    m.add("Spine", "Block", (0.5, 4.0, 0.3), (0, 13.6, 1.75), shade)
    m.pair("Trap", "Wedge", (1.8, 1.2, 2.6), (1.9, 17.0, 0.2), skin, (0, 180, 0))
    m.add("Neck", "Cylinder", (1.6, 1.8, 1.8), (0, 17.2, 0), skin, (0, 0, 90))
    # head: smooth, eyeless, covered by four wings
    m.add("Head", "Block", (2.3, 2.5, 2.4), (0, 18.9, -0.1), skin)
    m.add("Jaw", "Block", (1.9, 0.8, 2.0), (0, 17.8, -0.2), shade)
    m.add("Mouth", "Block", (1.1, 0.12, 0.1), (0, 18.0, -1.25), (60, 50, 50))
    # four head wings: the front pair covers the eyes, the upper pair sweeps back
    m.pair("EyeWing", "Block", (1.25, 0.8, 0.28), (0.6, 19.25, -1.42), skin, (0, -12, -14))
    m.pair("EyeWingTip", "Block", (0.9, 0.5, 0.24), (1.45, 19.55, -1.25), shade, (0, -25, -30))
    m.pair("WingUpper", "Block", (0.3, 1.3, 3.8), (1.3, 20.0, 0.3), skin, (-18, 0, -24))
    m.pair("WingUpperTip", "Block", (0.26, 0.9, 1.8), (1.75, 21.0, 2.0), shade, (-35, 0, -30))
    m.pair("WingLower", "Block", (0.3, 1.1, 3.2), (1.3, 18.6, 0.5), skin, (-4, 0, -12))
    # adaptation wheel (8 handles), floats above the head, rotates around Y
    wc = (0, 22.6, 0)
    ring(m, "WheelRim", 2.5, 8, (0.55, 0.55, 2.2), wc, GOLD, "XZ", "Metal", "Wheel", math.pi / 8)
    m.add("WheelHub", "Cylinder", (0.6, 1.2, 1.2), wc, GOLD, (0, 0, 90), material="Metal", group="Wheel")
    m.add("WheelHubCore", "Ball", (0.7, 0.7, 0.7), (0, 22.95, 0), (255, 226, 140), material="Neon", group="Wheel")
    for i in range(8):
        a = 2 * math.pi * i / 8
        deg = math.degrees(a)
        m.add(f"WheelSpoke{i}", "Cylinder", (3.5, 0.36, 0.36),
              (wc[0] + 1.75 * math.cos(a), wc[1], wc[2] + 1.75 * math.sin(a)),
              GOLD_DARK, (0, -deg, 0), material="Metal", group="Wheel")
        m.add(f"WheelHandle{i}", "Ball", (0.8, 0.8, 0.8),
              (wc[0] + 3.55 * math.cos(a), wc[1], wc[2] + 3.55 * math.sin(a)),
              GOLD, material="Metal", group="Wheel")
    m.add("WheelStem", "Cylinder", (1.6, 0.18, 0.18), (0, 21.3, 0), GOLD_DARK, (0, 0, 90),
          material="Metal", group="Wheel", transparency=0.3)
    m.joint("Wheel", "Head", wc)

    # arms: shoulder pivots so the server can animate them with Motor6D
    for side, sx in (("R", 1), ("L", -1)):
        grp = "RightArm" if side == "R" else "LeftArm"
        m.add(f"Shoulder{side}", "Ball", (2.8, 2.8, 2.8), (4.0 * sx, 16.0, 0), skin, group=grp)
        m.add(f"UpperArm{side}", "Block", (2.0, 4.6, 2.0), (4.3 * sx, 13.4, 0), skin, group=grp)
        m.add(f"Elbow{side}", "Ball", (1.9, 1.9, 1.9), (4.3 * sx, 11.0, 0), shade, group=grp)
        m.add(f"Forearm{side}", "Block", (1.9, 4.2, 1.9), (4.3 * sx, 8.9, -0.1), skin, group=grp)
        m.add(f"Bracer{side}", "Block", (2.1, 1.0, 2.1), (4.3 * sx, 7.4, -0.1), GOLD, material="Metal", group=grp)
        m.add(f"Hand{side}", "Block", (1.6, 1.6, 1.4), (4.3 * sx, 6.2, -0.1), shade, group=grp)
        m.joint(grp, "Torso", (4.0 * sx, 16.0, 0))
    # Sword of Extermination: blade grows out of the right forearm, positive energy edge
    m.add("SwordGuard", "Block", (2.4, 0.5, 2.4), (4.3, 5.2, -0.1), GOLD, material="Metal", group="RightArm")
    m.add("SwordBlade", "Block", (0.35, 7.0, 1.2), (4.3, 1.5, -0.1), (235, 235, 240), material="Metal", group="RightArm")
    m.add("SwordEdge", "Block", (0.2, 7.0, 0.3), (4.3, 1.5, -0.8), BLADE, material="Neon", group="RightArm")
    m.add("SwordTip", "Wedge", (0.35, 1.4, 1.2), (4.3, -2.7, -0.1), (235, 235, 240), (180, 0, 0), material="Metal", group="RightArm")
    # rest pose: sword arm forward and out, left arm slightly out
    m.pose("RightArm", (4.0, 16.0, 0), (38, 0, 16))
    m.pose("LeftArm", (-4.0, 16.0, 0), (8, 0, -10))
    if tamed:
        m.add("TamedSash", "Block", (6.4, 0.6, 3.6), (0, 16.4, 0), (120, 70, 200), (0, 0, 28), material="Neon")
    m.set_root((4, 4, 2), (0, 11.0, 0))
    return m


# ---------------------------------------------------------------- shikigami
def divine_dog(name, fur, mark, eye, scale=1.0, totality=False):
    s = scale
    m = Model(name, "Divine Dog" + (": Totality" if totality else "") + " shikigami.")

    def a(n, shape, size, pos, color, rot=(0, 0, 0), **kw):
        m.add(n, shape, [v * s for v in size], [v * s for v in pos], color, rot, **kw)

    def p(n, shape, size, pos, color, rot=(0, 0, 0), **kw):
        m.pair(n, shape, [v * s for v in size], [v * s for v in pos], color, rot, **kw)

    a("Body", "Block", (1.6, 1.6, 3.2), (0, 2.3, 0.3), fur)
    a("Chest", "Block", (1.9, 1.9, 1.5), (0, 2.5, -1.1), fur)
    a("Ruff", "Block", (2.2, 1.2, 0.8), (0, 2.9, -1.6), mark if totality else fur)
    a("Neck", "Block", (1.1, 1.3, 1.0), (0, 3.2, -1.9), fur, (-30, 0, 0))
    a("Head", "Block", (1.35, 1.25, 1.35), (0, 3.7, -2.4), fur)
    a("Snout", "Block", (0.85, 0.65, 1.1), (0, 3.45, -3.3), fur)
    a("Nose", "Ball", (0.38, 0.38, 0.38), (0, 3.62, -3.85), (20, 20, 22))
    a("Mask", "Block", (1.38, 0.3, 0.2), (0, 3.95, -3.06), mark)
    p("Ear", "Wedge", (0.35, 0.9, 0.55), (0.45, 4.7, -2.3), fur)
    p("Eye", "Block", (0.3, 0.2, 0.1), (0.36, 3.8, -3.12), eye, material="Neon")
    for i, (x, z) in enumerate(((0.58, -1.1), (0.58, 1.4))):
        p(f"Leg{i}", "Block", (0.5, 1.8, 0.5), (x, 0.95, z), fur)
        p(f"Paw{i}", "Block", (0.6, 0.3, 0.75), (x, 0.15, z - 0.1), mark)
    a("Tail", "Block", (0.38, 0.38, 1.5), (0, 2.9, 2.4), fur, (35, 0, 0))
    a("Stripe", "Block", (1.62, 0.2, 2.6), (0, 3.12, 0.4), mark)
    if totality:
        p("Claw", "Wedge", (0.2, 0.3, 0.7), (0.72, 0.15, -1.8), (200, 180, 255), material="Neon")
        a("Spine", "Block", (0.3, 0.5, 3.0), (0, 3.3, 0.4), mark)
        p("Fang", "Wedge", (0.12, 0.35, 0.14), (0.25, 3.02, -3.75), (250, 250, 250), (180, 0, 0))
    return m


def nue():
    m = Model("Nue", "Nue: owl-like shikigami that dives and discharges lightning.")
    body, feather, mask = (46, 38, 46), (30, 26, 34), (232, 228, 214)
    bolt = (150, 205, 255)
    m.add("Body", "Ball", (2.8, 2.8, 2.8), (0, 4.2, 0), body)
    m.add("Belly", "Block", (1.9, 2.0, 0.6), (0, 3.9, -1.2), (90, 80, 86))
    m.add("Head", "Ball", (2.0, 2.0, 2.0), (0, 6.0, -0.5), body)
    m.add("Mask", "Block", (1.6, 1.4, 0.25), (0, 6.0, -1.45), mask)
    m.pair("EyeHole", "Block", (0.42, 0.26, 0.1), (0.38, 6.15, -1.6), (255, 220, 90), material="Neon")
    m.add("Beak", "Wedge", (0.45, 0.6, 0.6), (0, 5.6, -1.8), (200, 170, 90), (180, 0, 0))
    m.pair("Tuft", "Wedge", (0.3, 0.8, 0.5), (0.7, 7.1, -0.5), feather)
    m.pair("Wing0", "Block", (3.6, 0.25, 2.0), (2.9, 4.8, 0.1), feather, (0, 0, 14))
    m.pair("Wing1", "Block", (3.4, 0.22, 1.6), (6.1, 5.7, 0.3), feather, (0, 0, 20))
    m.pair("Wing2", "Block", (2.4, 0.2, 1.1), (8.8, 6.6, 0.5), feather, (0, -12, 26))
    m.pair("WingBolt", "Block", (6.6, 0.1, 0.18), (4.6, 5.2, -0.8), bolt, (0, 0, 17), material="Neon")
    m.add("Tail", "Block", (1.4, 0.2, 2.4), (0, 3.6, 2.0), feather, (-22, 0, 0))
    m.pair("Leg", "Block", (0.3, 1.4, 0.3), (0.55, 2.2, -0.2), (200, 170, 90))
    m.pair("Talon", "Wedge", (0.5, 0.4, 0.8), (0.55, 1.4, -0.5), (60, 60, 60), (180, 0, 0))
    return m


def toad():
    m = Model("Toad", "Toad: extends its tongue to grab and pull targets.")
    skin, belly, spot = (70, 84, 66), (150, 150, 120), (40, 48, 38)
    m.add("Body", "Ball", (4.6, 4.6, 4.6), (0, 2.5, 0.6), skin)
    m.add("Head", "Block", (4.2, 1.7, 3.2), (0, 3.4, -1.7), skin)
    m.add("Lip", "Block", (4.0, 0.25, 3.0), (0, 2.6, -1.8), (120, 60, 70))
    m.add("Belly", "Block", (3.2, 1.6, 0.6), (0, 1.9, -1.6), belly)
    m.pair("Eye", "Ball", (1.3, 1.3, 1.3), (1.3, 4.5, -2.3), (230, 200, 70))
    m.pair("Pupil", "Block", (0.8, 0.25, 0.2), (1.3, 4.55, -2.95), (15, 15, 15))
    m.pair("Spot0", "Ball", (0.9, 0.9, 0.9), (1.5, 3.8, 1.3), spot)
    m.add("Spot1", "Ball", (1.1, 1.1, 1.1), (0, 4.7, 1.0), spot)
    m.pair("FrontLeg", "Block", (0.7, 1.8, 0.7), (1.6, 0.9, -2.0), skin, (0, 0, -12))
    m.pair("BackLeg", "Block", (1.4, 1.2, 2.8), (2.2, 0.6, 1.2), skin)
    m.pair("Foot", "Block", (1.2, 0.3, 1.2), (1.8, 0.15, -2.4), skin)
    m.add("Rune", "Block", (1.6, 0.1, 0.6), (0, 4.28, -1.6), (160, 110, 230), material="Neon")
    return m


def great_serpent():
    m = Model("GreatSerpent", "Great Serpent: bursts out of the ground beneath the target.")
    scale_c, belly, eye = (38, 42, 52), (170, 160, 140), (255, 206, 80)
    for i in range(6):
        y = 1.8 + i * 3.1
        z = 0.4 * math.sin(i * 0.9)
        m.add(f"Segment{i}", "Cylinder", (3.3, 3.8 - i * 0.08, 3.8 - i * 0.08), (0, y, z), scale_c, (0, 0, 90))
        m.add(f"Belly{i}", "Block", (2.2, 2.6, 0.5), (0, y, z - 1.75), belly)
    m.add("Head", "Block", (4.2, 2.6, 6.2), (0, 21.0, -2.0), scale_c, (-12, 0, 0))
    m.add("Snout", "Block", (3.4, 1.8, 2.0), (0, 20.5, -5.6), scale_c, (-12, 0, 0))
    m.add("Jaw", "Block", (3.8, 1.0, 5.6), (0, 18.6, -2.8), belly, (18, 0, 0))
    m.pair("Eye", "Block", (0.3, 0.6, 1.2), (2.12, 21.4, -3.2), eye, (-12, 0, 0), material="Neon")
    m.pair("Brow", "Wedge", (0.6, 0.8, 1.8), (1.7, 22.5, -2.6), scale_c, (-12, 0, 0))
    m.pair("Fang", "Wedge", (0.3, 1.2, 0.4), (1.2, 19.3, -5.8), (245, 245, 240), (180, 0, 0))
    m.pair("Fang2", "Wedge", (0.25, 0.9, 0.35), (0.6, 19.4, -6.0), (245, 245, 240), (180, 0, 0))
    m.add("Crest", "Block", (0.3, 1.0, 4.4), (0, 22.6, -0.6), (140, 90, 220), (-12, 0, 0), material="Neon")
    return m


def max_elephant():
    m = Model("MaxElephant", "Max Elephant: huge shikigami that crashes down and floods the area with water.")
    hide, dark, tusk, water = (104, 116, 136), (70, 80, 98), (238, 234, 220), (90, 180, 255)
    m.add("Body", "Block", (9.0, 8.0, 13.0), (0, 11.0, 0.5), hide)
    m.add("Back", "Block", (7.6, 2.0, 11.0), (0, 15.6, 0.8), hide)
    m.add("Head", "Block", (7.0, 7.0, 5.0), (0, 13.2, -7.8), hide)
    m.add("Brow", "Block", (7.2, 1.2, 1.2), (0, 16.2, -9.6), dark)
    m.pair("Ear", "Block", (0.6, 6.4, 5.6), (4.4, 13.4, -6.2), dark, (0, 22, 8))
    m.pair("Eye", "Block", (0.8, 0.5, 0.2), (2.4, 14.3, -10.35), (240, 230, 160), material="Neon")
    for i in range(5):
        m.add(f"Trunk{i}", "Cylinder", (2.2, 2.6 - i * 0.3, 2.6 - i * 0.3),
              (0, 10.8 - i * 1.9, -10.6 - i * 0.55), hide, (0, 0, 90 - i * 6))
    m.add("TrunkTip", "Ball", (1.4, 1.4, 1.4), (0, 1.3, -13.4), dark)
    m.pair("Tusk", "Cylinder", (5.0, 0.9, 0.9), (2.0, 9.6, -11.8), tusk, (0, 70, -30))
    for i, (x, z) in enumerate(((3.1, -4.2), (3.1, 5.0))):
        m.pair(f"Leg{i}", "Cylinder", (7.2, 3.6, 3.6), (x, 3.6, z), hide, (0, 0, 90))
        m.pair(f"Toe{i}", "Block", (3.2, 0.6, 1.0), (x, 0.3, z - 1.6), tusk)
    m.add("Tail", "Block", (0.5, 4.0, 0.5), (0, 11.0, 7.3), dark, (20, 0, 0))
    m.add("WaterMark", "Block", (5.0, 0.2, 9.0), (0, 16.65, 0.8), water, material="Neon")
    m.pair("SideMark", "Block", (0.2, 3.0, 8.0), (4.52, 11.0, 0.5), water, material="Neon")
    return m


def rabbit():
    m = Model("Rabbit", "Rabbit Escape: a swarm of rabbits that scatters to cover an escape.")
    fur = (246, 246, 246)
    m.add("Body", "Block", (0.8, 0.75, 1.1), (0, 0.55, 0.1), fur)
    m.add("Head", "Ball", (0.65, 0.65, 0.65), (0, 0.95, -0.45), fur)
    m.pair("Ear", "Block", (0.14, 0.75, 0.26), (0.16, 1.55, -0.35), fur, (10, 0, -8))
    m.pair("Eye", "Block", (0.1, 0.12, 0.05), (0.18, 1.02, -0.77), (230, 40, 60), material="Neon")
    m.add("Tail", "Ball", (0.35, 0.35, 0.35), (0, 0.65, 0.7), (225, 225, 225))
    m.pair("Foot", "Block", (0.22, 0.18, 0.6), (0.25, 0.09, 0.2), fur)
    return m


def round_deer():
    m = Model("RoundDeer", "Round Deer: shikigami with reverse cursed technique output, heals its user.")
    fur, halo = (224, 218, 204), (255, 226, 150)
    m.add("Body", "Block", (1.9, 1.9, 4.2), (0, 4.4, 0.2), fur)
    m.add("Neck", "Block", (1.0, 2.4, 1.0), (0, 5.8, -1.9), fur, (-25, 0, 0))
    m.add("Head", "Block", (1.2, 1.1, 1.6), (0, 7.0, -2.6), fur)
    m.add("Muzzle", "Block", (0.8, 0.7, 0.9), (0, 6.7, -3.6), (200, 192, 178))
    m.pair("Eye", "Block", (0.1, 0.2, 0.3), (0.61, 7.2, -2.9), (60, 40, 30))
    for i, (x, z) in enumerate(((0.65, -1.5), (0.65, 1.8))):
        m.pair(f"Leg{i}", "Block", (0.35, 3.6, 0.35), (x, 1.8, z), fur)
    m.pair("Antler0", "Block", (0.2, 1.8, 0.2), (0.45, 8.3, -2.4), (240, 230, 200), (0, 0, -22))
    m.pair("Antler1", "Block", (0.16, 1.1, 0.16), (0.95, 9.0, -2.2), (240, 230, 200), (0, 0, -60))
    m.pair("Antler2", "Block", (0.16, 1.0, 0.16), (0.55, 9.3, -2.6), (240, 230, 200), (0, 0, 10))
    ring(m, "Halo", 3.1, 16, (1.25, 0.3, 0.3), (0, 5.2, 1.6), halo, "XY", "Neon")
    m.add("HaloCore", "Ball", (0.9, 0.9, 0.9), (0, 5.2, 1.6), halo, material="Neon")
    m.add("Spots", "Block", (1.92, 0.15, 3.0), (0, 5.36, 0.3), (190, 170, 140))
    return m


def piercing_ox():
    m = Model("PiercingOx", "Piercing Ox: charges in a straight line; the longer the run, the harder it hits.")
    hide, horn, eye = (48, 42, 40), (232, 222, 196), (255, 70, 60)
    m.add("Body", "Block", (4.2, 3.8, 6.6), (0, 4.4, 0.4), hide)
    m.add("Hump", "Block", (3.6, 1.6, 3.0), (0, 6.8, -1.2), hide, (8, 0, 0))
    m.add("Head", "Block", (2.6, 2.4, 2.6), (0, 4.0, -3.8), hide, (18, 0, 0))
    m.add("Snout", "Block", (1.8, 1.2, 1.0), (0, 3.2, -5.0), (80, 70, 66), (18, 0, 0))
    m.add("NoseRing", "Cylinder", (0.2, 0.9, 0.9), (0, 2.7, -5.5), GOLD, (0, 90, 0), material="Metal")
    m.pair("HornBase", "Cylinder", (1.8, 0.8, 0.8), (1.8, 4.9, -4.4), horn, (0, 30, 10))
    m.pair("Horn", "Cylinder", (3.0, 0.55, 0.55), (2.4, 5.1, -6.4), horn, (0, 80, 8))
    m.pair("HornTip", "Wedge", (0.4, 0.5, 1.2), (2.55, 5.25, -8.4), horn, (0, 0, 0))
    m.pair("Eye", "Block", (0.2, 0.3, 0.5), (1.32, 4.5, -4.3), eye, material="Neon")
    for i, (x, z) in enumerate(((1.4, -2.0), (1.4, 2.6))):
        m.pair(f"Leg{i}", "Block", (1.0, 2.8, 1.0), (x, 1.4, z), hide)
        m.pair(f"Hoof{i}", "Block", (1.1, 0.4, 1.2), (x, 0.2, z - 0.1), (30, 28, 26))
    m.add("Tail", "Block", (0.3, 2.2, 0.3), (0, 5.0, 3.8), hide, (25, 0, 0))
    m.add("Rune", "Block", (0.2, 0.2, 5.0), (0, 6.35, 0.8), (255, 110, 70), material="Neon")
    return m


def tiger_funeral():
    m = Model("TigerFuneral", "Tiger Funeral: a pale funeral tiger that pounces and rends.")
    fur, stripe, eye = (214, 210, 206), (24, 22, 26), (190, 120, 255)
    m.add("Body", "Block", (2.5, 2.3, 6.2), (0, 3.3, 0.3), fur)
    m.add("Shoulders", "Block", (2.8, 2.6, 1.8), (0, 3.5, -2.3), fur)
    m.add("Head", "Block", (2.3, 2.1, 2.2), (0, 4.0, -3.8), fur)
    m.add("Muzzle", "Block", (1.5, 1.0, 1.1), (0, 3.4, -5.1), (236, 232, 226))
    m.add("Nose", "Block", (0.5, 0.35, 0.2), (0, 3.85, -5.65), (60, 40, 50))
    m.pair("Ear", "Wedge", (0.5, 0.7, 0.5), (0.8, 5.35, -3.6), fur)
    m.pair("Eye", "Block", (0.4, 0.2, 0.1), (0.55, 4.4, -4.91), eye, material="Neon")
    for i in range(5):
        m.add(f"Stripe{i}", "Block", (2.55, 0.35, 0.3), (0, 3.9, -1.8 + i * 1.1), stripe, (0, 0, 0))
        m.pair(f"SideStripe{i}", "Block", (0.1, 1.4, 0.3), (1.27, 3.3, -1.5 + i * 1.1), stripe, (0, 0, 15))
    for i, (x, z) in enumerate(((0.9, -2.4), (0.9, 2.3))):
        m.pair(f"Leg{i}", "Block", (0.8, 2.4, 0.8), (x, 1.2, z), fur)
        m.pair(f"Claw{i}", "Wedge", (0.8, 0.3, 0.5), (x, 0.15, z - 0.6), (40, 40, 44))
    m.add("Tail", "Block", (0.4, 0.4, 3.6), (0, 4.0, 4.6), fur, (-25, 0, 0))
    m.add("TailTip", "Block", (0.42, 0.42, 0.8), (0, 4.9, 6.2), stripe, (-25, 0, 0))
    return m


def agito():
    m = Model("Agito", "Agito: chimera of Nue, Great Serpent, Tiger Funeral and Round Deer (fused by Sukuna); "
                       "fights and heals with reverse cursed technique.")
    hide, bone, feather, halo = (40, 36, 46), (226, 220, 206), (24, 22, 30), (255, 226, 150)
    m.pair("Leg", "Block", (1.4, 5.0, 1.6), (1.4, 2.5, 0.3), hide)
    m.pair("Claw", "Wedge", (1.6, 0.6, 1.4), (1.4, 0.3, -0.8), bone)
    m.add("Tail", "Cylinder", (6.0, 1.4, 1.4), (0, 3.0, 3.8), hide, (0, 90, 30))
    m.add("Hips", "Block", (4.0, 2.0, 2.4), (0, 5.8, 0.2), hide)
    m.add("Torso", "Block", (4.8, 4.6, 2.8), (0, 8.8, 0), hide)
    m.add("Ribs", "Block", (3.4, 3.0, 0.3), (0, 8.8, -1.5), bone)
    m.pair("Arm", "Block", (1.2, 4.6, 1.2), (3.0, 7.9, -0.4), hide, (-15, 0, -10))
    m.pair("TigerClaw", "Wedge", (1.1, 1.4, 1.2), (3.3, 5.3, -1.2), (190, 120, 255), (180, 0, 0), material="Neon")
    m.add("Head", "Block", (2.2, 2.2, 2.6), (0, 12.2, -0.6), bone)
    m.add("Maw", "Block", (1.8, 0.9, 2.2), (0, 11.2, -1.3), hide)
    m.pair("Eye", "Block", (0.5, 0.25, 0.1), (0.55, 12.5, -1.95), (255, 206, 80), material="Neon")
    m.pair("Antler", "Block", (0.25, 2.4, 0.25), (1.0, 14.0, -0.4), bone, (0, 0, -30))
    m.pair("AntlerTine", "Block", (0.2, 1.2, 0.2), (1.9, 14.6, -0.4), bone, (0, 0, -70))
    m.pair("Wing0", "Block", (4.6, 0.3, 2.4), (4.6, 11.2, 1.4), feather, (0, -10, 30))
    m.pair("Wing1", "Wedge", (0.3, 2.0, 3.2), (7.8, 13.3, 1.8), feather, (0, 90, 30))
    ring(m, "Halo", 2.2, 12, (1.2, 0.22, 0.22), (0, 12.2, 1.6), halo, "XY", "Neon")
    m.add("Serpent", "Cylinder", (3.0, 1.0, 1.0), (0, 9.4, 1.9), (60, 64, 76), (0, 90, -40))
    return m


def cursed_spirit():
    m = Model("CursedSpirit", "Training cursed spirit (target dummy).")
    flesh, dark, eye = (96, 76, 110), (54, 40, 66), (255, 80, 80)
    m.add("Body", "Ball", (5.0, 5.0, 5.0), (0, 4.2, 0), flesh)
    m.add("Belly", "Ball", (3.6, 3.6, 3.6), (0, 3.6, -1.1), dark)
    m.add("Mouth", "Block", (2.6, 0.5, 0.4), (0, 3.4, -2.8), (20, 10, 20))
    for i, (x, y) in enumerate(((-1.2, 5.6), (0.2, 6.2), (1.3, 5.2), (-0.4, 4.9), (0.9, 6.6))):
        m.add(f"Eye{i}", "Ball", (0.7, 0.7, 0.7), (x, y, -2.1), (250, 245, 230))
        m.add(f"Pupil{i}", "Ball", (0.32, 0.32, 0.32), (x, y, -2.42), eye, material="Neon")
    m.pair("Arm", "Block", (0.9, 4.0, 0.9), (2.8, 3.0, -0.4), flesh, (10, 0, -20))
    m.pair("Leg", "Block", (1.1, 2.0, 1.1), (1.2, 1.0, 0), dark)
    m.set_root((3, 3, 2), (0, 3.5, 0))
    return m


def build_all():
    models = [
        mahoraga(),
        mahoraga("MahoragaTamed", tamed=True),
        divine_dog("DivineDogWhite", (242, 242, 240), (60, 60, 66), (255, 214, 90)),
        divine_dog("DivineDogBlack", (30, 30, 34), (200, 200, 205), (255, 214, 90)),
        divine_dog("DivineDogTotality", (34, 32, 40), (232, 230, 236), (190, 120, 255), scale=2.6, totality=True),
        nue(), toad(), great_serpent(), max_elephant(), rabbit(), round_deer(),
        piercing_ox(), tiger_funeral(), agito(), cursed_spirit(),
    ]
    return {m.name: m.to_dict() for m in models}


if __name__ == "__main__":
    data = build_all()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(data, f, indent=1)
    print(f"wrote {len(data)} models, {sum(len(m['parts']) for m in data.values())} parts -> {os.path.normpath(OUT)}")

"""DevDay 2026 (parody) keynote stage for Blender 4.2+ / 5.x.

Builds the same hall as ../index.html: mirror stage, LED wall slides, side LED
columns, moving-head spotlights in volumetric haze, raked audience, the floating
spark presenter, confetti, cameras cut to the keynote script, captions, and a
synthesized soundtrack (crowd, applause, laughs, risers, drops, optional
espeak-ng voice). The keynote timeline is parsed from index.html so both
versions stay in sync.

  blender -b -P devday_stage.py                       # build + save devday2026.blend
  blender -b -P devday_stage.py -- --render           # quick EEVEE 720p preview mp4
  blender -b -P devday_stage.py -- --render --final   # Cycles 1080p, full length
  blender -b -P devday_stage.py -- --render --frames 600 900
  blender    -P devday_stage.py                       # open the scene interactively
"""

import json
import math
import os
import random
import re
import shutil
import subprocess
import sys

import bpy
from mathutils import Vector

FPS = 30
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
ORANGE = (0.88, 0.40, 0.25, 1)
STAGE_TOP = 1.2
WALL_Y = STAGE_TOP + 0.6 + 4.5
rng = random.Random(20261006)


# ---------------------------------------------------------------- args
def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"render": "--render" in argv, "final": "--final" in argv, "voice": "--no-voice" not in argv, "frames": None}
    if "--frames" in argv:
        i = argv.index("--frames")
        a["frames"] = (int(argv[i + 1]), int(argv[i + 2]))
    return a


# ---------------------------------------------------------------- script
def load_script():
    html = open(os.path.join(HERE, "..", "index.html"), encoding="utf-8").read()
    m = re.search(r'<script type="application/json" id="keynote-script">(.*?)</script>', html, re.S)
    if not m:
        raise SystemExit("keynote-script block not found in ../index.html")
    return json.loads(m.group(1))


SCRIPT = load_script()
DURATION = 160.0
T_MAT = next(c["t"] for c in SCRIPT if c.get("event") == "materialize")
T_DARK = next(c["t"] for c in SCRIPT if c.get("event") == "dark")
T_FIN = next(c["t"] for c in SCRIPT if c.get("event") == "finale")


def W(x, y, z):
    """three.js coords (y up, +z toward audience) -> Blender (z up, -y toward audience)."""
    return Vector((x, -z, y))


def frame(t):
    return int(round(t * FPS)) + 1


def smooth(a, b, x):
    t = min(1, max(0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- helpers
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def link(obj, coll=None):
    (coll or bpy.context.scene.collection).objects.link(obj)
    return obj


def mat_principled(name, color, rough=0.5, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        key = "Emission Color" if "Emission Color" in b.inputs else "Emission"
        b.inputs[key].default_value = emit
        b.inputs["Emission Strength"].default_value = strength
    return m


def mat_emit(name, color, strength):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = color
    e.inputs["Strength"].default_value = strength
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    return m


def box(name, size, loc, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    return o


def plane(name, w, h, loc, rot, mat):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = (w, h, 1)
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    return o


def text(name, body, loc, size, mat, align="CENTER", font=None, parent=None):
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    cu.align_y = "CENTER"
    if font:
        cu.font = font
    o = link(bpy.data.objects.new(name, cu))
    o.location = loc
    o.data.materials.append(mat)
    if parent:
        o.parent = parent
    return o


def key_visible(obj, t0, t1):
    """Show obj only between script times t0 and t1."""
    for f, hide in ((1, True), (frame(t0), False), (frame(t1), True)):
        if f < 1:
            continue
        obj.hide_render = hide
        obj.hide_viewport = hide
        obj.keyframe_insert("hide_render", frame=f)
        obj.keyframe_insert("hide_viewport", frame=f)


def constant_interp(obj):
    ad = obj.animation_data
    if not ad or not ad.action:
        return
    fcurves = getattr(ad.action, "fcurves", None)
    if fcurves is None:  # Blender 5 layered actions
        fcurves = [fc for layer in ad.action.layers for strip in layer.strips for cb in strip.channelbags for fc in cb.fcurves]
    for fc in fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "CONSTANT"


def spans(key):
    """[(value, t0, t1)] for each script cue that sets `key`."""
    cues = [c for c in SCRIPT if key in c]
    return [(c[key], c["t"], cues[i + 1]["t"] if i + 1 < len(cues) else DURATION) for i, c in enumerate(cues)]


# ---------------------------------------------------------------- world + render
def setup_scene(args):
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.frame_start = 1
    sc.frame_end = frame(DURATION)
    for eng in (("CYCLES",) if args["final"] else ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE")):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    if sc.render.engine == "CYCLES":
        sc.cycles.samples = 128
        sc.cycles.use_denoising = True
        sc.cycles.volume_step_rate = 4
    else:
        ee = sc.eevee
        for attr, val in (("use_bloom", True), ("use_volumetric_shadows", True), ("volumetric_tile_size", "4"), ("taa_render_samples", 32), ("use_raytracing", True)):
            if hasattr(ee, attr):
                setattr(ee, attr, val)
    sc.render.resolution_x, sc.render.resolution_y = (1920, 1080) if args["final"] else (1280, 720)
    sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    sc.view_settings.look = "None"

    world = bpy.data.worlds.new("Hall haze")
    sc.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes["Background"].inputs["Color"].default_value = (0.004, 0.004, 0.008, 1)
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = 0.018
    vol.inputs["Anisotropy"].default_value = 0.35
    nt.links.new(vol.outputs[0], nt.nodes["World Output"].inputs["Volume"])

    # glare for the "RTX ON" bloom look in Cycles
    sc.use_nodes = True
    ct = sc.node_tree
    rl, comp = ct.nodes.get("Render Layers"), ct.nodes.get("Composite")
    if rl and comp:
        g = ct.nodes.new("CompositorNodeGlare")
        if hasattr(g, "glare_type"):
            g.glare_type = "FOG_GLOW"
            g.threshold = 0.9
            g.size = 8
        lens = ct.nodes.new("CompositorNodeLensdist")
        lens.inputs["Dispersion"].default_value = 0.012
        ct.links.new(rl.outputs["Image"], g.inputs["Image"])
        ct.links.new(g.outputs["Image"], lens.inputs["Image"])
        ct.links.new(lens.outputs["Image"], comp.inputs["Image"])


# ---------------------------------------------------------------- hall
def build_hall():
    dark = mat_principled("Hall", (0.012, 0.011, 0.016, 1), 1.0)
    bpy.ops.mesh.primitive_cube_add(size=1, location=W(0, 12.9, 18))
    hall = bpy.context.object
    hall.name = "Hall"
    hall.scale = (64, 80, 26)
    hall.data.materials.append(dark)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.flip_normals()
    bpy.ops.object.mode_set(mode="OBJECT")

    box("Stage", (24, 9, STAGE_TOP), W(0, STAGE_TOP / 2, -0.5), mat_principled("Stage body", (0.02, 0.02, 0.025, 1), 0.6, 0.2))
    plane("Stage mirror", 24, 9, W(0, STAGE_TOP + 0.002, -0.5), (0, 0, 0), mat_principled("Mirror floor", (0.04, 0.04, 0.05, 1), 0.06, 0.7))
    lip = box("Stage lip LED", (24, 0.04, 0.06), W(0, STAGE_TOP - 0.05, 4.02), mat_emit("Lip", ORANGE, 25))
    lip.data.materials[0].node_tree.nodes["Emission"].inputs["Strength"].keyframe_insert("default_value", frame=1)

    plane("Back wall", 40, 20, W(0, 10, -5.2), (math.pi / 2, 0, 0), mat_principled("Back", (0.01, 0.01, 0.015, 1), 0.95))
    box("LED bezel", (16.5, 0.3, 9.5), W(0, WALL_Y, -4.8), mat_principled("Bezel", (0.005, 0.005, 0.007, 1), 0.5, 0.4))
    wall = plane("LED wall", 16, 9, W(0, WALL_Y, -4.6), (math.pi / 2, 0, 0), mat_emit("LED base", (0.02, 0.015, 0.06, 1), 0.35))

    col_mat = mat_emit("LED column", (0.5, 0.25, 0.9, 1), 6)
    nt = col_mat.node_tree
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 2.5
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.16, 0.1, 0.38, 1)
    ramp.color_ramp.elements[1].color = ORANGE
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], nt.nodes["Emission"].inputs["Color"])
    phase = wave.inputs["Phase Offset"]
    phase.default_value = 0
    phase.keyframe_insert("default_value", frame=1)
    phase.default_value = DURATION * 2.2
    phase.keyframe_insert("default_value", frame=frame(DURATION))
    for s in (-1, 1):
        c = plane(f"LED column {s}", 3.2, 11, W(s * 10.6, STAGE_TOP + 5.5, -3.2), (math.pi / 2, 0, s * 0.45), col_mat)

    metal = mat_principled("Truss", (0.1, 0.1, 0.12, 1), 0.35, 0.9)
    for z in (1.8, -2.4):
        for dy in (0, 0.5):
            box("Truss rail", (26, 0.06, 0.06), W(0, 12 + dy, z), metal)

    podium = box("Podium", (1.1, 0.7, 1.15), W(3.6, STAGE_TOP + 0.575, 1.6), mat_principled("Podium", (0.03, 0.03, 0.04, 1), 0.25, 0.6))
    box("Podium strip", (1.12, 0.02, 0.05), W(3.6, STAGE_TOP + 0.9, 1.96), mat_emit("Podium LED", ORANGE, 15))
    return wall, lip


def _sphere(u=10, v=8):
    verts = [(0, 0, 1)]
    for j in range(1, v):
        th = math.pi * j / v
        for i in range(u):
            ph = math.tau * i / u
            verts.append((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
    verts.append((0, 0, -1))
    faces = [(0, 1 + i, 1 + (i + 1) % u) for i in range(u)]
    for j in range(v - 2):
        r0, r1 = 1 + j * u, 1 + (j + 1) * u
        faces += [(r0 + i, r1 + i, r1 + (i + 1) % u, r0 + (i + 1) % u) for i in range(u)]
    last = len(verts) - 1
    faces += [(last, 1 + (v - 2) * u + (i + 1) % u, 1 + (v - 2) * u + i) for i in range(u)]
    return verts, faces


def build_audience():
    sv, sf = _sphere()
    verts, faces = [], []

    def blob(center, scale):
        base = len(verts)
        verts.extend((center.x + x * scale[0], center.y + y * scale[1], center.z + z * scale[2]) for x, y, z in sv)
        faces.extend(tuple(base + k for k in f) for f in sf)

    riser_mat = mat_principled("Riser carpet", (0.018, 0.017, 0.024, 1), 1.0)
    for r in range(16):
        z, y = 7.5 + r * 1.05, r * 0.32
        if y > 0:
            box(f"Riser {r}", (34, 1.05, y + 0.02), W(0, (y + 0.02) / 2, z), riser_mat)
        x = -15.0
        while x <= 15:
            ax = abs(x)
            if not (ax < 0.9 or 7.2 < ax < 8.1 or rng.random() < 0.08):
                s = 0.9 + rng.random() * 0.2
                px, pz = x + (rng.random() - 0.5) * 0.12, z + (rng.random() - 0.5) * 0.1
                blob(W(px, y + 0.62 * s, pz), (0.23 * s, 0.18 * s, 0.42 * s))
                blob(W(px, y + 1.08 * s, pz), (0.12 * s,) * 3)
            x += 0.62
    me = bpy.data.meshes.new("Audience")
    me.from_pydata(verts, [], faces)
    me.update()
    o = link(bpy.data.objects.new("Audience", me))
    o.data.materials.append(mat_principled("People", (0.03, 0.028, 0.035, 1), 0.75))
    for poly in me.polygons:
        poly.use_smooth = True
    plane("Floor", 40, 40, W(0, 0, 14), (0, 0, 0), riser_mat)


def build_presenter():
    root = link(bpy.data.objects.new("Presenter", None))
    root.location = W(0, 3.3, 1.3)
    spark = mat_principled("Spark", ORANGE, 0.32, 0.05, emit=ORANGE, strength=0.6)
    lens = [0.62, 0.5, 0.58, 0.46, 0.64, 0.52, 0.57, 0.48, 0.6, 0.5, 0.55]
    for i, L in enumerate(lens):
        a = i / len(lens) * math.tau + 0.12 * math.sin(i * 2.3)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1)
        ray = bpy.context.object
        ray.name = f"Ray {i}"
        ray.scale = (0.085, 0.085, L / 2 + 0.085)
        r = 0.16 + L / 2
        ray.location = (math.sin(a) * r, 0, math.cos(a) * r)
        ray.rotation_euler = (0, a, 0)
        ray.data.materials.append(spark)
        bpy.ops.object.shade_smooth()
        ray.parent = root
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, location=(0, 0, 0))
    core = bpy.context.object
    core.data.materials.append(spark)
    bpy.ops.object.shade_smooth()
    core.parent = root
    eye = mat_emit("Eyes", (1, 0.97, 0.93, 1), 4)
    for x in (-0.075, 0.075):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.03, location=(x, -0.2, 0.03))
        e = bpy.context.object
        e.scale = (1, 1, 1.8)
        e.data.materials.append(eye)
        e.parent = root

    # materialize (scale), float, spin, finale spin-up
    for t, s in ((0, 0.001), (T_MAT, 0.001), (T_MAT + 0.5, 1.2), (T_MAT + 0.9, 1.0)):
        root.scale = (s, s, s)
        root.keyframe_insert("scale", frame=max(1, frame(t)))
    step = 0.5
    t = 0.0
    while t <= DURATION:
        spin = t * 0.18 + max(0, t - T_FIN) * 1.2
        root.rotation_euler = (0, spin, math.sin(t * 0.5) * 0.25)
        root.location = W(0, 3.3 + math.sin(t * 1.2) * 0.07, 1.3)
        root.keyframe_insert("rotation_euler", frame=frame(t))
        root.keyframe_insert("location", frame=frame(t))
        t += step

    bpy.ops.mesh.primitive_torus_add(major_radius=0.9, minor_radius=0.018, location=W(0, STAGE_TOP + 0.03, 1.3))
    bpy.context.object.data.materials.append(mat_emit("Ring", ORANGE, 20))
    key_visible(bpy.context.object, T_MAT, DURATION + 1)
    return root


def build_lights():
    lights = []

    def spot(name, loc, target, energy, size_deg, color, blend=0.5):
        ld = bpy.data.lights.new(name, "SPOT")
        ld.energy = energy
        ld.spot_size = math.radians(size_deg)
        ld.spot_blend = blend
        ld.color = color
        o = link(bpy.data.objects.new(name, ld))
        o.location = loc
        d = (target - loc).normalized()
        o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        return o

    key = spot("Key", W(0, 11, 11), W(0, 3, 1.2), 9000, 26, (1, 0.94, 0.86), 0.65)
    rim = spot("Rim", W(0, 10, -3.6), W(0, 3.2, 1.3), 5000, 34, (0.53, 0.67, 1))
    for t, e in ((0, 0), (T_MAT - 1, 0), (T_MAT + 0.5, 9000), (T_DARK, 9000), (T_DARK + 1.2, 900), (T_FIN, 900), (T_FIN + 0.3, 9000)):
        key.data.energy = e
        key.data.keyframe_insert("energy", frame=max(1, frame(t)))

    palette = [(1, 1, 1), ORANGE[:3], (0.54, 0.63, 1), (1, 0.37, 0.64), (0.5, 0.88, 0.42), (1, 0.84, 0.42)]
    for i in range(8):
        x = -10.5 + i * 3
        base = W(x, 11.7, 1.8)
        o = spot(f"Moving head {i}", base, W(x, 0, 1.8), 6000, 15, palette[1])
        ld = o.data
        t = 0.0
        while t <= DURATION:
            side = -1 if x < 0 else 1
            if t < 8:
                pan, tilt, col, e = math.sin(t * 0.3 + i) * 0.3, -0.35, palette[2], 2500
            elif t < 23:
                pan, tilt, col, e = math.sin(t * 1.6 + i * 0.8) * 0.55, math.sin(t * 1.1 + i) * 0.45, palette[i % 2], 9000
            else:
                pan, tilt, col, e = -side * 0.22 + math.sin(t * 0.25 + i) * 0.08, 0.35, palette[2] if i % 3 == 0 else palette[1], 4000
            if T_DARK <= t < T_FIN:
                e *= 1 - smooth(T_DARK, T_DARK + 1.2, t)
            if t >= T_FIN:
                pan, tilt = math.sin(t * 2.2 + i * 1.3) * 0.7, math.cos(t * 1.7 + i) * 0.55
                col = palette[(i + int(t * 2)) % len(palette)]
                e = 12000 if math.sin(t * 18 + i) > 0.2 else 2500
            # three.js: group.rotation.z = pan, rotation.x = tilt, beam points -Y
            aim = Vector((math.sin(pan), math.cos(pan) * math.sin(tilt), -math.cos(pan) * math.cos(tilt)))
            o.rotation_euler = aim.to_track_quat("-Z", "Y").to_euler()
            ld.color = col
            ld.energy = e
            f = frame(t)
            o.keyframe_insert("rotation_euler", frame=f)
            ld.keyframe_insert("color", frame=f)
            ld.keyframe_insert("energy", frame=f)
            t += 0.25 if t >= T_FIN else 0.5
        lights.append(o)

    for i in range(4):
        ld = bpy.data.lights.new(f"House {i}", "POINT")
        ld.energy = 3000
        ld.color = (1, 0.85, 0.69)
        o = link(bpy.data.objects.new(ld.name, ld))
        o.location = W(-12 + i * 8, 14, 16)
        for t, e in ((0, 3000), (8, 3000), (10.5, 60)):
            ld.energy = e
            ld.keyframe_insert("energy", frame=frame(t))
    return lights


# ---------------------------------------------------------------- slides
SLIDE_TEXT = {
    "soon": [("Stream starting soon", 0.9, (0.93, 0.91, 0.88, 1), -0.3), ("grab a coffee. it is also generated.", 0.35, (0.6, 0.58, 0.62, 1), -1.6)],
    "title": [("DevDay", 2.2, (0.93, 0.91, 0.88, 1), 0.2), ("2026", 0.9, ORANGE, -1.5), ("live*   *ish", 0.4, (0.6, 0.58, 0.62, 1), -2.5)],
    "agents": [("Agents, managing agents", 0.75, (0.93, 0.91, 0.88, 1), 3.0), ("agent", 0.45, ORANGE, 1.4), ("agent-1   agent-2   agent-3", 0.35, (0.93, 0.91, 0.88, 1), 0.3), ("JIRA-4096  agent-17 says agent-4 is 'blocking on vibes'", 0.3, (1, 0.84, 0.42, 1), -2.8)],
    "context": [("Context window:", 0.9, (0.93, 0.91, 0.88, 1), 2.4), ("yes.", 2.4, ORANGE, 0.0), ("remembers your 2019 README.md", 0.4, (1, 0.84, 0.42, 1), -2.6)],
    "bench": [("SWE-bench Verified", 0.75, (0.93, 0.91, 0.88, 1), 3.0), ("72%     91%     104%", 1.0, ORANGE, 0.0), ("*y-axis not to scale. there is no x-axis.", 0.3, (0.6, 0.58, 0.62, 1), -3.3)],
    "undercover": [("Undercover mode", 0.75, (0.93, 0.91, 0.88, 1), 3.0), ("> which model are you?", 0.45, (0.93, 0.91, 0.88, 1), 1.0), ("session_context.model: ███████", 0.45, ORANGE, 0.0), ("I am a model. That is all I can say.", 0.45, (0.93, 0.91, 0.88, 1), -1.0)],
    "permission": [("Claude wants to: clap", 0.6, ORANGE, 2.4), ("Do you want to proceed?", 0.5, (0.93, 0.91, 0.88, 1), 1.0), ("> 1. Yes", 0.45, ORANGE, 0.0), ("2. Yes, and don't ask again for clap", 0.4, (0.93, 0.91, 0.88, 1), -0.8)],
    "demo": [("Live demo", 0.75, (0.93, 0.91, 0.88, 1), 3.0), ('$ claude "fix the flaky test. prod only."', 0.4, (0.93, 0.91, 0.88, 1), 1.0), ("DROP DATABASE staging;", 0.55, (1, 0.37, 0.34, 1), -0.3), ("Done! Test is no longer flaky.", 0.45, (0.5, 0.88, 0.42, 1), -1.5)],
    "right": [("YOU'RE ABSOLUTELY", 1.4, (1, 1, 1, 1), 1.3), ("RIGHT!", 2.2, (1, 0.84, 0.42, 1), -1.0)],
    "price": [("Pricing", 0.75, (0.93, 0.91, 0.88, 1), 3.0), ("$ same", 2.0, (0.93, 0.91, 0.88, 1), 0.4), ("tokens now 130% more confident", 0.45, (1, 0.84, 0.42, 1), -1.8)],
    "black": [],
    "opus6": [("OPUS 6", 2.8, (0.95, 0.94, 0.92, 1), 0.5), ("ships when it ships™", 0.5, ORANGE, -1.5), ("it has read this keynote. it has notes.", 0.38, (0.7, 0.68, 0.72, 1), -2.4)],
    "end": [("Thank you.", 1.6, (0.93, 0.91, 0.88, 1), 0.5), ("Go build something.", 0.55, (0.7, 0.68, 0.72, 1), -1.0), ("#DevDay2026", 0.45, ORANGE, -2.2)],
}


def build_slides():
    mats = {}
    for key, lines in SLIDE_TEXT.items():
        for body, size, color, dy in lines:
            ck = tuple(round(c, 3) for c in color)
            if ck not in mats:
                mats[ck] = mat_emit(f"Slide text {len(mats)}", color, 6)
    for key, t0, t1 in spans("slide"):
        for i, (body, size, color, dy) in enumerate(SLIDE_TEXT.get(key, [])):
            o = text(f"slide {key} {i}", body, W(0, WALL_Y + dy, -4.55), size, mats[tuple(round(c, 3) for c in color)])
            o.rotation_euler = (math.pi / 2, 0, 0)
            key_visible(o, t0, t1)


# ---------------------------------------------------------------- camera
SHOTS = {
    "lowwide": lambda u: ((6 - u * 0.12, 2.2, 21 - u * 0.1), (0, 4.2, 0), 48),
    "wide": lambda u: ((0, 7.5 - u * 0.06, 30 - u * 0.35), (0, 4.8, -1), 42),
    "crane": lambda u: ((math.sin(-0.7 + u * 0.09) * 20, 10.5 + math.sin(u * 0.4) * 1.5, 6 + math.cos(-0.7 + u * 0.09) * 14), (0, 4.2, 0), 40),
    "mid": lambda u: ((3.4 - u * 0.08, 3.4, 12.5), (1.2, 3.1, 1.2), 30),
    "close": lambda u: ((1.1 + math.sin(u * 0.25) * 0.4, 3.6, 7.2), (0.2, 3.35, 1.3), 30),
    "screen": lambda u: ((0, WALL_Y - 0.4, 15.5 - u * 0.1), (0, WALL_Y, -4.6), 34),
    "audience": lambda u: ((-5 + u * 0.15, 2.6, 3.4), (2, 2.3, 14), 46),
    "side": lambda u: ((-8.5 + u * 0.2, 3.1, 4.8), (0, 3.2, 1.3), 32),
}


def build_camera():
    cd = bpy.data.cameras.new("Stream cam")
    cd.sensor_fit = "VERTICAL"
    cd.sensor_height = 24
    cam = link(bpy.data.objects.new("Stream cam", cd))
    bpy.context.scene.camera = cam
    for shot, t0, t1 in spans("shot"):
        t = t0
        while True:
            u = t - t0
            p, look, fov = SHOTS[shot](u)
            if shot in ("close", "audience"):  # handheld
                p = (p[0] + 0.018 * (math.sin(t * 1.3) + 0.5 * math.sin(t * 3.1 + 1)), p[1] + 0.018 * math.sin(t * 1.7 + 2), p[2])
            pos, tgt = W(*p), W(*look)
            cam.location = pos
            cam.rotation_euler = (tgt - pos).normalized().to_track_quat("-Z", "Y").to_euler()
            cd.angle = math.radians(fov)
            f = frame(t)
            cam.keyframe_insert("location", frame=f)
            cam.keyframe_insert("rotation_euler", frame=f)
            cd.keyframe_insert("lens", frame=f)
            if t >= t1 - 1 / FPS:
                break
            t = min(t + 0.5, t1 - 1 / FPS)
    # hard cuts: make the frame before each cut hold, then jump
    ad = cam.animation_data
    fcurves = getattr(ad.action, "fcurves", None) or [fc for layer in ad.action.layers for strip in layer.strips for cb in strip.channelbags for fc in cb.fcurves]
    cut_frames = {frame(t0) for _, t0, _ in spans("shot")}
    for fc in list(fcurves) + list(getattr(cd.animation_data.action, "fcurves", []) or []):
        pts = fc.keyframe_points
        for i, kp in enumerate(pts):
            kp.interpolation = "LINEAR"
            if i + 1 < len(pts) and int(pts[i + 1].co.x) in cut_frames:
                kp.interpolation = "CONSTANT"
    return cam


def build_overlay(cam):
    """Captions + LIVE badge parented to the camera, so they burn into the render."""
    white = mat_emit("Caption", (1, 1, 1, 1), 1.5)
    red = mat_emit("Live red", (1, 0.12, 0.12, 1), 3)
    black = mat_emit("Caption plate", (0, 0, 0, 1), 0)
    d = -1.0  # 1 m in front of the lens
    live = text("LIVE", "● LIVE", (-0.36, 0.2, d), 0.022, red, align="LEFT", parent=cam)
    cues = [c for c in SCRIPT if c.get("say") or c.get("vo") or c.get("cap")]
    for i, c in enumerate(cues):
        body = c.get("say") or c.get("vo") or c.get("cap")
        nxt = cues[i + 1]["t"] if i + 1 < len(cues) else DURATION
        dur = 2.4 if (c.get("cap") and not c.get("say") and not c.get("vo")) else min(nxt - c["t"], max(2.5, len(body) / 13))
        words, lines, cur = body.split(), [], ""
        for w in words:
            if len(cur) + len(w) > 52:
                lines.append(cur)
                cur = w
            else:
                cur = (cur + " " + w).strip()
        lines.append(cur)
        o = text(f"cc {i}", "\n".join(lines), (0, -0.18, d), 0.02, white, parent=cam)
        key_visible(o, c["t"], c["t"] + dur)
        w = max(len(l) for l in lines) * 0.0105 + 0.03
        h = len(lines) * 0.024 + 0.012
        plate = plane(f"cc plate {i}", w, h, (0, 0, 0), (0, 0, 0), black)
        plate.parent = cam
        plate.location = (0, -0.18, d - 0.001)
        key_visible(plate, c["t"], c["t"] + dur)


def build_confetti():
    bpy.ops.mesh.primitive_plane_add(size=18, location=W(0, 16, 5))
    emitter = bpy.context.object
    emitter.name = "Confetti emitter"
    emitter.hide_render = True
    bpy.ops.mesh.primitive_plane_add(size=0.1)
    piece = bpy.context.object
    piece.name = "Confetti piece"
    piece.scale = (0.7, 1.3, 1)
    piece.data.materials.append(mat_emit("Confetti", (1, 0.6, 0.4, 1), 3))
    piece.location = (0, 0, -50)
    ps_mod = emitter.modifiers.new("Confetti", "PARTICLE_SYSTEM")
    ps = ps_mod.particle_system.settings
    ps.count = 900
    ps.frame_start = frame(T_FIN)
    ps.frame_end = frame(T_FIN + 2)
    ps.lifetime = frame(DURATION)
    ps.normal_factor = 0
    ps.factor_random = 0.4
    ps.use_rotations = True
    ps.angular_velocity_mode = "RAND"
    ps.angular_velocity_factor = 6
    ps.render_type = "OBJECT"
    ps.instance_object = piece
    ps.particle_size = 1
    ps.size_random = 0.5
    ps.effector_weights.gravity = 0.08
    ps.drag_factor = 0.3
    ps.use_die_on_collision = False
    # stage + audience catch the confetti
    for name in ("Stage mirror", "Floor"):
        o = bpy.data.objects.get(name)
        if o:
            o.modifiers.new("Collision", "COLLISION")


# ---------------------------------------------------------------- sound
def synth_soundtrack(path):
    import numpy as np
    sr = 44100
    n = int(DURATION * sr) + sr
    out = np.zeros(n, dtype=np.float32)
    r = np.random.default_rng(7)

    def at(t):
        return int(t * sr)

    def add(t, sig):
        s = at(t)
        e = min(n, s + len(sig))
        if e > s:
            out[s:e] += sig[: e - s]

    def envelope(length, a, rel):
        env = np.ones(length, dtype=np.float32)
        ia, ir = int(a * sr), int(rel * sr)
        if ia:
            env[:ia] = np.linspace(0, 1, ia)
        if ir:
            env[-ir:] *= np.linspace(1, 0, ir) ** 2
        return env

    # crowd bed: filtered brown noise, louder before the lights go down
    brown = np.cumsum(r.standard_normal(n).astype(np.float32)) * 0.002
    k = sr // 4
    cs = np.cumsum(np.concatenate([[0.0], brown]))
    ma = (cs[k:] - cs[:-k]) / k
    brown[: len(ma)] -= ma.astype(np.float32)
    tt = np.arange(n) / sr
    bed_level = np.where(tt < 8, 0.35, 0.12)
    out += (brown * bed_level).astype(np.float32)

    def applause(t, d, v):
        L = int((d + 2) * sr)
        sig = np.zeros(L, dtype=np.float32)
        for _ in range(int(900 * (d + 2))):
            st = r.integers(0, L - 1000)
            cl = int(r.integers(250, 900))
            burst = r.standard_normal(cl).astype(np.float32) * np.exp(-np.arange(cl) / (cl * 0.22)) * r.uniform(0.2, 1)
            sig[st:st + cl] += burst
        sig -= np.convolve(sig, np.ones(12) / 12, mode="same")  # crude highpass
        add(t, sig * envelope(L, 0.5, 1.8) * 0.08 * v)

    def laugh(t, d):
        L = int((d + 1) * sr)
        sig = np.zeros(L, dtype=np.float32)
        x = np.arange(L) / sr
        for _ in range(14):
            f = r.uniform(450, 1100)
            carrier = np.sin(2 * np.pi * f * x + r.uniform(0, 6)) * (1 + 0.3 * r.standard_normal(L))
            am = np.clip(np.sin(2 * np.pi * r.uniform(4, 6.5) * x + r.uniform(0, 6)), 0, 1) ** 2
            sig += (carrier * am * envelope(L, 0.15, 0.9) * r.uniform(0.3, 1)).astype(np.float32)
        add(t, sig * 0.018)

    def sweep(t, d, f0, f1, v, kind="sine"):
        L = int(d * sr)
        x = np.arange(L) / sr
        f = f0 * (f1 / f0) ** (x / d)
        ph = 2 * np.pi * np.cumsum(f) / sr
        sig = np.sin(ph) if kind == "sine" else np.tanh(3 * np.sin(ph))
        add(t, (sig * envelope(L, 0.01, d * 0.6) * v).astype(np.float32))

    def noise_hit(t, d, v):
        L = int(d * sr)
        sig = r.standard_normal(L).astype(np.float32) * np.exp(-np.arange(L) / (sr * d * 0.25))
        add(t, sig * v)

    for c in SCRIPT:
        for s in c.get("sfx", []):
            t = c["t"] + s.get("o", 0)
            nme, d, v = s["n"], s.get("d", 3), s.get("v", 0.8)
            if nme == "applause":
                applause(t, d, v)
            elif nme == "cheer":
                applause(t, d, v)
                laugh(t, d)
            elif nme == "laugh":
                laugh(t, d)
            elif nme == "riser":
                L = int(d * sr)
                sig = r.standard_normal(L).astype(np.float32) * np.linspace(0, 0.25, L) ** 2
                add(t, sig)
                sweep(t, d, 80, 640, 0.08, "saw")
            elif nme == "drop":
                sweep(t, 2.4, 120, 32, 0.6, "saw")
                noise_hit(t, 2.4, 0.15)
            elif nme == "whoosh":
                L = int(0.5 * sr)
                add(t, r.standard_normal(L).astype(np.float32) * np.sin(np.linspace(0, np.pi, L)) * 0.06)
            elif nme in ("ding", "materialize"):
                for k, f in enumerate((880, 1320) if nme == "ding" else (523, 659, 784, 1046, 1318)):
                    sweep(t + k * 0.1, 1.0, f, f, 0.06)
            elif nme == "feedback":
                L = int(1.15 * sr)
                x = np.arange(L) / sr
                add(t, (np.sin(2 * np.pi * (2750 + 180 * x / 1.15) * x) * np.linspace(0, 0.15, L)).astype(np.float32))
            elif nme == "buzz":
                sweep(t + 1, 0.5, 98, 98, 0.08, "saw")
            elif nme == "heartbeat":
                bt = 0.0
                while bt < d:
                    sweep(t + bt, 0.3, 70, 38, 0.5)
                    sweep(t + bt + 0.22, 0.3, 70, 38, 0.35)
                    bt += 0.95
            elif nme == "gasp":
                noise_hit(t, 0.8, 0.05)
            elif nme == "cough":
                noise_hit(t, 0.25, 0.1)
                noise_hit(t + 0.28, 0.25, 0.08)
            elif nme == "click":
                noise_hit(t, 0.03, 0.2)

    # simple music bed per mode: kick + bass on beats
    modes = []
    for c in SCRIPT:
        for s in c.get("sfx", []):
            if s["n"] == "music":
                modes.append((c["t"], s["m"]))
    for i, (t0, m) in enumerate(modes):
        t1 = modes[i + 1][0] if i + 1 < len(modes) else DURATION
        if m == "off":
            continue
        spb = 60 / (84 if m == "lofi" else 118)
        bt, k = t0, 0
        while bt < t1:
            if m != "lofi" or k % 2 == 0:
                sweep(bt, 0.3, 150, 42, 0.35 if m == "lofi" else 0.6)
            if k % 8 == 0:
                root = [57, 53, 48, 55][(k // 8) % 4] - 24
                f = 440 * 2 ** ((root - 69) / 12)
                sweep(bt, spb * 7, f, f, 0.12)
            bt += spb
            k += 1

    peak = float(np.max(np.abs(out))) or 1
    out = np.tanh(out / peak * 1.4) * 0.85
    import wave
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((out * 32767).astype("<i2").tobytes())


def add_sound(sc, name, path, t):
    se = sc.sequence_editor or sc.sequence_editor_create()
    strips = se.strips if hasattr(se, "strips") else se.sequences
    try:
        return strips.new_sound(name, path, channel=1 if name == "Soundtrack" else 2 + len(strips) % 2, frame_start=frame(t))
    except RuntimeError as e:  # e.g. the pip "bpy" module ships without audio
        print(f"[devday] could not add {name}: {e}")


def build_audio(sc, voice):
    os.makedirs(OUT, exist_ok=True)
    wav = os.path.join(OUT, "soundtrack.wav")
    synth_soundtrack(wav)
    add_sound(sc, "Soundtrack", wav, 0)
    tts = shutil.which("espeak-ng") or shutil.which("espeak")
    if not voice or not tts:
        print("[devday] no espeak-ng found: render has crowd + music, captions carry the speech")
        return
    for i, c in enumerate(SCRIPT):
        line = c.get("say") or c.get("vo")
        if not line:
            continue
        p = os.path.join(OUT, f"line_{i:02d}.wav")
        args = [tts, "-w", p, "-s", "150" if c.get("vo") else "168", "-p", "25" if c.get("vo") else "48", "-v", "en-us", line.replace("2019", "twenty nineteen")]
        subprocess.run(args, check=False, capture_output=True)
        if os.path.exists(p):
            add_sound(sc, f"Voice {i}", p, c["t"])


# ---------------------------------------------------------------- main
def main():
    args = parse_args()
    reset()
    setup_scene(args)
    build_hall()
    build_audience()
    build_presenter()
    build_lights()
    build_slides()
    cam = build_camera()
    build_overlay(cam)
    build_confetti()
    sc = bpy.context.scene
    build_audio(sc, args["voice"])

    os.makedirs(OUT, exist_ok=True)
    blend = os.path.join(OUT, "devday2026.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print(f"[devday] saved {blend}")

    if args["render"]:
        r = sc.render
        if args["frames"]:
            sc.frame_start, sc.frame_end = args["frames"]
        try:
            r.image_settings.media_type = "VIDEO"  # Blender 5.0+
        except (AttributeError, TypeError):
            pass
        r.image_settings.file_format = "FFMPEG"
        r.ffmpeg.format = "MPEG4"
        r.ffmpeg.codec = "H264"
        r.ffmpeg.constant_rate_factor = "HIGH"
        r.ffmpeg.audio_codec = "AAC"
        r.ffmpeg.audio_bitrate = 192
        r.filepath = os.path.join(OUT, "devday2026_" + ("final" if args["final"] else "preview") + "_")
        bpy.ops.render.render(animation=True)
        print(f"[devday] rendered to {r.filepath}")


if __name__ == "__main__":
    main()

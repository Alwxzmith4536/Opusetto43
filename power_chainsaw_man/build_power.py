"""
POWER (Chainsaw Man) - procedural Blender character builder
===========================================================

Builds a rigged, clothed 3D model of Power with simulated cloth:
  * sculpted body (SDF sculpt -> surface nets -> decimated mesh)
  * eyes with her red cross-hair pupils, fang, lashes, brows, hair, horns
  * shirt (with collar, buttons, tie) and trousers simulated as cloth,
    colliding with the body, pinned at shoulders / cuffs / waist so that
    they hang loosely "like a rag"
  * armature with IK hand / foot controls and a per-hand "grip" slider

Usage (Blender 4.2 or newer):
    blender --background --python build_power.py -- --out Power_ChainsawMan.blend
or open this file in Blender's Scripting workspace and press "Run Script"
(keep sdf_core.py, anatomy.py and textures.py next to it).
"""
import os
import sys
import math
import time

import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix, Euler
from mathutils.kdtree import KDTree

HERE = os.path.dirname(os.path.abspath(__file__)) if '__file__' in globals() else os.getcwd()
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import sdf_core as S        # noqa: E402
import anatomy as AN        # noqa: E402
import textures as TX       # noqa: E402

ARGV = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []


def arg(name, default=None):
    if name in ARGV:
        i = ARGV.index(name)
        if i + 1 < len(ARGV) and not ARGV[i + 1].startswith('--'):
            return ARGV[i + 1]
        return True
    return default


H_BODY = float(arg('--h', 0.00125))          # sculpt voxel size (m)
BODY_TRIS = int(arg('--tris', 220000))        # final body triangle budget
CACHE = arg('--cache', None)                  # optional .npz cache dir for dev
T0 = time.time()


def log(*a):
    print(f"[{time.time() - T0:7.1f}s]", *a, flush=True)


# =============================================================================
# generic helpers
# =============================================================================
def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves):
        for x in list(c):
            c.remove(x)


def link(ob, coll=None):
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def new_collection(name, parent=None):
    c = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(c)
    return c


def make_mesh(name, verts, faces, coll=None, smooth=True):
    verts = np.asarray(verts, np.float32)
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.ravel())
    if isinstance(faces, np.ndarray) and faces.ndim == 2:
        sizes = np.full(len(faces), faces.shape[1], np.int32)
        flat = faces.astype(np.int32).ravel()
    else:
        sizes = np.array([len(f) for f in faces], np.int32)
        flat = np.concatenate([np.asarray(f, np.int32) for f in faces]) if len(faces) else np.zeros(0, np.int32)
    me.loops.add(len(flat))
    me.loops.foreach_set("vertex_index", flat)
    me.polygons.add(len(sizes))
    starts = np.zeros(len(sizes), np.int32)
    if len(sizes) > 1:
        starts[1:] = np.cumsum(sizes)[:-1]
    me.polygons.foreach_set("loop_start", starts)
    me.update(calc_edges=True)
    me.validate()
    if smooth:
        me.shade_smooth()
    ob = bpy.data.objects.new(name, me)
    link(ob, coll)
    return ob


def mesh_arrays(me):
    v = np.zeros(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", v)
    return v.reshape(-1, 3).astype(np.float64)


def set_coords(me, v):
    me.vertices.foreach_set("co", np.asarray(v, np.float32).ravel())
    me.update()


def apply_modifiers(ob, keep=()):
    """Bake the evaluated mesh of ob into its data (modifier apply without ops)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    me.name = old.name
    if old.users == 0:
        bpy.data.meshes.remove(old)


def tube_mesh(path, radii, sides=8, normals=None, flat=1.0, close_start=True, close_end=True,
              twist=None):
    """
    Generic tapered tube along a polyline.
    path [N,3], radii [N] (width), flat = thickness/width ratio,
    normals [N,3] = direction of the flat axis (optional).
    Returns verts, faces (lists) and uv (per vertex u,v).
    """
    P = np.asarray(path, float)
    N = len(P)
    R = np.broadcast_to(np.asarray(radii, float), (N,))
    T = np.gradient(P, axis=0)
    T /= np.linalg.norm(T, axis=1)[:, None] + 1e-12
    if normals is None:
        ref = np.array([0, 0, 1.0]) if abs(T[0][2]) < 0.9 else np.array([1.0, 0, 0])
        n0 = np.cross(T[0], ref)
        n0 /= np.linalg.norm(n0)
        Ns = [n0]
        for i in range(1, N):
            n = Ns[-1] - T[i] * (Ns[-1] @ T[i])
            n /= np.linalg.norm(n) + 1e-12
            Ns.append(n)
        Ns = np.array(Ns)
    else:
        Ns = np.asarray(normals, float)
        Ns = Ns - T * np.einsum('ij,ij->i', Ns, T)[:, None]
        Ns /= np.linalg.norm(Ns, axis=1)[:, None] + 1e-12
    B = np.cross(T, Ns)
    ang = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    verts, uvs = [], []
    for i in range(N):
        tw = 0.0 if twist is None else twist[i]
        for j, a in enumerate(ang):
            aa = a + tw
            off = B[i] * np.cos(aa) * R[i] + Ns[i] * np.sin(aa) * R[i] * flat
            verts.append(P[i] + off)
            uvs.append((j / sides, i / (N - 1)))
    faces = []
    for i in range(N - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    if close_start:
        faces.append(tuple(range(sides))[::-1])
    if close_end:
        faces.append(tuple(range((N - 1) * sides, N * sides)))
    return np.array(verts), faces, np.array(uvs)


def set_uv(me, uv_per_vertex, name="UVMap"):
    uvl = me.uv_layers.new(name=name)
    vi = np.zeros(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", vi)
    uvl.data.foreach_set("uv", np.asarray(uv_per_vertex, np.float32)[vi].ravel())


def image_from_array(name, arr, colorspace='sRGB'):
    """Create a packed PNG image from a float array (values already in the
    image's colour space)."""
    import tempfile
    h, w = arr.shape[:2]
    if arr.ndim == 2:
        a = np.ones((h, w, 4), np.float32)
        a[..., 0] = a[..., 1] = a[..., 2] = arr
        arr = a
    tmp = bpy.data.images.new(name + "_tmp", w, h, alpha=True)
    tmp.pixels.foreach_set(np.asarray(arr, np.float32).ravel())
    fn = os.path.join(tempfile.gettempdir(), name + ".png")
    tmp.filepath_raw = fn
    tmp.file_format = 'PNG'
    tmp.save()
    bpy.data.images.remove(tmp)
    img = bpy.data.images.load(fn)
    img.name = name
    img.colorspace_settings.name = colorspace
    img.pack()
    try:
        os.remove(fn)
    except OSError:
        pass
    return img


# =============================================================================
# materials
# =============================================================================
def srgb(c):
    c = np.asarray(c, float)
    return tuple(np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)) + (1.0,)


def principled(name, color, rough=0.5, metal=0.0, sss=0.0, sss_radius=(1, 0.4, 0.2), spec=0.5,
               sheen=0.0, coat=0.0, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(color)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if sss > 0:
        b.inputs["Subsurface Weight"].default_value = sss
        b.inputs["Subsurface Radius"].default_value = sss_radius
        b.inputs["Subsurface Scale"].default_value = 0.01
    b.inputs["Specular IOR Level"].default_value = spec
    if sheen > 0:
        b.inputs["Sheen Weight"].default_value = sheen
    if coat > 0:
        b.inputs["Coat Weight"].default_value = coat
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
    return m


def node(nt, typ, loc=(0, 0), **kw):
    n = nt.nodes.new(typ)
    n.location = loc
    for k, v in kw.items():
        if k in n.inputs:
            n.inputs[k].default_value = v
        else:
            setattr(n, k, v)
    return n


def bsdf(m):
    return m.node_tree.nodes["Principled BSDF"]


def add_bump(m, height_socket, strength=0.2, distance=0.002):
    nt = m.node_tree
    bp = node(nt, 'ShaderNodeBump', (-250, -400), Strength=strength, Distance=distance)
    nt.links.new(height_socket, bp.inputs['Height'])
    nt.links.new(bp.outputs['Normal'], bsdf(m).inputs['Normal'])
    return bp


# =============================================================================
# BODY
# =============================================================================
def sculpt_body():
    """Return (verts, quads) of the sculpted body, optionally cached."""
    if CACHE:
        fn = os.path.join(CACHE, f"body_{H_BODY:.5f}.npz")
        if os.path.exists(fn) and not arg('--rebuild'):
            d = np.load(fn)
            return d['v'], d['q']
    sc = AN.build_body()
    log("sculpting body (surface nets, voxel %.2f mm)" % (H_BODY * 1000))
    v, q = S.surface_nets(sc, H_BODY, block=48)
    v, q = S.mesh_cleanup(v, q)
    if CACHE:
        os.makedirs(CACHE, exist_ok=True)
        np.savez(fn, v=v, q=q)
    return v, q


def _sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def body_masks(v):
    """
    Per-vertex *signed* fields (metres, >0 inside the region) used by the skin
    shader for lips, finger nails and the modest underwear layer. Signed
    fields interpolate across triangles, so the shader can cut crisp edges.
    """
    n = len(v)
    x, y, z = v[:, 0], v[:, 1], v[:, 2]
    ax = np.abs(x)
    lips = np.full(n, -0.01)
    for c, r in (((0, -0.0848, 1.4705), (0.0156, 0.0068, 0.0052)),
                 ((0, -0.0832, 1.4630), (0.0138, 0.0072, 0.0055))):
        q = (v - np.array(c)) / np.array(r)
        lips = np.maximum(lips, (1.25 - np.linalg.norm(q, axis=1)) * 0.004)
    nails = np.full(n, -0.01)
    for side in (1, -1):
        hp = AN.HandPrim(side)
        near = np.linalg.norm(v - hp.o, axis=1) < 0.25
        idx = np.nonzero(near)[0]
        Ll = hp.to_local(v[idx])
        chains = [AN.finger_chain(nm) for nm in AN.FINGER_DEF] + [AN.thumb_chain()]
        for pts, R in chains:
            a, b = pts[2], pts[3]
            ab = b - a
            L = np.linalg.norm(ab)
            t = ((Ll - a) @ ab) / (L * L)
            closest = a + np.clip(t, 0, 1)[:, None] * ab
            off = Ll - closest
            dist = np.linalg.norm(off, axis=1)
            dz = np.array([0, 0, -1.0])
            dz = dz - ab * (dz @ ab) / (L * L)
            dz /= np.linalg.norm(dz)
            dors = (off @ dz) / np.maximum(dist, 1e-9)
            f = np.minimum.reduce([(t - 0.42) * L, (1.15 - t) * L, (dors - 0.5) * R[3],
                                   1.7 * R[3] - dist])
            nails[idx] = np.maximum(nails[idx], f)
    # sports bra
    dip = 0.035 * np.exp(-(x / 0.025) ** 2) * _sstep(0.0, -0.03, y)
    top = 1.275 - dip - 0.035 * _sstep(-0.02, 0.05, y)
    band = np.minimum.reduce([z - 1.135, top - z, 0.165 - ax])
    strap = np.minimum.reduce([0.011 - np.abs(ax - 0.085), z - 1.2, 1.40 - z, 0.12 - np.abs(y)])
    bra = np.maximum(band, strap)
    # briefs
    btop = 0.915 + 0.08 * np.clip(ax - 0.05, 0, None)
    leg = 0.865 - 1.0 * np.clip(0.115 - ax, 0, None) - 0.05 * _sstep(0.0, 0.06, y)
    briefs = np.minimum.reduce([btop - z, z - leg, 0.21 - ax])
    under = np.maximum(bra, briefs)
    # keep it off the arms (armpits)
    for s_ in (1, -1):
        m = (lambda p: np.asarray(p, float)) if s_ > 0 else AN.mirror
        a, b = m(AN.SK.J['shoulder']), m(AN.SK.J['elbow'])
        ab = b - a
        t = np.clip(((v - a) @ ab) / (ab @ ab), 0, 1)
        dist = np.linalg.norm(v - (a + t[:, None] * ab), axis=1)
        under = np.minimum(under, dist - 0.058)
    return lips, nails, under


def build_body(coll):
    v, q = sculpt_body()
    log(f"body raw: {len(v)} verts")
    ob = make_mesh("Power_Body", v, q, coll)
    dec = ob.modifiers.new("Decimate", 'DECIMATE')
    dec.ratio = min(1.0, BODY_TRIS / (2.0 * len(q)))
    apply_modifiers(ob)
    me = ob.data
    log(f"body decimated: {len(me.vertices)} verts / {len(me.polygons)} faces")
    v = mesh_arrays(me)
    lips, nails, under = body_masks(v)
    for nm, arr in (("lips", lips), ("nails", nails), ("underwear", under)):
        at = me.attributes.new(nm, 'FLOAT', 'POINT')
        at.data.foreach_set("value", arr.astype(np.float32))
    me.shade_smooth()
    return ob


def skin_material():
    m = principled("Power_Skin", (0.96, 0.80, 0.70), rough=0.45, sss=0.15,
                   sss_radius=(1.0, 0.35, 0.2), spec=0.45)
    nt = m.node_tree
    b = bsdf(m)
    # colour variation: blush on cheeks/knuckles via noise, lips, nails, underwear
    tc = node(nt, 'ShaderNodeTexCoord', (-1400, 0))
    noise = node(nt, 'ShaderNodeTexNoise', (-1200, 200), Scale=40.0, Detail=6.0)
    nt.links.new(tc.outputs['Object'], noise.inputs['Vector'])
    base = node(nt, 'ShaderNodeMix', (-900, 200), data_type='RGBA', blend_type='MULTIPLY')
    base.inputs['Factor'].default_value = 0.06
    base.inputs[6].default_value = srgb((0.96, 0.80, 0.70))
    nt.links.new(noise.outputs['Color'], base.inputs[7])
    # cheeks blush: sphere masks in object space
    def sphere_mask(c, r, loc):
        sub = node(nt, 'ShaderNodeVectorMath', loc, operation='DISTANCE')
        sub.inputs[1].default_value = c
        nt.links.new(tc.outputs['Object'], sub.inputs[0])
        mr = node(nt, 'ShaderNodeMapRange', (loc[0] + 180, loc[1]))
        mr.inputs['From Min'].default_value = 0.0
        mr.inputs['From Max'].default_value = r
        mr.inputs['To Min'].default_value = 1.0
        mr.inputs['To Max'].default_value = 0.0
        nt.links.new(sub.outputs['Value'], mr.inputs['Value'])
        return mr.outputs['Result']
    bl = node(nt, 'ShaderNodeMath', (-700, 400), operation='MAXIMUM')
    nt.links.new(sphere_mask((0.040, -0.072, 1.495), 0.026, (-1150, 500)), bl.inputs[0])
    nt.links.new(sphere_mask((-0.040, -0.072, 1.495), 0.026, (-1150, 350)), bl.inputs[1])
    blush = node(nt, 'ShaderNodeMix', (-600, 200), data_type='RGBA')
    nt.links.new(bl.outputs[0], blush.inputs['Factor'])
    nt.links.new(base.outputs[2], blush.inputs[6])
    blush.inputs[7].default_value = srgb((0.98, 0.62, 0.58))

    def attr_mix(prev, attr, col, loc, soft=0.0006):
        a = node(nt, 'ShaderNodeAttribute', (loc[0] - 400, loc[1] - 150), attribute_name=attr)
        mr = node(nt, 'ShaderNodeMapRange', (loc[0] - 200, loc[1] - 150))
        mr.inputs['From Min'].default_value = -soft
        mr.inputs['From Max'].default_value = soft
        nt.links.new(a.outputs['Fac'], mr.inputs['Value'])
        mx = node(nt, 'ShaderNodeMix', loc, data_type='RGBA')
        nt.links.new(mr.outputs['Result'], mx.inputs['Factor'])
        nt.links.new(prev, mx.inputs[6])
        mx.inputs[7].default_value = srgb(col)
        return mx, mr
    lipmix, lipa = attr_mix(blush.outputs[2], "lips", (0.86, 0.47, 0.46), (-400, 200), soft=0.0012)
    nailmix, naila = attr_mix(lipmix.outputs[2], "nails", (0.98, 0.84, 0.80), (-200, 200))
    undermix, undera = attr_mix(nailmix.outputs[2], "underwear", (0.55, 0.55, 0.60), (0, 300))
    nt.links.new(undermix.outputs[2], b.inputs['Base Color'])
    # roughness: lips & nails glossier, underwear matte fabric
    r1 = node(nt, 'ShaderNodeMath', (-200, -100), operation='MULTIPLY_ADD')
    nt.links.new(naila.outputs['Result'], r1.inputs[0])
    r1.inputs[1].default_value = -0.25
    r1.inputs[2].default_value = 0.45
    r2 = node(nt, 'ShaderNodeMath', (0, -100), operation='MULTIPLY_ADD')
    nt.links.new(undera.outputs['Result'], r2.inputs[0])
    r2.inputs[1].default_value = 0.4
    nt.links.new(r1.outputs[0], r2.inputs[2])
    nt.links.new(r2.outputs[0], b.inputs['Roughness'])
    # subtle skin pores bump
    vor = node(nt, 'ShaderNodeTexVoronoi', (-800, -400), Scale=900.0)
    nt.links.new(tc.outputs['Object'], vor.inputs['Vector'])
    add_bump(m, vor.outputs['Distance'], strength=0.04, distance=0.0005)
    return m


# =============================================================================
# EYES, TEETH, BROWS, LASHES
# =============================================================================
def build_eyes(coll):
    img = image_from_array("Power_Eye_Tex", TX.power_eye(512, srgb_out=True), 'sRGB')
    m = principled("Power_Eye", (1, 1, 1), rough=0.08, spec=0.6, coat=0.6)
    nt = m.node_tree
    tex = node(nt, 'ShaderNodeTexImage', (-500, 200))
    tex.image = img
    nt.links.new(tex.outputs['Color'], bsdf(m).inputs['Base Color'])
    eyes = []
    for s, nm in ((1, "L"), (-1, "R")):
        c = AN.EYE_C * np.array([s, 1, 1])
        fwd = AN.EYE_FWD * np.array([s, 1, 1])
        R = AN.EYE_R
        # UV sphere oriented along fwd
        nu, nv = 48, 32
        verts, uvs = [], []
        Rm = S.frame(-fwd, (0, 0, 1))  # local x = backwards
        for i in range(nv + 1):
            th = np.pi * i / nv  # 0 = front pole
            for j in range(nu):
                ph = 2 * np.pi * j / nu
                lp = np.array([-np.cos(th), np.sin(th) * np.cos(ph), np.sin(th) * np.sin(ph)])
                verts.append(c + Rm @ lp * R)
                # planar projection for the front, wraps to sclera at the back
                rr = np.sin(th) * 0.5 if th < np.pi / 2 else 0.499
                yy = np.cos(ph) * s  # horizontal (mirror for the right eye)
                uvs.append((0.5 + rr * yy * (-1), 0.5 + rr * np.sin(ph)))
        faces = []
        for i in range(nv):
            for j in range(nu):
                a = i * nu + j
                b = i * nu + (j + 1) % nu
                faces.append((a, b, b + nu, a + nu))
        ob = make_mesh(f"Eye.{nm}", np.array(verts), faces, coll)
        set_uv(ob.data, np.array(uvs))
        ob.data.materials.append(m)
        eyes.append(ob)
    return eyes


def recalc_normals(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def project_to_body(sc, pts, offset=0.0, iters=4):
    """Project points onto the body SDF surface (+offset along the normal)."""
    p = np.asarray(pts, float).copy()
    e = 1e-4
    for _ in range(iters):
        d = sc(p)
        g = np.stack([(sc(p + o) - sc(p - o)) / (2 * e) for o in np.eye(3) * e], 1)
        g /= np.linalg.norm(g, axis=1)[:, None] + 1e-12
        p = p - (d - offset)[:, None] * g
    return p, g


def build_face_details(coll, sc):
    """Eyelashes, eyebrows and Power's little fang."""
    objs = []
    lash_m = principled("Power_Lashes", (0.12, 0.06, 0.05), rough=0.6)
    brow_m = principled("Power_Brows", (0.80, 0.50, 0.42), rough=0.7)
    tooth_m = principled("Power_Teeth", (0.97, 0.95, 0.9), rough=0.25, sss=0.1, coat=0.3)
    for s, nm in ((1, "L"), (-1, "R")):
        lid = AN.EyeLids(s)
        V, F = [], []
        us = np.linspace(-0.92, 0.97, 24)
        for i, u in enumerate(us):
            top = 0.47 * max(0.0, 1 - ((u - 0.04) / 0.93) ** 2) ** 0.75 + 0.10 * u
            vv = top - 0.02
            ff = math.sqrt(max(1e-4, 1 - u * u - vv * vv))
            w = S.norm(lid.fwd * ff + lid.right * u + lid.up * vv)
            base = lid.c + w * (lid.r_out + 0.0002)
            out = S.norm(w * 0.6 + lid.up * 0.8)
            t = (u + 0.92) / 1.89
            L = 0.0018 + 0.0032 * t ** 1.6          # longer toward the outer corner
            wing = lid.right * 0.0018 * max(0.0, t - 0.75) / 0.25
            thick = 0.00055 + 0.0006 * t
            tip = base + out * L + wing
            V += [base - lid.up * thick * 0.4, base + w * thick, tip + w * 0.0002]
        for i in range(len(us) - 1):
            a, b = 3 * i, 3 * (i + 1)
            F += [(a, b, b + 1, a + 1), (a + 1, b + 1, b + 2, a + 2), (a, a + 2, b + 2, b)]
        ob = make_mesh(f"Lashes.{nm}", np.array(V), F, coll)
        recalc_normals(ob)
        ob.data.materials.append(lash_m)
        objs.append(ob)
        # brow: thin tapered ribbon lying on the skin
        xs = np.linspace(0.013, 0.051, 16) * s
        zs = 1.5655 + 0.006 * np.sin(np.linspace(0.2, 2.6, 16)) - 0.004 * np.linspace(0, 1, 16) ** 2
        guess = np.stack([xs, np.full(16, -0.09), zs], 1)
        pts, nrm = project_to_body(sc, guess, offset=0.0006)
        widths = 0.0016 * np.sin(np.linspace(0.35, 2.9, 16)) + 0.0005
        V = []
        for p, n_, w in zip(pts, nrm, widths):
            up = S.norm(np.array([0, 0, 1.0]) - n_ * n_[2])
            V += [p - up * w, p + up * w, p + n_ * 0.0004]
        F = []
        for i in range(15):
            a, b = 3 * i, 3 * (i + 1)
            F += [(a, b, b + 1, a + 1), (a + 1, b + 1, b + 2, a + 2), (a + 2, b + 2, b, a)]
        ob = make_mesh(f"Brow.{nm}", np.array(V), F, coll)
        recalc_normals(ob)
        ob.data.materials.append(brow_m)
        objs.append(ob)
    # fang peeking over the lower lip (her left side)
    base = np.array([0.0085, -0.0858, 1.4672])
    tip = np.array([0.0080, -0.0868, 1.4605])
    V, F, _ = tube_mesh(np.linspace(base, tip, 6), np.linspace(0.0021, 0.0002, 6), sides=10,
                        flat=0.55, normals=np.tile([0, -1.0, 0], (6, 1)))
    ob = make_mesh("Fang", V, F, coll)
    recalc_normals(ob)
    ob.data.materials.append(tooth_m)
    objs.append(ob)
    return objs


def hair_material():
    m = principled("Power_Hair", (0.97, 0.70, 0.60), rough=0.38, spec=0.5, sheen=0.25)
    nt = m.node_tree
    b = bsdf(m)
    uvn = node(nt, 'ShaderNodeUVMap', (-1300, 0))
    sep = node(nt, 'ShaderNodeSeparateXYZ', (-1100, 0))
    nt.links.new(uvn.outputs['UV'], sep.inputs[0])
    # root -> tip gradient (slightly deeper pink at the roots, lighter tips)
    ramp = node(nt, 'ShaderNodeValToRGB', (-850, 200))
    ramp.color_ramp.elements[0].color = srgb((0.90, 0.55, 0.48))
    ramp.color_ramp.elements[1].color = srgb((0.99, 0.80, 0.68))
    nt.links.new(sep.outputs['Y'], ramp.inputs['Fac'])
    # strand stripes across the clump
    wave = node(nt, 'ShaderNodeTexWave', (-850, -150), Scale=6.0, Distortion=4.0, Detail=3.0)
    wave.wave_type = 'BANDS'
    wave.bands_direction = 'X'
    nt.links.new(uvn.outputs['UV'], wave.inputs['Vector'])
    attr = node(nt, 'ShaderNodeAttribute', (-1100, -350), attribute_name="clump_rnd")
    mix = node(nt, 'ShaderNodeMix', (-550, 100), data_type='RGBA', blend_type='MULTIPLY')
    mix.inputs['Factor'].default_value = 0.18
    nt.links.new(ramp.outputs['Color'], mix.inputs[6])
    nt.links.new(wave.outputs['Color'], mix.inputs[7])
    hue = node(nt, 'ShaderNodeHueSaturation', (-350, 100))
    mr = node(nt, 'ShaderNodeMapRange', (-850, -400))
    mr.inputs['To Min'].default_value = 0.9
    mr.inputs['To Max'].default_value = 1.08
    nt.links.new(attr.outputs['Fac'], mr.inputs['Value'])
    nt.links.new(mr.outputs['Result'], hue.inputs['Value'])
    nt.links.new(mix.outputs[2], hue.inputs['Color'])
    nt.links.new(hue.outputs['Color'], b.inputs['Base Color'])
    # anisotropic highlight along the strands
    tg = node(nt, 'ShaderNodeTangent', (-350, -300))
    tg.direction_type = 'UV_MAP'
    tg.uv_map = "UVMap"
    b.inputs['Anisotropic'].default_value = 0.6
    b.inputs['Anisotropic Rotation'].default_value = 0.25
    nt.links.new(tg.outputs['Tangent'], b.inputs['Tangent'])
    add_bump(m, wave.outputs['Fac'], strength=0.15, distance=0.0005)
    return m


def build_hair_and_horns(coll):
    import hair as HR
    log("growing hair clumps")
    V, F, UV, RND = HR.build_hair()
    ob = make_mesh("Power_Hair", V, F, coll)
    recalc_normals(ob)
    set_uv(ob.data, UV)
    at = ob.data.attributes.new("clump_rnd", 'FLOAT', 'POINT')
    at.data.foreach_set("value", RND.astype(np.float32))
    ob.data.materials.append(hair_material())
    sub = ob.modifiers.new("Subdivision", 'SUBSURF')
    sub.levels = 0
    sub.render_levels = 1
    log(f"hair: {len(V)} verts")
    horn_m = principled("Power_Horns", (0.78, 0.06, 0.07), rough=0.35, coat=0.4, sss=0.05,
                        sss_radius=(1.0, 0.2, 0.1))
    horns = []
    for s, nm in ((1, "L"), (-1, "R")):
        hv, hf = HR.horn_mesh(s)
        h = make_mesh(f"Horn.{nm}", hv, hf, coll)
        recalc_normals(h)
        h.data.materials.append(horn_m)
        sub = h.modifiers.new("Subdivision", 'SUBSURF')
        sub.levels = 1
        sub.render_levels = 2
        horns.append(h)
    return ob, horns


# =============================================================================
# CLOTHES
# =============================================================================
def remesh_quads(ob, faces):
    """Even quad topology for a closed shell: QuadriFlow when it accepts the
    mesh, otherwise a voxel remesh sized for the same face budget."""
    select_only([ob], ob)
    area = sum(p.area for p in ob.data.polygons)
    n0 = len(ob.data.polygons)
    try:
        ob.data.remesh_voxel_size = 0.006
        bpy.ops.object.voxel_remesh()
        bpy.ops.object.quadriflow_remesh(target_faces=faces, use_mesh_symmetry=False,
                                         use_preserve_sharp=False, use_preserve_boundary=False,
                                         smooth_normals=False, seed=3)
    except Exception as e:  # pragma: no cover
        log("  quadriflow error:", e)
    n1 = len(ob.data.polygons)
    if n1 > faces * 1.5:
        ob.data.remesh_voxel_size = math.sqrt(area / faces)
        bpy.ops.object.voxel_remesh()
        log(f"  voxel remesh {n0} -> {len(ob.data.polygons)} faces")
    else:
        log(f"  quadriflow {n0} -> {n1} faces")


def cut_faces(ob, kill_fn):
    """Delete faces whose centre satisfies kill_fn(centres)->bool array."""
    me = ob.data
    c = np.zeros(len(me.polygons) * 3)
    me.polygons.foreach_get("center", c)
    kill = kill_fn(c.reshape(-1, 3))
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in np.nonzero(kill)[0]], context='FACES')
    # remove loose verts / dangling faces (single faces connected by a vertex)
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    bm.to_mesh(me)
    bm.free()
    me.update()


def keep_largest_island(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    islands = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, isl = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            isl.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        islands.append(isl)
    islands.sort(key=len, reverse=True)
    kill = [f for isl in islands[1:] for f in isl]
    if kill:
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(ob.data)
    bm.free()


def boundary_verts(me):
    bm = bmesh.new()
    bm.from_mesh(me)
    idx = np.array([v.index for v in bm.verts if v.is_boundary], np.int64)
    bm.free()
    return idx


def relax(ob, iters=4, fac=0.5, keep_boundary=True):
    """Laplacian relax that keeps the shape (tangential) - evens out quads."""
    me = ob.data
    v = mesh_arrays(me)
    e = np.zeros(len(me.edges) * 2, np.int64)
    me.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    bnd = np.zeros(len(v), bool)
    bnd[boundary_verts(me)] = True
    n = np.zeros(len(me.vertices) * 3)
    me.vertices.foreach_get("normal", n)
    n = n.reshape(-1, 3)
    for _ in range(iters):
        acc = np.zeros_like(v)
        cnt = np.zeros(len(v))
        np.add.at(acc, e[:, 0], v[e[:, 1]])
        np.add.at(acc, e[:, 1], v[e[:, 0]])
        np.add.at(cnt, e[:, 0], 1)
        np.add.at(cnt, e[:, 1], 1)
        avg = acc / np.maximum(cnt, 1)[:, None]
        dlt = avg - v
        dlt -= n * np.einsum('ij,ij->i', dlt, n)[:, None]
        if keep_boundary:
            dlt[bnd] = 0
        v = v + fac * dlt
    set_coords(me, v)


def fabric_uv(v, sleeves=True):
    """Cylindrical UVs: around Z for the torso/legs, around the arm for sleeves."""
    import garments as GM
    u = np.arctan2(v[:, 0], -v[:, 1]) * 0.16
    w = v[:, 2]
    if sleeves:
        for s in (1, -1):
            sh, el, wr = GM.arm_axis(s)
            ax = S.norm(wr - sh)
            rel = v - sh
            t = rel @ ax
            perp = rel - t[:, None] * ax
            ref = S.norm(np.cross(ax, (0, 1, 0)))
            ref2 = np.cross(ax, ref)
            ang = np.arctan2(perp @ ref2, perp @ ref)
            on = (np.sign(v[:, 0]) == s) & (np.abs(v[:, 0]) > 0.19 + 0.0 * t)
            u = np.where(on, ang * 0.06 + 2.0 * (s > 0), u)
            w = np.where(on, t + 3.0, w)
    return np.stack([u, w], 1) * 4.0


def build_shirt(coll):
    import garments as GM
    log("building shirt")
    v, q = S.surface_nets(GM.shirt_scene(), 0.008)
    v, q = S.mesh_cleanup(v, q)
    ob = make_mesh("Power_Shirt", v, q, coll)
    remesh_quads(ob, 4300)

    def kill(c):
        x, y, z = c[:, 0], c[:, 1], c[:, 2]
        k = z < GM.shirt_hem_z(x, y)
        k |= (z > GM.shirt_neck_z(x, y)) & (np.abs(x) < 0.12)
        for s in (1, -1):
            p0, d = GM.cuff_plane(s)
            k |= ((c - p0) @ d > 0) & (np.linalg.norm(c - p0, axis=1) < 0.15)
        return k
    cut_faces(ob, kill)
    keep_largest_island(ob)
    # snap the cut borders onto the cut curves so hems / cuffs are clean
    me = ob.data
    v = mesh_arrays(me)
    b = boundary_verts(me)
    for i in b:
        p = v[i]
        hz = GM.shirt_hem_z(p[0], p[1])
        nz = GM.shirt_neck_z(p[0], p[1])
        cands = [(abs(p[2] - hz), 'hem'), (abs(p[2] - nz) if abs(p[0]) < 0.12 else 9, 'neck')]
        for s in (1, -1):
            p0, d = GM.cuff_plane(s)
            if np.linalg.norm(p - p0) < 0.15:
                cands.append((abs((p - p0) @ d), ('cuff', s)))
        dist, kind = min(cands, key=lambda t: t[0])
        if kind == 'hem':
            p[2] = hz
        elif kind == 'neck':
            p[2] = nz
        else:
            p0, d = GM.cuff_plane(kind[1])
            p -= d * ((p - p0) @ d)
        v[i] = p
    set_coords(me, v)
    relax(ob, iters=6, fac=0.5)
    v = mesh_arrays(me)
    set_uv(me, fabric_uv(v))
    # attributes for seams (signed fields, metres)
    x, y, z = v[:, 0], v[:, 1], v[:, 2]
    front = y < -0.02
    placket = np.where(front, 0.0125 - np.abs(x), -0.05)
    hem = z - GM.shirt_hem_z(x, y)
    cuff = np.full(len(v), 1.0)
    for s in (1, -1):
        p0, d = GM.cuff_plane(s)
        near = np.linalg.norm(v - p0, axis=1) < 0.2
        cuff = np.where(near, np.minimum(cuff, -((v - p0) @ d)), cuff)
    # chest pocket on her left side: signed distance to a rounded-bottom rectangle
    px, pz = x - 0.068, z - 1.185
    pocket = np.minimum.reduce([0.05 - np.abs(px), 0.055 - pz, pz + 0.06 - 0.012 * (np.abs(px) / 0.05) ** 2])
    pocket = np.where(front, pocket, -0.05)
    for nm, arr in (("placket", placket), ("hem", hem), ("cuff", cuff), ("pocket", pocket)):
        at = me.attributes.new(nm, 'FLOAT', 'POINT')
        at.data.foreach_set("value", arr.astype(np.float32))
    log(f"shirt: {len(me.vertices)} verts")
    return ob


def build_pants(coll):
    import garments as GM
    log("building trousers")
    v, q = S.surface_nets(GM.pants_scene(), 0.008)
    v, q = S.mesh_cleanup(v, q)
    ob = make_mesh("Power_Trousers", v, q, coll)
    remesh_quads(ob, 2900)

    def kill(c):
        x, y, z = c[:, 0], c[:, 1], c[:, 2]
        return (z > GM.pants_top_z(x, y)) | (z < GM.PANTS_HEM_Z)
    cut_faces(ob, kill)
    keep_largest_island(ob)
    me = ob.data
    v = mesh_arrays(me)
    for i in boundary_verts(me):
        p = v[i]
        tz = GM.pants_top_z(p[0], p[1])
        p[2] = tz if abs(p[2] - tz) < abs(p[2] - GM.PANTS_HEM_Z) else GM.PANTS_HEM_Z
    set_coords(me, v)
    relax(ob, iters=6, fac=0.5)
    v = mesh_arrays(me)
    # UV: per-leg cylinders below the crotch
    u = np.arctan2(v[:, 0] - np.sign(v[:, 0]) * 0.095 * (v[:, 2] < 0.72), -v[:, 1]) * 0.12
    set_uv(me, np.stack([u + (v[:, 0] > 0) * 2, v[:, 2]], 1) * 4.0)
    x, y, z = v[:, 0], v[:, 1], v[:, 2]
    # side seams + front crease lines
    side = np.abs(np.arctan2(np.abs(x) - 0.095 * (z < 0.74), y)) - np.pi / 2
    crease = np.where((z < 0.70) & (y < 0), 0.002 - np.abs(np.abs(x) - 0.096), -0.05)
    hemf = z - GM.PANTS_HEM_Z
    for nm, arr in (("seam", side), ("crease", crease), ("hem", hemf)):
        at = me.attributes.new(nm, 'FLOAT', 'POINT')
        at.data.foreach_set("value", arr.astype(np.float32))
    log(f"trousers: {len(me.vertices)} verts")
    return ob


def build_collar(coll):
    """Classic shirt collar: a stand around the neck plus the folded-over fall."""
    rows = []
    n = 44
    # angle measured from the back of the neck; leave a gap at the front
    ths = np.linspace(-2.75, 2.75, n)
    for th in ths:
        dx, dy = np.sin(th), np.cos(th)
        a, bb = 0.066, (0.069 if dy > 0 else 0.064)
        base = np.array([dx * a, 0.018 + dy * bb, 0.0])
        front = np.clip((abs(th) - 1.6) / 1.15, 0, 1)
        zb = 1.405 - 0.035 * front ** 1.5
        out = S.norm(np.array([dx, dy, 0.0]))
        stand_h = 0.030 - 0.006 * front
        p0 = base + np.array([0, 0, zb])
        p1 = p0 + np.array([0, 0, stand_h]) - out * 0.004
        p2 = p1 + out * 0.010 + np.array([0, 0, 0.002])
        fall = 0.040 + 0.030 * front ** 2
        p3 = p2 + out * (0.020 + 0.012 * front) + np.array([0, 0, -fall])
        # collar points sweep forward/down at the front
        if front > 0:
            p3 = p3 + np.array([0, -0.012 * front, -0.008 * front])
        rows.append([p0, p1, p2, p3])
    rows = np.array(rows)
    V = rows.reshape(-1, 3)
    F = []
    for i in range(n - 1):
        for j in range(3):
            a = i * 4 + j
            F.append((a, a + 1, a + 5, a + 4))
    ob = make_mesh("Shirt_Collar", V, F, coll)
    recalc_normals(ob)
    sol = ob.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = 0.0025
    sol.offset = 1.0
    sub = ob.modifiers.new("Subdivision", 'SUBSURF')
    sub.levels = 2
    sub.render_levels = 2
    return ob


def build_tie(coll, shirt):
    """Black necktie: rigid knot + a cloth blade that hangs over the shirt."""
    import garments as GM
    sc = GM.shirt_scene()
    # follow the shirt front at x=0
    zs = np.linspace(1.355, 0.93, 44)
    ys = []
    for z in zs:
        yy = np.linspace(-0.25, 0.0, 400)
        d = sc(np.stack([np.zeros_like(yy), yy, np.full_like(yy, z)], 1))
        i = np.argmax(d < 0)
        ys.append(yy[i] - 0.009)
    ys = np.minimum.accumulate(np.array(ys))  # hangs straight down off the bust
    widths = np.interp(zs, [0.93, 0.95, 1.0, 1.30, 1.355], [0.0, 0.036, 0.038, 0.017, 0.0085])
    V, F = [], []
    cols = 7
    for z, y, w in zip(zs, ys, widths):
        for k in range(cols):
            t = k / (cols - 1) - 0.5
            # pointed tip
            zz = z
            if z < 0.95:
                zz = z - (0.02 - 0.02 * abs(t) * 2)
            V.append((t * 2 * max(w, 0.002), y, zz))
    for i in range(len(zs) - 1):
        for k in range(cols - 1):
            a = i * cols + k
            F.append((a, a + 1, a + 1 + cols, a + cols))
    blade = make_mesh("Necktie", np.array(V), F, coll)
    recalc_normals(blade)
    me = blade.data
    v = mesh_arrays(me)
    # make the normals face forward (-Y)
    if me.polygons[0].normal.y > 0:
        me.flip_normals()
    set_uv(me, np.stack([v[:, 0] * 10 + 0.5, v[:, 2] * 3], 1))
    # knot: a soft trapezoid wedge (subdivided box)
    kz, ky = 1.371, ys[0] - 0.003
    tw, bw, hh, dp = 0.021, 0.008, 0.017, 0.007
    kv = np.array([(-tw, ky - dp, kz + hh), (tw, ky - dp, kz + hh), (bw, ky - dp * 0.8, kz - hh),
                   (-bw, ky - dp * 0.8, kz - hh), (-tw * 0.9, ky + dp, kz + hh), (tw * 0.9, ky + dp, kz + hh),
                   (bw * 0.9, ky + dp, kz - hh), (-bw * 0.9, ky + dp, kz - hh)])
    kf = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    knot = make_mesh("Necktie_Knot", kv, kf, coll)
    recalc_normals(knot)
    sub = knot.modifiers.new("Subdivision", 'SUBSURF')
    sub.levels = 2
    sub.render_levels = 3
    return blade, knot


def profile_ring(loft, z, inset, n=96):
    """Points of a Loft cross-section at height z, grown by `inset` metres."""
    a, bf, bb, yc, ex = [float(t[0]) for t in loft.profile(np.array([z]))]
    pts = []
    for k in range(n):
        th = 2 * np.pi * k / n
        cx, cy = np.sin(th), -np.cos(th)
        b = bf if cy < 0 else bb
        sx = np.sign(cx) * abs(cx) ** (2 / ex) * (a + inset)
        sy = np.sign(cy) * abs(cy) ** (2 / ex) * (b + inset)
        pts.append((sx, sy + yc, z))
    return pts


def build_waist_guard(coll):
    """Invisible sloped collar from the waist skin out over the belt. The
    shirt hem slides over it instead of slipping into the waistband gap."""
    import garments as GM
    from sdf_core import Loft
    body = Loft(AN.TORSO_KEYS)
    pants = Loft(GM.PANTS_KEYS)
    n = 96
    rows = [profile_ring(body, 1.035, -0.006, n), profile_ring(body, 1.012, 0.004, n),
            profile_ring(pants, 0.983, 0.011, n), profile_ring(pants, 0.972, 0.011, n)]
    V = [p for r in rows for p in r]
    F = []
    for r in range(len(rows) - 1):
        for k in range(n):
            a = r * n + k
            b = r * n + (k + 1) % n
            F.append((a, a + n, b + n, b))
    ob = make_mesh("Collision_WaistGuard", np.array(V), F, coll)
    recalc_normals(ob)
    ob.display_type = 'WIRE'
    ob.hide_render = True
    return ob


def build_belt(coll):
    import garments as GM
    from sdf_core import Loft
    lo = Loft(GM.PANTS_KEYS)
    n = 96
    V, F = [], []
    zs = [0.951, 0.957, 0.979, 0.985]
    insets = [0.0005, 0.004, 0.004, 0.0005]
    for z, ins in zip(zs, insets):
        a, bf, bb, yc, ex = [float(t[0]) for t in lo.profile(np.array([z]))]
        for k in range(n):
            th = 2 * np.pi * k / n
            cx, cy = np.sin(th), -np.cos(th)
            b = bf if cy < 0 else bb
            # super-ellipse point
            sx = np.sign(cx) * abs(cx) ** (2 / ex) * (a + ins)
            sy = np.sign(cy) * abs(cy) ** (2 / ex) * (b + ins)
            V.append((sx, sy + yc, z))
    for r in range(len(zs) - 1):
        for k in range(n):
            a = r * n + k
            b = r * n + (k + 1) % n
            F.append((a, b, b + n, a + n))
    belt = make_mesh("Belt", np.array(V), F, coll)
    recalc_normals(belt)
    sol = belt.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = 0.003
    sub = belt.modifiers.new("Subdivision", 'SUBSURF')
    sub.levels = 1
    sub.render_levels = 2
    # buckle
    a, bf, bb, yc, ex = [float(t[0]) for t in lo.profile(np.array([0.968]))]
    bsc = S.SDFScene()
    bsc.add(S.RoundBox((0, yc - bf - 0.008, 0.968), (0.020, 0.002, 0.0145), 0.0025))
    bsc.sub(S.RoundBox((0, yc - bf - 0.012, 0.968), (0.013, 0.006, 0.008), 0.001), 0.001)
    bv, bq = S.surface_nets(bsc, 0.0008, verbose=False)
    bv, bq = S.mesh_cleanup(bv, bq)
    buckle = make_mesh("Belt_Buckle", bv, bq, coll)
    return belt, buckle


def build_shoes(coll):
    import garments as GM
    shoes = []
    for s, nm in ((1, "L"), (-1, "R")):
        v, q = S.surface_nets(GM.shoe_scene(s), 0.0022, verbose=False)
        v, q = S.mesh_cleanup(v, q)
        ob = make_mesh(f"Shoe.{nm}", v, q, coll)
        dec = ob.modifiers.new("Decimate", 'DECIMATE')
        dec.ratio = min(1.0, 12000 / max(1, len(q) * 2))
        apply_modifiers(ob)
        shoes.append(ob)
    return shoes


def build_buttons(coll, shirt, mat):
    """Buttons vertex-parented to the shirt so they ride on the cloth."""
    me = shirt.data
    v = mesh_arrays(me)
    kd = KDTree(len(v))
    for i, p in enumerate(v):
        kd.insert(p, i)
    kd.balance()
    out = []
    for i, z in enumerate((1.300, 1.205, 1.110, 1.015, 0.920, 0.825)):
        cand = v[(np.abs(v[:, 0]) < 0.03) & (v[:, 1] < 0) & (np.abs(v[:, 2] - z) < 0.03)]
        if not len(cand):
            continue
        p = cand[np.argmin(np.abs(cand[:, 0]) + np.abs(cand[:, 2] - z))].copy()
        p[0] = 0.0
        p[1] -= 0.0035
        bsc = S.SDFScene()
        bsc.add(S.Ellipsoid(p, (0.0058, 0.0016, 0.0058)))
        for dx in (-0.0016, 0.0016):
            for dz in (-0.0016, 0.0016):
                bsc.sub(S.Capsule(p + np.array([dx, -0.004, dz]), p + np.array([dx, 0.004, dz]), 0.0006))
        bv, bq = S.surface_nets(bsc, 0.0005, verbose=False)
        bv, bq = S.mesh_cleanup(bv, bq)
        b = make_mesh(f"Shirt_Button.{i:02d}", bv, bq, coll)
        b.data.materials.append(mat)
        near = [idx for (_, idx, _) in kd.find_n(p, 3)]
        out.append((b, near))
    return out


# =============================================================================
# RIG
# =============================================================================
FINGERS = ('thumb', 'index', 'middle', 'ring', 'pinky')


def V(p):
    return Vector((float(p[0]), float(p[1]), float(p[2])))


def widget_meshes(coll):
    """Custom bone shapes for the controls."""
    w = {}
    n = 32
    circ = [(math.cos(2 * math.pi * i / n), 0.0, math.sin(2 * math.pi * i / n)) for i in range(n)]
    me = bpy.data.meshes.new("WGT_Circle")
    me.from_pydata(circ, [(i, (i + 1) % n) for i in range(n)], [])
    w['circle'] = bpy.data.objects.new("WGT_Circle", me)
    cube_v = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    cube_e = [(0, 1), (0, 2), (0, 4), (1, 3), (1, 5), (2, 3), (2, 6), (3, 7), (4, 5), (4, 6), (5, 7), (6, 7)]
    me = bpy.data.meshes.new("WGT_Cube")
    me.from_pydata(cube_v, cube_e, [])
    w['cube'] = bpy.data.objects.new("WGT_Cube", me)
    sv, se = [], []
    for ax in range(3):
        base = len(sv)
        for i in range(n):
            a = 2 * math.pi * i / n
            p = [0.0, 0.0, 0.0]
            p[(ax + 1) % 3] = math.cos(a)
            p[(ax + 2) % 3] = math.sin(a)
            sv.append(tuple(p))
            se.append((base + i, base + (i + 1) % n))
    me = bpy.data.meshes.new("WGT_Sphere")
    me.from_pydata(sv, se, [])
    w['sphere'] = bpy.data.objects.new("WGT_Sphere", me)
    # hand: a box-ish paddle outline
    pv = [(-0.5, 0, -0.15), (-0.5, 1.2, -0.15), (0.5, 1.2, -0.15), (0.5, 0, -0.15),
          (-0.5, 0, 0.15), (-0.5, 1.2, 0.15), (0.5, 1.2, 0.15), (0.5, 0, 0.15)]
    pe = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4), (0, 4), (1, 5), (2, 6), (3, 7)]
    me = bpy.data.meshes.new("WGT_Paddle")
    me.from_pydata(pv, pe, [])
    w['paddle'] = bpy.data.objects.new("WGT_Paddle", me)
    for o in w.values():
        coll.objects.link(o)
    return w


def build_rig(coll, wgt_coll):
    J = AN.SK.J
    arm = bpy.data.armatures.new("Power_Rig")
    arm.display_type = 'OCTAHEDRAL'
    rig = bpy.data.objects.new("Power_Rig", arm)
    link(rig, coll)
    rig.show_in_front = True
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.edit_bones

    def bone(name, head, tail, parent=None, connect=False, deform=True, roll_to=None):
        b = eb.new(name)
        b.head = V(head)
        b.tail = V(tail)
        if roll_to is not None:
            b.align_roll(V(roll_to))
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        b.use_deform = deform
        return b

    fwd = (0, -1, 0)
    bone("root", (0, 0, 0), (0, 0.30, 0), deform=False, roll_to=(0, 0, 1))
    bone("hips", J['pelvis'] + np.array([0, 0, -0.05]), J['pelvis'] + np.array([0, 0.0, 0.07]), "root",
         roll_to=fwd)
    bone("spine", J['pelvis'] + np.array([0, 0, 0.07]), J['chest'], "hips", connect=True, roll_to=fwd)
    bone("chest", J['chest'], J['upper_chest'], "spine", connect=True, roll_to=fwd)
    bone("upper_chest", J['upper_chest'], J['neck'], "chest", connect=True, roll_to=fwd)
    bone("neck", J['neck'], J['head'], "upper_chest", connect=True, roll_to=fwd)
    bone("head", J['head'], J['head_top'], "neck", connect=True, roll_to=fwd)
    for s, sfx in ((1, ".L"), (-1, ".R")):
        m = (lambda p: np.asarray(p, float)) if s > 0 else AN.mirror
        sh, el, wr = m(J['shoulder']), m(J['elbow']), m(J['wrist'])
        bone("shoulder" + sfx, m(J['clavicle_in']), sh + np.array([-0.012 * s, 0, 0.012]), "upper_chest",
             roll_to=(0, 0, 1))
        # elbow bends backwards -> roll so X points down the bend axis
        bone("upper_arm" + sfx, sh, el, "shoulder" + sfx, roll_to=(0, 1, 0))
        bone("forearm" + sfx, el, wr, "upper_arm" + sfx, connect=True, roll_to=(0, 1, 0))
        hj = AN.hand_joints(s)
        dorsal = -hj['R'][:, 2]
        bone("hand" + sfx, wr, hj['palm'], "forearm" + sfx, connect=True, roll_to=dorsal)
        for f in FINGERS:
            pts = hj[f]
            for i in range(3):
                parent = "hand" + sfx if i == 0 else f"{f}.{i:02d}{sfx}"
                bone(f"{f}.{i + 1:02d}{sfx}", pts[i], pts[i + 1], parent, connect=(i > 0), roll_to=dorsal)
        # legs
        hip, kn, an = m(J['hip']), m(J['knee']), m(J['ankle'])
        ball, toe = m(J['ball']), m(J['toe'])
        bone("thigh" + sfx, hip, kn, "hips", roll_to=fwd)
        bone("shin" + sfx, kn, an, "thigh" + sfx, connect=True, roll_to=fwd)
        bone("foot" + sfx, an, ball + np.array([0, 0, 0.01]), "shin" + sfx, connect=True, roll_to=(0, 0, 1))
        bone("toe" + sfx, ball + np.array([0, 0, 0.01]), toe + np.array([0, 0, 0.01]), "foot" + sfx,
             connect=True, roll_to=(0, 0, 1))
        # ---- controls
        hb = eb["hand" + sfx]
        c = bone("IK_hand" + sfx, hb.head, hb.tail, "root", deform=False)
        c.roll = hb.roll
        bone("pole_arm" + sfx, el + np.array([0, 0.32, 0]), el + np.array([0, 0.37, 0]), "root", deform=False)
        fb = eb["foot" + sfx]
        c = bone("IK_foot" + sfx, fb.head, fb.tail, "root", deform=False)
        c.roll = fb.roll
        bone("pole_leg" + sfx, kn + np.array([0, -0.45, 0]), kn + np.array([0, -0.50, 0]), "root", deform=False)
    bpy.ops.object.mode_set(mode='OBJECT')

    # ---- constraints, drivers, custom shapes, colours
    pb = rig.pose.bones
    for sfx in (".L", ".R"):
        ik = pb["forearm" + sfx].constraints.new('IK')
        ik.target = rig
        ik.subtarget = "IK_hand" + sfx
        ik.pole_target = rig
        ik.pole_subtarget = "pole_arm" + sfx
        ik.chain_count = 2
        cr = pb["hand" + sfx].constraints.new('COPY_ROTATION')
        cr.target = rig
        cr.subtarget = "IK_hand" + sfx
        ik = pb["shin" + sfx].constraints.new('IK')
        ik.target = rig
        ik.subtarget = "IK_foot" + sfx
        ik.pole_target = rig
        ik.pole_subtarget = "pole_leg" + sfx
        ik.chain_count = 2
        cr = pb["foot" + sfx].constraints.new('COPY_ROTATION')
        cr.target = rig
        cr.subtarget = "IK_foot" + sfx
        # grip slider on the hand control
        ctl = pb["IK_hand" + sfx]
        ctl["grip"] = 0.0
        ui = ctl.id_properties_ui("grip")
        ui.update(min=0.0, max=1.0, soft_min=0.0, soft_max=1.0, description="0 = open hand, 1 = fist")
        ctl["spread"] = 0.0
        ui = ctl.id_properties_ui("spread")
        ui.update(min=-1.0, max=1.0, description="Finger spread")
    fix_pole_angles(rig)
    finger_drivers(rig)
    style_rig(rig, wgt_coll)
    return rig


def _pose_error(rig, names):
    bpy.context.view_layer.update()
    err = 0.0
    for n in names:
        pbn = rig.pose.bones[n]
        err += (pbn.matrix.to_translation() - pbn.bone.matrix_local.to_translation()).length
        err += (pbn.tail - pbn.bone.tail_local).length
    return err


def fix_pole_angles(rig):
    """Pick IK pole angles that keep the modelled rest pose exactly."""
    for chain, ctl in (("forearm", "upper_arm"), ("shin", "thigh")):
        for sfx in (".L", ".R"):
            c = rig.pose.bones[chain + sfx].constraints[0]
            names = [chain + sfx, ctl + sfx]
            best = min(((_set_pole(c, a, rig, names), a) for a in np.radians(np.arange(-180, 180, 5))))
            lo, hi = best[1] - math.radians(5), best[1] + math.radians(5)
            for _ in range(30):
                m1, m2 = lo + (hi - lo) / 3, hi - (hi - lo) / 3
                if _set_pole(c, m1, rig, names) < _set_pole(c, m2, rig, names):
                    hi = m2
                else:
                    lo = m1
            err = _set_pole(c, 0.5 * (lo + hi), rig, names)
            log(f"  pole {chain}{sfx}: {math.degrees(c.pole_angle):.1f} deg (rest error {err * 1000:.2f} mm)")


def _set_pole(c, a, rig, names):
    c.pole_angle = float(a)
    return _pose_error(rig, names)


def _tip_after(rig, bone, tip_bone, axis, ang):
    b = rig.pose.bones[bone]
    b.rotation_mode = 'XYZ'
    e = [0.0, 0.0, 0.0]
    e[axis] = ang
    b.rotation_euler = e
    bpy.context.view_layer.update()
    p = rig.pose.bones[tip_bone].tail.copy()
    b.rotation_euler = (0, 0, 0)
    bpy.context.view_layer.update()
    return p


def _best_axis(rig, bone, tip_bone, goal, axes=(0, 2)):
    """Axis/sign whose positive rotation moves the finger tip toward `goal`."""
    bpy.context.view_layer.update()
    p0 = rig.pose.bones[tip_bone].tail.copy()
    best = None
    for ax in axes:
        for sg in (1.0, -1.0):
            p = _tip_after(rig, bone, tip_bone, ax, 0.5 * sg)
            gain = (goal - p0).length - (goal - p).length
            if best is None or gain > best[0]:
                best = (gain, ax, sg)
    return best[1], best[2]


def _add_driver(rig, bone, axis, prop, sfx, expr_factor):
    b = rig.pose.bones[bone]
    b.rotation_mode = 'XYZ'
    fc = b.driver_add("rotation_euler", axis)
    d = fc.driver
    d.type = 'SCRIPTED'
    var = d.variables.new()
    var.name = prop
    var.type = 'SINGLE_PROP'
    var.targets[0].id = rig
    var.targets[0].data_path = f'pose.bones["IK_hand{sfx}"]["{prop}"]'
    d.expression = f"{prop}*{expr_factor:.3f}"


def finger_drivers(rig):
    """grip (0..1) curls every finger joint, spread fans the fingers.
    Rotation axes/signs are measured on the actual rig, so they are right
    for both hands regardless of bone roll."""
    pb = rig.pose.bones
    bpy.context.view_layer.update()
    curls = {'thumb': (0.55, 0.65, 0.85), 'index': (1.25, 1.55, 1.05), 'middle': (1.30, 1.60, 1.10),
             'ring': (1.30, 1.65, 1.10), 'pinky': (1.35, 1.65, 1.10)}
    spread = {'thumb': 0.30, 'index': 0.16, 'middle': 0.0, 'ring': 0.12, 'pinky': 0.26}
    for sfx, s in ((".L", 1), (".R", -1)):
        hj = AN.hand_joints(s)
        palm_n = V(hj['R'][:, 2])
        for f in FINGERS:
            tipb = f"{f}.03{sfx}"
            used = None
            for i in range(3):
                bn = f"{f}.{i + 1:02d}{sfx}"
                if f == 'thumb':
                    # thumb folds across the palm toward the base of the ring finger
                    goal = V(hj['ring'][0]) + palm_n * 0.025
                    ax, sg = _best_axis(rig, bn, tipb, goal)
                else:
                    goal = pb[bn].head + palm_n * 0.08 - V(hj['R'][:, 0]) * 0.02
                    ax, sg = _best_axis(rig, bn, tipb, goal, axes=(0,))
                _add_driver(rig, bn, ax, "grip", sfx, sg * curls[f][i])
                if i == 0:
                    used = ax
            if f in ('middle',):
                continue
            # spread: away from the middle finger
            mid = V(hj['middle'][3])
            away = (pb[tipb].tail - mid)
            goal = pb[tipb].tail + away.normalized() * 0.05
            bn = f"{f}.01{sfx}"
            free_axes = tuple(a for a in (0, 2) if a != used) if f == 'thumb' else (2,)
            ax, sg = _best_axis(rig, bn, tipb, goal, axes=free_axes)
            _add_driver(rig, bn, ax, "spread", sfx, sg * spread[f])


def style_rig(rig, wgt_coll):
    w = widget_meshes(wgt_coll)
    arm = rig.data
    try:
        bc_ctl = arm.collections.new("Controls")
        bc_def = arm.collections.new("Deform")
        bc_fing = arm.collections.new("Fingers")
    except AttributeError:  # very old API - skip collections
        bc_ctl = bc_def = bc_fing = None
    pb = rig.pose.bones
    for b in pb:
        nm = b.name
        if nm.startswith(("IK_", "pole_", "root")):
            if bc_ctl:
                bc_ctl.assign(b.bone)
        elif nm.split('.')[0] in FINGERS:
            if bc_fing:
                bc_fing.assign(b.bone)
        else:
            if bc_def:
                bc_def.assign(b.bone)

    def shape(name, wg, scale, color, rot=None, trans=None):
        b = pb[name]
        b.custom_shape = w[wg]
        b.custom_shape_scale_xyz = scale
        if rot:
            b.custom_shape_rotation_euler = rot
        if trans:
            b.custom_shape_translation = trans
        try:
            b.color.palette = color
        except AttributeError:
            pass
    shape("root", 'circle', (1.4, 1.4, 1.4), 'THEME09', rot=(math.pi / 2, 0, 0))
    for sfx, col in ((".L", 'THEME01'), (".R", 'THEME03')):
        shape("IK_hand" + sfx, 'paddle', (0.9, 1.0, 1.0), col)
        shape("IK_foot" + sfx, 'cube', (0.5, 1.0, 0.3), col, trans=(0, 0.05, -0.02))
        shape("pole_arm" + sfx, 'sphere', (0.4, 0.4, 0.4), col)
        shape("pole_leg" + sfx, 'sphere', (0.4, 0.4, 0.4), col)
    for b in pb:
        if b.name.split('.')[0] in ("hips", "spine", "chest", "upper_chest", "neck", "head"):
            b.custom_shape = w['circle']
            b.custom_shape_scale_xyz = (2.2, 2.2, 2.2) if b.name != "neck" else (1.2, 1.2, 1.2)
            b.custom_shape_rotation_euler = (0, 0, 0)
            try:
                b.color.palette = 'THEME04'
            except AttributeError:
                pass
    # lock what should not move
    for sfx in (".L", ".R"):
        for n in ("pole_arm", "pole_leg"):
            pb[n + sfx].lock_rotation = (True, True, True)
            pb[n + sfx].lock_scale = (True, True, True)
    for b in pb:
        b.rotation_mode = 'XYZ' if b.name.split('.')[0] in FINGERS else 'QUATERNION'


# =============================================================================
# SKINNING
# =============================================================================
def select_only(objs, active):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


def read_weights(ob):
    names = [g.name for g in ob.vertex_groups]
    W = np.zeros((len(ob.data.vertices), len(names)), np.float32)
    for v in ob.data.vertices:
        for g in v.groups:
            W[v.index, g.group] = g.weight
    return names, W


def write_weights(ob, names, W, limit=4):
    groups = {}
    for n in names:
        groups[n] = ob.vertex_groups.get(n) or ob.vertex_groups.new(name=n)
    if limit:
        idx = np.argsort(-W, axis=1)[:, limit:]
        np.put_along_axis(W, idx, 0.0, axis=1)
    W = W / np.maximum(W.sum(1, keepdims=True), 1e-9)
    for gi, n in enumerate(names):
        col = W[:, gi]
        nz = np.nonzero(col > 1e-4)[0]
        if len(nz) == 0:
            continue
        g = groups[n]
        for w in np.unique(np.round(col[nz], 3)):
            ids = nz[np.round(col[nz], 3) == w].tolist()
            g.add(ids, float(w), 'REPLACE')


def nearest_weights(src_v, src_W, dst_v, k=6):
    kd = KDTree(len(src_v))
    for i, p in enumerate(src_v):
        kd.insert(p, i)
    kd.balance()
    out = np.zeros((len(dst_v), src_W.shape[1]), np.float32)
    for i, p in enumerate(dst_v):
        hits = kd.find_n(p, k)
        ws = np.array([1.0 / (d * d + 1e-6) for (_, _, d) in hits])
        ids = [j for (_, j, _) in hits]
        out[i] = (src_W[ids] * ws[:, None]).sum(0) / ws.sum()
    return out


def skin_body(rig, body):
    log("automatic (heat) weights for the body")
    select_only([body, rig], rig)
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    names, W = read_weights(body)
    bad = np.nonzero(W.sum(1) < 1e-3)[0]
    log(f"  {len(bad)} vertices without weights")
    if len(bad):
        # fill holes from weighted neighbours
        v = mesh_arrays(body.data)
        good = np.nonzero(W.sum(1) >= 1e-3)[0]
        W[bad] = nearest_weights(v[good], W[good], v[bad], k=8)
        for g in body.vertex_groups:
            g.remove(range(len(v)))
        write_weights(body, names, W)
    mod = body.modifiers.get("Armature")
    if mod:
        mod.use_deform_preserve_volume = True
    return names


def armature_bind(ob, rig, names, W):
    ob.parent = rig
    ob.matrix_parent_inverse = rig.matrix_world.inverted()
    write_weights(ob, names, W)
    m = ob.modifiers.new("Armature", 'ARMATURE')
    m.object = rig
    # armature must come first in the stack
    i = ob.modifiers.find("Armature")
    if i > 0:
        ob.modifiers.move(i, 0)
    return m


def bind_like_body(ob, rig, body_v, body_names, body_W):
    v = mesh_arrays(ob.data) if ob.type == 'MESH' else None
    W = nearest_weights(body_v, body_W, v)
    armature_bind(ob, rig, body_names, W)


def parent_to_bone(ob, rig, bone):
    mw = ob.matrix_world.copy()
    ob.parent = rig
    ob.parent_type = 'BONE'
    ob.parent_bone = bone
    bpy.context.view_layer.update()
    ob.matrix_world = mw


def make_collider(body, rig, coll, faces=14000):
    log("building low-poly collision body")
    col = body.copy()
    col.data = body.data.copy()
    col.name = "Collision_Body"
    col.data.name = "Collision_Body"
    for m in list(col.modifiers):
        col.modifiers.remove(m)
    coll.objects.link(col)
    dec = col.modifiers.new("Decimate", 'DECIMATE')
    dec.ratio = faces / len(body.data.polygons)
    apply_modifiers(col)
    col.data.materials.clear()
    for a in list(col.data.attributes):
        if a.name in ("lips", "nails", "underwear"):
            col.data.attributes.remove(a)
    m = col.modifiers.new("Armature", 'ARMATURE')
    m.object = rig
    col.parent = rig
    col.modifiers.new("Collision", 'COLLISION')
    col.collision.thickness_outer = 0.007
    col.collision.thickness_inner = 0.006
    col.collision.cloth_friction = 3.0
    col.collision.damping = 0.2
    # single sided + normal override: cloth that ends up inside the body is
    # pushed back out instead of getting stuck (fast arm moves)
    col.collision.use_culling = True
    col.collision.use_normal = True
    col.display_type = 'WIRE'
    col.hide_render = True
    col.hide_viewport = False
    col.hide_set(True)
    return col


# =============================================================================
# CLOTH PHYSICS
# =============================================================================
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def set_group(ob, name, w):
    g = ob.vertex_groups.get(name) or ob.vertex_groups.new(name=name)
    w = np.clip(np.asarray(w, float), 0, 1)
    for val in np.unique(np.round(w, 3)):
        ids = np.nonzero(np.round(w, 3) == val)[0].tolist()
        if val > 0:
            g.add(ids, float(val), 'REPLACE')
    return g


def add_cloth(ob, pin_group, col_coll, quality=5, mass=0.22, tension=12.0, bending=0.12,
              self_collision=True, air=1.2, friction=2.0, shrink=0.0, pin_stiffness=0.15):
    cl = ob.modifiers.new("Cloth", 'CLOTH')
    st = cl.settings
    st.quality = quality
    st.mass = mass
    st.air_damping = air
    st.tension_stiffness = tension
    st.compression_stiffness = tension
    st.shear_stiffness = tension * 0.4
    st.bending_stiffness = bending
    st.tension_damping = 5.0
    st.compression_damping = 5.0
    st.shear_damping = 5.0
    st.bending_damping = 0.5
    st.vertex_group_mass = pin_group
    st.pin_stiffness = pin_stiffness  # soft goals (weights < 1) stay gentle
    st.shrink_min = shrink   # negative = a bit more fabric than the pattern -> folds
    try:
        st.bending_model = 'ANGULAR'
    except Exception:
        pass
    cs = cl.collision_settings
    cs.use_collision = True
    cs.collision_quality = 3
    cs.distance_min = 0.005
    cs.impulse_clamp = 0.0
    cs.collection = col_coll
    cs.use_self_collision = self_collision
    cs.self_distance_min = 0.003
    cs.self_friction = friction
    cs.friction = friction
    pc = cl.point_cache
    pc.frame_start = 1
    pc.frame_end = 250
    return cl


def finish_stack(ob, thickness, subdiv=1, collide=False):
    if collide:
        ob.modifiers.new("Collision", 'COLLISION')
        ob.collision.thickness_outer = 0.004
        ob.collision.thickness_inner = 0.002
        ob.collision.cloth_friction = 0.8   # lets the shirt slide back down
        # single sided: fabric that slips behind this garment is pushed back out
        ob.collision.use_culling = True
        ob.collision.use_normal = True
    sol = ob.modifiers.new("Solidify", 'SOLIDIFY')
    sol.thickness = thickness
    sol.offset = 0.0
    sub = ob.modifiers.new("Subdivision", 'SUBSURF')
    sub.levels = subdiv
    sub.render_levels = 2


# =============================================================================
# CLOTH MATERIALS
# =============================================================================
def seam_lines(nt, specs, loc=(-900, -200)):
    """specs: list of (attribute, offset, half_width). Returns a 0..1 socket."""
    acc = None
    x, y = loc
    for i, (attr, off, hw) in enumerate(specs):
        a = node(nt, 'ShaderNodeAttribute', (x - 600, y - 160 * i), attribute_name=attr)
        sub = node(nt, 'ShaderNodeMath', (x - 420, y - 160 * i), operation='SUBTRACT')
        sub.inputs[1].default_value = off
        nt.links.new(a.outputs['Fac'], sub.inputs[0])
        ab = node(nt, 'ShaderNodeMath', (x - 260, y - 160 * i), operation='ABSOLUTE')
        nt.links.new(sub.outputs[0], ab.inputs[0])
        mr = node(nt, 'ShaderNodeMapRange', (x - 100, y - 160 * i))
        mr.inputs['From Min'].default_value = hw * 0.4
        mr.inputs['From Max'].default_value = hw
        mr.inputs['To Min'].default_value = 1.0
        mr.inputs['To Max'].default_value = 0.0
        nt.links.new(ab.outputs[0], mr.inputs['Value'])
        if acc is None:
            acc = mr.outputs['Result']
        else:
            mx = node(nt, 'ShaderNodeMath', (x + 80, y - 160 * i), operation='MAXIMUM')
            nt.links.new(acc, mx.inputs[0])
            nt.links.new(mr.outputs['Result'], mx.inputs[1])
            acc = mx.outputs[0]
    return acc


def fabric_material(name, color, rough, sheen, weave_scale, seams=None, seam_dark=0.75, sss=0.0):
    m = principled(name, color, rough=rough, sheen=sheen, sss=sss, sss_radius=(0.2, 0.2, 0.2), spec=0.3)
    nt = m.node_tree
    b = bsdf(m)
    uv = node(nt, 'ShaderNodeUVMap', (-1500, -500))
    w1 = node(nt, 'ShaderNodeTexWave', (-1200, -450), Scale=weave_scale, Distortion=0.0, Detail=0.0)
    w1.bands_direction = 'X'
    w2 = node(nt, 'ShaderNodeTexWave', (-1200, -700), Scale=weave_scale, Distortion=0.0, Detail=0.0)
    w2.bands_direction = 'Y'
    nt.links.new(uv.outputs['UV'], w1.inputs['Vector'])
    nt.links.new(uv.outputs['UV'], w2.inputs['Vector'])
    weave = node(nt, 'ShaderNodeMath', (-950, -550), operation='MULTIPLY')
    nt.links.new(w1.outputs['Fac'], weave.inputs[0])
    nt.links.new(w2.outputs['Fac'], weave.inputs[1])
    height = weave.outputs[0]
    col = srgb(color)
    if seams:
        line = seam_lines(nt, seams, loc=(-700, 300))
        mix = node(nt, 'ShaderNodeMix', (-300, 300), data_type='RGBA')
        mix.inputs[6].default_value = col
        mix.inputs[7].default_value = tuple(c * seam_dark for c in col[:3]) + (1.0,)
        nt.links.new(line, mix.inputs['Factor'])
        nt.links.new(mix.outputs[2], b.inputs['Base Color'])
        hmix = node(nt, 'ShaderNodeMath', (-700, -550), operation='MULTIPLY_ADD')
        nt.links.new(line, hmix.inputs[0])
        hmix.inputs[1].default_value = -0.6
        nt.links.new(weave.outputs[0], hmix.inputs[2])
        height = hmix.outputs[0]
    add_bump(m, height, strength=0.12, distance=0.0008)
    return m


def clothing_materials():
    M = {}
    M['shirt'] = fabric_material(
        "Shirt_Cotton", (0.86, 0.87, 0.885), 0.82, 0.45, 900.0, sss=0.04,
        seams=[("placket", 0.0, 0.0011), ("placket", 0.0045, 0.0007), ("hem", 0.012, 0.0008),
               ("pocket", 0.0, 0.0008), ("pocket", 0.004, 0.0006),
               ("cuff", 0.006, 0.0008), ("cuff", 0.052, 0.0010)], seam_dark=0.82)
    M['shirt_plain'] = fabric_material("Shirt_Cotton_Plain", (0.86, 0.87, 0.885), 0.82, 0.45, 900.0)
    M['pants'] = fabric_material(
        "Trousers_Wool", (0.040, 0.040, 0.046), 0.68, 0.35, 700.0,
        seams=[("seam", 0.0, 0.012), ("crease", 0.0, 0.0012), ("hem", 0.025, 0.0009)], seam_dark=1.8)
    M['tie'] = fabric_material("Necktie_Silk", (0.018, 0.018, 0.022), 0.32, 0.6, 500.0)
    M['leather'] = principled("Belt_Leather", (0.025, 0.022, 0.022), rough=0.38, coat=0.25)
    M['shoes'] = principled("Shoe_Leather", (0.02, 0.02, 0.022), rough=0.22, coat=0.7)
    M['metal'] = principled("Buckle_Metal", (0.82, 0.82, 0.84), rough=0.22, metal=1.0)
    M['button'] = principled("Button_Plastic", (0.95, 0.94, 0.90), rough=0.25, coat=0.3)
    return M


# =============================================================================
# SCENE: lights, camera, floor, render settings
# =============================================================================
def build_environment(coll, floor_z):
    sc = bpy.context.scene
    # floor
    me = bpy.data.meshes.new("Floor")
    s = 4.0
    me.from_pydata([(-s, -s, floor_z), (s, -s, floor_z), (s, s, floor_z), (-s, s, floor_z)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("Floor", me)
    link(floor, coll)
    fm = principled("Floor", (0.42, 0.43, 0.45), rough=0.55)
    nt = fm.node_tree
    tc = node(nt, 'ShaderNodeTexCoord', (-900, 0))
    gr = node(nt, 'ShaderNodeTexGradient', (-700, 0))
    gr.gradient_type = 'SPHERICAL'
    mp = node(nt, 'ShaderNodeMapping', (-800, 0))
    mp.inputs['Scale'].default_value = (0.3, 0.3, 0.3)
    nt.links.new(tc.outputs['Object'], mp.inputs['Vector'])
    nt.links.new(mp.outputs['Vector'], gr.inputs['Vector'])
    ramp = node(nt, 'ShaderNodeValToRGB', (-450, 0))
    ramp.color_ramp.elements[0].color = srgb((0.20, 0.21, 0.23))
    ramp.color_ramp.elements[1].color = srgb((0.55, 0.56, 0.58))
    nt.links.new(gr.outputs['Fac'], ramp.inputs['Fac'])
    nt.links.new(ramp.outputs['Color'], bsdf(fm).inputs['Base Color'])
    me.materials.append(fm)
    floor.modifiers.new("Collision", 'COLLISION')
    floor.collision.cloth_friction = 8.0

    def light(name, kind, loc, rot, energy, size=1.0, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == 'AREA':
            ld.size = size
        ob = bpy.data.objects.new(name, ld)
        ob.location = loc
        ob.rotation_euler = rot
        link(ob, coll)
        return ob
    light("Key_Light", 'AREA', (-1.6, -2.2, 2.6), (math.radians(50), 0, math.radians(-35)), 380, 1.6,
          (1.0, 0.96, 0.92))
    light("Fill_Light", 'AREA', (2.2, -1.6, 1.4), (math.radians(70), 0, math.radians(55)), 120, 2.5,
          (0.85, 0.9, 1.0))
    light("Rim_Light", 'AREA', (0.9, 2.2, 2.4), (math.radians(-55), 0, math.radians(160)), 420, 1.2,
          (1.0, 0.75, 0.7))
    # camera
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    link(cam, coll)
    cam.data.lens = 55
    cam.location = (1.55, -4.3, 1.25)
    tgt = Vector((0.0, 0.0, 0.86))
    cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    # world
    w = bpy.data.worlds.new("Studio")
    sc.world = w
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = srgb((0.30, 0.32, 0.36))
    bg.inputs[1].default_value = 0.45
    # render
    try:
        sc.render.engine = 'BLENDER_EEVEE_NEXT'
    except TypeError:
        sc.render.engine = 'BLENDER_EEVEE'
    try:
        sc.eevee.use_shadows = True
        sc.eevee.use_raytracing = True
        sc.eevee.taa_render_samples = 64
    except AttributeError:
        pass
    sc.cycles.samples = 128
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 1920
    sc.render.resolution_y = 1080
    sc.render.fps = 24
    sc.frame_start = 1
    sc.frame_end = 250
    try:
        sc.view_settings.view_transform = 'AgX'
        sc.view_settings.look = 'AgX - Medium High Contrast'
    except TypeError:
        pass
    return floor, cam


# =============================================================================
# PRE-DRAPE + DEMO ANIMATION
# =============================================================================
def cloth_mods(ob):
    return [m for m in ob.modifiers if m.type == 'CLOTH']


def predrape(cloth_objs, frames=45):
    """Let the cloth settle in the rest pose, then store that as a shape key so
    the file opens with the clothes already hanging naturally."""
    sc = bpy.context.scene
    log(f"pre-draping cloth for {frames} frames")
    after = {}
    for ob in cloth_objs:
        ci = ob.modifiers.find("Cloth")
        after[ob.name] = [m for i, m in enumerate(ob.modifiers) if i > ci and m.type != 'COLLISION']
        for m in after[ob.name]:
            m.show_viewport = False
    t = time.time()
    for f in range(1, frames + 1):
        sc.frame_set(f)
    log(f"  {(time.time() - t) / frames:.2f} s/frame")
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in cloth_objs:
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        co = np.zeros(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        ev.to_mesh_clear()
        if len(co) != len(ob.data.vertices) * 3:
            log("  !! vertex count changed for", ob.name)
            continue
        if not ob.data.shape_keys:
            ob.shape_key_add(name="Basis (sewing pattern)", from_mix=False)
        k = ob.shape_key_add(name="Draped", from_mix=False)
        k.data.foreach_set("co", co)
        k.value = 1.0
        cl = ob.modifiers["Cloth"]
        cl.settings.rest_shape_key = ob.data.shape_keys.key_blocks[0]
        for m in after[ob.name]:
            m.show_viewport = True
    sc.frame_set(1)
    for ob in cloth_objs:
        for m in cloth_mods(ob):
            m.point_cache.frame_end = 250  # touching the cache settings frees it


def key_pose(rig, frame, poses, hips_z=0.0, shoulder_up=(0.0, 0.0)):
    """poses: dict ctl -> (world position or None, rotation Matrix3 delta or None, grip)"""
    pb = rig.pose.bones
    for name, (pos, rot, grip) in poses.items():
        b = pb[name]
        rest = b.bone.matrix_local.copy()
        M = rest.copy()
        if rot is not None:
            M = Matrix.Translation(rest.to_translation()) @ rot.to_4x4() @ Matrix.Translation(
                -rest.to_translation()) @ M
        if pos is not None:
            M.translation = V(pos)
        b.matrix = M
        bpy.context.view_layer.update()
        b.keyframe_insert("location", frame=frame)
        b.keyframe_insert("rotation_quaternion", frame=frame)
        if grip is not None:
            b["grip"] = grip
            b.keyframe_insert('["grip"]', frame=frame)
    h = pb["hips"]
    # hips bone points up: its local Y is world Z
    h.location = (0, hips_z, 0)
    h.keyframe_insert("location", frame=frame)
    for sfx, up in ((".L", shoulder_up[0]), (".R", shoulder_up[1])):
        b = pb["shoulder" + sfx]
        b.rotation_quaternion = Euler((up, 0, 0)).to_quaternion()
        b.keyframe_insert("rotation_quaternion", frame=frame)


def hand_rot(s, fingers, palm):
    """World rotation taking the rest hand frame to (fingers, palm normal)."""
    R0 = AN.hand_joints(s)['R']
    f0, n0 = R0[:, 0], R0[:, 2]
    A = np.stack([f0, np.cross(n0, f0), n0], 1)
    f1 = S.norm(fingers)
    n1 = S.norm(np.asarray(palm, float) - f1 * (f1 @ np.asarray(palm, float)))
    B = np.stack([f1, np.cross(n1, f1), n1], 1)
    return Matrix((B @ A.T).tolist())


def demo_animation(rig):
    """A short demo: wave, grab, arms up, a little squat - press Play."""
    J = AN.SK.J
    wl = np.asarray(J['wrist'])
    wr = AN.mirror(J['wrist'])
    restL = (wl, None, 0.0)
    restR = (wr, None, 0.0)
    waveA = hand_rot(1, (0.25, -0.05, 1.0), (0.1, -1.0, 0.0))
    waveB = hand_rot(1, (-0.25, -0.05, 1.0), (-0.1, -1.0, 0.0))
    grab = hand_rot(-1, (0.0, -1.0, -0.15), (0.6, 0.0, -0.8))
    upL = hand_rot(1, (0.15, -0.3, 1.0), (-0.6, -0.8, 0.0))
    upR = hand_rot(-1, (-0.15, -0.3, 1.0), (0.6, -0.8, 0.0))
    G = ((-0.21, -0.40, 1.10), grab, 1.0)
    keys = [
        (1, restL, restR, 0.0, (0, 0)),
        (20, restL, restR, 0.0, (0, 0)),
        # left hand up for a wave, right hand reaches forward and grabs
        (55, ((0.30, -0.10, 1.64), waveA, 0.0), ((-0.21, -0.40, 1.10), grab, 0.0), 0.0, (0.22, 0.0)),
        (66, ((0.36, -0.10, 1.62), waveA, 0.0), G, 0.0, (0.22, 0.0)),
        (78, ((0.26, -0.10, 1.64), waveB, 0.0), G, 0.0, (0.22, 0.0)),
        (90, ((0.36, -0.10, 1.62), waveA, 0.0), G, 0.0, (0.22, 0.0)),
        (102, ((0.26, -0.10, 1.64), waveB, 0.0), G, 0.0, (0.22, 0.0)),
        # both arms up
        (135, ((0.30, -0.20, 1.55), upL, 0.7), ((-0.30, -0.20, 1.55), upR, 0.7), 0.0, (0.25, 0.25)),
        # arms down, squat a little
        (170, restL, restR, -0.09, (0, 0)),
        (190, restL, restR, -0.09, (0, 0)),
        (215, restL, restR, 0.0, (0, 0)),
        (250, restL, restR, 0.0, (0, 0)),
    ]
    for f, L, R, hz, sh in keys:
        key_pose(rig, f, {"IK_hand.L": L, "IK_hand.R": R}, hips_z=hz, shoulder_up=sh)
    rig.animation_data.action.name = "Power_Demo"
    bpy.context.scene.frame_set(1)


# =============================================================================
# MAIN
# =============================================================================
def set_viewports():
    for scr in bpy.data.screens:
        for area in scr.areas:
            if area.type == 'VIEW_3D':
                for sp in area.spaces:
                    if sp.type == 'VIEW_3D':
                        sp.shading.type = 'MATERIAL'
                        sp.overlay.show_relationship_lines = False
                        r3 = sp.region_3d
                        r3.view_location = (0, 0, 0.9)
                        r3.view_distance = 3.2
                        r3.view_rotation = Euler((math.radians(80), 0, math.radians(20))).to_quaternion()


def main():
    out = arg('--out', os.path.join(HERE, "Power_ChainsawMan.blend"))
    clear_scene()
    sc = bpy.context.scene
    sc.name = "Power"
    C_char = new_collection("Power")
    C_clothes = new_collection("Clothes")
    C_rig = new_collection("Rig")
    C_phys = new_collection("Physics")
    C_env = new_collection("Environment")
    C_wgt = new_collection("Widgets")

    # --- character -----------------------------------------------------------
    body = build_body(C_char)
    body.data.materials.append(skin_material())
    eyes = build_eyes(C_char)
    face_bits = build_face_details(C_char, AN.build_body())
    hair, horns = build_hair_and_horns(C_char)

    # --- clothes ---------------------------------------------------------------
    M = clothing_materials()
    shirt = build_shirt(C_clothes)
    shirt.data.materials.append(M['shirt'])
    pants = build_pants(C_clothes)
    pants.data.materials.append(M['pants'])
    collar = build_collar(C_clothes)
    collar.data.materials.append(M['shirt_plain'])
    tie, knot = build_tie(C_clothes, shirt)
    tie.data.materials.append(M['tie'])
    knot.data.materials.append(M['tie'])
    belt, buckle = build_belt(C_clothes)
    belt.data.materials.append(M['leather'])
    buckle.data.materials.append(M['metal'])
    shoes = build_shoes(C_clothes)
    for o in shoes:
        o.data.materials.append(M['shoes'])
    buttons = build_buttons(C_clothes, shirt, M['button'])
    floor_z = min(float(mesh_arrays(o.data)[:, 2].min()) for o in shoes)

    # --- rig + skinning ----------------------------------------------------------
    log("building rig")
    rig = build_rig(C_rig, C_wgt)
    skin_body(rig, body)
    bv = mesh_arrays(body.data)
    bnames, bW = read_weights(body)
    for ob in (shirt, pants, collar, tie, knot, belt, buckle):
        bind_like_body(ob, rig, bv, bnames, bW)
    for ob in list(eyes) + list(face_bits) + [hair] + list(horns):
        parent_to_bone(ob, rig, "head")
    parent_to_bone(shoes[0], rig, "foot.L")
    parent_to_bone(shoes[1], rig, "foot.R")
    collider = make_collider(body, rig, C_phys)
    guard = build_waist_guard(C_phys)
    bind_like_body(guard, rig, bv, bnames, bW)
    guard.modifiers.new("Collision", 'COLLISION')
    guard.collision.thickness_outer = 0.004
    guard.collision.cloth_friction = 0.5
    guard.hide_set(True)

    # --- physics -----------------------------------------------------------------
    floor, cam = build_environment(C_env, floor_z)
    for o in shoes + [belt, buckle]:
        o.modifiers.new("Collision", 'COLLISION')
        o.collision.thickness_outer = 0.004
        o.collision.cloth_friction = 0.8 if o in (belt, buckle) else 5.0
    col_body = bpy.data.collections.new("COLLIDE_body")
    col_shirt = bpy.data.collections.new("COLLIDE_shirt")
    col_tie = bpy.data.collections.new("COLLIDE_tie")
    for c in (col_body, col_shirt, col_tie):
        c.use_fake_user = True
    for o in (collider, floor, shoes[0], shoes[1]):
        col_body.objects.link(o)
        col_shirt.objects.link(o)
    for o in (pants, belt, buckle, guard):
        col_shirt.objects.link(o)
    col_tie.objects.link(collider)
    col_tie.objects.link(shirt)

    import garments as GM
    # Pin groups. 1.0 = glued to the skeleton, small values act as soft
    # "goal" springs that keep the fabric loosely around the limbs while it
    # still sags and folds freely.
    sv = mesh_arrays(shirt.data)
    x, y, z = sv[:, 0], sv[:, 1], sv[:, 2]
    pin = smoothstep(1.315, 1.365, z) * (np.abs(x) < 0.21)
    pin = np.maximum(pin, smoothstep(0.05, 0.02, GM.shirt_neck_z(x, y) - z) * (np.abs(x) < 0.12))
    for s_ in (1, -1):
        p0, d = GM.cuff_plane(s_)
        dist = -((sv - p0) @ d)
        near = np.linalg.norm(sv - p0, axis=1) < 0.12
        pin = np.maximum(pin, near * smoothstep(0.055, 0.035, dist))
        # sleeves: soft goal so the arm can't slip out of them
        sh, el, wr = GM.arm_axis(s_)
        ax = S.norm(wr - sh)
        t = (sv - sh) @ ax
        perp = np.linalg.norm((sv - sh) - t[:, None] * ax, axis=1)
        sleeve = (t > -0.02) & (t < np.linalg.norm(wr - sh) + 0.03) & (perp < 0.11) & (np.sign(x) == s_)
        # free near the shoulder/armpit so a raised arm doesn't drag the whole shirt up
        pin = np.maximum(pin, sleeve * 0.70 * smoothstep(0.06, 0.15, t))
    # (Blender uses weight^4 as goal strength: 0.7 -> 0.24 x pin stiffness)
    # a whisper of goal on the body of the shirt so it settles back after a move
    pin = np.maximum(pin, 0.40)
    set_group(shirt, "pin", pin)
    pv = mesh_arrays(pants.data)
    ppin = np.maximum(smoothstep(0.925, 0.962, pv[:, 2]), 0.55 * smoothstep(0.80, 0.70, pv[:, 2]))
    set_group(pants, "pin", ppin)
    tv = mesh_arrays(tie.data)
    set_group(tie, "pin", smoothstep(1.315, 1.345, tv[:, 2]))

    add_cloth(pants, "pin", col_body, quality=6, mass=0.30, tension=14.0, bending=0.2, shrink=-0.02)
    finish_stack(pants, 0.003, collide=True)
    add_cloth(shirt, "pin", col_shirt, quality=6, mass=0.18, tension=10.0, bending=0.06, air=0.8,
              shrink=-0.015)
    finish_stack(shirt, 0.0022, collide=True)
    add_cloth(tie, "pin", col_tie, quality=6, mass=0.12, tension=20.0, bending=0.6, self_collision=False)
    finish_stack(tie, 0.003)

    # buttons ride on the simulated shirt (parented to 3 of its vertices)
    for b, near in buttons:
        b.parent = shirt
        b.parent_type = 'VERTEX_3'
        b.parent_vertices = near
        b.matrix_parent_inverse = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for b, near in buttons:
        b.matrix_parent_inverse = b.matrix_world.inverted()
    bpy.context.view_layer.update()

    # --- tidy up -----------------------------------------------------------------
    C_wgt.hide_viewport = True
    C_wgt.hide_render = True
    for o in C_wgt.objects:
        o.hide_set(True)
    predrape([pants, shirt, tie], frames=int(arg('--drape', 60)))
    if not arg('--no-anim'):
        demo_animation(rig)
    sc.frame_set(1)
    set_viewports()
    # select the rig in pose mode-ready state
    select_only([rig], rig)
    bpy.ops.wm.save_as_mainfile(filepath=out, compress=True)
    log("saved", out, f"{os.path.getsize(out) / 1e6:.1f} MB")
    return out


if __name__ == "__main__":
    main()

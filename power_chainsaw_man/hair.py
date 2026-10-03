"""
Power's hair (long, straight, peachy-pink blonde, messy bangs) and horns,
generated as flattened tapered "clumps" in numpy.

Every clump is grown like a strand: it starts on the scalp, falls under
gravity, and is pushed out of a set of simple collision shapes (head, ears,
neck, shoulders, back, chest) so it drapes over the body.
"""
import numpy as np
from sdf_core import norm

RNG = np.random.default_rng(2022)

HEAD_C = np.array([0.0, 0.016, 1.567])
HEAD_R = np.array([0.0695, 0.089, 0.083])
SCALP = 0.0065          # cap thickness above the skin


# ----------------------------------------------------------------------------
# colliders (ellipsoids / capsules) that strands are pushed out of
# ----------------------------------------------------------------------------
class EllC:
    def __init__(self, c, r):
        self.c, self.r = np.array(c, float), np.array(r, float)

    def push(self, p, margin=0.0):
        r = self.r + margin
        q = (p - self.c) / r
        L = np.linalg.norm(q)
        if L < 1.0:
            p = self.c + q / max(L, 1e-9) * r
        return p

    def normal(self, p):
        g = (p - self.c) / (self.r ** 2)
        return norm(g)


class CapC:
    def __init__(self, a, b, r):
        self.a, self.b, self.r = np.array(a, float), np.array(b, float), r

    def push(self, p, margin=0.0):
        ab = self.b - self.a
        t = np.clip((p - self.a) @ ab / (ab @ ab), 0, 1)
        c = self.a + t * ab
        d = p - c
        L = np.linalg.norm(d)
        r = self.r + margin
        if L < r:
            p = c + d / max(L, 1e-9) * r
        return p


HEAD = EllC(HEAD_C, HEAD_R + SCALP + 0.002)
FOREHEAD = EllC((0, -0.038, 1.583), (0.064, 0.052, 0.055))
COLLIDERS = [
    HEAD,
    FOREHEAD,
    EllC((0.072, 0.016, 1.528), (0.016, 0.026, 0.034)),     # ears
    EllC((-0.072, 0.016, 1.528), (0.016, 0.026, 0.034)),
    CapC((0, 0.024, 1.33), (0, 0.016, 1.47), 0.060),          # neck + collar
    EllC((0, 0.012, 1.215), (0.200, 0.150, 0.175)),           # upper torso (+shirt)
    CapC((0.04, 0.02, 1.395), (0.20, 0.015, 1.345), 0.055),   # shoulders
    CapC((-0.04, 0.02, 1.395), (-0.20, 0.015, 1.345), 0.055),
    EllC((0.064, -0.082, 1.205), (0.075, 0.072, 0.078)),      # bust (+shirt)
    EllC((-0.064, -0.082, 1.205), (0.075, 0.072, 0.078)),
]


class FaceGuard:
    """Keeps falling hair beside the face instead of in front of it."""

    def push(self, p, margin=0.0):
        z = p[2]
        if 1.38 < z < 1.556 and p[1] < 0.01:
            # half width of the free zone, narrowing toward the chin
            hw = 0.074 - 0.02 * np.clip((1.47 - z) / 0.08, 0, 1) + margin
            if abs(p[0]) < hw:
                p = p.copy()
                p[0] = np.sign(p[0] if p[0] != 0 else 1) * hw
        return p


FACE_GUARD = FaceGuard()


def push_all(p, margin=0.0, hug=False, guard=True):
    for _ in range(3):
        for c in COLLIDERS:
            if hug and c is FOREHEAD:
                continue
            p = c.push(p, margin)
        if guard and not hug:
            p = FACE_GUARD.push(p, margin * 0.5)
    return p


def scalp_point(theta, phi, extra=0.0):
    """theta: polar angle from the top (0..pi), phi: azimuth, 0 = front (-Y)."""
    d = np.array([np.sin(theta) * np.sin(phi), -np.sin(theta) * np.cos(phi), np.cos(theta)])
    return HEAD_C + d * (HEAD_R + SCALP + extra)


# ----------------------------------------------------------------------------
# strand growth
# ----------------------------------------------------------------------------
def head_normal(p):
    return norm((p - HEAD_C) / HEAD_R ** 2)


def head_proj(p, extra):
    r = HEAD_R + SCALP + 0.002 + extra
    q = (p - HEAD_C) / r
    return HEAD_C + q / np.linalg.norm(q) * r


def grow(root, d0, length, n=26, stiff=0.86, noise=0.01, margin=0.0, gravity=(0, 0, -1.0),
         hug=True, hug_stiff=0.93, leave_nz=-0.05, curl_end=0.0, guard=True):
    """
    Grow a strand: first it hugs the scalp (following its initial direction
    and slowly turning downhill), once it passes the widest part of the skull
    it falls freely under gravity and collides with the body.
    """
    seg = length / (n - 1)
    pts = [np.array(root, float)]
    d = norm(d0)
    g = norm(np.array(gravity, float))
    mode = 'hug' if (hug and head_normal(pts[0])[2] > leave_nz) else 'fall'
    side = norm(np.cross(d, (0, 0, 1)) + 1e-6)
    for i in range(1, n):
        s = i / (n - 1)
        prev = pts[-1]
        nz = RNG.normal(size=3) * noise
        if mode == 'hug':
            nrm = head_normal(prev)
            gt = g - nrm * (g @ nrm)
            d = d - nrm * (d @ nrm)
            d = norm(d * hug_stiff + gt * (1 - hug_stiff) + nz)
            p = head_proj(prev + d * seg, margin)
            p = push_all(p, margin, hug=True)
            if head_normal(p)[2] < leave_nz:
                mode = 'fall'
        else:
            k = stiff
            d = norm(d * k + g * (1 - k) + nz)
            if curl_end and s > 0.75:
                d = norm(d + side * curl_end * (s - 0.75))
            p = push_all(prev + d * seg, margin, guard=guard)
        d = norm(p - prev)
        pts.append(p)
    return np.array(pts)


def tangent_dir(root, want):
    nrm = head_normal(root)
    t = want - nrm * (want @ nrm)
    return norm(t)


def surface_normals(pts):
    """Outward direction for a strand: away from the nearest collider centre."""
    out = []
    for p in pts:
        best, bd = None, 1e9
        for c in COLLIDERS:
            if isinstance(c, EllC):
                q = (p - c.c) / c.r
                dd = abs(np.linalg.norm(q) - 1) * c.r.min()
                n = c.normal(p)
            else:
                ab = c.b - c.a
                t = np.clip((p - c.a) @ ab / (ab @ ab), 0, 1)
                v = p - (c.a + t * ab)
                dd = abs(np.linalg.norm(v) - c.r)
                n = norm(v)
            if dd < bd:
                bd, best = dd, n
        out.append(best)
    out = np.array(out)
    # smooth along the strand
    for _ in range(3):
        out[1:-1] = norm_rows(out[:-2] + 2 * out[1:-1] + out[2:])
    return out


def norm_rows(a):
    return a / (np.linalg.norm(a, axis=1)[:, None] + 1e-12)


# ----------------------------------------------------------------------------
# clump mesh
# ----------------------------------------------------------------------------
def clump_mesh(pts, width, thick=0.32, sides=8, root_fade=0.25, tip_shape=1.6, flip=1.0):
    """Flattened tube whose flat side faces away from the body."""
    N = len(pts)
    T = np.gradient(pts, axis=0)
    T = norm_rows(T)
    Nn = surface_normals(pts) * flip
    Nn = Nn - T * np.einsum('ij,ij->i', Nn, T)[:, None]
    Nn = norm_rows(Nn)
    B = np.cross(T, Nn)
    s = np.linspace(0, 1, N)
    w = width * (1 - s ** tip_shape) ** 0.7 * (0.75 + 0.25 * np.clip(s / root_fade, 0, 1))
    w = np.maximum(w, width * 0.02)
    ang = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    V = (pts[:, None, :]
         + B[:, None, :] * (np.cos(ang)[None, :, None] * w[:, None, None])
         + Nn[:, None, :] * (np.sin(ang)[None, :, None] * (w * thick)[:, None, None]))
    V = V.reshape(-1, 3)
    F = []
    for i in range(N - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            F.append((a, b, b + sides, a + sides))
    F.append(tuple(range(sides))[::-1])
    tip = len(V)
    V = np.vstack([V, pts[-1] + T[-1] * width * 0.05])
    for j in range(sides):
        a = (N - 1) * sides + j
        b = (N - 1) * sides + (j + 1) % sides
        F.append((a, b, tip))
    uv = np.zeros((len(V), 2))
    uv[:-1, 0] = np.tile(np.arange(sides) / sides, N)
    uv[:-1, 1] = np.repeat(s, sides)
    uv[-1] = (0.5, 1.0)
    return V, F, uv


class MeshAcc:
    def __init__(self):
        self.V, self.F, self.UV, self.R = [], [], [], []
        self.n = 0

    def add(self, V, F, uv, rnd=None):
        self.V.append(V)
        self.UV.append(uv)
        self.F.extend([tuple(i + self.n for i in f) for f in F])
        self.R.append(np.full(len(V), RNG.random() if rnd is None else rnd))
        self.n += len(V)

    def arrays(self):
        return np.vstack(self.V), self.F, np.vstack(self.UV), np.concatenate(self.R)


# ----------------------------------------------------------------------------
# hairstyle
# ----------------------------------------------------------------------------
def hairline_theta(phi):
    """Polar angle where the scalp ends, as a function of azimuth (0=front)."""
    a = np.abs(np.angle(np.exp(1j * phi)))  # 0..pi
    front = 0.95   # forehead hairline (covered by bangs anyway)
    temple = 1.48  # sides in front of the ears
    back = 2.05    # nape
    return np.interp(a, [0, 0.6, 1.2, 1.7, np.pi], [front, 1.18, temple, 1.85, back])


def build_cap(res_t=40, res_p=72):
    """Scalp cap mesh (thin shell) under the clumps."""
    V, uv = [], []
    phis = np.linspace(-np.pi, np.pi, res_p, endpoint=False)
    rows = []
    for i in range(res_t + 1):
        row = []
        for j, ph in enumerate(phis):
            th_max = hairline_theta(ph)
            th = th_max * (i / res_t) ** 0.9
            V.append(scalp_point(th, ph, -0.0015))
            uv.append((j / res_p, i / res_t * 0.3))
            row.append(len(V) - 1)
        rows.append(row)
    F = []
    for i in range(res_t):
        for j in range(res_p):
            a, b = rows[i][j], rows[i][(j + 1) % res_p]
            c, d = rows[i + 1][(j + 1) % res_p], rows[i + 1][j]
            if i == 0:
                continue
            F.append((a, d, c, b))
    # top fan
    top = len(V)
    V.append(scalp_point(0, 0, -0.0015))
    uv.append((0.5, 0.0))
    for j in range(res_p):
        F.append((top, rows[1][j], rows[1][(j + 1) % res_p])[::-1])
    return np.array(V), F, np.array(uv)


def build_hair():
    acc = MeshAcc()
    crown = np.array([0.004, 0.045, 1.650])     # whorl the hair falls away from
    part_x = 0.010                             # slightly off-centre parting

    # --- long hair: back and sides -----------------------------------------
    for k in range(170):
        phi = RNG.uniform(0.75, 2 * np.pi - 0.75)
        th = RNG.uniform(0.25, hairline_theta(phi) - 0.04)
        root = scalp_point(th, phi)
        want = norm(root - crown) + np.array([0, 0.15, -0.8])
        d0 = tangent_dir(root, want)
        a = abs(np.angle(np.exp(1j * phi)))
        L = np.interp(a, [0.75, 1.5, np.pi], [0.40, 0.50, 0.55]) * RNG.uniform(0.86, 1.06)
        pts = grow(root, d0, L, n=32, stiff=0.86, noise=0.012, margin=0.0015 + 0.0065 * RNG.random())
        acc.add(*clump_mesh(pts, RNG.uniform(0.014, 0.024), thick=0.28))

    # --- top layer: swept back and to the sides from the part ---------------
    for k in range(80):
        x = RNG.uniform(-0.055, 0.055)
        y = RNG.uniform(-0.05, 0.075)
        phi = np.arctan2(x, -y)
        th = np.clip(np.hypot(x / HEAD_R[0], (y - HEAD_C[1]) / HEAD_R[1]) * 1.2, 0.08, 0.95)
        root = scalp_point(th, phi, 0.001)
        side = 1.0 if x > part_x else -1.0
        want = np.array([side * 1.0, 0.45 + (y > 0.0) * 0.6, -0.35])
        d0 = tangent_dir(root, want)
        L = RNG.uniform(0.38, 0.52)
        pts = grow(root, d0, L, n=32, stiff=0.86, noise=0.010, margin=0.006 + 0.004 * RNG.random())
        acc.add(*clump_mesh(pts, RNG.uniform(0.016, 0.026), thick=0.28))

    # --- face framing locks (fall in front of the shoulders) -----------------
    for s in (1, -1):
        for k in range(12):
            phi = s * RNG.uniform(0.80, 1.20)
            th = RNG.uniform(0.55, 1.05)
            root = scalp_point(th, phi)
            d0 = tangent_dir(root, np.array([1.0 * s, -0.25, -1.0]))
            L = RNG.uniform(0.30, 0.44)
            pts = grow(root, d0, L, n=32, stiff=0.86, noise=0.012,
                       gravity=(0.06 * s, -0.06, -1.0), margin=0.002 + 0.004 * RNG.random())
            acc.add(*clump_mesh(pts, RNG.uniform(0.012, 0.020), thick=0.30))

    # --- bangs ---------------------------------------------------------------
    for k in range(34):
        u = (k + RNG.random()) / 34.0
        phi = (-0.85 + 1.70 * u)
        th = RNG.uniform(0.62, 0.86)
        root = scalp_point(th, phi, 0.0015)
        d0 = tangent_dir(root, np.array([0.55 * np.sin(phi) + RNG.normal() * 0.12, -1.0, -0.4]))
        # length so the tips end around the eyebrows (longer at the sides)
        L = (0.086 + 0.045 * abs(phi) + RNG.uniform(-0.008, 0.010))
        pts = grow(root, d0, L, n=22, stiff=0.9, noise=0.006, hug_stiff=0.95, guard=False,
                   gravity=(0, -0.12, -1.0), margin=0.007 + 0.004 * RNG.random())
        acc.add(*clump_mesh(pts, RNG.uniform(0.010, 0.017), thick=0.32, tip_shape=1.3))
    # Power's signature strand between the eyes
    for phi0, dx in ((0.06, -0.15), (-0.08, 0.12)):
        root = scalp_point(0.7, phi0, 0.002)
        d0 = tangent_dir(root, np.array([dx, -1.0, -0.5]))
        pts = grow(root, d0, 0.115, n=22, stiff=0.93, noise=0.003, hug_stiff=0.96, guard=False,
                   gravity=(0, -0.15, -1.0), margin=0.0095)
        acc.add(*clump_mesh(pts, 0.0085, thick=0.38, tip_shape=1.2))

    # --- cap -----------------------------------------------------------------
    V, F, uv = build_cap()
    acc.add(V, F, uv, rnd=0.5)
    return acc.arrays()


def horn_mesh(side, sides=14, n=20):
    """Power's small red horns: curved cones growing from the top-front of her head."""
    root = scalp_point(0.42, 0.33 * side, -0.004)
    d = norm(np.array([0.30 * side, -0.38, 1.0]))
    curve = norm(np.array([0.05 * side, -0.6, 0.15]))
    L = 0.075
    pts = []
    p = root.copy()
    for i in range(n):
        s = i / (n - 1)
        pts.append(p.copy())
        dd = norm(d + curve * 0.55 * s)
        p = p + dd * (L / (n - 1))
    pts = np.array(pts)
    s = np.linspace(0, 1, n)
    r = 0.0112 * (1 - s) ** 0.85 + 0.0006
    T = norm_rows(np.gradient(pts, axis=0))
    ref = np.array([1.0, 0, 0])
    N1 = norm_rows(np.cross(T, ref))
    B1 = np.cross(T, N1)
    ang = np.linspace(0, 2 * np.pi, sides, endpoint=False)
    V = (pts[:, None, :] + (N1[:, None, :] * np.cos(ang)[None, :, None]
                            + B1[:, None, :] * np.sin(ang)[None, :, None]) * r[:, None, None])
    V = V.reshape(-1, 3)
    F = []
    for i in range(n - 1):
        for j in range(sides):
            a = i * sides + j
            b = i * sides + (j + 1) % sides
            F.append((a, b, b + sides, a + sides))
    F.append(tuple(range(sides))[::-1])
    tip = len(V)
    V = np.vstack([V, pts[-1] + T[-1] * 0.0015])
    for j in range(sides):
        a = (n - 1) * sides + j
        b = (n - 1) * sides + (j + 1) % sides
        F.append((a, b, tip))
    return V, F

"""
Anatomy definition for Power (Chainsaw Man) as a smooth SDF sculpt.

Units: metres, Z up, the character faces -Y, her left side is +X.
Height ~1.65 m. Built in an A-pose (arms ~50 deg below horizontal) which is
the friendliest pose for rigging and for the cloth simulation.

Everything here is pure numpy so it can run inside Blender.
"""
import numpy as np
from sdf_core import (SDFScene, Sphere, RoundCone, Capsule, Ellipsoid, RoundBox,
                      Loft, Custom, v3, norm, frame, rot_axis, smax)

D2R = np.pi / 180.0


def mirror(p):
    p = np.array(p, dtype=float)
    p[..., 0] *= -1
    return p


def mirror_R(R):
    """Mirror a local frame across the YZ plane, keeping it right handed."""
    M = np.diag([-1.0, 1.0, 1.0])
    R2 = M @ R
    R2[:, 1] *= -1  # flip one axis to keep det=+1
    return R2


# ----------------------------------------------------------------------------
# skeleton landmarks (left side, mirrored for right)
# ----------------------------------------------------------------------------
class Skeleton:
    def __init__(self):
        J = {}
        J['pelvis'] = v3(0, 0.0, 0.93)
        J['spine'] = v3(0, 0.005, 1.03)
        J['chest'] = v3(0, 0.01, 1.15)
        J['upper_chest'] = v3(0, 0.015, 1.28)
        J['neck'] = v3(0, 0.02, 1.385)
        J['head'] = v3(0, 0.012, 1.49)
        J['head_top'] = v3(0, 0.012, 1.66)
        J['clavicle_in'] = v3(0.02, -0.02, 1.37)
        J['shoulder'] = v3(0.158, 0.012, 1.318)
        # arm in A pose: upper arm 50 deg below horizontal, a bit forward
        d1 = norm((0.64, -0.03, -0.766))
        J['elbow'] = J['shoulder'] + 0.272 * d1
        d2 = norm((0.60, -0.16, -0.785))
        J['wrist'] = J['elbow'] + 0.238 * d2
        self.d_upper = d1
        self.d_fore = d2
        J['hip'] = v3(0.088, 0.0, 0.86)
        J['knee'] = v3(0.093, -0.008, 0.468)
        J['ankle'] = v3(0.092, 0.03, 0.078)
        J['ball'] = v3(0.10, -0.105, 0.018)
        J['toe'] = v3(0.104, -0.168, 0.016)
        J['heel'] = v3(0.09, 0.06, 0.02)
        self.J = J
        # hand frame: x = toward fingers, y = toward thumb, z = out of the palm
        f = d2.copy()
        palm = norm((-0.80, 0.08, -0.60))
        zf = norm(palm - f * (palm @ f))
        yf = np.cross(zf, f)
        if yf[1] > 0:  # thumb must point forward (-Y)
            yf = -yf
            zf = -zf
        self.hand_R = np.stack([f, yf, zf], axis=1)
        if np.linalg.det(self.hand_R) < 0:
            self.hand_R[:, 2] *= -1
        self.fingers = {}  # name -> list of joint positions (world, left)


SK = Skeleton()


# ----------------------------------------------------------------------------
# hand (built in local hand space, then transformed)
# ----------------------------------------------------------------------------
class Local(Custom):
    """Wraps a prim defined in a local frame (origin o, rotation R)."""

    def __init__(self, prim, o, R):
        self.prim, self.o, self.R = prim, v3(o), np.asarray(R, float)
        corners = np.array([[x, y, z] for x in (prim.lo[0], prim.hi[0])
                            for y in (prim.lo[1], prim.hi[1])
                            for z in (prim.lo[2], prim.hi[2])])
        w = corners @ self.R.T + self.o
        self.lo, self.hi = w.min(0), w.max(0)

    def __call__(self, P):
        return self.prim((P - self.o) @ self.R)


FINGER_DEF = {
    #          base (x, y),     lengths,                 radii (base, mid, dist, tip),   spread, curl(mcp,pip,dip)
    'index': ((0.094, 0.0265), (0.043, 0.025, 0.020), (0.0093, 0.0084, 0.0077, 0.0069), 6, (10, 18, 10)),
    'middle': ((0.097, 0.0080), (0.047, 0.029, 0.021), (0.0096, 0.0087, 0.0079, 0.0071), 0, (12, 22, 12)),
    'ring': ((0.094, -0.0110), (0.044, 0.027, 0.020), (0.0091, 0.0082, 0.0075, 0.0067), -6, (14, 26, 14)),
    'pinky': ((0.086, -0.0285), (0.034, 0.020, 0.018), (0.0081, 0.0073, 0.0066, 0.0059), -13, (17, 30, 16)),
}


def finger_chain(name):
    """Return local joints [mcp, pip, dip, tip] and radii for a finger."""
    (bx, by), L, R, spread, curl = FINGER_DEF[name]
    p = v3(bx, by, -0.001)
    d = norm((np.cos(spread * D2R), np.sin(spread * D2R), 0.0))
    pts = [p.copy()]
    ang = 0.0
    side = norm(np.cross(d, (0, 0, 1)))  # flexion axis
    for seg, c in zip(L, curl):
        ang += c * D2R
        dd = rot_axis(side, -ang) @ d  # curl toward +z (palm side)
        if dd[2] < 0:
            dd = rot_axis(side, ang) @ d
        p = p + seg * dd
        pts.append(p.copy())
    return pts, R


def thumb_chain():
    cmc = v3(0.024, 0.022, 0.008)
    dirs = [norm((0.62, 0.62, 0.40)), norm((0.80, 0.42, 0.42)), norm((0.88, 0.22, 0.42))]
    L = (0.040, 0.031, 0.026)
    pts = [cmc]
    p = cmc
    for d, l in zip(dirs, L):
        p = p + d * l
        pts.append(p)
    return pts, (0.0125, 0.0105, 0.0094, 0.0083)


def hand_prims():
    """Hand in local space. Returns list of (mode, prim, k)."""
    ops = []
    A = ops.append
    # wrist / carpus
    A(('add', Ellipsoid((0.004, -0.002, -0.001), (0.026, 0.026, 0.0155)), 0.0))
    # palm block
    A(('add', RoundBox((0.054, 0.0, 0.0005), (0.036, 0.029, 0.0035), 0.0105), 0.012))
    # knuckle ridge, slightly arched
    A(('add', Capsule((0.090, 0.028, -0.002), (0.086, -0.028, -0.002), 0.0095), 0.010))
    # thenar (thumb ball) and hypothenar pads
    A(('add', Ellipsoid((0.034, 0.024, 0.010), (0.030, 0.016, 0.0125),
                        frame((1, 0.55, 0.15), (0, 0, 1))), 0.012))
    A(('add', Ellipsoid((0.042, -0.026, 0.007), (0.036, 0.011, 0.010)), 0.010))
    # metacarpal pads under the fingers
    A(('add', Capsule((0.085, 0.025, 0.007), (0.080, -0.026, 0.007), 0.0085), 0.008))
    # palm hollow
    A(('sub', Ellipsoid((0.058, 0.002, 0.020), (0.026, 0.016, 0.006)), 0.008))
    # fingers
    for name in FINGER_DEF:
        pts, R = finger_chain(name)
        for i in range(3):
            A(('add', RoundCone(pts[i], pts[i + 1], R[i], R[i + 1]), 0.006 if i == 0 else 0.0025))
        # knuckle bumps on the back of the PIP joints
        A(('add', Sphere(pts[1] + v3(0, 0, -0.0025), R[1] * 0.92), 0.003))
        # finger pad
        A(('add', Ellipsoid(0.5 * (pts[2] + pts[3]) + v3(0, 0, 0.0018),
                            (np.linalg.norm(pts[3] - pts[2]) * 0.45, R[2] * 0.9, R[2] * 0.85),
                            frame(pts[3] - pts[2], (0, 0, 1))), 0.003))
    pts, R = thumb_chain()
    A(('add', RoundCone(pts[0], pts[1], R[0] * 1.15, R[1]), 0.012))
    A(('add', RoundCone(pts[1], pts[2], R[1], R[2]), 0.004))
    A(('add', RoundCone(pts[2], pts[3], R[2], R[3]), 0.003))
    # web between thumb and index
    A(('add', Ellipsoid((0.060, 0.034, 0.002), (0.018, 0.008, 0.004),
                        frame((1, 0.3, 0), (0, 0, 1))), 0.010))
    return ops


class HandPrim(Custom):
    """Whole hand evaluated as a sub-scene (keeps fingers' small blends local)."""

    def __init__(self, side):
        self.side = side
        o = SK.J['wrist'] if side > 0 else mirror(SK.J['wrist'])
        R = SK.hand_R if side > 0 else mirror_R(SK.hand_R)
        self.o, self.R = o, R
        self.sub = SDFScene()
        for m, p, k in hand_prims():
            self.sub.ops.append((m, p, k))
        llo, lhi = v3(-0.03, -0.05, -0.03), v3(0.20, 0.10, 0.05)
        corners = np.array([[x, y, z] for x in (llo[0], lhi[0]) for y in (llo[1], lhi[1])
                            for z in (llo[2], lhi[2])])
        w = corners @ R.T + o
        self.lo, self.hi = w.min(0), w.max(0)

    def to_local(self, P):
        L = (P - self.o) @ self.R
        if self.side < 0:
            L = L * np.array([1, -1, 1])  # mirrored hand: flip thumb axis
        return L

    def __call__(self, P):
        return self.sub(self.to_local(P))

    def to_world(self, L):
        L = np.asarray(L, float)
        if self.side < 0:
            L = L * np.array([1, -1, 1])
        return L @ self.R.T + self.o


# ----------------------------------------------------------------------------
# head
# ----------------------------------------------------------------------------
EYE_C = v3(0.0325, -0.0672, 1.5330)
EYE_R = 0.0132
EYE_FWD = norm((0.10, -1.0, 0.0))


class EyeLids(Custom):
    """Shell around the eyeball with an almond shaped opening."""

    def __init__(self, side):
        self.c = EYE_C * np.array([side, 1, 1])
        fwd = EYE_FWD * np.array([side, 1, 1])
        self.fwd = fwd
        up = v3(0, 0, 1)
        self.up = norm(up - fwd * (up @ fwd))
        self.right = np.cross(self.fwd, self.up) * side  # points to the outer corner
        self.r_in = EYE_R + 0.0006
        self.r_out = EYE_R + 0.0028
        r = self.r_out + 0.004
        self.lo, self.hi = self.c - r, self.c + r

    def __call__(self, P):
        q = P - self.c
        L = np.linalg.norm(q, axis=1) + 1e-9
        w = q / L[:, None]
        u = w @ self.right  # + toward outer corner
        v = w @ self.up
        f = w @ self.fwd
        # almond opening: outer corner a bit higher (cat-like eyes)
        uu = np.clip(u, -1, 1)
        top = 0.47 * np.clip(1 - ((uu - 0.04) / 0.93) ** 2, 0, None) ** 0.75 + 0.10 * uu
        bot = -0.37 * np.clip(1 - ((uu + 0.02) / 0.90) ** 2, 0, None) ** 0.95 + 0.07 * uu
        g_open = np.maximum(v - top, bot - v)  # <0 inside opening (angular)
        g_open = np.maximum(g_open, -f)        # only on the front hemisphere
        g_open = g_open * EYE_R
        shell = np.abs(L - 0.5 * (self.r_in + self.r_out)) - 0.5 * (self.r_out - self.r_in)
        lid = smax(shell, -g_open, 0.0012)
        # lids only exist on the front part of the ball
        lid = smax(lid, -(f + 0.15) * EYE_R, 0.002)
        return lid


def head_ops():
    """Slightly stylised (anime-leaning) young woman's head."""
    ops = []
    A = ops.append
    # cranium
    A(('add', Ellipsoid((0, 0.016, 1.567), (0.0695, 0.089, 0.083)), 0.03))
    # forehead
    A(('add', Ellipsoid((0, -0.038, 1.583), (0.057, 0.045, 0.048)), 0.035))
    # upper face and a soft V shaped lower face
    A(('add', Ellipsoid((0, -0.032, 1.522), (0.057, 0.051, 0.050)), 0.04))
    A(('add', RoundCone((0, -0.022, 1.506), (0, -0.052, 1.455), 0.047, 0.016), 0.03))
    A(('add', Ellipsoid((0, -0.0605, 1.4465), (0.016, 0.0115, 0.0125)), 0.016))
    for s in (1, -1):
        A(('add', RoundCone(v3(0.012 * s, -0.055, 1.449), v3(0.045 * s, 0.003, 1.481), 0.0100, 0.0115), 0.024))
        # cheek bone
        A(('add', Ellipsoid((0.045 * s, -0.050, 1.519), (0.019, 0.017, 0.013),
                            frame((s, -0.6, 0), (0, 0, 1))), 0.025))
        # under-eye fill and soft round cheeks
        A(('add', Ellipsoid((0.032 * s, -0.066, 1.508), (0.019, 0.012, 0.014)), 0.02))
        A(('add', Ellipsoid((0.031 * s, -0.057, 1.486), (0.019, 0.017, 0.019)), 0.025))
        # soft brow
        A(('add', Ellipsoid((0.031 * s, -0.0715, 1.5585), (0.023, 0.009, 0.0065),
                            frame((s, 0.3, 0), (0, 0, 1))), 0.014))
    # muzzle
    A(('add', Ellipsoid((0, -0.0705, 1.472), (0.022, 0.014, 0.020)), 0.022))
    # nose: small and straight
    A(('add', RoundCone((0, -0.078, 1.540), (0, -0.0935, 1.5035), 0.0045, 0.0055), 0.010))
    A(('add', Sphere((0, -0.0935, 1.5005), 0.0068), 0.006))
    for s in (1, -1):
        A(('add', Ellipsoid((0.0080 * s, -0.0855, 1.4955), (0.0055, 0.0058, 0.0048)), 0.006))
        A(('sub', Ellipsoid((0.0045 * s, -0.0905, 1.4915), (0.0021, 0.0034, 0.0017),
                            frame((0.4 * s, -1, 0.25), (0, 0, 1))), 0.0015))
    # lips: small, soft
    A(('add', Ellipsoid((0, -0.0846, 1.4703), (0.0138, 0.0045, 0.0035),
                        frame((1, 0, 0), (0, 0.35, 1))), 0.005))
    A(('add', Ellipsoid((0, -0.0828, 1.4635), (0.0120, 0.0049, 0.0037),
                        frame((1, 0, 0), (0, -0.4, 1))), 0.005))
    # mouth line and corners
    A(('sub', Ellipsoid((0, -0.0890, 1.4670), (0.0140, 0.0055, 0.0008)), 0.0012))
    for s in (1, -1):
        A(('sub', Sphere((0.0143 * s, -0.0812, 1.4675), 0.0014), 0.002))
    # philtrum dip
    A(('sub', Capsule((0, -0.0912, 1.4762), (0, -0.0920, 1.4855), 0.0014), 0.002))
    # eyes: hole for the eyeball, lids, upper lid crease
    for s in (1, -1):
        c = EYE_C * np.array([s, 1, 1])
        A(('sub', Ellipsoid(c + v3(0, -0.006, 0.001), (0.0165, 0.010, 0.0118)), 0.004))
        A(('sub', Sphere(c, EYE_R + 0.0006), 0.0))
        A(('add', EyeLids(s), 0.0018))
        A(('sub', Ellipsoid(c + v3(0.001 * s, -0.0095, 0.0118), (0.0145, 0.004, 0.0028),
                            frame((s, 0.25, 0), (0, 0, 1))), 0.003))
    # ears
    for s in (1, -1):
        R = frame((0, 0.25, 1), (s, -0.25, 0))  # x=up-ish, z=outward
        c = v3(0.067 * s, 0.018, 1.528)
        A(('add', Ellipsoid(c, (0.027, 0.016, 0.0065), R), 0.006))
        A(('add', Ellipsoid(c + v3(0.004 * s, 0.0, 0.0), (0.023, 0.013, 0.0030), R), 0.002))
        A(('sub', Ellipsoid(c + v3(0.007 * s, -0.001, -0.003), (0.010, 0.0072, 0.0035), R), 0.002))
        A(('sub', Ellipsoid(c + v3(0.0075 * s, 0.002, 0.009), (0.0095, 0.0068, 0.0022), R), 0.0015))
    return ops


# ----------------------------------------------------------------------------
# torso, limbs
# ----------------------------------------------------------------------------
TORSO_KEYS = [
    #  z      a      front  back   yc     n
    (0.765, 0.150, 0.068, 0.080, 0.008, 2.3),
    (0.800, 0.165, 0.076, 0.098, 0.006, 2.4),
    (0.850, 0.171, 0.082, 0.108, 0.002, 2.45),
    (0.900, 0.163, 0.084, 0.098, -0.004, 2.35),
    (0.950, 0.146, 0.083, 0.083, -0.006, 2.2),
    (1.000, 0.129, 0.078, 0.073, -0.006, 2.1),
    (1.040, 0.122, 0.076, 0.070, -0.006, 2.1),
    (1.100, 0.129, 0.083, 0.072, -0.004, 2.15),
    (1.150, 0.137, 0.088, 0.076, -0.001, 2.2),
    (1.220, 0.145, 0.089, 0.079, 0.002, 2.35),
    (1.280, 0.150, 0.083, 0.076, 0.006, 2.5),
    (1.325, 0.146, 0.068, 0.068, 0.010, 2.7),
    (1.360, 0.120, 0.056, 0.060, 0.014, 2.6),
    (1.395, 0.066, 0.044, 0.050, 0.018, 2.1),
    (1.420, 0.048, 0.040, 0.046, 0.018, 2.0),
]


def arm_ops(s):
    """s=+1 left, -1 right."""
    J = SK.J
    m = (lambda p: p) if s > 0 else mirror
    sh, el, wr = m(J['shoulder']), m(J['elbow']), m(J['wrist'])
    du, df = el - sh, wr - el
    ops = []
    A = ops.append
    # deltoid cap
    Rd = frame(du, (0, 0, 1))
    A(('add', Ellipsoid(sh + 0.028 * norm(du) + v3(0.008 * s, 0, 0.004), (0.068, 0.046, 0.044), Rd), 0.03))
    # upper arm
    A(('add', RoundCone(sh, el, 0.040, 0.031), 0.03))
    # biceps (front) and triceps (back)
    fr = v3(0, -1, 0)
    A(('add', Ellipsoid(sh + 0.55 * du + 0.012 * fr, (0.075, 0.024, 0.028), frame(du, fr)), 0.02))
    A(('add', Ellipsoid(sh + 0.45 * du - 0.014 * fr, (0.085, 0.026, 0.030), frame(du, fr)), 0.02))
    # elbow
    A(('add', Sphere(el + 0.004 * fr * -1, 0.030), 0.02))
    # forearm: flatter, wider near the elbow
    Rf = frame(df, SK.hand_R[:, 2] * np.array([s, 1, 1]))
    A(('add', RoundCone(el, wr, 0.032, 0.022), 0.02))
    A(('add', Ellipsoid(el + 0.30 * df, (0.075, 0.036, 0.028), Rf), 0.03))
    # wrist (flattened)
    A(('add', Ellipsoid(wr - 0.01 * norm(df), (0.026, 0.026, 0.017), Rf), 0.02))
    return ops


def leg_ops(s):
    J = SK.J
    m = (lambda p: p) if s > 0 else mirror
    hip, kn, an = m(J['hip']), m(J['knee']), m(J['ankle'])
    ops = []
    A = ops.append
    dth = kn - hip
    Rt = frame(dth, (0, -1, 0))
    thigh_top = hip + v3(0.006 * s, 0.0, -0.05)
    A(('add', RoundCone(thigh_top, kn, 0.083, 0.050), 0.05))
    # quads, outer thigh, inner thigh, hamstrings
    A(('add', Ellipsoid(hip + 0.48 * dth + v3(0.004 * s, -0.024, 0), (0.15, 0.052, 0.050), Rt), 0.03))
    A(('add', Ellipsoid(hip + 0.40 * dth + v3(0.030 * s, 0.002, 0), (0.15, 0.045, 0.040), Rt), 0.03))
    A(('add', Ellipsoid(hip + 0.25 * dth + v3(-0.017 * s, 0.004, 0), (0.12, 0.040, 0.046), Rt), 0.025))
    A(('add', Ellipsoid(hip + 0.48 * dth + v3(-0.002 * s, 0.026, 0), (0.15, 0.050, 0.047), Rt), 0.03))
    # vastus medialis teardrop
    A(('add', Ellipsoid(kn + v3(-0.026 * s, -0.020, 0.070), (0.026, 0.026, 0.052)), 0.02))
    # glute
    A(('add', Ellipsoid(m(v3(0.072, 0.058, 0.832)), (0.080, 0.068, 0.092),
                        frame((0.3 * s, 0, -1), (0, 1, 0))), 0.04))
    # knee
    A(('add', Ellipsoid(kn + v3(0, -0.040, 0.004), (0.024, 0.014, 0.027)), 0.012))
    A(('add', Sphere(kn, 0.041), 0.03))
    # calf
    dsh = an - kn
    A(('add', RoundCone(kn, an, 0.047, 0.029), 0.02))
    Rc = frame(dsh, (0, 1, 0))
    A(('add', Ellipsoid(kn + 0.33 * dsh + v3(-0.012 * s, 0.024, 0), (0.095, 0.030, 0.032), Rc), 0.025))
    A(('add', Ellipsoid(kn + 0.30 * dsh + v3(0.014 * s, 0.022, 0), (0.085, 0.026, 0.028), Rc), 0.025))
    # shin front
    A(('add', Capsule(kn + v3(0.002 * s, -0.022, -0.05), an + v3(0.002 * s, -0.012, 0.06), 0.018), 0.02))
    # ankle bones
    A(('add', Sphere(an + v3(0.018 * s, 0.004, 0.0), 0.012), 0.01))
    A(('add', Sphere(an + v3(-0.016 * s, -0.002, 0.008), 0.012), 0.01))
    # foot
    heel, ball, toe = m(J['heel']), m(J['ball']), m(J['toe'])
    A(('add', Sphere(heel + v3(0, 0.0, 0.012), 0.030), 0.02))
    A(('add', RoundCone(an + v3(0, 0.0, -0.025), ball + v3(0, 0, 0.012), 0.032, 0.022), 0.03))
    A(('add', RoundBox(0.5 * (heel + ball) + v3(0, 0, -0.002), (0.075, 0.026, 0.006), 0.016,
                       frame((0.08 * s, 1, 0), (0, 0, 1))), 0.02))
    A(('add', RoundCone(ball + v3(-0.008 * s, 0, 0.004), toe + v3(-0.018 * s, 0.004, 0.002), 0.017, 0.012), 0.015))
    A(('add', RoundCone(ball + v3(0.018 * s, 0.01, 0.0), toe + v3(0.012 * s, 0.03, -0.002), 0.014, 0.010), 0.015))
    return ops


def build_body():
    """Order matters for culling: big blend radii first, small details last."""
    sc = SDFScene()
    J = SK.J
    torso = Loft(TORSO_KEYS, cap_lo=0.05, cap_hi=0.02)
    sc.add(torso)
    # legs
    for s in (1, -1):
        for m, p, k in leg_ops(s):
            sc.ops.append((m, p, k))
    # ribcage / back shaping
    sc.add(Ellipsoid((0, 0.012, 1.19), (0.128, 0.088, 0.13)), 0.05)
    # belly / abdomen
    sc.add(Ellipsoid((0, -0.040, 0.945), (0.105, 0.050, 0.075)), 0.04)
    # shoulder blades
    for s in (1, -1):
        sc.add(Ellipsoid((0.065 * s, 0.062, 1.255), (0.048, 0.022, 0.06),
                         frame((0, 0.3, 1), (s * 0.3, 1, 0))), 0.03)
    # breasts (natural, moderate)
    for s in (1, -1):
        c = v3(0.062 * s, -0.072, 1.205)
        sc.add(Ellipsoid(c, (0.058, 0.044, 0.054), frame((s, -0.25, 0), (0, 0, 1))), 0.035)
        sc.add(Ellipsoid(c + v3(0.004 * s, -0.016, -0.010), (0.044, 0.034, 0.040),
                         frame((s, -0.4, 0), (0, 0, 1))), 0.02)
    # arms
    for s in (1, -1):
        for m, p, k in arm_ops(s):
            sc.ops.append((m, p, k))
    # trapezius & neck
    sc.add(RoundCone(J['neck'] + v3(0, 0.0, -0.02), J['head'] + v3(0, 0.0, 0.005), 0.049, 0.042), 0.035)
    for s in (1, -1):
        sc.add(RoundCone(v3(0.03 * s, 0.03, 1.415), v3(0.15 * s, 0.018, 1.343), 0.022, 0.024), 0.04)
        # pecs (subtle, mostly under breast tissue)
        sc.add(Ellipsoid(v3(0.075 * s, -0.050, 1.28), (0.065, 0.025, 0.045),
                         frame((s, -0.2, -0.3), (0, -0.2, 1))), 0.03)
        # sternocleidomastoid
        sc.add(Capsule(v3(0.052 * s, 0.026, 1.505), v3(0.016 * s, -0.036, 1.372), 0.0105), 0.016)
        # clavicles
        sc.add(Capsule(v3(0.020 * s, -0.050, 1.374), v3(0.150 * s, -0.004, 1.352), 0.0085), 0.016)
    sc.sub(Sphere((0, -0.062, 1.381), 0.011), 0.010)  # jugular notch
    sc.sub(Sphere((0, -0.0835, 0.985), 0.0045), 0.003)   # navel
    # head
    for m, p, k in head_ops():
        sc.ops.append((m, p, k))
    # hands
    for s in (1, -1):
        sc.add(HandPrim(s), 0.018)
    return sc


# ----------------------------------------------------------------------------
# landmark data for the rig
# ----------------------------------------------------------------------------
def hand_joints(side):
    hp = HandPrim(side)
    out = {}
    for name in FINGER_DEF:
        pts, _ = finger_chain(name)
        out[name] = [hp.to_world(p) for p in pts]
    pts, _ = thumb_chain()
    out['thumb'] = [hp.to_world(p) for p in pts]
    out['palm'] = hp.to_world(v3(0.095, 0.0, 0.0))
    out['R'] = hp.R
    out['side'] = side
    return out

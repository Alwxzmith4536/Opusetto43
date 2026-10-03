"""
Garment shells (shirt, trousers) and shoes as SDF scenes, built around the
body landmarks in anatomy.py. The shells are deliberately loose so the cloth
simulation can let them sag and fold "like a rag".
"""
import numpy as np
from sdf_core import (SDFScene, RoundCone, Ellipsoid, RoundBox, Loft,
                      v3, norm, frame)
import anatomy as AN

SK = AN.SK
J = SK.J

SHIRT_KEYS = [
    #  z      a      front  back   yc     n
    (0.740, 0.212, 0.138, 0.182, 0.000, 2.6),
    (0.860, 0.212, 0.136, 0.180, 0.000, 2.6),
    (0.950, 0.212, 0.135, 0.160, 0.000, 2.6),
    (1.050, 0.198, 0.134, 0.130, 0.000, 2.5),
    (1.150, 0.186, 0.138, 0.126, 0.000, 2.5),
    (1.220, 0.182, 0.142, 0.132, 0.002, 2.5),
    (1.290, 0.180, 0.124, 0.124, 0.006, 2.6),
    (1.340, 0.170, 0.094, 0.096, 0.010, 2.9),
    (1.380, 0.140, 0.074, 0.080, 0.015, 2.6),
    (1.415, 0.086, 0.064, 0.070, 0.018, 2.2),
    (1.460, 0.062, 0.060, 0.064, 0.018, 2.0),
]

PANTS_KEYS = [
    (0.745, 0.178, 0.094, 0.125, 0.006, 2.4),
    (0.800, 0.190, 0.100, 0.165, 0.006, 2.5),
    (0.860, 0.194, 0.100, 0.162, 0.002, 2.5),
    (0.920, 0.182, 0.100, 0.130, -0.003, 2.4),
    (0.970, 0.160, 0.097, 0.100, -0.006, 2.25),
    (1.020, 0.150, 0.095, 0.094, -0.006, 2.2),
]


def arm_axis(s):
    m = (lambda p: p) if s > 0 else AN.mirror
    return m(J['shoulder']), m(J['elbow']), m(J['wrist'])


def shirt_scene():
    sc = SDFScene()
    sc.add(Loft(SHIRT_KEYS, cap_lo=0.01, cap_hi=0.01))
    for s in (1, -1):
        sh, el, wr = arm_axis(s)
        df = norm(wr - el)
        # sleeve: roomy at the shoulder, loose down the arm, gathered into a cuff
        sc.add(RoundCone(sh + v3(-0.01 * s, 0, 0.004), el, 0.072, 0.060), 0.045)
        sc.add(RoundCone(el, wr - 0.045 * df, 0.060, 0.052), 0.02)
        sc.add(RoundCone(wr - 0.070 * df, wr + 0.020 * df, 0.036, 0.0355), 0.022)
    return sc


def pants_scene():
    sc = SDFScene()
    sc.add(Loft(PANTS_KEYS, cap_lo=0.03, cap_hi=0.01))
    for s in (1, -1):
        m = (lambda p: p) if s > 0 else AN.mirror
        hip = m(v3(0.099, 0.008, 0.84))
        kn = m(J['knee']) + v3(0.006 * s, 0, 0)
        hem = m(v3(0.098, 0.024, 0.0))
        sc.add(RoundCone(hip, kn, 0.097, 0.079), 0.03)
        sc.add(RoundCone(kn, hem, 0.079, 0.075), 0.02)
    return sc


# ---------------------------------------------------------------------------
# cut lines (functions of position) - faces beyond them are removed
# ---------------------------------------------------------------------------
def shirt_hem_z(x, y):
    """Shirt-tail hem: lower at centre front/back, curved up at the sides."""
    side = np.clip(np.abs(x) / 0.2, 0, 1)
    return 0.765 + 0.06 * side ** 2.2


def neck_angle(x, y):
    return np.arctan2(x, -(y - 0.018))  # 0 = front


def shirt_neck_z(x, y):
    th = np.abs(neck_angle(x, y))
    # top button open: a small V at the front
    return 1.418 - 0.072 * np.exp(-(th / 0.42) ** 2)


def cuff_plane(s):
    sh, el, wr = arm_axis(s)
    d = norm(wr - el)
    return wr + 0.018 * d, d


def pants_top_z(x, y):
    th = np.abs(np.arctan2(x, -y))
    return 0.988 - 0.012 * np.exp(-(th / 0.6) ** 2)


PANTS_HEM_Z = 0.032


# ---------------------------------------------------------------------------
# shoes
# ---------------------------------------------------------------------------
def shoe_scene(s):
    m = (lambda p: p) if s > 0 else AN.mirror
    sc = SDFScene()
    heel, ball, toe, an = m(J['heel']), m(J['ball']), m(J['toe']), m(J['ankle'])
    fwd = norm(toe - heel)
    R = frame(fwd * np.array([1, 1, 0]), (0, 0, 1))
    sc.add(Ellipsoid(heel + v3(0, -0.005, 0.022), (0.047, 0.040, 0.046), R))
    sc.add(RoundCone(an + v3(0, -0.008, -0.034), ball + v3(0, 0, 0.018), 0.046, 0.042), 0.03)
    sc.add(Ellipsoid(toe + v3(-0.004 * s, 0.020, 0.016), (0.060, 0.044, 0.028), R), 0.035)
    # sole and heel block
    mid = 0.5 * (heel + toe)
    sc.add(RoundBox(mid + v3(-0.002 * s, -0.004, -0.004), (0.122, 0.044, 0.006), 0.004, R), 0.006)
    sc.add(RoundBox(heel + v3(0, 0.004, -0.004), (0.030, 0.034, 0.012), 0.004, R), 0.004)
    # ankle opening
    sc.sub(Ellipsoid(an + v3(0, 0.004, 0.032), (0.043, 0.052, 0.040)), 0.012)
    return sc

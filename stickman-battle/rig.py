"""Stickman skeleton: forward kinematics, a little IK, pose library and keyframe tracks.

Conventions
-----------
* World units are pixels at camera zoom 1; +y is UP, ground is y = 0.
* Joint angles are degrees, CCW from +x, in the fighter's *own* frame (facing right).
  `face = -1` mirrors the whole figure.
* Every limb angle is absolute (not relative to its parent) which makes poses easy to author.
"""
import math

DEG = math.pi / 180.0

# bone lengths
TORSO, NECK, HEAD_R = 50.0, 7.0, 12.5
UA, FA = 27.0, 27.0            # upper arm / forearm
TH, SH = 35.0, 35.0            # thigh / shin
HILT, BLADE = 13.0, 112.0

JOINT_KEYS = ['torso', 'head', 'rua', 'rfa', 'lua', 'lfa', 'rth', 'rsh', 'lth', 'lsh', 'sab']
# extra numeric channels (non-angle) and their defaults
EXTRA_DEFAULTS = dict(x=0.0, air=0.0, rot=0.0, yaw=0.0, face=1.0, son=0.0, aim=0.0,
                      twohand=0.0, flail=0.0, runw=0.0, phase=0.0, walkw=0.0, scale=1.0,
                      lean_w=0.0, aura=0.0)
ANGLE_CHANNELS = set(JOINT_KEYS) | {'rot', 'yaw'}


def dr(a):
    return math.cos(a * DEG), math.sin(a * DEG)


def mk(torso=90, head=90, rua=-95, rfa=-85, lua=-85, lfa=-95, rth=-95, rsh=-90,
       lth=-85, lsh=-90, sab=-100):
    return dict(torso=torso, head=head, rua=rua, rfa=rfa, lua=lua, lfa=lfa,
                rth=rth, rsh=rsh, lth=lth, lsh=lsh, sab=sab)


# ----------------------------------------------------------------------------------------
# pose library  (facing right).  Tuned by eye with preview.py
# ----------------------------------------------------------------------------------------
POSES = {
    # relaxed, saber hanging
    'idle': mk(torso=90, head=92, rua=-100, rfa=-80, lua=-80, lfa=-100, rth=-98, rsh=-88,
               lth=-82, lsh=-92, sab=-70),
    # saber raised ready to ignite
    'raise': mk(torso=88, head=90, rua=-20, rfa=40, lua=-95, lfa=-85, rth=-98, rsh=-88,
                lth=-82, lsh=-92, sab=55),
    # classic combat stance, blade up-forward
    'guard': mk(torso=82, head=86, rua=-35, rfa=35, lua=-60, lfa=15, rth=-55, rsh=-105,
                lth=-125, lsh=-80, sab=72),
    'guard_low': mk(torso=78, head=84, rua=-60, rfa=-5, lua=-70, lfa=30, rth=-48, rsh=-112,
                    lth=-132, lsh=-78, sab=20),
    'guard_back': mk(torso=100, head=94, rua=-40, rfa=50, lua=-70, lfa=0, rth=-70, rsh=-98,
                     lth=-112, lsh=-82, sab=95),
    # overhead strike
    'wind_over': mk(torso=100, head=96, rua=125, rfa=75, lua=-30, lfa=10, rth=-62, rsh=-108,
                    lth=-130, lsh=-85, sab=150),
    'end_over': mk(torso=62, head=70, rua=20, rfa=-10, lua=-20, lfa=-50, rth=-30, rsh=-110,
                   lth=-165, lsh=-160, sab=-35),
    # horizontal slash (back across body -> forward)
    'wind_hor': mk(torso=96, head=92, rua=165, rfa=170, lua=-40, lfa=0, rth=-60, rsh=-105,
                   lth=-130, lsh=-85, sab=180),
    'end_hor': mk(torso=70, head=78, rua=0, rfa=5, lua=-120, lfa=-150, rth=-35, rsh=-105,
                  lth=-165, lsh=-150, sab=0),
    # rising slash
    'wind_rise': mk(torso=78, head=82, rua=-70, rfa=-40, lua=-110, lfa=-130, rth=-45, rsh=-110,
                    lth=-140, lsh=-100, sab=-50),
    'end_rise': mk(torso=100, head=100, rua=75, rfa=95, lua=-120, lfa=-110, rth=-80, rsh=-100,
                   lth=-130, lsh=-110, sab=110),
    # thrust
    'wind_thrust': mk(torso=95, head=90, rua=-75, rfa=130, lua=-25, lfa=-10, rth=-62, rsh=-100,
                      lth=-125, lsh=-80, sab=2),
    'end_thrust': mk(torso=55, head=62, rua=5, rfa=3, lua=-130, lfa=-170, rth=-25, rsh=-110,
                     lth=-170, lsh=-175, sab=3),
    # parries
    'parry_high': mk(torso=95, head=92, rua=30, rfa=80, lua=-40, lfa=10, rth=-60, rsh=-105,
                     lth=-125, lsh=-80, sab=125),
    'parry_mid': mk(torso=88, head=90, rua=-10, rfa=45, lua=-60, lfa=-10, rth=-58, rsh=-105,
                    lth=-125, lsh=-80, sab=95),
    'parry_low': mk(torso=80, head=82, rua=-50, rfa=-20, lua=-70, lfa=-20, rth=-50, rsh=-112,
                    lth=-132, lsh=-78, sab=-45),
    # saber lock / press (two hands)
    'lock': mk(torso=66, head=72, rua=-15, rfa=22, lua=-35, lfa=15, rth=-34, rsh=-118,
               lth=-160, lsh=-112, sab=75),
    'lock_low': mk(torso=60, head=70, rua=-25, rfa=15, lua=-45, lfa=0, rth=-28, rsh=-130,
                   lth=-175, lsh=-100, sab=60),
    # evade
    'crouch': mk(torso=62, head=70, rua=-40, rfa=20, lua=-70, lfa=-10, rth=-30, rsh=-150,
                 lth=-150, lsh=-95, sab=80),
    'lean_back': mk(torso=122, head=112, rua=-60, rfa=20, lua=-100, lfa=-40, rth=-70, rsh=-115,
                    lth=-120, lsh=-80, sab=95),
    # airborne
    'jump_up': mk(torso=95, head=95, rua=80, rfa=95, lua=60, lfa=100, rth=-50, rsh=-130,
                  lth=-110, lsh=-150, sab=95),
    'air_tuck': mk(torso=100, head=110, rua=-30, rfa=40, lua=-50, lfa=20, rth=-20, rsh=-140,
                   lth=-35, lsh=-155, sab=100),
    'air_slash': mk(torso=70, head=78, rua=40, rfa=-30, lua=-10, lfa=-60, rth=-40, rsh=-125,
                    lth=-120, lsh=-170, sab=-40),
    'air_spread': mk(torso=95, head=95, rua=20, rfa=10, lua=160, lfa=170, rth=-40, rsh=-60,
                     lth=-140, lsh=-120, sab=10),
    'land': mk(torso=58, head=66, rua=-30, rfa=30, lua=-60, lfa=-10, rth=-35, rsh=-150,
               lth=-145, lsh=-100, sab=60),
    # force push
    'push': mk(torso=78, head=82, rua=-140, rfa=-170, lua=2, lfa=12, rth=-38, rsh=-105,
               lth=-158, lsh=-150, sab=-150),
    'push_wind': mk(torso=100, head=96, rua=-110, rfa=-150, lua=100, lfa=40, rth=-70, rsh=-100,
                    lth=-115, lsh=-85, sab=-140),
    # hurt / flung / ground
    'hurt': mk(torso=115, head=125, rua=140, rfa=100, lua=170, lfa=190, rth=-80, rsh=-70,
               lth=-105, lsh=-120, sab=170),
    'fling': mk(torso=140, head=150, rua=170, rfa=200, lua=120, lfa=150, rth=-60, rsh=-30,
                lth=-100, lsh=-140, sab=190),
    'lying': mk(torso=178, head=178, rua=-120, rfa=-150, lua=-60, lfa=-20, rth=-10, rsh=-8,
                lth=-5, lsh=-12, sab=-170),
    'kneel': mk(torso=82, head=80, rua=-80, rfa=-70, lua=-100, lfa=-110, rth=-20, rsh=-92,
                lth=-110, lsh=-170, sab=-60),
    'kneel_guard': mk(torso=84, head=86, rua=-35, rfa=35, lua=-65, lfa=10, rth=-20, rsh=-90,
                      lth=-112, lsh=-172, sab=70),
    'hunch': mk(torso=40, head=50, rua=-80, rfa=-100, lua=-100, lfa=-85, rth=-70, rsh=-100,
                lth=-110, lsh=-80, sab=-100),
    # emotion
    'rage_down': mk(torso=62, head=40, rua=-110, rfa=-120, lua=-70, lfa=-60, rth=-48, rsh=-95,
                    lth=-132, lsh=-85, sab=-110),
    'rage_up': mk(torso=108, head=118, rua=-150, rfa=-170, lua=-30, lfa=-10, rth=-52, rsh=-100,
                  lth=-128, lsh=-80, sab=130),
    'kneel_up': mk(torso=92, head=96, rua=62, rfa=100, lua=72, lfa=108, rth=-25, rsh=-92,
                   lth=-115, lsh=-172, sab=92),
    'push_back': mk(torso=90, head=100, rua=-40, rfa=45, lua=176, lfa=182, rth=-55, rsh=-105,
                    lth=-125, lsh=-80, sab=75),
    'victory': mk(torso=96, head=100, rua=75, rfa=88, lua=-80, lfa=-100, rth=-70, rsh=-95,
                  lth=-110, lsh=-88, sab=95),
    'kick': mk(torso=115, head=105, rua=-90, rfa=-60, lua=-30, lfa=20, rth=5, rsh=0,
               lth=-95, lsh=-90, sab=100),
    'throw': mk(torso=70, head=78, rua=30, rfa=15, lua=-120, lfa=-140, rth=-40, rsh=-105,
                lth=-160, lsh=-150, sab=25),
    'catch': mk(torso=88, head=90, rua=40, rfa=50, lua=-70, lfa=-30, rth=-60, rsh=-100,
                lth=-120, lsh=-82, sab=60),
}


def pose_mix(a, b, t):
    """linear mix of two poses (names or dicts)"""
    a = POSES[a] if isinstance(a, str) else a
    b = POSES[b] if isinstance(b, str) else b
    return {k: a[k] + (b[k] - a[k]) * t for k in JOINT_KEYS}


def run_angles(phase, lean=1.0):
    """procedural sprint with a trailing saber arm. returns joint dict"""
    a = 2 * math.pi * phase
    s, c = math.sin(a), math.cos(a)
    rth = -90 + 52 * s
    lth = -90 - 52 * s
    rsh = rth - 18 - 78 * max(0.0, math.cos(a + 0.5))
    lsh = lth - 18 - 78 * max(0.0, -math.cos(a + 0.5))
    return dict(torso=72 * lean + 90 * (1 - lean), head=80, rth=rth, rsh=rsh, lth=lth, lsh=lsh,
                rua=-130 + 6 * s, rfa=-160 + 8 * s,
                lua=-90 - 55 * s, lfa=-90 - 55 * s + 70 + 20 * s, sab=-170)


def walk_angles(phase):
    """slow stalking walk in guard stance"""
    a = 2 * math.pi * phase
    s = math.sin(a)
    rth = -78 + 24 * s
    lth = -102 - 24 * s
    rsh = rth - 12 - 38 * max(0.0, math.cos(a + 0.4))
    lsh = lth + 12 + 38 * max(0.0, -math.cos(a + 0.4)) * -1
    return dict(rth=rth, rsh=rsh, lth=lth, lsh=lsh)


# ----------------------------------------------------------------------------------------
# keyframed scalar tracks
# ----------------------------------------------------------------------------------------
def _ease(name, u):
    u = 0.0 if u < 0 else 1.0 if u > 1 else u
    if name == 'lin':
        return u
    if name == 'smooth':
        return u * u * (3 - 2 * u)
    if name == 'in':
        return u * u * u
    if name == 'in2':
        return u * u
    if name == 'out':
        return 1 - (1 - u) ** 3
    if name == 'out2':
        return 1 - (1 - u) ** 2
    if name == 'snap':          # very fast in the first part, tiny settle
        return 1 - (1 - u) ** 5
    if name == 'back':          # slight overshoot
        c1 = 1.9
        c3 = c1 + 1
        return 1 + c3 * (u - 1) ** 3 + c1 * (u - 1) ** 2
    if name == 'inout':
        return 4 * u * u * u if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2
    if name == 'hold':
        return 0.0 if u < 1 else 1.0
    raise KeyError(name)


class Track:
    __slots__ = ('keys', 'angle')

    def __init__(self, angle=False):
        self.keys = []      # (t, value, ease)
        self.angle = angle

    def add(self, t, v, ease='smooth'):
        # keep sorted; replace identical times
        for i, k in enumerate(self.keys):
            if abs(k[0] - t) < 1e-9:
                self.keys[i] = (t, v, ease)
                return
        self.keys.append((t, v, ease))
        self.keys.sort(key=lambda k: k[0])

    def __call__(self, t):
        ks = self.keys
        if not ks:
            return 0.0
        if t <= ks[0][0]:
            return ks[0][1]
        if t >= ks[-1][0]:
            return ks[-1][1]
        lo, hi = 0, len(ks) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if ks[mid][0] <= t:
                lo = mid
            else:
                hi = mid
        t0, v0, _ = ks[lo]
        t1, v1, e1 = ks[hi]
        if self.angle:
            dv = (v1 - v0 + 180.0) % 360.0 - 180.0
            v1 = v0 + dv
        u = (t - t0) / (t1 - t0)
        return v0 + (v1 - v0) * _ease(e1, u)


# ----------------------------------------------------------------------------------------
# forward kinematics
# ----------------------------------------------------------------------------------------
def _add(p, q, s=1.0):
    return (p[0] + q[0] * s, p[1] + q[1] * s)


def ik2(a, target, l1, l2, bend):
    """two-bone IK from a toward target. bend=+1/-1 chooses elbow side. returns joint pos."""
    dx, dy = target[0] - a[0], target[1] - a[1]
    dist = math.hypot(dx, dy)
    dist = max(1e-6, min(dist, l1 + l2 - 1e-3))
    base = math.atan2(dy, dx)
    cosang = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    cosang = max(-1.0, min(1.0, cosang))
    ang = base + bend * math.acos(cosang)
    return (a[0] + l1 * math.cos(ang), a[1] + l1 * math.sin(ang))


def skeleton(p, face=1.0, yaw=0.0, rot=0.0):
    """p: dict of joint angles + 'twohand', 'flail' etc.  Returns local joint positions
    (relative to the pelvis, y up) after mirror / yaw / rotation."""
    P = (0.0, 0.0)
    td = dr(p['torso'])
    N = (td[0] * TORSO, td[1] * TORSO)
    S = (td[0] * (TORSO - 3), td[1] * (TORSO - 3))
    hd = dr(p['head'])
    Hc = (N[0] + hd[0] * (NECK + HEAD_R), N[1] + hd[1] * (NECK + HEAD_R))

    re = _add(S, dr(p['rua']), UA)
    rh = _add(re, dr(p['rfa']), FA)
    le = _add(S, dr(p['lua']), UA)
    lh = _add(le, dr(p['lfa']), FA)

    sd = dr(p['sab'])
    # saber geometry
    pommel = _add(rh, sd, -6.0)
    hilt_top = _add(rh, sd, HILT - 6.0)
    # two-handed grip: left hand to the pommel end of the hilt
    w = p.get('twohand', 0.0)
    if w > 1e-3:
        tgt = _add(rh, sd, -7.0)
        lh2 = (lh[0] + (tgt[0] - lh[0]) * w, lh[1] + (tgt[1] - lh[1]) * w)
        bend = -1.0 if True else 1.0
        le2 = ik2(S, lh2, UA, FA, bend)
        # make sure elbow ends up below the line (natural); flip if above
        alt = ik2(S, lh2, UA, FA, -bend)
        if alt[1] < le2[1]:
            le2 = alt
        le = (le[0] + (le2[0] - le[0]) * w, le[1] + (le2[1] - le[1]) * w)
        lh = lh2

    rk = _add(P, dr(p['rth']), TH)
    rf = _add(rk, dr(p['rsh']), SH)
    lk = _add(P, dr(p['lth']), TH)
    lf = _add(lk, dr(p['lsh']), SH)

    J = dict(P=P, N=N, S=S, H=Hc, re=re, rh=rh, le=le, lh=lh, rk=rk, rf=rf, lk=lk, lf=lf,
             pommel=pommel, hilt=hilt_top)
    son = p.get('son', 1.0)
    J['tip'] = _add(hilt_top, sd, BLADE * son)

    c = math.cos(yaw * DEG)
    ca, sa = math.cos(rot * DEG), math.sin(rot * DEG)
    cx, cy = 0.0, TORSO * 0.45
    out = {}
    for k, (x, y) in J.items():
        x = x * face * c
        # rotate around body center
        dx, dy = x - cx * face, y - cy
        x2 = cx * face + dx * ca - dy * sa
        y2 = cy + dx * sa + dy * ca
        out[k] = (x2, y2)
    return out


LOW_JOINTS = ('rf', 'lf', 'rk', 'lk', 'rh', 'lh', 're', 'le', 'N', 'P', 'H')


def lowest(J):
    lows = []
    for k in LOW_JOINTS:
        y = J[k][1]
        if k == 'H':
            y -= HEAD_R
        if k in ('rf', 'lf'):
            y -= 1
        lows.append(y)
    return min(lows)

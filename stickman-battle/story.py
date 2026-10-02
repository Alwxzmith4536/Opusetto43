"""Choreography: green vs blue vs yellow on an ash planet.  Yellow wins."""
import math
from rig import *
from scene import *

FPS = 60
GREEN = (0.10, 0.80, 0.32)
BLUE = (0.14, 0.44, 1.0)
YELLOW = (1.0, 0.76, 0.04)
T_END = 59.8


def wind(t):
    return t * 0.6 + 1.2 * math.sin(t * 0.35)


class Scene:
    def __init__(self):
        self.events = []
        self.sfx_list = []
        self.flashes = []
        self.inverts = []
        self.speed_lines = []
        self.whites = []        # (script_t_start, script_t_end_ramp) fade-to-white spans
        self.cam = Camera()
        self.warp = TimeWarp()
        self.fighters = {}

    # ---- helpers ------------------------------------------------------------
    def snd(self, t, kind, **kw):
        self.sfx_list.append((t, kind, kw))

    def clash(self, t, a, b, lift=45.0, power=1.0, shake=None, quiet=False):
        self.events.append(Event(t, 'clash', None, None, power=power, at=(a, b, lift)))
        self.snd(t, 'clash', power=power, at=(a, b, lift))
        sh = shake if shake is not None else 5 + 11 * power
        self.cam.shake(t, sh, 0.22 + 0.16 * power)

    def hit(self, t, x, y, power=1.0, color=(1, 0.85, 0.4), shake=None):
        self.events.append(Event(t, 'hit', x, y, power=power, color=color))
        self.snd(t, 'hit', power=power, x=x)
        self.cam.shake(t, shake if shake is not None else 8 + 14 * power, 0.3 + 0.15 * power)

    def push(self, t, x, y, d, color=(1, 1, 1), life=0.7):
        self.events.append(Event(t, 'push', x, y, dir=d, color=color, life=life))
        self.snd(t, 'push', x=x)
        self.cam.shake(t, 10, 0.4)

    def dust(self, t, x, y=0, n=9, spread=120, d=0, life=1.0, snd=True):
        self.events.append(Event(t, 'dust', x, y, n=n, spread=spread, dir=d, life=life))
        if snd:
            self.snd(t, 'thud', x=x, power=min(1.5, spread / 140.0))

    def ring(self, t, x, maxr=700, color=(1, 1, 1), life=0.9, flat=0.22):
        self.events.append(Event(t, 'ring', x, 0, maxr=maxr, color=color, life=life, flat=flat))

    def debris(self, t, x, y=0, n=14, power=1.0, side=None):
        self.events.append(Event(t, 'debris', x, y, n=n, power=power, side=side))

    def flash(self, t, amp=0.8, dur=0.25):
        self.flashes.append((t, amp, dur))

    def invert(self, t, dur=0.09):
        self.inverts.append((t, dur))

    def slow(self, s0, s1, v):
        self.warp.slow(s0, s1, v)

    def finalize(self):
        F = self.fighters
        for ev in self.events:
            if ev.kw.get('at') is not None:
                a, b, lift = ev.kw['at']
                ja = F[a].state(ev.t)['J']['rh']
                jb = F[b].state(ev.t)['J']['rh']
                ev.x = (ja[0] + jb[0]) / 2
                ev.y = (ja[1] + jb[1]) / 2 + lift
        for ev in self.events:
            if ev.kw.get('tipof') is not None:
                f, frac = ev.kw['tipof']
                st = f.state(ev.t)['J']
                h, tp = st['hilt'], st['tip']
                ev.x = h[0] + (tp[0] - h[0]) * frac
                ev.y = h[1] + (tp[1] - h[1]) * frac
        self.events.sort(key=lambda e: e.t)
        self.warp.bake(T_END)
        self.cam.bake(F, T_END)

    # ---- render hooks ---------------------------------------------------------
    def zorder(self, f, t):
        if f.dead_t is not None and t >= f.dead_t:
            return -1
        return {'blue': 0, 'green': 1, 'yellow': 2}[f.name]

    def fx(self, ot, t, cam):
        d = dict(chroma=1.0)
        fl = 0.0
        for (ts, amp, dec) in self.flashes:
            a = ot - self.warp.to_out(ts)
            if 0 <= a < dec:
                fl = max(fl, amp * (1 - a / dec) ** 2)
        d['flash'] = fl
        for (ts, dur) in self.inverts:
            o0 = self.warp.to_out(ts)
            if o0 <= ot < o0 + dur:
                d['invert'] = True
        sh = 0.0
        for (t0, amp, dur, freq) in self.cam.shakes:
            age = t - t0
            if 0 <= age < dur:
                sh += amp * (1 - age / dur)
        d['chroma'] = 1.0 + min(4.0, sh / 9.0)
        d['blur'] = cam['blur']
        w = 0.0
        if ot < 1.5:
            w = max(w, 1.0 - smooth_(ot / 1.5))
        for (a, b) in self.whites:
            w = max(w, smooth_((t - a) / (b - a)))
        d['white'] = w
        return d


def smooth_(u):
    u = max(0.0, min(1.0, u))
    return u * u * (3 - 2 * u)


def build():
    S = Scene()
    B = register(Fighter('blue', BLUE, (0.04, 0.12, 0.42)))
    G = register(Fighter('green', GREEN, (0.02, 0.30, 0.10)))
    Y = register(Fighter('yellow', YELLOW, (0.50, 0.32, 0.0)))
    S.fighters = dict(blue=B, green=G, yellow=Y)
    Y.aura_cols = ((1.0, 0.85, 0.15), (1.0, 0.45, 0.05))
    G.aura_cols = ((0.35, 1.0, 0.45), (0.0, 0.55, 0.2))
    cam = S.cam

    act1(S, B, G, Y)
    act2(S, B, G, Y)
    act3(S, B, G, Y)
    act3b(S, B, G, Y)
    act4(S, B, G, Y)
    act5(S, B, G, Y)

    S.finalize()
    return S


# =====================================================================================
# authoring helpers
# =====================================================================================
def sgn(f, t):
    return 1.0 if f.tr['face'](t) >= 0 else -1.0


def turn(f, t0, t1, to_face):
    """quick body turn: yaw 0->180 then swap facing"""
    f.key(t0, yaw=(0.0, 'lin'))
    f.key(t1, yaw=(180.0, 'smooth'))
    f.key(t1 + 0.001, yaw=(0.0, 'lin'), face=(to_face, 'hold'))


def spin(f, t0, t1, turns=1.0):
    f.key(t0, yaw=(0.0, 'lin'))
    f.key(t1, yaw=(360.0 * turns, 'lin'))
    f.key(t1 + 0.001, yaw=(0.0, 'lin'))


def tip_point(f, frac=0.8):
    def fn(t):
        st = f.state(t)['J']
        h, tp = st['hilt'], st['tip']
        return (h[0] + (tp[0] - h[0]) * frac, h[1] + (tp[1] - h[1]) * frac)
    return fn


def ex(S, A, D, t, atk=('wind_hor', 'lock'), par='parry_mid', lift=45.0, hold=0.28, lunge=35.0,
       power=1.0, wind_dt=0.26, a_two=False, d_two=False, rec=('guard', 'guard'), rec_dt=0.25,
       sparks=True):
    """A attacks, D parries, blades meet at time t and stay locked for `hold`."""
    sg = sgn(A, t)
    x0 = A.tr['x'](t - wind_dt)
    A.key(t - wind_dt, atk[0], ease='out', x=(x0, 'lin'), twohand=(1.0 if a_two else 0.0, 'smooth'))
    A.key(t - 0.04, atk[1], ease='in2', x=(x0 + lunge * sg, 'out2'))
    A.key(t + hold, atk[1], ease='lin', x=(x0 + lunge * sg, 'lin'))
    A.key(t + hold + rec_dt, rec[0], ease='out', x=(x0 + lunge * sg * 0.45, 'out2'), twohand=(0.0, 'smooth'))
    D.key(t - 0.22, par, ease='out', twohand=(1.0 if d_two else 0.0, 'smooth'))
    D.key(t + hold, par, ease='lin')
    D.key(t + hold + rec_dt, rec[1], ease='out', twohand=(0.0, 'smooth'))
    A.aim(t - 0.05, t + hold, D.name, lift)
    D.aim(t - 0.05, t + hold, A.name, lift)
    S.clash(t, A.name, D.name, lift=lift, power=power)
    if sparks:
        tt = t + 0.14
        while tt < t + hold - 0.05:
            S.clash(tt, A.name, D.name, lift=lift, power=0.35, shake=2)
            tt += 0.13
    return t + hold + rec_dt


def catmull(pts, t):
    """pts: [(t, x, y, ang)] -> (x, y, ang) smooth through the points"""
    if t <= pts[0][0]:
        return pts[0][1:]
    if t >= pts[-1][0]:
        return pts[-1][1:]
    i = 0
    while pts[i + 1][0] < t:
        i += 1
    p0 = pts[max(0, i - 1)]
    p1, p2 = pts[i], pts[i + 1]
    p3 = pts[min(len(pts) - 1, i + 2)]
    u = (t - p1[0]) / (p2[0] - p1[0])
    out = []
    for k in (1, 2):
        m1 = (p2[k] - p0[k]) / max(1e-6, (p2[0] - p0[0])) * (p2[0] - p1[0])
        m2 = (p3[k] - p1[k]) / max(1e-6, (p3[0] - p1[0])) * (p2[0] - p1[0])
        h00 = 2 * u ** 3 - 3 * u ** 2 + 1
        h10 = u ** 3 - 2 * u ** 2 + u
        h01 = -2 * u ** 3 + 3 * u ** 2
        h11 = u ** 3 - u ** 2
        out.append(h00 * p1[k] + h10 * m1 + h01 * p2[k] + h11 * m2)
    out.append(p1[3] + (p2[3] - p1[3]) * (u * u * (3 - 2 * u)))
    return tuple(out)


def free_saber(f, pts):
    """detach f's saber and fly it through waypoints [(t,x,y,ang),...]"""
    f.saber_free.append((pts[0][0], pts[-1][0], lambda t, pts=pts: catmull(pts, t)))


def hand(f, t, j='rh'):
    return f.state(t)['J'][j]


# =====================================================================================
# ACT 1  - arrival, ignition, standoff
# =====================================================================================
def act1(S, B, G, Y):
    cam = S.cam
    B.key(0, 'idle', x=-430, face=1)
    G.key(0, 'idle', x=430, face=-1)
    Y.key(0, 'idle', x=0, face=1)

    # blue ignites
    B.key(2.30, 'idle')
    B.key(2.95, 'raise', ease='out')
    B.key(3.28, son=(1.0, 'out'))
    B.key(3.05, son=0.0)
    B.key(3.95, 'guard', ease='smooth')
    # green
    G.key(3.70, 'idle')
    G.key(4.20, 'raise', ease='out')
    G.key(4.62, son=(1.0, 'out'))
    G.key(4.40, son=0.0)
    G.key(5.30, 'guard_low', ease='smooth')
    # yellow (slow, confident)
    Y.key(4.85, 'idle')
    Y.key(5.55, 'raise', ease='out')
    Y.key(5.85, son=(1.0, 'out'))
    Y.key(5.65, son=0.0)
    Y.key(6.5, 'guard_low', ease='smooth')

    # slow stalking circle
    B.key(6.3, 'guard')
    B.walk(6.3, 7.75, -430, -335)
    G.key(6.3, 'guard_low')
    G.walk(6.3, 7.75, 430, 340)
    Y.key(7.0, 'guard_low')
    Y.key(7.6, 'guard')

    # camera
    cam.key(0, cx=0, cy=92, zoom=1.10)
    cam.key(2.5, cx=0, cy=88, zoom=1.30, ease='lin')
    cam.cut(2.55, cx=-405, cy=92, zoom=3.0)
    cam.key(3.7, cx=-395, cy=96, zoom=3.35, ease='lin')
    cam.cut(3.75, cx=405, cy=92, zoom=3.0)
    cam.key(4.8, cx=395, cy=96, zoom=3.35, ease='lin')
    cam.cut(4.85, cx=18, cy=98, zoom=2.9)
    cam.key(6.2, cx=14, cy=102, zoom=3.3, ease='lin')
    cam.cut(6.25, cx=0, cy=86, zoom=1.25)
    cam.key(7.0, cx=0, cy=84, zoom=1.42, ease='lin')
    # pebble drops
    S.events.append(Event(7.0, 'pebble', -95, 0, y0=440))
    cam.cut(7.05, cx=-95, cy=330, zoom=2.6)
    cam.key(7.76, cx=-95, cy=40, zoom=3.0, ease='in2')
    S.dust(7.78, -95, n=5, spread=40, life=0.7, snd=False)
    S.snd(7.78, 'tick')
    cam.cut(7.9, cx=0, cy=80, zoom=1.5)

    # ignition flashes and sounds
    for (t, f) in ((3.28, B), (4.62, G), (5.85, Y)):
        S.snd(t - 0.02, 'ignite', who=f.name)
        S.flash(t + 0.02, 0.0, 0.1)
    S.snd(0.0, 'start')


# =====================================================================================
# ACT 2  - blue and green charge, yellow flips over, first clash, force push
# =====================================================================================
def act2(S, B, G, Y):
    cam = S.cam
    # reaction crouch -> sprint
    B.key(7.82, 'guard'); B.key(8.10, 'crouch', ease='out')
    G.key(7.82, 'guard_low'); G.key(8.10, 'crouch', ease='out')
    B.run(8.15, 8.72, -335, -92, ease='lin')
    G.run(8.15, 8.72, 340, 92, ease='lin')
    B.key(8.45, 'wind_hor', ease='out')
    G.key(8.45, 'wind_over', ease='out')
    B.key(8.95, 'lock', ease='in2', x=(-95, 'out'))
    G.key(8.95, 'lock', ease='in2', x=(95, 'out'))
    B.key(8.95, twohand=0.0); G.key(8.95, twohand=0.0)
    B.key(9.05, twohand=(1.0, 'out')); G.key(9.05, twohand=(1.0, 'out'))
    B.key(10.4, 'lock', twohand=1.0); G.key(10.4, 'lock', twohand=1.0)
    B.aim(8.90, 10.45, 'green', lift=48)
    G.aim(8.90, 10.45, 'blue', lift=48)

    # yellow's flip over green
    Y.key(7.9, 'guard')
    Y.key(8.30, 'crouch', ease='out')
    Y.key(8.52, 'jump_up', ease='snap', x=(0, 'lin'), air=(0.0, 'lin'))
    Y.key(8.98, 'air_tuck', ease='out2', air=(205.0, 'out2'), x=(150, 'lin'))
    Y.key(9.50, 'land', ease='in2', air=(0.0, 'in2'), x=(330, 'lin'))
    Y.key(8.58, rot=(0.0, 'lin'))
    Y.key(9.40, rot=(-360.0, 'smooth'))
    Y.key(9.56, face=(-1.0, 'hold'), rot=(-360.0, 'lin'))
    Y.key(9.58, rot=(0.0, 'lin'))
    Y.key(9.9, 'guard', ease='out')
    Y.walk(9.9, 10.25, 330, 262)
    Y.key(10.22, 'push_wind', ease='out')
    Y.key(10.38, 'push', ease='snap')
    Y.key(10.9, 'push', ease='lin')
    Y.key(11.5, 'guard_low', ease='smooth')

    # clash sparks
    S.clash(9.02, 'blue', 'green', lift=48, power=1.5)
    S.slow(8.98, 9.42, 0.3)
    S.flash(9.02, 0.55, 0.3)
    S.invert(9.02, 0.07)
    t = 9.3
    while t < 10.4:
        S.clash(t, 'blue', 'green', lift=48, power=0.45, shake=3)
        t += 0.17
    S.dust(9.52, 330, n=8, spread=110, d=0, life=0.8)

    # force push
    hp = hand(Y, 10.42, 'lh')
    S.push(10.42, hp[0] - 20, hp[1], -1, color=YELLOW)

    # blue + green thrown to the left
    G.key(10.50, 'lock', twohand=1.0, aim=(1.0, 'lin'))
    for f, xs, dly in ((G, 95, 0.0), (B, -95, 0.07)):
        t0 = 10.56 + dly
        f.key(t0 - 0.03, 'lock', twohand=1.0)
        f.key(t0, 'fling', ease='snap', twohand=0.0, flail=0.0)
        f.key(t0 + 0.2, flail=(1.0, 'out'))
        f.key(t0, x=(xs, 'lin'), air=(0.0, 'lin'), rot=(0.0, 'lin'), son=1.0)
        f.key(t0 + 0.9, x=(xs - 330 - (60 if f is B else 0), 'out2'))
        f.key(t0 + 0.30, air=(95.0, 'out2'))
        f.key(t0 + 0.78, air=(0.0, 'in2'))
        f.key(t0 + 0.80, rot=(330.0, 'smooth'))
        f.key(t0 + 0.82, 'lying', ease='snap', flail=(0.0, 'lin'), rot=(360.0, 'lin'))
        f.key(t0 + 1.05, x=(xs - 400 - (60 if f is B else 0), 'out'))
        f.key(t0 + 1.2, 'lying', ease='lin')
        f.key(t0 + 1.45, 'kneel_guard', ease='out', rot=(360.0, 'lin'))
        f.key(t0 + 1.85, 'guard', ease='out')
    G.aim_segs[:] = [s for s in G.aim_segs]
    S.hit(10.60, hand(G, 10.60, 'N')[0], hand(G, 10.60, 'N')[1], power=1.1, color=(1, 0.9, 0.5))
    S.slow(10.52, 10.95, 0.45)
    S.invert(10.60, 0.06)
    S.dust(11.40, G.tr['x'](11.4), n=10, spread=170, d=-1, life=1.1)
    S.dust(11.50, B.tr['x'](11.5), n=10, spread=170, d=-1, life=1.1)

    # camera
    cam.cut(7.9, cx=0, cy=90, zoom=1.5)
    cam.auto(7.9, 8.8, ['blue', 'green', 'yellow'], margin=520, zmin=1.2, zmax=2.0, yc=95)
    cam.cut(8.84, cx=40, cy=150, zoom=1.85, rot=-3)
    cam.key(9.6, cx=120, cy=150, zoom=1.9, rot=-1, ease='lin')
    cam.key(10.0, cx=250, cy=100, zoom=1.8, rot=0, ease='smooth')
    cam.cut(10.2, cx=300, cy=105, zoom=3.0, rot=0)
    cam.key(10.5, cx=290, cy=105, zoom=3.2, ease='lin')
    cam.cut(10.56, cx=-60, cy=95, zoom=1.7)
    cam.key(11.2, cx=-210, cy=70, zoom=1.7, ease='lin')
    cam.auto(11.4, 12.9, ['blue', 'green', 'yellow'], margin=520, zmin=1.0, zmax=1.9, yc=90)


# =====================================================================================
# ACT 3  - yellow against both
# =====================================================================================
def act3(S, B, G, Y):
    cam = S.cam
    # yellow strides to the middle and waits
    Y.key(11.5, 'guard_low')
    Y.walk(11.6, 12.4, 262, 120)
    Y.key(12.45, 'guard', face=-1.0)

    # blue sprints, then flips over yellow's head
    B.run(12.45, 12.98, -555, -300)
    B.key(13.02, 'crouch', ease='out', x=-300)
    B.key(13.14, 'jump_up', ease='snap', x=(-300, 'lin'), air=(0.0, 'lin'), rot=(0.0, 'lin'))
    B.key(13.40, 'air_slash', ease='out2', air=(175.0, 'out2'), x=(20, 'lin'))
    B.key(13.72, 'land', ease='in2', air=(0.0, 'in2'), x=(290, 'lin'))
    B.key(13.62, rot=(-360.0, 'smooth'))
    B.key(13.76, face=(-1.0, 'hold'), rot=(-360.0, 'lin'))
    B.key(13.78, rot=(0.0, 'lin'))
    B.key(13.95, 'guard', ease='out')

    # green sprints in, high slash parried
    G.key(12.46, 'guard')
    G.run(12.75, 13.2, -305, -62)
    ex(S, G, Y, 13.52, atk=('wind_hor', 'end_hor'), par='parry_mid', lift=-22, hold=0.22, lunge=30,
       power=1.2, wind_dt=0.3)
    # yellow kicks green away and turns on blue
    Y.key(13.88, 'kick', ease='snap')
    Y.key(14.02, 'kick', ease='lin')
    S.hit(13.9, G.tr['x'](13.9) + 40, 70, power=0.9, color=YELLOW)
    G.key(13.86, 'guard', ease='lin')
    G.key(13.95, 'hurt', ease='snap', x=(G.tr['x'](13.86), 'lin'))
    G.key(14.35, 'hurt', ease='out', x=(-190, 'out2'))
    G.key(14.65, 'guard', ease='out')
    turn(Y, 14.02, 14.2, 1.0)
    Y.key(14.2, 'guard', ease='out')

    # blue attacks from behind, yellow meets it
    ex(S, B, Y, 14.5, atk=('wind_over', 'lock'), par='parry_high', lift=48, hold=0.25, lunge=25,
       power=1.1, wind_dt=0.3, a_two=True)
    # yellow spins: blades meet green (left) then blue (right)
    Y.key(14.80, 'end_hor', ease='out', x=(Y.tr['x'](14.8), 'lin'))
    spin(Y, 14.85, 15.4, 1.0)
    Y.key(15.45, 'end_hor', ease='lin')
    Y.key(15.9, 'guard', ease='out')
    G.run(14.4, 14.85, -190, -40)
    G.key(14.9, 'end_thrust', ease='out')
    G.key(15.12, 'end_thrust', ease='lin')
    G.key(15.5, 'guard', ease='out')
    G.aim(15.0, 15.2, tip_point(Y, 0.85), 0)
    B.key(15.05, 'guard', ease='out')
    B.key(15.25, 'wind_over', ease='out')
    B.key(15.40, 'end_over', ease='in2')
    B.key(15.55, 'end_over', ease='lin')
    B.key(15.95, 'guard', ease='out')
    B.aim(15.3, 15.5, tip_point(Y, 0.85), 0)
    S.events.append(Event(15.12, 'clash', None, None, power=1.0, tipof=(Y, 0.85), col=None))
    S.snd(15.12, 'clash', power=1.0)
    S.events.append(Event(15.40, 'clash', None, None, power=1.0, tipof=(Y, 0.85)))
    S.snd(15.40, 'clash', power=1.0)
    S.cam.shake(15.12, 12, 0.3); S.cam.shake(15.4, 12, 0.3)

    cam.cut(12.4, cx=-60, cy=95, zoom=1.35)
    cam.auto(12.5, 16.0, ['blue', 'green', 'yellow'], margin=360, zmin=1.1, zmax=2.2, yc=100)


def act3b(S, B, G, Y):
    cam = S.cam
    # ---- simultaneous attack, yellow ducks, blue & green clash above him ---------------
    gx, bx = G.tr['x'](16.0), B.tr['x'](16.0)
    G.key(16.0, 'guard', x=(gx, 'lin'))
    B.key(16.0, 'guard', x=(bx, 'lin'))
    G.key(16.22, 'wind_thrust', ease='out', x=(gx, 'lin'), twohand=(0.0, 'lin'))
    B.key(16.22, 'wind_over', ease='out', x=(bx, 'lin'), twohand=(0.0, 'lin'))
    G.key(16.52, 'lock', ease='in2', x=(18, 'out2'), twohand=(1.0, 'out'))
    B.key(16.52, 'lock', ease='in2', x=(222, 'out2'), twohand=(1.0, 'out'))
    G.key(17.15, 'lock', ease='lin', twohand=1.0)
    B.key(17.15, 'lock', ease='lin', twohand=1.0)
    G.aim(16.47, 17.15, 'blue', lift=62)
    B.aim(16.47, 17.15, 'green', lift=62)
    S.clash(16.58, 'green', 'blue', lift=62, power=1.6)
    for tt in (16.8, 16.95, 17.08):
        S.clash(tt, 'green', 'blue', lift=62, power=0.4, shake=2)
    S.slow(16.5, 16.9, 0.35)
    S.invert(16.58, 0.06)

    yx = Y.tr['x'](16.0)
    Y.key(16.0, 'guard', x=(yx, 'lin'))
    Y.key(16.40, 'lean_back', ease='snap', x=(yx, 'lin'))
    Y.key(17.0, 'lean_back', ease='lin')
    # roll away to the left under the locked blades
    Y.key(17.12, 'crouch', ease='out')
    Y.key(17.2, 'air_tuck', ease='out2', x=(yx, 'lin'), rot=(0.0, 'lin'))
    Y.key(17.62, 'air_tuck', ease='lin', x=(-260, 'out2'), rot=(360.0, 'inout'))
    Y.key(17.7, 'crouch', ease='out', rot=(360.0, 'lin'))
    Y.key(17.72, rot=(0.0, 'lin'))
    Y.key(17.95, 'guard_low', ease='out')
    S.dust(17.66, -260, n=8, spread=120, d=-1, life=0.9)

    # ---- blue and green fight each other --------------------------------------------
    end = ex(S, G, B, 17.55, atk=('wind_over', 'end_over'), par='parry_high', lift=50, hold=0.2,
             lunge=50, power=1.0, wind_dt=0.3, rec=('guard', 'guard'), rec_dt=0.2)
    end = ex(S, B, G, 18.3, atk=('wind_hor', 'end_hor'), par='parry_mid', lift=-24, hold=0.2,
             lunge=55, power=1.0, wind_dt=0.28, rec=('guard', 'guard'), rec_dt=0.2)
    # green blasts blue away with the force
    gxx = G.tr['x'](18.85)
    G.key(18.85, 'push_wind', ease='out', x=(gxx, 'lin'))
    G.key(19.02, 'push', ease='snap')
    G.key(19.45, 'push', ease='lin')
    G.key(19.75, 'guard_low', ease='out')
    hp = hand(G, 19.05, 'lh')
    S.push(19.06, hp[0] + 20, hp[1], 1, color=GREEN)
    bxx = B.tr['x'](19.0)
    B.key(19.0, 'guard', ease='lin', x=(bxx, 'lin'))
    B.key(19.16, 'hurt', ease='snap', x=(bxx, 'lin'))
    B.key(19.62, 'hurt', ease='out', x=(bxx + 150, 'out2'))
    B.key(19.9, 'guard', ease='out')
    S.hit(19.16, bxx - 10, 90, power=0.8, color=GREEN)
    S.dust(19.55, bxx + 150, n=8, spread=110, d=1, life=0.9)
    # blue storms back and floors green
    B.run(19.95, 20.35, bxx + 150, 150)
    B.key(20.3, 'wind_hor', ease='out')
    B.key(20.5, 'end_hor', ease='in2')
    B.key(21.0, 'end_hor', ease='lin')
    G.key(20.35, 'guard', ease='out', x=(G.tr['x'](20.0), 'lin'))
    G.key(20.58, 'hurt', ease='snap', x=(G.tr['x'](20.0), 'lin'))
    G.key(20.95, 'hurt', ease='out', x=(-90, 'out2'))
    G.key(21.3, 'kneel_guard', ease='out')
    S.clash(20.52, 'blue', 'green', lift=0, power=1.0)
    B.aim(20.45, 20.7, 'green', lift=0)
    G.aim(20.45, 20.7, 'blue', lift=0)

    cam.cut(16.0, cx=120, cy=100, zoom=1.9)
    cam.auto(16.1, 21.3, ['blue', 'green', 'yellow'], margin=330, zmin=1.4, zmax=2.5, yc=100)
    cam.cut(16.4, cx=125, cy=105, zoom=2.7, rot=3)
    cam.key(17.0, cx=125, cy=108, zoom=2.9, rot=1, ease='lin')
    cam.cut(17.15, cx=60, cy=100, zoom=1.8, rot=0)
    # ---- yellow leaps in, triple lock, final rage ------------------------------------------
    Y.key(21.2, 'guard_low', ease='out', x=(-260, 'lin'))
    Y.key(21.30, 'crouch', ease='out')
    Y.key(21.42, 'jump_up', ease='snap', x=(-260, 'lin'), air=(0.0, 'lin'), rot=(0.0, 'lin'))
    Y.key(21.68, 'air_tuck', ease='out2', air=(185.0, 'out2'), x=(-110, 'lin'))
    Y.key(21.90, 'parry_high', ease='in2', air=(0.0, 'in2'), x=(30, 'lin'))
    Y.key(21.5, rot=(0.0, 'lin'))
    Y.key(21.84, rot=(-360.0, 'smooth'))
    Y.key(21.92, rot=(-360.0, 'lin'))
    Y.key(21.94, rot=(0.0, 'lin'))
    S.dust(21.92, 30, n=8, spread=100, life=0.8)

    # blue's overhead meets yellow's blade
    B.key(21.25, 'guard', ease='out', x=(150, 'lin'))
    B.key(21.62, 'wind_over', ease='out')
    B.key(21.96, 'lock', ease='in2', x=(135, 'out2'), twohand=(1.0, 'out'))
    B.key(23.88, 'lock', ease='lin', twohand=1.0, x=(150, 'lin'))
    B.aim(21.9, 23.9, 'yellow', lift=48)
    Y.aim(21.9, 22.3, 'blue', lift=48)
    S.clash(22.0, 'blue', 'yellow', lift=48, power=1.5)
    S.slow(21.95, 22.25, 0.35)
    S.invert(22.0, 0.06)
    Y.key(22.35, 'kneel_up', ease='out', twohand=(1.0, 'out'))
    Y.key(23.2, 'kneel_up', ease='lin', twohand=1.0)
    Y.key(23.88, 'parry_high', ease='inout', twohand=1.0)
    # green rises and joins from the left
    G.key(21.5, 'kneel_guard', ease='lin', x=(-90, 'lin'))
    G.key(22.0, 'guard', ease='out')
    G.key(22.3, 'wind_over', ease='out')
    G.key(22.62, 'lock', ease='in2', x=(-62, 'out2'), twohand=(1.0, 'out'))
    G.key(23.88, 'lock', ease='lin', twohand=1.0, x=(-70, 'lin'))
    G.aim(22.55, 23.9, tip_point(Y, 0.3), 0)
    B.aim(22.3, 23.9, tip_point(Y, 0.3), 0)
    S.events.append(Event(22.66, 'clash', None, None, power=1.8, tipof=(Y, 0.3)))
    S.snd(22.66, 'clash', power=1.8)
    S.cam.shake(22.66, 20, 0.5)
    S.flash(22.66, 0.5, 0.25)
    t = 22.8
    while t < 23.85:
        S.events.append(Event(t, 'clash', None, None, power=0.5 + 0.6 * (t - 22.8), tipof=(Y, 0.3)))
        S.snd(t, 'clash', power=0.5 + 0.6 * (t - 22.8))
        S.cam.shake(t, 3 + 9 * (t - 22.8), 0.15)
        t += 0.11
    # final rage builds
    Y.key(22.4, aura=(0.0, 'lin'))
    Y.key(23.85, aura=(1.0, 'in2'))
    for tt, off in ((22.75, 0), (23.1, 50), (23.45, -60)):
        S.events.append(Event(tt, 'crack', 30 + off, -6, life=1.8, color=(1.0, 0.78, 0.15)))
    S.snd(22.4, 'riser', dur=1.5)

    # ---- the burst ----------------------------------------------------------------------------
    TB = 23.92
    S.slow(TB - 0.03, TB + 0.4, 0.3)
    S.flash(TB, 1.0, 0.5)
    S.invert(TB, 0.1)
    S.invert(TB + 0.15, 0.06)
    S.ring(TB, 30, maxr=1500, color=YELLOW, life=1.2)
    S.ring(TB + 0.12, 30, maxr=1000, color=(1, 1, 1), life=1.0)
    S.events.append(Event(TB, 'pillar', 30, 0, life=1.4, color=(1.0, 0.8, 0.2), w=170))
    S.events.append(Event(TB, 'crack', 30, -6, life=2.2, color=(1.0, 0.8, 0.2)))
    S.debris(TB, 30, n=26, power=1.3)
    S.cam.shake(TB, 46, 0.9)
    S.snd(TB, 'burst')
    Y.key(TB - 0.02, 'parry_high', twohand=1.0)
    Y.key(TB + 0.12, 'rage_up', ease='snap', twohand=(0.0, 'out'))
    Y.key(TB + 1.5, 'rage_up', ease='lin')
    Y.key(TB + 2.3, 'guard_low', ease='smooth')
    for f, xs, d, dly in ((B, 135, 1, 0.0), (G, -70, -1, 0.04)):
        t0 = TB + 0.1 + dly
        f.key(t0 - 0.02, 'lock', twohand=1.0)
        f.key(t0, 'fling', ease='snap', twohand=0.0, flail=0.0, x=(xs, 'lin'), air=(0.0, 'lin'), rot=(0.0, 'lin'))
        f.key(t0 + 0.2, flail=(1.0, 'out'))
        f.key(t0 + 1.0, x=(xs + d * 380, 'out2'))
        f.key(t0 + 0.35, air=(110.0, 'out2'))
        f.key(t0 + 0.85, air=(0.0, 'in2'))
        f.key(t0 + 0.88, rot=(-d * 330.0, 'smooth'))
        f.key(t0 + 0.9, 'lying', ease='snap', flail=(0.0, 'lin'), rot=(-d * 360.0, 'lin'))
        f.key(t0 + 1.15, x=(xs + d * 450, 'out'))
        f.key(t0 + 1.2, rot=(0.0, 'lin'))
        f.key(t0 + 1.8, 'lying', ease='lin')
        f.key(t0 + 2.3, 'kneel_guard', ease='out')
        f.key(t0 + 2.8, 'guard', ease='out')
        S.dust(t0 + 0.9, xs + d * 400, n=10, spread=190, d=d, life=1.2)
        f.key(t0, face=(1.0 if f is B else -1.0, 'hold'))
        # faces flip: they were hit from the centre
        f.key(t0 + 0.8, face=(-1.0 if f is B else 1.0, 'hold'))
        f.key(t0 + 2.2, face=(-1.0 if f is B else 1.0, 'lin'))

    cam.cut(21.25, cx=0, cy=110, zoom=1.9)
    cam.auto(21.3, 22.0, ['blue', 'green', 'yellow'], margin=330, zmin=1.3, zmax=2.4, yc=105)
    cam.cut(21.95, cx=80, cy=120, zoom=2.3)
    cam.key(22.5, cx=40, cy=125, zoom=2.7, ease='lin')
    cam.key(23.85, cx=35, cy=150, zoom=3.9, rot=-5, ease='in2')
    cam.cut(TB - 0.01, cx=30, cy=130, zoom=2.2, rot=0)
    cam.key(TB + 0.9, cx=30, cy=150, zoom=1.5, ease='out')
    cam.auto(TB + 1.0, TB + 3.0, ['blue', 'green', 'yellow'], margin=520, zmin=1.0, zmax=2.0, yc=105)



# =====================================================================================
# ACT 4  - yellow in final rage beats blue, redirecting green's thrown saber
# =====================================================================================
def act4(S, B, G, Y):
    cam = S.cam
    # ---- blue and yellow close in ---------------------------------------------------------
    B.run(26.9, 27.4, B.tr['x'](26.9), 430)
    B.key(27.45, 'guard')
    Y.key(26.9, 'guard_low', x=(Y.tr['x'](26.9), 'lin'))
    Y.run(27.0, 27.4, Y.tr['x'](26.9), 215)
    G.walk(26.95, 29.4, G.tr['x'](26.9), -330)
    G.key(26.9, 'guard_low')
    S.speed_lines.append((27.0, 27.4, 1.0, 1))
    ex(S, Y, B, 27.58, atk=('wind_over', 'end_over'), par='parry_high', lift=48, hold=0.14, lunge=40,
       power=1.6, wind_dt=0.26, rec=('guard', 'guard'), rec_dt=0.12)
    S.slow(27.55, 27.78, 0.3)
    S.invert(27.58, 0.06)
    # blue is shoved back, then they trade blows
    bx = B.tr['x'](27.75)
    B.key(27.78, 'parry_high', ease='lin', x=(bx, 'lin'))
    B.key(28.0, 'hurt', ease='out', x=(bx + 70, 'out2'))
    B.key(28.15, 'guard', ease='out')
    ex(S, B, Y, 28.55, atk=('wind_hor', 'end_hor'), par='parry_mid', lift=-24, hold=0.1, lunge=50,
       power=1.1, wind_dt=0.26, rec=('guard', 'guard'), rec_dt=0.1)
    ex(S, Y, B, 29.0, atk=('wind_hor', 'end_hor'), par='parry_mid', lift=-24, hold=0.1, lunge=50,
       power=1.2, wind_dt=0.24, rec=('guard', 'guard'), rec_dt=0.1)
    ex(S, B, Y, 29.4, atk=('wind_thrust', 'end_thrust'), par='parry_low', lift=-34, hold=0.1, lunge=50,
       power=1.1, wind_dt=0.22, rec=('guard', 'guard'), rec_dt=0.1)
    # yellow overpowers: rising slash launches blue
    ex(S, Y, B, 29.88, atk=('wind_rise', 'end_rise'), par='parry_low', lift=-30, hold=0.04, lunge=40,
       power=1.8, wind_dt=0.3, rec=('guard', 'guard'), rec_dt=0.08)
    S.slow(29.86, 30.1, 0.4)
    S.invert(29.9, 0.07)
    bx2 = B.tr['x'](29.95)
    yx2 = Y.tr['x'](29.95)
    B.key(29.93, 'parry_low', ease='lin', x=(bx2, 'lin'), air=(0.0, 'lin'), rot=(0.0, 'lin'), twohand=0.0)
    B.key(29.99, 'fling', ease='snap', flail=(0.0, 'lin'))
    B.key(30.05, flail=(1.0, 'out'))
    B.key(30.2, 'fling', ease='lin', air=(230.0, 'out2'), x=(bx2 + 40, 'out'), rot=(-90.0, 'out'))
    B.key(30.62, 'fling', ease='lin', air=(0.0, 'in'), x=(bx2 + 85, 'lin'), rot=(-250.0, 'lin'))
    B.key(30.66, 'lying', ease='snap', flail=(0.0, 'lin'), rot=(-360.0, 'lin'))
    B.key(30.7, rot=(0.0, 'lin'))
    B.key(31.0, 'lying', ease='lin')
    B.key(31.45, 'kneel_guard', ease='out')
    # yellow leaps after him and slams down
    Y.key(29.93, 'wind_rise', ease='lin', x=(yx2, 'lin'), air=(0.0, 'lin'))
    Y.key(30.05, 'crouch', ease='out')
    Y.key(30.12, 'jump_up', ease='snap', rot=(0.0, 'lin'), x=(yx2 + 10, 'lin'))
    Y.key(30.3, 'air_slash', ease='out2', air=(235.0, 'out2'), x=(yx2 + 70, 'lin'))
    Y.key(30.48, 'air_slash', ease='in2', air=(110.0, 'in'), x=(yx2 + 110, 'lin'))
    Y.key(30.6, 'air_slash', ease='in', air=(10.0, 'in'), x=(yx2 + 135, 'lin'))
    Y.key(30.7, 'land', ease='snap', air=(0.0, 'lin'), x=(yx2 + 140, 'lin'))
    Y.key(31.15, 'guard_low', ease='out')
    S.hit(30.64, B.tr['x'](30.64), 12, power=1.6, color=YELLOW, shake=34)
    S.ring(30.64, B.tr['x'](30.64), maxr=620, color=YELLOW, life=0.8)
    S.debris(30.64, B.tr['x'](30.64), n=20, power=1.0)
    S.dust(30.66, B.tr['x'](30.66), n=14, spread=240, life=1.3)
    S.events.append(Event(30.64, 'crack', B.tr['x'](30.64), -6, life=0.9, color=(1.0, 0.8, 0.2)))
    S.invert(30.64, 0.08)
    S.slow(30.6, 30.9, 0.45)

    # ---- green throws her saber; yellow bends it into blue --------------------------------------
    gx = G.tr['x'](29.4)
    G.key(29.45, 'guard_low', ease='out')
    G.key(30.7, 'guard', ease='lin')
    G.key(30.82, 'wind_over', ease='out')
    G.key(31.0, 'throw', ease='snap')
    G.key(31.4, 'throw', ease='lin')
    G.key(31.9, 'guard_low', ease='out')
    yfinal = Y.tr['x'](31.2)
    bfin = B.tr['x'](31.2)
    gh = (gx + 55, 105)
    free_saber(G, [(31.0, gx + 55, 105, 20.0), (31.15, gx + 180, 104, 360.0 + 20),
                   (31.32, yfinal - 140, 100, 900.0), (31.42, yfinal - 10, 150, 1080.0),
                   (31.55, yfinal + 120, 215, 1330.0), (31.72, bfin - 10, 115, 1600.0),
                   (31.9, bfin - 5, 55, 1680.0), (32.2, bfin + 25, 10, 1795.0),
                   (33.3, bfin + 25, 10, 1795.0)])
    # yellow senses it, hand flung back behind him
    Y.key(31.0, 'guard_low', ease='out')
    Y.key(31.2, 'push_back', ease='out')
    Y.key(31.55, 'push_back', ease='lin')
    Y.key(31.66, 'push', ease='snap')
    Y.key(32.2, 'push', ease='lin')
    Y.key(32.7, 'guard_low', ease='smooth')
    hp = hand(Y, 31.7, 'lh')
    S.push(31.68, hp[0], hp[1], 1, color=YELLOW, life=0.6)
    S.snd(31.0, 'throw')
    # blue rises into it
    B.key(31.55, 'guard', ease='out', x=(bfin, 'lin'))
    B.key(31.7, 'guard', ease='lin')
    B.key(31.76, 'hurt', ease='snap')
    B.key(32.1, 'kneel', ease='out', son=(1.0, 'lin'))
    B.key(32.3, 'kneel', ease='lin', son=(0.0, 'out'))
    S.hit(31.74, bfin, 90, power=1.3, color=BLUE, shake=24)
    S.invert(31.74, 0.07)
    S.slow(31.7, 32.0, 0.45)
    B.die(32.55)
    S.snd(32.5, 'dissolve')
    S.flash(32.55, 0.35, 0.4)

    # green pulls it home with the force
    Gh = lambda t: (G.state(t)['J']['rh'][0], G.state(t)['J']['rh'][1])
    gcatch = 33.55
    gp = Gh(gcatch)
    G.key(32.8, 'push', ease='out')
    G.key(33.2, 'push', ease='lin')
    G.key(gcatch, 'catch', ease='snap')
    G.key(34.2, 'guard', ease='out')
    G.key(33.6, aura=(0.0, 'lin'))
    G.key(34.5, aura=(1.0, 'in2'))
    pull = [(33.3, bfin + 25, 10, 1795.0), (33.4, bfin + 25, 24, 1850.0), (33.7, bfin - 150, 90, 2300.0),
            (34.05, (bfin + gp[0]) / 2, 140, 2900.0), (gcatch + 0.0, gp[0], gp[1], 3330.0 + 0.0)]
    free_saber(G, pull)
    S.snd(33.3, 'pull')
    S.flash(gcatch, 0.3, 0.3)

    # cameras
    cam.cut(26.1, cx=30, cy=110, zoom=1.6)
    cam.auto(26.7, 27.4, ['blue', 'green', 'yellow'], margin=450, zmin=1.0, zmax=2.0, yc=100)
    cam.cut(27.5, cx=240, cy=115, zoom=2.5)
    cam.key(28.0, cx=300, cy=110, zoom=2.3, ease='lin')
    cam.auto(28.1, 29.8, ['blue', 'yellow'], margin=300, zmin=1.6, zmax=2.6, yc=105)
    cam.cut(29.8, cx=380, cy=105, zoom=2.4)
    cam.auto(30.0, 30.6, ['blue', 'yellow'], margin=520, zmin=1.0, zmax=1.9, yc=175)
    cam.cut(30.62, cx=B.tr['x'](30.64) + 10, cy=60, zoom=2.8)
    cam.key(31.0, cx=B.tr['x'](31) - 30, cy=70, zoom=2.2, ease='lin')
    cam.auto(31.05, 32.4, ['green', 'blue', 'yellow'], margin=380, zmin=0.95, zmax=1.8, yc=100)
    cam.cut(32.0, cx=bfin + 10, cy=75, zoom=3.2)
    cam.key(33.0, cx=bfin + 10, cy=85, zoom=3.6, ease='lin')
    cam.cut(33.0, cx=bfin + 25, cy=40, zoom=2.2)
    cam.auto(33.3, 36.0, ['green', 'yellow'], margin=450, zmin=1.0, zmax=2.0, yc=100)



# =====================================================================================
# ACT 5  - yellow vs green, disarm, final cut, victory
# =====================================================================================
def act5(S, B, G, Y):
    cam = S.cam
    # ---- cut to a clean arena: they face each other in rage -----------------------------------
    T = 34.55
    Y.key(T - 0.01, x=(Y.tr['x'](T - 0.01), 'lin'))
    G.key(T - 0.01, x=(G.tr['x'](T - 0.01), 'lin'))
    Y.key(T, 'guard', x=(330, 'lin'), face=(-1.0, 'hold'), aura=(1.0, 'lin'), son=1.0, air=(0.0, 'lin'), rot=(0.0, 'lin'))
    G.key(T, 'guard', x=(-330, 'lin'), face=(1.0, 'hold'), son=1.0, air=(0.0, 'lin'), rot=(0.0, 'lin'))
    Y.walk(T + 0.05, 35.55, 330, 250)
    G.walk(T + 0.05, 35.55, -330, -250)
    # last eye contact, then both dash
    Y.run(35.72, 36.0, 250, 92)
    G.run(35.72, 36.0, -250, -92)
    S.speed_lines.append((35.72, 36.05, 1.2, -1))
    S.snd(35.7, 'whoosh2')
    Y.key(35.88, 'wind_over', ease='out')
    G.key(35.88, 'wind_hor', ease='out')
    Y.key(36.05, 'lock', ease='in2', twohand=(1.0, 'out'))
    G.key(36.05, 'lock', ease='in2', twohand=(1.0, 'out'))
    Y.key(36.8, 'lock', ease='lin', twohand=1.0)
    G.key(36.8, 'lock', ease='lin', twohand=1.0)
    Y.aim(36.0, 36.8, 'green', lift=50)
    G.aim(36.0, 36.8, 'yellow', lift=50)
    S.clash(36.08, 'yellow', 'green', lift=50, power=2.2, shake=36)
    S.slow(36.04, 36.4, 0.3)
    S.invert(36.08, 0.07)
    S.flash(36.1, 0.6, 0.3)
    S.ring(36.08, 0, maxr=1300, color=(1, 1, 1), life=0.9)
    S.ring(36.14, 0, maxr=900, color=(0.6, 1.0, 0.7), life=0.9)
    t = 36.3
    while t < 36.8:
        S.clash(t, 'yellow', 'green', lift=50, power=0.55, shake=3)
        t += 0.12
    # recoil
    for f, d_ in ((Y, 1), (G, -1)):
        f.key(36.8, 'lock', twohand=1.0, x=(d_ * 92, 'lin'))
        f.key(36.95, 'hurt', ease='snap', twohand=(0.0, 'lin'), x=(d_ * 92, 'lin'))
        f.key(37.2, 'guard', ease='out', x=(d_ * 160, 'out2'))
    S.dust(36.95, 0, n=12, spread=300, life=1.0)

    # ---- trade blows ----------------------------------------------------------------------------
    ex(S, Y, G, 37.65, atk=('wind_over', 'end_over'), par='parry_high', lift=50, hold=0.12, lunge=65,
       power=1.3, wind_dt=0.3, rec=('guard', 'guard'), rec_dt=0.12)
    ex(S, G, Y, 38.2, atk=('wind_hor', 'end_hor'), par='parry_mid', lift=-24, hold=0.12, lunge=65,
       power=1.3, wind_dt=0.28, rec=('guard', 'guard'), rec_dt=0.12)
    ex(S, Y, G, 38.7, atk=('wind_thrust', 'end_thrust'), par='parry_low', lift=-34, hold=0.12, lunge=65,
       power=1.3, wind_dt=0.26, rec=('guard', 'guard'), rec_dt=0.12)

    # aerial clash
    yx, gx = Y.tr['x'](39.1), G.tr['x'](39.1)
    for f, tx, sg_ in ((Y, 90, -1), (G, -90, 1)):
        f0 = f.tr['x'](39.1)
        f.key(39.05, 'guard', x=(f0, 'lin'), air=(0.0, 'lin'))
        f.key(39.18, 'crouch', ease='out')
        f.key(39.28, 'jump_up', ease='snap', x=(f0, 'lin'), air=(0.0, 'lin'))
        f.key(39.62, 'air_slash', ease='out2', air=(190.0, 'out2'), x=(tx, 'out2'))
        f.key(40.05, 'air_slash', ease='lin', air=(150.0, 'lin'), x=(tx, 'lin'))
        f.key(40.35, 'land', ease='in2', air=(0.0, 'in2'), x=(sg_ * -125 * -1 * -1, 'lin'))
        f.key(40.7, 'guard', ease='out')
    Y.aim(39.55, 40.05, 'green', lift=44)
    G.aim(39.55, 40.05, 'yellow', lift=44)
    S.clash(39.62, 'yellow', 'green', lift=44, power=2.0, shake=30)
    S.slow(39.58, 39.9, 0.35)
    S.invert(39.62, 0.07)
    t = 39.8
    while t < 40.0:
        S.clash(t, 'yellow', 'green', lift=44, power=0.5, shake=3)
        t += 0.1
    S.dust(40.36, 125, n=8, spread=120, life=0.8)
    S.dust(40.36, -125, n=8, spread=120, life=0.8)

    # green force-pushes yellow far
    G.key(40.6, 'push_wind', ease='out')
    G.key(40.74, 'push', ease='snap')
    G.key(41.1, 'push', ease='lin')
    G.key(41.4, 'guard', ease='out')
    hp = hand(G, 40.76, 'lh')
    S.push(40.77, hp[0], hp[1], 1, color=GREEN)
    Y.key(40.85, 'guard', ease='lin', x=(Y.tr['x'](40.85), 'lin'))
    Y.key(40.9, 'hurt', ease='snap')
    Y.key(41.3, 'hurt', ease='out', x=(430, 'out2'), son=1.0)
    Y.key(41.65, 'guard', ease='out')
    S.hit(40.9, Y.tr['x'](40.9), 90, power=0.9, color=GREEN)
    S.dust(41.2, 400, n=12, spread=200, d=1, life=1.1)

    # yellow storms back: rapid-fire combo
    Y.run(41.7, 42.0, 430, 90)
    S.speed_lines.append((41.7, 42.05, 1.3, -1))
    ex(S, Y, G, 42.25, atk=('wind_over', 'end_over'), par='parry_high', lift=50, hold=0.07, lunge=55,
       power=1.4, wind_dt=0.2, rec=('guard', 'guard'), rec_dt=0.06)
    G.key(42.38, 'hurt', ease='lin')
    G.key(42.5, 'guard', ease='out', x=(G.tr['x'](42.4) - 45, 'out2'))
    ex(S, Y, G, 42.62, atk=('wind_rise', 'end_rise'), par='parry_low', lift=-30, hold=0.07, lunge=55,
       power=1.4, wind_dt=0.2, rec=('guard', 'guard'), rec_dt=0.06)
    G.key(42.72, 'hurt', ease='lin')
    G.key(42.85, 'guard', ease='out', x=(G.tr['x'](42.75) - 45, 'out2'))
    ex(S, Y, G, 42.98, atk=('wind_hor', 'end_hor'), par='parry_mid', lift=-24, hold=0.07, lunge=55,
       power=1.6, wind_dt=0.2, rec=('guard', 'guard'), rec_dt=0.06)
    G.key(43.1, 'hurt', ease='lin')
    G.key(43.25, 'guard', ease='out', x=(G.tr['x'](43.12) - 50, 'out2'))
    S.slow(42.2, 43.2, 0.75)

    # green's last leap attack
    gx0 = G.tr['x'](43.3)
    yx0 = Y.tr['x'](43.3)
    G.key(43.3, 'guard', x=(gx0, 'lin'), air=(0.0, 'lin'))
    G.key(43.45, 'crouch', ease='out')
    G.key(43.55, 'jump_up', ease='snap', x=(gx0, 'lin'))
    G.key(43.85, 'wind_over', ease='out2', air=(205.0, 'out2'), x=(yx0 - 190, 'out'))
    G.key(44.12, 'air_slash', ease='in2', air=(120.0, 'in'), x=(yx0 - 150, 'lin'))
    G.key(44.2, 'air_slash', ease='lin', air=(105.0, 'lin'), x=(yx0 - 150, 'lin'))
    Y.key(43.5, 'guard', x=(yx0, 'lin'))
    Y.key(43.95, 'parry_high', ease='out', twohand=(1.0, 'out'))
    Y.key(44.22, 'parry_high', ease='lin', twohand=1.0)
    G.aim(44.1, 44.22, 'yellow', lift=45)
    Y.aim(44.1, 44.22, 'green', lift=45)
    S.clash(44.14, 'green', 'yellow', lift=45, power=2.0, shake=34)
    S.slow(44.08, 44.3, 0.3)
    S.invert(44.14, 0.07)
    # the disarming rising cut
    Y.key(44.3, 'wind_rise', ease='snap', twohand=(0.0, 'lin'))
    Y.key(44.42, 'end_rise', ease='snap')
    Y.key(44.9, 'end_rise', ease='lin')
    Y.key(45.3, 'guard_low', ease='out')
    Ghand = lambda t: (G.state(t)['J']['rh'][0], G.state(t)['J']['rh'][1])
    hh = Ghand(44.42)
    S.hit(44.42, hh[0], hh[1], power=1.4, color=GREEN)
    free_saber(G, [(44.42, hh[0], hh[1], 330.0), (44.7, hh[0] + 120, 380, 760.0),
                   (45.1, hh[0] + 330, 440, 1440.0), (45.5, hh[0] + 560, 260, 2000.0),
                   (45.78, hh[0] + 640, 10, 2240.0), (47.3, hh[0] + 640, 10, 2240.0)])
    G.key(44.4, 'hurt', ease='snap', son=1.0)
    G.key(44.8, 'hurt', ease='lin', air=(40.0, 'out'))
    G.key(45.05, 'hurt', ease='in2', air=(0.0, 'in2'), x=(G.tr['x'](44.4) - 70, 'out2'))
    G.key(45.4, 'kneel', ease='out')
    S.dust(45.1, G.tr['x'](45.1), n=8, spread=110, life=0.8)
    G.key(45.8, aura=(0.4, 'smooth'))
    S.dust(45.8, hh[0] + 640, n=6, spread=60, life=0.8)
    S.snd(45.8, 'tick')

    # green tries to pull it back; yellow stops her
    G.key(46.1, 'push', ease='out')
    G.key(46.5, 'push', ease='lin')
    S.snd(46.1, 'pull')
    Y.key(46.4, 'guard_low', ease='lin')
    Y.key(46.6, 'push', ease='snap')
    Y.key(47.1, 'push', ease='lin')
    # saber lifts a little, then is slammed and snuffed
    G.saber_free.pop()
    free_saber(G, [(44.42, hh[0], hh[1], 330.0), (44.7, hh[0] + 120, 380, 760.0),
                   (45.1, hh[0] + 330, 440, 1440.0), (45.5, hh[0] + 560, 260, 2000.0),
                   (45.78, hh[0] + 640, 10, 2240.0), (46.15, hh[0] + 640, 10, 2240.0),
                   (46.45, hh[0] + 600, 60, 2290.0), (46.65, hh[0] + 560, 120, 2360.0),
                   (46.78, hh[0] + 640, 8, 2240.0), (90.0, hh[0] + 640, 8, 2240.0)])
    G.key(46.8, son=(1.0, 'lin'))
    G.key(46.83, son=(0.0, 'lin'))
    S.debris(46.8, hh[0] + 640, n=10, power=0.8)
    S.ring(46.8, hh[0] + 640, maxr=380, color=GREEN, life=0.6)
    S.dust(46.8, hh[0] + 640, n=8, spread=100, life=0.8)
    S.snd(46.8, 'hit', power=1.2, x=hh[0] + 640)
    S.cam.shake(46.8, 14, 0.4)

    # ---- the last stand --------------------------------------------------------------------------
    G.key(47.1, 'kneel', ease='out')
    G.key(47.6, 'guard', ease='out', aura=(1.0, 'out'), son=0.0)
    G.key(48.1, 'idle', ease='smooth')
    Y.key(47.35, 'guard_low', ease='out')
    Y.walk(47.2, 48.4, Y.tr['x'](47.1), G.tr['x'](47.6) + 230)
    G.key(48.4, 'push_wind', ease='out')
    G.key(48.62, 'push', ease='snap')
    G.key(49.1, 'push', ease='lin')
    hp = hand(G, 48.64, 'lh')
    S.push(48.64, hp[0], hp[1], 1, color=GREEN, life=0.9)
    S.snd(48.64, 'push', x=hp[0])
    S.cam.shake(48.64, 22, 0.8)
    Y.key(48.5, 'parry_high', ease='out', twohand=(1.0, 'out'))
    Y.key(49.0, 'parry_high', ease='lin', twohand=1.0, x=(Y.tr['x'](48.4), 'lin'))
    Y.key(49.08, x=(Y.tr['x'](48.4) + 60, 'out'))
    S.dust(48.7, Y.tr['x'](48.4) + 30, n=10, spread=150, d=1, life=1.0)
    # then the pass
    ypass = Y.tr['x'](49.1)
    gposs = G.tr['x'](49.1)
    Y.key(49.25, 'wind_hor', ease='out', twohand=(0.0, 'out'))
    Y.run(49.2, 49.5, ypass, gposs - 160)
    Y.key(49.34, 'end_hor', ease='in2')
    Y.key(49.6, 'end_hor', ease='lin')
    Y.key(49.62, face=(-1.0, 'hold'))
    Y.key(50.8, 'end_hor', ease='lin')
    Y.key(51.5, 'guard_low', ease='smooth')
    S.slow(49.33, 49.42, 0.1)
    S.slow(49.42, 49.9, 0.35)
    S.invert(49.38, 0.1)
    S.flash(49.42, 0.8, 0.5)
    S.hit(49.38, gposs, 100, power=2.0, color=(1, 1, 1), shake=40)
    S.snd(49.38, 'final')
    G.key(49.3, 'push', ease='lin', son=0.0)
    G.key(49.5, 'hurt', ease='snap')
    G.key(50.6, 'hurt', ease='out')
    G.key(50.9, 'kneel', ease='out')
    G.die(51.2)
    S.snd(51.2, 'dissolve')
    S.flash(51.2, 0.35, 0.5)

    # ---- aftermath / victory ----------------------------------------------------------------
    Y.key(51.6, aura=(1.0, 'lin'))
    Y.key(53.0, aura=(0.0, 'smooth'))
    Y.key(52.6, 'guard_low', ease='lin')
    Y.key(53.4, 'victory', ease='smooth')
    Y.key(53.4, son=(1.0, 'lin'))
    Y.key(53.5, son=(0.0, 'out'))
    Y.key(54.0, son=(0.0, 'lin'))
    Y.key(55.4, 'victory', ease='lin')
    Y.key(55.6, son=(1.0, 'out'))
    Y.key(54.6, 'raise', ease='out')
    Y.key(55.6, 'victory', ease='out')
    S.snd(55.5, 'ignite', who='yellow')
    S.flash(55.5, 0.4, 0.4)
    S.events.append(Event(55.6, 'pillar', Y.tr['x'](55.6), 0, life=2.0, color=(1.0, 0.82, 0.2), w=110))
    S.ring(55.6, Y.tr['x'](55.6), maxr=900, color=YELLOW, life=1.4)
    S.snd(55.6, 'victory')
    S.whites.append((57.2, 59.2))

    # ---- cameras ---------------------------------------------------------------------------------
    cam.cut(T, cx=0, cy=62, zoom=1.7, rot=-2)
    cam.key(35.65, cx=0, cy=70, zoom=2.0, rot=0, ease='lin')
    cam.cut(35.72, cx=0, cy=95, zoom=1.45)
    cam.auto(35.78, 36.0, ['yellow', 'green'], margin=330, zmin=1.3, zmax=2.4, yc=100)
    cam.cut(36.03, cx=0, cy=120, zoom=2.6)
    cam.key(36.8, cx=0, cy=125, zoom=3.0, ease='lin')
    cam.cut(36.96, cx=0, cy=95, zoom=1.9)
    cam.auto(37.1, 39.0, ['yellow', 'green'], margin=330, zmin=1.5, zmax=2.4, yc=100)
    cam.cut(39.1, cx=0, cy=150, zoom=1.9)
    cam.key(39.6, cx=0, cy=160, zoom=2.4, ease='lin')
    cam.key(40.2, cx=0, cy=140, zoom=2.2, ease='lin')
    cam.cut(40.45, cx=-60, cy=100, zoom=1.9)
    cam.key(40.9, cx=100, cy=100, zoom=1.6, ease='smooth')
    cam.auto(41.2, 41.7, ['yellow', 'green'], margin=520, zmin=0.95, zmax=1.7, yc=100)
    cam.cut(41.75, cx=100, cy=95, zoom=1.7)
    cam.auto(41.95, 43.4, ['yellow', 'green'], margin=300, zmin=1.5, zmax=2.7, yc=105)
    cam.cut(43.5, cx=-20, cy=150, zoom=1.7)
    cam.auto(43.7, 44.5, ['yellow', 'green'], margin=380, zmin=1.0, zmax=2.0, yc=170)
    cam.cut(44.45, cx=hh[0] + 80, cy=130, zoom=1.7)
    cam.key(45.0, cx=hh[0] + 360, cy=210, zoom=1.2, ease='smooth')
    cam.key(45.8, cx=hh[0] + 600, cy=60, zoom=2.6, ease='smooth')
    cam.cut(46.0, cx=-60, cy=95, zoom=1.6)
    cam.auto(46.2, 47.2, ['yellow', 'green'], margin=500, zmin=1.0, zmax=1.9, yc=100)
    cam.cut(47.2, cx=-40, cy=70, zoom=1.9, rot=-2)
    cam.auto(47.5, 49.0, ['yellow', 'green'], margin=460, zmin=1.0, zmax=1.9, yc=95)
    cam.cut(49.15, cx=gposs - 20, cy=100, zoom=1.6)
    cam.key(49.38, cx=gposs - 40, cy=105, zoom=2.4, ease='in2')
    cam.cut(49.38, cx=gposs - 30, cy=105, zoom=3.0)
    cam.key(50.8, cx=gposs - 30, cy=100, zoom=3.4, ease='lin')
    cam.cut(51.0, cx=gposs, cy=90, zoom=3.0)
    cam.key(52.2, cx=gposs - 60, cy=95, zoom=2.0, ease='smooth')
    cam.cut(52.6, cx=Y.tr['x'](52.6), cy=95, zoom=2.4)
    cam.key(53.6, cx=Y.tr['x'](53.6), cy=100, zoom=2.0, ease='smooth')
    cam.key(55.2, cx=Y.tr['x'](55.2), cy=115, zoom=1.7, ease='smooth')
    cam.key(57.6, cx=Y.tr['x'](55.6), cy=250, zoom=0.95, ease='inout')

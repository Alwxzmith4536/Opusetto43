"""Scene description: fighters (keyframed), camera, events, time warp."""
import math
import bisect
from rig import *

HORIZON = 70.0          # world y of the horizon line  (-> half white / half ash at default camera)


def wrap_deg(a):
    return (a + 180.0) % 360.0 - 180.0


class Fighter:
    def __init__(self, name, color, dark):
        self.name = name
        self.color = color          # (r,g,b) 0..1
        self.dark = dark
        self.tr = {}
        self.aim_segs = []          # (t0, t1, partner, lift)
        self.dead_t = None          # time of dissolve start
        self.saber_free = []        # (t0, t1, fn(t)->(x,y,ang))  detached saber paths
        self.lit_from = None
        for k in JOINT_KEYS:
            self.tr[k] = Track(angle=True)
        for k, v in EXTRA_DEFAULTS.items():
            self.tr[k] = Track(angle=False)
        self._init()

    def _init(self):
        base = POSES['idle']
        for k in JOINT_KEYS:
            self.tr[k].add(-100.0, base[k], 'lin')
        for k, v in EXTRA_DEFAULTS.items():
            self.tr[k].add(-100.0, v, 'lin')

    # ---------------------------------------------------------------- authoring
    def key(self, t, pose=None, ease='smooth', **props):
        if pose is not None:
            pd = POSES[pose] if isinstance(pose, str) else pose
            for k in JOINT_KEYS:
                if k in pd and k not in props:
                    self.tr[k].add(t, pd[k], ease)
        for k, v in props.items():
            e = ease
            if isinstance(v, tuple):
                v, e = v
            self.tr[k].add(t, v, e)
        return self

    def hold(self, t):
        """freeze every channel at its current value at time t (adds a key)"""
        for k, tr in self.tr.items():
            tr.add(t, tr(t), 'lin')
        return self

    def aim(self, t0, t1, partner, lift=40.0, ramp_in=0.10, ramp_out=0.14):
        """blades converge on the midpoint between the two hilts (+lift) from t0..t1.
        partner may also be a (x, y) world point or a callable t->(x, y)"""
        self.aim_segs.append((t0, t1, partner, lift))
        tr = self.tr['aim']
        tr.add(t0 - ramp_in, 0.0, 'smooth')
        tr.add(t0, 1.0, 'out')
        tr.add(t1, 1.0, 'lin')
        tr.add(t1 + ramp_out, 0.0, 'smooth')
        return self

    def run(self, t0, t1, x0, x1, ease='lin', stride=None, ramp=0.10):
        if stride is None:
            stride = max(1.6, abs(x1 - x0) / (t1 - t0) / 135.0)
        self.key(t0, x=(x0, 'lin'))
        self.key(t1, x=(x1, ease))
        self.key(t0, runw=(0.0, 'lin'), phase=(0.0, 'lin'))
        self.key(t0 + ramp, runw=(1.0, 'smooth'))
        self.key(t1 - ramp, runw=(1.0, 'lin'))
        self.key(t1, runw=(0.0, 'smooth'), phase=((t1 - t0) * stride, 'lin'))
        # facing follows direction
        self.key(t0, face=(1.0 if x1 >= x0 else -1.0, 'hold'))
        return self

    def walk(self, t0, t1, x0, x1, stride=0.9, ramp=0.25):
        self.key(t0, x=(x0, 'lin'), walkw=(0.0, 'lin'), phase=(0.0, 'lin'))
        self.key(t0 + ramp, walkw=(1.0, 'smooth'))
        self.key(t1 - ramp, walkw=(1.0, 'lin'))
        self.key(t1, x=(x1, 'lin'), walkw=(0.0, 'smooth'), phase=((t1 - t0) * stride, 'lin'))
        return self

    def die(self, t):
        self.dead_t = t

    # ---------------------------------------------------------------- evaluation
    def raw(self, t):
        v = {k: self.tr[k](t) for k in self.tr}
        return v

    def angles(self, t, v=None):
        v = v or self.raw(t)
        a = {k: v[k] for k in JOINT_KEYS}
        rw = v['runw']
        if rw > 1e-3:
            r = run_angles(v['phase'])
            for k, val in r.items():
                a[k] = a[k] + wrap_deg(val - a[k]) * rw
        ww = v['walkw']
        if ww > 1e-3:
            w = walk_angles(v['phase'])
            for k, val in w.items():
                a[k] = a[k] + wrap_deg(val - a[k]) * ww
        if v['runw'] < 0.2 and v['air'] < 5:
            ph = (hash(self.name) % 97) * 0.37
            br = math.sin(t * 2.3 + ph)
            a['torso'] += 1.1 * br
            a['head'] += 1.4 * math.sin(t * 1.7 + ph)
            a['lua'] += 2.0 * math.sin(t * 2.3 + ph + 1.0)
            a['rua'] += 1.4 * math.sin(t * 2.3 + ph + 2.0)
        fl = v['flail']
        if fl > 1e-3:
            for i, k in enumerate(('rua', 'rfa', 'lua', 'lfa', 'rth', 'rsh', 'lth', 'lsh')):
                a[k] += fl * 28.0 * math.sin(t * (9.0 + i * 1.7) + i * 1.3)
        return a

    def state(self, t, with_aim=True):
        v = self.raw(t)
        a = self.angles(t, v)
        face = 1.0 if v['face'] >= 0 else -1.0
        a['son'] = max(0.0, min(1.0, v['son']))
        a['twohand'] = v['twohand']
        yaw = v['yaw']
        rot = v['rot']
        sc = v['scale']
        J0 = skeleton(a, face, yaw, rot)
        base_rot = -lowest(J0)
        Ju = skeleton(a, face, yaw, 0.0)
        base_un = -lowest(Ju)
        air = v['air']
        g = max(0.0, min(1.0, 1.0 - air / 45.0))
        py = (1 - g) * (base_un + air) + g * (base_rot + air)
        x = v['x']

        # aim: blades converge on the clash point
        aimw = v['aim'] if with_aim else 0.0
        if aimw > 1e-3 and self.aim_segs:
            seg = None
            for s in self.aim_segs:
                if s[0] - 0.4 <= t <= s[1] + 0.4:
                    seg = s
                    if s[0] <= t <= s[1]:
                        break
            if seg is not None:
                mine_h = (J0['rh'][0] + x, J0['rh'][1] + py)
                if isinstance(seg[2], str):
                    other = _FIGHTERS[seg[2]]
                    oj = other.state(t, with_aim=False)
                    oth_h = oj['J']['rh']
                    P = ((mine_h[0] + oth_h[0]) * 0.5, (mine_h[1] + oth_h[1]) * 0.5 + seg[3])
                else:
                    P = seg[2](t) if callable(seg[2]) else seg[2]
                ang = math.degrees(math.atan2(P[1] - mine_h[1], P[0] - mine_h[0]))
                cur = a['sab']
                # in mirrored frame a['sab'] is in fighter space; convert world angle back
                loc = ang if face > 0 else 180.0 - ang
                a['sab'] = cur + wrap_deg(loc - cur) * min(1.0, aimw)
                J0 = skeleton(a, face, yaw, rot)
                Ju = skeleton(a, face, yaw, 0.0)
                base_rot = -lowest(J0)
                base_un = -lowest(Ju)
                py = (1 - g) * (base_un + air) + g * (base_rot + air)

        J = {k: (p[0] + x, p[1] + py) for k, p in J0.items()}
        return dict(J=J, x=x, py=py, face=face, v=v, a=a)

    def saber_segment(self, t):
        """(hilt, tip) in world coordinates or None when unlit/detached"""
        st = self.state(t)
        return st['J']['hilt'], st['J']['tip'], st


_FIGHTERS = {}


def register(f):
    _FIGHTERS[f.name] = f
    return f


class Camera:
    def __init__(self):
        self.tr = {k: Track() for k in ('cx', 'cy', 'zoom', 'rot', 'auto', 'blur', 'push')}
        self.tr['cx'].add(-100, 0, 'lin')
        self.tr['cy'].add(-100, 70, 'lin')
        self.tr['zoom'].add(-100, 1.5, 'lin')
        self.tr['rot'].add(-100, 0, 'lin')
        self.tr['auto'].add(-100, 0, 'lin')
        self.tr['blur'].add(-100, 0, 'lin')
        self.tr['push'].add(-100, 0, 'lin')
        self.focus = []         # (t0, t1, [names], margin, zmin, zmax, ycenter)
        self.cuts = []          # times where smoothing resets
        self.shakes = []        # (t, amp, dur, freq)
        self.path = None

    def key(self, t, ease='smooth', **props):
        for k, v in props.items():
            e = ease
            if isinstance(v, tuple):
                v, e = v
            self.tr[k].add(t, v, e)
        return self

    def cut(self, t, **props):
        """hard cut: previous value is held until t, then jumps"""
        for k, v in props.items():
            tr = self.tr[k]
            prev = tr(t - 1e-4)
            tr.add(t - 1e-3, prev, 'lin')
            tr.add(t, v, 'lin')
        self.cuts.append(t)
        return self

    def auto(self, t0, t1, names, margin=380, zmin=1.0, zmax=2.2, yc=70, ramp=0.5):
        self.focus.append((t0, t1, names, margin, zmin, zmax, yc))
        a = self.tr['auto']
        a.add(t0 - ramp, a(t0 - ramp), 'smooth')
        a.add(t0, 1.0, 'smooth')
        a.add(t1, 1.0, 'lin')
        a.add(t1 + ramp, 0.0, 'smooth')
        return self

    def shake(self, t, amp=14, dur=0.35, freq=26):
        self.shakes.append((t, amp, dur, freq))

    def bake(self, fighters, t_end, step=1 / 120.0, W=1920):
        n = int(t_end / step) + 2
        xs, ys, zs = [], [], []
        cx = cy = None
        z = None
        vx = vy = vz = 0.0
        for i in range(n):
            t = i * step
            seg = None
            for f in self.focus:
                if f[0] - 0.8 <= t <= f[1] + 0.8:
                    seg = f
                    if f[0] <= t <= f[1]:
                        break
            if seg is None:
                tx, ty, tz = (cx or 0.0), (cy or 70.0), (z or 1.5)
            else:
                pts = []
                for nme in seg[2]:
                    st = fighters[nme].state(t)
                    pts.append(st['J']['N'])
                    pts.append(st['J']['P'])
                minx = min(p[0] for p in pts)
                maxx = max(p[0] for p in pts)
                tx = (minx + maxx) / 2
                width = (maxx - minx) + seg[3]
                tz = max(seg[4], min(seg[5], W / width))
                ty = seg[6]
            if cx is None:
                cx, cy, z = tx, ty, tz
            # critically damped spring (ts = smoothing time)
            ts = 0.22
            w = 2 / ts
            for (cur, tgt, vel, name) in ((cx, tx, vx, 'x'), (cy, ty, vy, 'y'), (z, tz, vz, 'z')):
                pass
            def spring(cur, vel, tgt):
                x = cur - tgt
                tmp = (vel + w * x) * step
                e = 1.0 / (1.0 + w * step + 0.48 * w * w * step * step + 0.235 * w ** 3 * step ** 3)
                vel2 = (vel - w * tmp) * e
                cur2 = tgt + (x + tmp) * e
                return cur2, vel2
            cx, vx = spring(cx, vx, tx)
            cy, vy = spring(cy, vy, ty)
            z, vz = spring(z, vz, tz)
            xs.append(cx); ys.append(cy); zs.append(z)
        self.path = (step, xs, ys, zs)

    def _auto(self, t):
        step, xs, ys, zs = self.path
        f = max(0.0, t / step)
        i = int(f)
        if i >= len(xs) - 1:
            return xs[-1], ys[-1], zs[-1]
        u = f - i
        return (xs[i] + (xs[i + 1] - xs[i]) * u, ys[i] + (ys[i + 1] - ys[i]) * u,
                zs[i] + (zs[i + 1] - zs[i]) * u)

    def at(self, t):
        w = self.tr['auto'](t)
        cx, cy, z, rot = self.tr['cx'](t), self.tr['cy'](t), self.tr['zoom'](t), self.tr['rot'](t)
        if w > 1e-3 and self.path:
            ax, ay, az = self._auto(t)
            cx += (ax - cx) * w
            cy += (ay - cy) * w
            z = math.exp(math.log(z) + (math.log(az) - math.log(z)) * w)
        # shake
        sx = sy = sr = 0.0
        for (t0, amp, dur, freq) in self.shakes:
            age = t - t0
            if 0 <= age < dur:
                k = (1 - age / dur) ** 2 * amp
                sx += k * math.sin(age * freq * 6.1 + t0 * 3.7)
                sy += k * math.cos(age * freq * 5.3 + t0 * 1.9)
                sr += k * 0.045 * math.sin(age * freq * 4.1 + t0)
        return dict(cx=cx, cy=cy, zoom=z, rot=rot, sx=sx, sy=sy, srot=sr,
                    blur=self.tr['blur'](t), push=self.tr['push'](t))


class TimeWarp:
    """maps output time -> script time through slow-motion / hit-stop segments"""

    def __init__(self):
        self.segs = []      # (s0, s1, speed)  in script time
        self.arr = None

    def slow(self, s0, s1, speed):
        self.segs.append((s0, s1, speed))

    def speed_at(self, s):
        sp = 1.0
        for a, b, v in self.segs:
            if a <= s < b:
                sp = min(sp, v) if sp != 1.0 else v
        return sp

    def bake(self, s_end, dt=1 / 960.0):
        out_t = [0.0]
        scr_t = [0.0]
        s = 0.0
        o = 0.0
        # smooth speed transitions (about 80ms) so slow-mo ramps feel cinematic
        cur = 1.0
        while s < s_end:
            target = self.speed_at(s)
            cur += (target - cur) * min(1.0, dt / 0.05)
            s += dt * cur
            o += dt
            out_t.append(o)
            scr_t.append(s)
        self.arr = (out_t, scr_t, dt)
        self.duration = out_t[-1]

    def to_script(self, o):
        out_t, scr_t, dt = self.arr
        i = int(o / dt)
        if i >= len(scr_t) - 1:
            return scr_t[-1] + (o - out_t[-1])
        u = o / dt - i
        return scr_t[i] + (scr_t[i + 1] - scr_t[i]) * u

    def to_out(self, s):
        out_t, scr_t, dt = self.arr
        i = bisect.bisect_left(scr_t, s)
        if i <= 0:
            return out_t[0]
        if i >= len(scr_t):
            return out_t[-1] + (s - scr_t[-1])
        u = (s - scr_t[i - 1]) / max(1e-9, scr_t[i] - scr_t[i - 1])
        return out_t[i - 1] + (out_t[i] - out_t[i - 1]) * u


class Event:
    def __init__(self, t, kind, x=0.0, y=0.0, **kw):
        self.t = t
        self.kind = kind
        self.x = x
        self.y = y
        self.kw = kw

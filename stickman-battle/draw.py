"""All drawing: backdrop, stickmen, sabers, effects and post processing."""
import math
import random
import cairo
import numpy as np
from PIL import Image, ImageFilter

from rig import *
from scene import HORIZON, wrap_deg

import os
_Q = float(os.environ.get('QUICK', '1'))
W, H = int(1920 * _Q), int(1080 * _Q)
K = W / 1920.0
TAU = math.pi * 2


def mixc(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def smooth(u):
    u = max(0.0, min(1.0, u))
    return u * u * (3 - 2 * u)


# ======================================================================================
# backdrop
# ======================================================================================
class Backdrop:
    def __init__(self, seed=7):
        rng = random.Random(seed)
        self.rng = rng
        # far -> near ruined skylines.  (parallax, color, base offset, polys)
        self.layers = [
            (0.20, (0.91, 0.91, 0.93), 0, self._skyline(rng, -4200, 4200, 40, 250, 40, 120, 0.0, far=True)),
            (0.38, (0.83, 0.83, 0.86), 0, self._skyline(rng, -3600, 3600, 30, 190, 36, 110, 0.0, far=True)),
            (0.58, (0.69, 0.69, 0.73), -4, self._skyline(rng, -3200, 3200, 20, 150, 34, 100, 0.2)),
        ]
        self.near = [
            (0.86, (0.33, 0.33, 0.37), self._sparse(rng, -2600, 2600, 12, 40, 150, 260, 30, 80)),
            (1.0, (0.16, 0.16, 0.19), self._sparse(rng, -2200, 2200, -70, -10, 140, 250, 26, 70)),
        ]
        self.hull = self._hull()
        self.smoke = [(rng.uniform(-1800, 1800), rng.uniform(220, 380), rng.uniform(28, 55),
                       rng.uniform(0.12, 0.3)) for _ in range(7)]
        self.embers = [(rng.uniform(-1700, 1700), rng.uniform(4, 16)) for _ in range(9)]
        self.ridges = []
        for k in range(16):
            y = -rng.uniform(5, 330)
            self.ridges.append((rng.uniform(-2400, 2400), y, rng.uniform(220, 700),
                                rng.uniform(5, 18), rng.uniform(0.05, 0.16)))
        self.rocks = []
        for k in range(46):
            x = rng.uniform(-2600, 2600)
            y = -rng.uniform(10, 340)
            s = rng.uniform(6, 26) * (1 + (-y) / 380)
            pts = []
            n = rng.randint(5, 8)
            for i in range(n):
                a = TAU * i / n + rng.uniform(-0.3, 0.3)
                r = s * rng.uniform(0.6, 1.1)
                pts.append((math.cos(a) * r, abs(math.sin(a)) * r * 0.8))
            self.rocks.append((x, y, pts))
        self.fore = []
        for k in range(10):
            x = rng.uniform(-1600, 1600)
            s = rng.uniform(60, 170)
            pts = [(-s, 0), (-s * 0.5, s * rng.uniform(0.4, 1.0)), (s * 0.1, s * rng.uniform(0.3, 0.8)),
                   (s * 0.6, s * rng.uniform(0.6, 1.1)), (s, 0)]
            self.fore.append((x, pts))
        # ash flakes (screen space layers)
        self.flakes = [(rng.random(), rng.random(), rng.uniform(0.3, 1.0), rng.uniform(1.0, 3.2),
                        rng.random()) for _ in range(230)]
        self.fg_flakes = [(rng.random(), rng.random(), rng.uniform(5, 16), rng.random(),
                           rng.uniform(1.5, 2.4)) for _ in range(26)]

    # ---- shape factories --------------------------------------------------------
    def _skyline(self, rng, x0, x1, hmin, hmax, wmin, wmax, detail, far=False):
        polys = []
        x = x0
        while x < x1:
            w = rng.uniform(wmin, wmax)
            h = rng.uniform(hmin, hmax)
            kind = rng.random()
            base = -400
            if kind < 0.18 and hmax > 80:       # spire
                pts = [(x, base), (x, h * 0.5), (x + w * 0.45, h * 1.15), (x + w * 0.5, h * 1.5),
                       (x + w * 0.55, h * 1.15), (x + w, h * 0.5), (x + w, base)]
                pts[3] = (x + w * 0.5, h * 1.9)
            elif kind < 0.34:                   # broken, slanted top
                pts = [(x, base), (x, h), (x + w * rng.uniform(0.2, 0.5), h * rng.uniform(0.7, 1.0)),
                       (x + w * rng.uniform(0.5, 0.75), h * rng.uniform(0.4, 0.8)),
                       (x + w, h * rng.uniform(0.2, 0.6)), (x + w, base)]
            elif kind < 0.5:                    # stepped block
                s1 = h * rng.uniform(0.5, 0.85)
                pts = [(x, base), (x, s1), (x + w * 0.3, s1), (x + w * 0.3, h), (x + w * 0.7, h),
                       (x + w * 0.7, s1 * 0.8), (x + w, s1 * 0.8), (x + w, base)]
            elif kind < 0.62:                   # arch / gate ruin
                gw = w * 1.6
                pts = [(x, base), (x, h * 0.9)]
                n = 9
                for i in range(n + 1):
                    a = math.pi * (1 - i / n)
                    pts.append((x + gw / 2 + math.cos(a) * gw / 2, h * 0.85 + math.sin(a) * h * 0.25))
                pts += [(x + gw, base)]
                # open the arch: cut a dark void is skipped; keep silhouette simple
                w = gw
            else:
                pts = [(x, base), (x + w * 0.1, h), (x + w * 0.5, h * rng.uniform(0.85, 1.05)),
                       (x + w * 0.9, h * rng.uniform(0.6, 1.0)), (x + w, base)]
            polys.append(pts)
            x += w * rng.uniform(0.55, 1.1) + (rng.uniform(0, 36) if rng.random() < 0.4 else 0)
        return polys

    def _sparse(self, rng, x0, x1, ybase0, ybase1, hmin, hmax, wmin, wmax):
        """isolated broken pillars / walls standing on the plain; returns (base_y, poly)"""
        out = []
        x = x0 + rng.uniform(0, 300)
        while x < x1:
            w = rng.uniform(wmin, wmax)
            h = rng.uniform(hmin, hmax)
            yb = rng.uniform(ybase0, ybase1)
            k = rng.random()
            if k < 0.4:        # snapped pillar
                pts = [(0, 0), (0, h), (w * 0.35, h * 0.93), (w * 0.6, h * 1.0), (w * 0.8, h * 0.72), (w, h * 0.78), (w, 0)]
            elif k < 0.7:      # broken wall with a gap
                pts = [(0, 0), (0, h * 0.8), (w * 0.4, h), (w * 0.55, h * 0.45), (w * 1.1, h * 0.5), (w * 1.5, h * 0.9), (w * 1.6, 0)]
            else:              # leaning spire
                pts = [(0, 0), (w * 0.2, h), (w * 0.35, h * 1.25), (w * 0.55, h * 0.9), (w, 0)]
            out.append((x, yb, pts))
            x += w * 1.6 + rng.uniform(150, 520)
        return out

    def _hull(self):
        # a crashed wedge-shaped capital ship, nose buried in the ash, tilted
        body = [(0, -80), (1150, 215), (1150, 120), (260, -80)]
        deck = [(160, 5), (1000, 215), (1000, 238), (880, 232), (240, 25)]
        tower = [(820, 205), (840, 330), (900, 345), (930, 300), (960, 330), (975, 210)]
        dome = [(900, 345), (905, 372), (925, 372), (930, 345)]
        return body, deck, tower, dome

    # ---- drawing ----------------------------------------------------------------
    def draw(self, ctx, cam, t, windx):
        cx = cam['cx']
        # sky: white, with soft top-down haze (kept very light so the upper half stays white)
        ctx.set_source_rgb(1, 1, 1)
        ctx.rectangle(-9000, HORIZON, 18000, 9000)
        ctx.fill()
        lg = cairo.LinearGradient(0, HORIZON, 0, HORIZON + 260)
        lg.add_color_stop_rgba(0, 0.86, 0.86, 0.88, 0.0)
        lg.add_color_stop_rgba(0.0, 0.88, 0.88, 0.9, 0.75)
        lg.add_color_stop_rgba(1, 1, 1, 1, 0.0)
        ctx.set_source(lg)
        ctx.rectangle(-9000, HORIZON, 18000, 260)
        ctx.fill()

        # pale ringed planet, almost fixed to the sky
        ctx.save()
        ctx.translate(cx * 0.93 + 560, 330)
        ctx.save()
        ctx.rotate(-0.25)
        ctx.scale(1, 0.2)
        ctx.set_source_rgba(0.80, 0.80, 0.85, 0.95)
        ctx.set_line_width(14)
        ctx.arc(0, 0, 330, math.pi, TAU)     # back half of the ring
        ctx.stroke()
        ctx.set_line_width(5)
        ctx.arc(0, 0, 372, math.pi, TAU)
        ctx.stroke()
        ctx.restore()
        ctx.set_source_rgb(0.925, 0.925, 0.94)
        ctx.arc(0, 0, 190, 0, TAU)
        ctx.fill()
        ctx.save()
        ctx.arc(0, 0, 190, 0, TAU)
        ctx.clip()
        ctx.set_source_rgba(0.78, 0.78, 0.84, 0.55)
        ctx.arc(-120, 70, 230, 0, TAU)
        ctx.arc(-30, 20, 215, 0, TAU)
        ctx.set_fill_rule(cairo.FILL_RULE_EVEN_ODD)
        ctx.fill()
        ctx.restore()
        ctx.save()
        ctx.rotate(-0.25)
        ctx.scale(1, 0.2)
        ctx.set_source_rgba(0.80, 0.80, 0.85, 0.95)
        ctx.set_line_width(14)
        ctx.arc(0, 0, 330, 0, math.pi)       # front half
        ctx.stroke()
        ctx.set_line_width(5)
        ctx.arc(0, 0, 372, 0, math.pi)
        ctx.stroke()
        ctx.restore()
        ctx.restore()
        # little moon
        ctx.set_source_rgb(0.93, 0.93, 0.945)
        ctx.arc(cx * 0.9 - 780, 360, 42, 0, TAU)
        ctx.fill()

        # smoke columns
        for (sx, sh, sw, sa) in self.smoke:
            ctx.save()
            ctx.translate(cx * 0.8 + sx, HORIZON)
            g = cairo.LinearGradient(0, 0, 0, sh)
            g.add_color_stop_rgba(0, 0.45, 0.45, 0.48, sa * 2.0)
            g.add_color_stop_rgba(1, 0.8, 0.8, 0.82, 0.0)
            ctx.set_source(g)
            ctx.move_to(-sw * 0.5, 0)
            n = 8
            for i in range(n + 1):
                y = sh * i / n
                ctx.line_to(-sw * (0.5 + i * 0.2) + 7 * math.sin(t * 0.4 + i + sx), y)
            for i in range(n, -1, -1):
                y = sh * i / n
                ctx.line_to(sw * (0.5 + i * 0.2) + 7 * math.sin(t * 0.37 + i * 1.3 + sx), y)
            ctx.close_path()
            ctx.fill()
            ctx.restore()

        # far skylines + crashed hull
        for li, (p, col, boff, polys) in enumerate(self.layers):
            ctx.save()
            ctx.translate(cx * (1 - p), boff)
            ctx.set_source_rgb(*col)
            for pts in polys:
                ctx.move_to(*pts[0])
                for q in pts[1:]:
                    ctx.line_to(*q)
                ctx.close_path()
            ctx.fill()
            if li == 1:
                ctx.save()
                ctx.translate(-1650, -25)
                ctx.rotate(0.11)
                body, deck, tower, dome = self.hull
                for pts, c in ((body, (0.80, 0.80, 0.83)), (deck, (0.74, 0.74, 0.78)),
                               (tower, (0.70, 0.70, 0.75)), (dome, (0.66, 0.66, 0.71))):
                    ctx.set_source_rgb(*c)
                    ctx.move_to(*pts[0])
                    for q in pts[1:]:
                        ctx.line_to(*q)
                    ctx.close_path()
                    ctx.fill()
                ctx.restore()
            ctx.restore()

        # distant fires at the horizon
        for (ex, es) in self.embers:
            fl = 0.7 + 0.3 * math.sin(t * 9 + ex)
            ctx.save()
            ctx.translate(cx * 0.4 + ex, HORIZON)
            g = cairo.RadialGradient(0, es, 0, 0, es, es * 5)
            g.add_color_stop_rgba(0, 1.0, 0.55, 0.15, 0.55 * fl)
            g.add_color_stop_rgba(1, 1.0, 0.55, 0.15, 0.0)
            ctx.set_source(g)
            ctx.arc(0, es, es * 5, 0, TAU)
            ctx.fill()
            ctx.restore()

        # ground
        g = cairo.LinearGradient(0, HORIZON, 0, -420)
        g.add_color_stop_rgb(0, 0.43, 0.43, 0.47)
        g.add_color_stop_rgb(0.18, 0.31, 0.31, 0.345)
        g.add_color_stop_rgb(0.55, 0.19, 0.19, 0.215)
        g.add_color_stop_rgb(1, 0.10, 0.10, 0.12)
        ctx.set_source(g)
        ctx.rectangle(-9000, -9000, 18000, 9000 + HORIZON)
        ctx.fill()
        # ash drifts
        for (x, y, w, h, a) in self.ridges:
            ctx.save()
            ctx.translate(x, y)
            ctx.scale(w, h)
            ctx.set_source_rgba(0.74, 0.74, 0.78, a)
            ctx.arc(0, 0, 1, 0, TAU)
            ctx.fill()
            ctx.restore()
        # rocks / debris on the plain
        ctx.set_source_rgb(0.085, 0.085, 0.10)
        for (x, y, pts) in self.rocks:
            ctx.save()
            ctx.translate(x, y)
            ctx.move_to(*pts[0])
            for q in pts[1:]:
                ctx.line_to(*q)
            ctx.close_path()
            ctx.fill()
            ctx.restore()
        # near ruins standing on the plain
        for (p, col, items) in self.near:
            ctx.save()
            ctx.translate(cx * (1 - p), 0)
            ctx.set_source_rgb(*col)
            for (x, yb, pts) in items:
                ctx.save()
                ctx.translate(x, yb)
                ctx.move_to(*pts[0])
                for q in pts[1:]:
                    ctx.line_to(*q)
                ctx.close_path()
                ctx.fill()
                ctx.restore()
            ctx.restore()
        # re-lay a thin dark ground tone over the base of the near ruins so they sit in the ash
        g = cairo.LinearGradient(0, -60, 0, -150)
        g.add_color_stop_rgba(0, 0.12, 0.12, 0.14, 0.0)
        g.add_color_stop_rgba(1, 0.12, 0.12, 0.14, 0.0)

    def draw_foreground(self, ctx, cam, t):
        cx = cam['cx']
        p = 1.45
        ctx.save()
        ctx.translate(cx * (1 - p), 0)
        ctx.set_source_rgba(0.045, 0.045, 0.06, 0.96)
        for (x, pts) in self.fore:
            ctx.save()
            ctx.translate(x * 1.1, -330)
            ctx.move_to(*pts[0])
            for q in pts[1:]:
                ctx.line_to(*q)
            ctx.close_path()
            ctx.fill()
            ctx.restore()
        ctx.restore()

    def draw_flakes(self, ctx, cam, t, windx, W_, H_, fg=False):
        """screen-space ash flakes. ctx must have identity transform"""
        cx, cy, z = cam['cx'], cam['cy'], cam['zoom']
        if not fg:
            ctx.set_source_rgba(0.42, 0.42, 0.45, 0.55)
            for (u, v, d, r, ph) in self.flakes:
                sx = (u * 2400 + windx * (60 + 130 * d) - cx * z * d * 0.6) % 2400 - 240
                sy = (v * 1400 + t * (28 + 40 * d) * (1.0 + 0.3 * math.sin(t * 0.7 + ph * 9)) + cy * z * d * 0.3) % 1400 - 160
                sx += math.sin(t * 1.3 + ph * 20) * 9
                ctx.arc(sx * K, sy * K, r * (0.6 + d * 0.7) * K, 0, TAU)
                ctx.fill()
        else:
            for (u, v, r, ph, d) in self.fg_flakes:
                sx = (u * 2600 + windx * 380 * d - cx * z * d) % 2600 - 340
                sy = (v * 1500 + t * 60 * d + cy * z * 0.6) % 1500 - 200
                sx, sy, rr = sx * K, sy * K, r * d * 1.4 * K
                g = cairo.RadialGradient(sx, sy, 0, sx, sy, rr)
                g.add_color_stop_rgba(0, 0.4, 0.4, 0.43, 0.34)
                g.add_color_stop_rgba(1, 0.35, 0.35, 0.38, 0.0)
                ctx.set_source(g)
                ctx.arc(sx, sy, rr, 0, TAU)
                ctx.fill()


# ======================================================================================
# fighters
# ======================================================================================
BONES_FAR = (('S', 'le'), ('le', 'lh'), ('P', 'lk'), ('lk', 'lf'))
BONES_NEAR = (('P', 'N'), ('P', 'rk'), ('rk', 'rf'), ('S', 're'), ('re', 'rh'))
ALL_BONES = BONES_FAR + BONES_NEAR


def _bone(ctx, J, a, b):
    ctx.move_to(*J[a])
    ctx.line_to(*J[b])


def draw_figure(ctx, J, color, dark, alpha=1.0, lw=7.5, outline=True, bone_alpha=None):
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ol = (0.07, 0.07, 0.09)
    if outline:
        ctx.set_source_rgba(*ol, 0.88 * alpha)
        ctx.set_line_width(lw + 5.5)
        for a, b in ALL_BONES:
            ctx.new_sub_path() if False else None
            _bone(ctx, J, a, b)
        ctx.stroke()
        ctx.arc(J['H'][0], J['H'][1], HEAD_R + 2.8, 0, TAU)
        ctx.fill()
    far = mixc(color, dark, 0.55)
    ctx.set_line_width(lw)
    for idx, (a, b) in enumerate(ALL_BONES):
        al = alpha if bone_alpha is None else alpha * bone_alpha[idx]
        if al <= 0.01:
            continue
        c = far if idx < len(BONES_FAR) else color
        ctx.set_source_rgba(*c, al)
        _bone(ctx, J, a, b)
        ctx.stroke()
    ha = alpha if bone_alpha is None else alpha * bone_alpha[-1]
    # neck + head
    ctx.set_source_rgba(*color, ha)
    ctx.set_line_width(lw)
    ctx.move_to(*J['N'])
    hd = (J['H'][0] - J['N'][0], J['H'][1] - J['N'][1])
    ln = math.hypot(*hd) or 1
    ctx.line_to(J['N'][0] + hd[0] / ln * NECK, J['N'][1] + hd[1] / ln * NECK)
    ctx.stroke()
    ctx.arc(J['H'][0], J['H'][1], HEAD_R, 0, TAU)
    ctx.fill()


def saber_color(color):
    # saturated blade color
    return color


def draw_saber_glow(ctx, hilt, tip, color, a=1.0, scale=1.0):
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    for w, al in ((46, 0.07), (30, 0.12), (19, 0.2)):
        ctx.set_source_rgba(*color, al * a)
        ctx.set_line_width(w * scale)
        ctx.move_to(*hilt)
        ctx.line_to(*tip)
        ctx.stroke()


def draw_saber(ctx, hilt_base, hilt_top, tip, color, dark, lit):
    """hilt_base->hilt_top is the metal handle; hilt_top->tip is the blade"""
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    # handle
    ctx.set_source_rgb(0.06, 0.06, 0.08)
    ctx.set_line_width(7.5)
    ctx.move_to(*hilt_base)
    ctx.line_to(*hilt_top)
    ctx.stroke()
    ctx.set_source_rgb(0.72, 0.72, 0.76)
    ctx.set_line_width(4)
    ctx.move_to(*hilt_base)
    ctx.line_to(*hilt_top)
    ctx.stroke()
    if lit < 0.02:
        return
    ln = math.hypot(tip[0] - hilt_top[0], tip[1] - hilt_top[1])
    if ln < 1:
        return
    # glow halo
    draw_saber_glow(ctx, hilt_top, tip, color, 1.0)
    # dark edge so the blade reads on the white sky
    ctx.set_source_rgba(*mixc(color, (0, 0, 0), 0.62), 0.95)
    ctx.set_line_width(12.5)
    ctx.move_to(*hilt_top)
    ctx.line_to(*tip)
    ctx.stroke()
    ctx.set_source_rgb(*mixc(color, (1, 1, 1), 0.12))
    ctx.set_line_width(9)
    ctx.move_to(*hilt_top)
    ctx.line_to(*tip)
    ctx.stroke()
    ctx.set_source_rgb(*mixc(color, (1, 1, 1), 0.82))
    ctx.set_line_width(4.2)
    ctx.move_to(*hilt_top)
    ctx.line_to(*tip)
    ctx.stroke()


def saber_geom(f, t):
    """hilt_base, hilt_top, tip, lit, state"""
    st = f.state(t)
    free = None
    for (t0, t1, fn) in f.saber_free:
        if t0 <= t <= t1:
            free = fn(t)
    son = st['v']['son']
    if free is not None:
        x, y, ang = free
        d = dr(ang)
        half = (16.0 + BLADE) / 2
        hb = (x - d[0] * half, y - d[1] * half)
        ht = (hb[0] + d[0] * 16, hb[1] + d[1] * 16)
        tip = (ht[0] + d[0] * BLADE, ht[1] + d[1] * BLADE)
        return hb, ht, tip, 1.0 if son > 0.02 else 0.0, st
    J = st['J']
    # son==0 -> hilt only
    return J['pommel'], J['hilt'], J['tip'], max(0.0, min(1.0, son)), st


def draw_smear(ctx, f, t, color, nsamp=7, dt=1 / 100.0):
    """swept-area ribbon behind a moving blade"""
    pts = []
    for k in range(nsamp):
        tt = t - k * dt
        hb, ht, tip, lit, st = saber_geom(f, tt)
        if lit < 0.5:
            return
        a = (ht[0] + (tip[0] - ht[0]) * 0.28, ht[1] + (tip[1] - ht[1]) * 0.28)
        pts.append((a, tip))
    # skip when almost no motion
    mv = math.hypot(pts[0][1][0] - pts[-1][1][0], pts[0][1][1] - pts[-1][1][1])
    if mv < 14:
        return
    for k in range(nsamp - 1):
        (a0, t0), (a1, t1) = pts[k], pts[k + 1]
        al = (1 - k / (nsamp - 1)) ** 1.4 * 0.62
        ctx.set_source_rgba(*mixc(color, (1, 1, 1), 0.25), al)
        ctx.move_to(*a0); ctx.line_to(*t0); ctx.line_to(*t1); ctx.line_to(*a1)
        ctx.close_path()
        ctx.fill()


def fighter_speed(f, t):
    a = f.state(t)['x']
    b = f.state(t - 0.05)['x']
    return abs(a - b) / 0.05


def draw_aura(ctx, f, st, t, level, tint):
    J = st['J']
    c1, c2 = getattr(f, 'aura_cols', ((1.0, 0.82, 0.12), (1.0, 0.42, 0.05)))
    cx = (J['P'][0] + J['N'][0]) / 2
    cy = (J['P'][1] + J['N'][1]) / 2
    r = 120 * (0.7 + 0.3 * level)
    g = cairo.RadialGradient(cx, cy, 0, cx, cy, r)
    g.add_color_stop_rgba(0, *c1, 0.26 * level)
    g.add_color_stop_rgba(0.55, *c2, 0.12 * level)
    g.add_color_stop_rgba(1, *c2, 0.0)
    ctx.set_source(g)
    ctx.arc(cx, cy, r, 0, TAU)
    ctx.fill()
    rng = random.Random(11)
    bones = [('P', 'N'), ('P', 'rk'), ('P', 'lk'), ('rk', 'rf'), ('lk', 'lf'), ('S', 're'),
             ('re', 'rh'), ('S', 'le'), ('le', 'lh')]
    for i in range(46):
        a, b = bones[i % len(bones)]
        s = rng.random()
        ax = J[a][0] + (J[b][0] - J[a][0]) * s
        ay = J[a][1] + (J[b][1] - J[a][1]) * s
        ph = (t * rng.uniform(1.4, 2.4) + rng.random()) % 1.0
        hgt = (36 + 80 * rng.random()) * level * (1 - ph * 0.5)
        sway = math.sin(t * 7 + i) * 8 * level
        bx = ax + sway * ph + rng.uniform(-6, 6)
        by = ay + hgt * ph
        wd = (10 + 8 * rng.random()) * level * (1 - ph)
        col = mixc(c1, c2, ph)
        ctx.set_source_rgba(*col, 0.72 * (1 - ph) * min(1, level * 1.3))
        ctx.move_to(ax - wd, ay)
        ctx.curve_to(ax - wd * 0.7, ay + hgt * ph * 0.5, bx - wd * 0.3, by - hgt * 0.15, bx, by + hgt * 0.35)
        ctx.curve_to(bx + wd * 0.3, by - hgt * 0.15, ax + wd * 0.7, ay + hgt * ph * 0.5, ax + wd, ay)
        ctx.close_path()
        ctx.fill()


def draw_dissolve(ctx, f, t):
    t_eval = f.dead_t
    st = f.state(t_eval)
    J = st['J']
    u = (t - f.dead_t) / 1.3
    # progressive bone fade: feet first
    order = [0.55, 0.30, 0.38, 0.12, 0.22, 0.62, 0.72, 0.52, 0.66, 0.18]
    # BONES order: far arm(2), far leg(2), torso, near leg(2), near arm(2) + head
    seq = [0.55, 0.62, 0.20, 0.10, 0.45, 0.30, 0.12, 0.60, 0.70, 0.80]
    ba = [max(0.0, 1.0 - smooth((u - s * 0.55) / 0.35)) for s in seq]
    if max(ba) > 0.01:
        ctx.save()
        draw_figure(ctx, J, f.color, f.dark, alpha=1.0, bone_alpha=ba)
        ctx.restore()
    # particles
    rng = random.Random(hash(f.name) & 0xffff)
    bones = ALL_BONES
    n = 130
    for i in range(n):
        a, b = bones[rng.randrange(len(bones))]
        s = rng.random()
        px = J[a][0] + (J[b][0] - J[a][0]) * s
        py = J[a][1] + (J[b][1] - J[a][1]) * s
        delay = rng.random() * 0.9 * (0.4 + 0.6 * (1 - py / 150.0)) + (0.0)
        life = rng.uniform(1.1, 2.2)
        age = (t - f.dead_t) - delay * 0.8
        if age < 0 or age > life:
            continue
        vx = rng.uniform(30, 220)
        vy = rng.uniform(20, 160)
        q = age / life
        x = px + vx * age * (1 - 0.3 * q) + math.sin(age * 4 + i) * 6
        y = py + vy * age - 40 * age * age
        sz = rng.uniform(2.5, 6.5) * (1 - q * 0.6)
        c = mixc(f.color, (0.38, 0.38, 0.40), smooth(q * 1.5))
        ctx.set_source_rgba(*c, (1 - q) ** 0.8)
        ctx.save()
        ctx.translate(x, y)
        ctx.rotate(i + age * 3)
        ctx.rectangle(-sz / 2, -sz / 2, sz, sz)
        ctx.fill()
        ctx.restore()


def draw_fighter_aura(ctx, f, t):
    if f.dead_t is not None and t >= f.dead_t:
        return
    st = f.state(t)
    if st['v']['aura'] > 0.02:
        draw_aura(ctx, f, st, t, st['v']['aura'], f.color)


def draw_fighter(ctx, f, t, scene):
    st0 = f.state(t)
    dead = f.dead_t is not None and t >= f.dead_t
    if dead:
        draw_dissolve(ctx, f, t)
        return
    st = st0
    J = st['J']
    v = st['v']
    # ground shadow
    sx = st['x']
    ctx.save()
    ctx.translate(sx, -6)
    ctx.scale(1, 0.22)
    sh = max(0.35, 1.0 - max(0.0, v['air']) / 260.0)
    ctx.set_source_rgba(0, 0, 0, 0.38 * sh)
    ctx.arc(0, 0, 44 * sh, 0, TAU)
    ctx.fill()
    ctx.restore()

    # speed after-images
    spd = fighter_speed(f, t)
    if spd > 380 or v['runw'] > 0.6:
        for k in range(1, 4):
            tt = t - k * 0.035
            s2 = f.state(tt)
            ctx.save()
            draw_figure(ctx, s2['J'], f.color, f.dark, alpha=0.24 * (1 - k / 4.0), lw=7.0, outline=False)
            ctx.restore()

    draw_figure(ctx, J, f.color, f.dark)
    # saber
    hb, ht, tip, lit, _ = saber_geom(f, t)
    if lit > 0.02:
        draw_smear(ctx, f, t, f.color)
    # blade partial extension
    if lit > 0.02:
        ln = math.hypot(tip[0] - ht[0], tip[1] - ht[1])
    draw_saber(ctx, hb, ht, tip, f.color, f.dark, lit)


def draw_saber_emissive(ctx, f, t, scene):
    if f.dead_t is not None and t >= f.dead_t:
        return
    hb, ht, tip, lit, st = saber_geom(f, t)
    if lit > 0.02:
        draw_saber_glow(ctx, ht, tip, f.color, 1.0, 1.35)
        ctx.set_source_rgba(*mixc(f.color, (1, 1, 1), 0.5), 0.9)
        ctx.set_line_width(7)
        ctx.set_line_cap(cairo.LINE_CAP_ROUND)
        ctx.move_to(*ht)
        ctx.line_to(*tip)
        ctx.stroke()
    aura = st['v']['aura']
    if aura > 0.02:
        J = st['J']
        cx = (J['P'][0] + J['N'][0]) / 2
        cy = (J['P'][1] + J['N'][1]) / 2
        c1 = getattr(f, 'aura_cols', ((1.0, 0.82, 0.12), (1.0, 0.42, 0.05)))[0]
        g = cairo.RadialGradient(cx, cy, 0, cx, cy, 180)
        g.add_color_stop_rgba(0, *c1, 0.22 * aura)
        g.add_color_stop_rgba(1, *c1, 0.0)
        ctx.set_source(g)
        ctx.arc(cx, cy, 180, 0, TAU)
        ctx.fill()


# ======================================================================================
# effects (all analytic functions of script time)
# ======================================================================================
def starburst(ctx, x, y, r_out, r_in, n, rot, fill, line, lw):
    ctx.new_path()
    for i in range(n * 2):
        a = rot + math.pi * i / n
        r = r_out if i % 2 == 0 else r_in
        px, py = x + math.cos(a) * r, y + math.sin(a) * r
        if i == 0:
            ctx.move_to(px, py)
        else:
            ctx.line_to(px, py)
    ctx.close_path()
    if line is not None:
        ctx.set_source_rgba(*line)
        ctx.set_line_width(lw)
        ctx.set_line_join(cairo.LINE_JOIN_ROUND)
        ctx.stroke_preserve()
    ctx.set_source_rgba(*fill)
    ctx.fill()


def spark_set(ctx, ev, age, emissive, n, speed, life, col, grav=900.0):
    rng = random.Random(int(ev.t * 1000) * 7 + 3)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    for i in range(n):
        a = rng.uniform(0, TAU) if ev.kw.get('dir') is None else ev.kw['dir'] + rng.gauss(0, 0.9)
        sp = rng.uniform(0.25, 1.0) * speed
        lf = rng.uniform(0.5, 1.0) * life
        if age > lf:
            continue
        q = age / lf
        e = 1 - (1 - q) ** 2
        d = sp * life * 0.38 * e
        x = ev.x + math.cos(a) * d
        y = ev.y + math.sin(a) * d - 0.5 * grav * 0.35 * age * age
        # streak behind the head
        d2 = sp * life * 0.38 * (1 - (1 - max(0.0, q - 0.07)) ** 2)
        x2 = ev.x + math.cos(a) * d2
        y2 = ev.y + math.sin(a) * d2 - 0.5 * grav * 0.35 * max(0.0, age - 0.025) ** 2
        w = 4.2 * (1 - q) + 0.8
        if not emissive:
            ctx.set_source_rgba(0.35, 0.12, 0.02, 0.8 * (1 - q))
            ctx.set_line_width(w + 2.6)
            ctx.move_to(x2, y2); ctx.line_to(x, y); ctx.stroke()
        ctx.set_source_rgba(*mixc(col, (1, 1, 1), 0.5 * (1 - q)), 1.0 - q * 0.6)
        ctx.set_line_width(w)
        ctx.move_to(x2, y2); ctx.line_to(x, y); ctx.stroke()


def draw_event(ctx, ev, t, emissive=False):
    age = t - ev.t
    k = ev.kind
    kw = ev.kw
    if age < 0:
        return
    if k in ('clash', 'hit'):
        p = kw.get('power', 1.0)
        col = kw.get('color', (1.0, 0.82, 0.35))
        life = 0.55 * (0.7 + 0.3 * p)
        if age > life:
            return
        # core burst
        if age < 0.16:
            q = age / 0.16
            if emissive:
                g = cairo.RadialGradient(ev.x, ev.y, 0, ev.x, ev.y, 95 * p)
                g.add_color_stop_rgba(0, 1, 1, 1, 0.55 * (1 - q))
                g.add_color_stop_rgba(1, *col, 0.0)
                ctx.set_source(g)
                ctx.arc(ev.x, ev.y, 95 * p, 0, TAU)
                ctx.fill()
            else:
                starburst(ctx, ev.x, ev.y, 66 * p * (1 - q * 0.5), 16 * p, 11, ev.t * 40 + q,
                          (1, 1, 1, 0.92 * (1 - q) ** 1.5), (0.08, 0.07, 0.1, 0.8 * (1 - q)), 4)
                starburst(ctx, ev.x, ev.y, 38 * p * (1 - q * 0.4), 9 * p, 7, ev.t * 33,
                          (*mixc(col, (1, 1, 1), 0.5), 0.9 * (1 - q)), None, 0)
        spark_set(ctx, ev, age, emissive, int(22 + 18 * p), 900 * (0.8 + 0.5 * p), life, col)
        # shock ring
        if age < 0.35:
            q = age / 0.35
            r = 20 + 230 * p * (1 - (1 - q) ** 2)
            if not emissive:
                ctx.set_source_rgba(0.08, 0.07, 0.1, 0.5 * (1 - q))
                ctx.set_line_width(9 * (1 - q) + 2)
                ctx.arc(ev.x, ev.y, r + 3, 0, TAU)
                ctx.stroke()
            ctx.set_source_rgba(1, 1, 1, 0.9 * (1 - q))
            ctx.set_line_width(6 * (1 - q) + 1)
            ctx.arc(ev.x, ev.y, r, 0, TAU)
            ctx.stroke()
        # anamorphic flare
        if age < 0.32:
            q = age / 0.32
            ln = 520 * p * (1 - q) ** 1.5 + 40
            g = cairo.LinearGradient(ev.x - ln, 0, ev.x + ln, 0)
            g.add_color_stop_rgba(0, *col, 0.0)
            g.add_color_stop_rgba(0.5, 1, 1, 1, 0.95 * (1 - q))
            g.add_color_stop_rgba(1, *col, 0.0)
            ctx.set_source(g)
            ctx.rectangle(ev.x - ln, ev.y - 2.5 * (1 - q) - 0.5, ln * 2, 5 * (1 - q) + 1)
            ctx.fill()
    elif k == 'pebble':
        if emissive:
            return
        g = 1500.0
        tl = math.sqrt(2 * kw['y0'] / g)
        if age < tl:
            y = kw['y0'] - 0.5 * g * age * age
            rot = age * 7
        else:
            y = 4
            rot = 1.0
        ctx.save()
        ctx.translate(ev.x, y)
        ctx.rotate(rot)
        ctx.set_source_rgb(0.12, 0.12, 0.14)
        ctx.move_to(-6, -3); ctx.line_to(2, -7); ctx.line_to(7, 0); ctx.line_to(1, 6); ctx.line_to(-5, 4)
        ctx.close_path()
        ctx.fill()
        ctx.restore()
    elif k == 'dust':
        n = kw.get('n', 9)
        sp = kw.get('spread', 120)
        life = kw.get('life', 1.0)
        if age > life or emissive:
            return
        rng = random.Random(int(ev.t * 997))
        for i in range(n):
            d = kw.get('dir', 0)
            vx = rng.uniform(-1, 1) * sp + d * sp * 0.6
            q = age / life
            e = 1 - (1 - q) ** 2
            x = ev.x + vx * e
            y = ev.y + rng.uniform(4, 28) * e + 6 * q
            r = (14 + rng.uniform(0, 22)) * (0.4 + 1.2 * e)
            ctx.set_source_rgba(0.62, 0.62, 0.65, 0.5 * (1 - q) ** 1.3)
            ctx.arc(x, y, r, 0, TAU)
            ctx.fill()
    elif k == 'push':
        life = kw.get('life', 0.7)
        if age > life:
            return
        d = kw.get('dir', 1)
        col = kw.get('color', (1, 1, 1))
        q = age / life
        for j in range(3):
            qq = q - j * 0.1
            if qq < 0:
                continue
            e = 1 - (1 - qq) ** 2
            r = 60 + 560 * e
            a0, a1 = (-0.9, 0.9) if d > 0 else (math.pi - 0.9, math.pi + 0.9)
            ctx.save()
            ctx.translate(ev.x - d * 80, ev.y)
            ctx.scale(1, 1.15)
            if not emissive:
                ctx.set_source_rgba(0.1, 0.1, 0.13, 0.35 * (1 - qq))
                ctx.set_line_width(20 * (1 - qq) + 3)
                ctx.arc(0, 0, r, a0, a1)
                ctx.stroke()
            ctx.set_source_rgba(*mixc(col, (1, 1, 1), 0.6), 0.85 * (1 - qq))
            ctx.set_line_width(13 * (1 - qq) + 2)
            ctx.arc(0, 0, r, a0, a1)
            ctx.stroke()
            ctx.restore()
        # speed lines
        if not emissive:
            rng = random.Random(int(ev.t * 313))
            for i in range(14):
                yy = ev.y + rng.uniform(-90, 90)
                xx = ev.x + d * (rng.uniform(30, 200) + 700 * q * rng.uniform(0.6, 1.2))
                ln = rng.uniform(80, 220) * (1 - q)
                ctx.set_source_rgba(0.08, 0.08, 0.1, 0.5 * (1 - q))
                ctx.set_line_width(3)
                ctx.move_to(xx, yy); ctx.line_to(xx - d * ln, yy); ctx.stroke()
    elif k == 'ring':
        life = kw.get('life', 0.9)
        if age > life:
            return
        q = age / life
        e = 1 - (1 - q) ** 3
        r = kw.get('maxr', 700) * e
        col = kw.get('color', (1, 1, 1))
        ctx.save()
        ctx.translate(ev.x, ev.y)
        ctx.scale(1, kw.get('flat', 0.22))
        if not emissive:
            ctx.set_source_rgba(0.08, 0.08, 0.1, 0.45 * (1 - q))
            ctx.set_line_width(26 * (1 - q) + 4)
            ctx.arc(0, 0, r + 2, 0, TAU)
            ctx.stroke()
        ctx.set_source_rgba(*mixc(col, (1, 1, 1), 0.5), 0.9 * (1 - q))
        ctx.set_line_width(16 * (1 - q) + 2)
        ctx.arc(0, 0, r, 0, TAU)
        ctx.stroke()
        ctx.restore()
    elif k == 'debris':
        life = kw.get('life', 1.4)
        if age > life or emissive:
            return
        n = kw.get('n', 14)
        pw = kw.get('power', 1.0)
        rng = random.Random(int(ev.t * 777))
        for i in range(n):
            a = rng.uniform(0.15, math.pi - 0.15) if not kw.get('side') else rng.uniform(-0.5, 0.9) + (0 if kw['side'] > 0 else math.pi - 0.4)
            sp = rng.uniform(250, 780) * pw
            vx, vy = math.cos(a) * sp, math.sin(a) * sp
            x = ev.x + vx * age
            y = ev.y + vy * age - 0.5 * 1500 * age * age
            if y < -8:
                y = -8 - (-8 - y) * 0.0
            sz = rng.uniform(5, 18)
            ctx.save()
            ctx.translate(x, y)
            ctx.rotate(rng.uniform(0, 6) + age * rng.uniform(-8, 8))
            ctx.set_source_rgba(0.10, 0.10, 0.12, 1 - smooth((age - life * 0.7) / (life * 0.3)))
            ctx.move_to(-sz, -sz * 0.5); ctx.line_to(sz * 0.4, -sz); ctx.line_to(sz, sz * 0.4)
            ctx.line_to(-sz * 0.3, sz); ctx.close_path()
            ctx.fill()
            ctx.restore()
    elif k == 'crack':
        life = kw.get('life', 1.6)
        if age > life:
            return
        q = age / life
        col = kw.get('color', (1.0, 0.75, 0.15))
        rng = random.Random(int(ev.t * 555))
        e = 1 - (1 - min(1, age / 0.5)) ** 3
        ctx.set_line_cap(cairo.LINE_CAP_ROUND)
        for i in range(16):
            ang = (i / 16.0) * TAU * 0.5 + rng.uniform(-0.12, 0.12)
            ang = ang if rng.random() < 0.5 else math.pi - ang
            ln = rng.uniform(250, 700) * e
            ctx.set_source_rgba(*col, 0.9 * (1 - q))
            ctx.set_line_width(5 * (1 - q) + 1)
            x, y = ev.x, ev.y
            ctx.move_to(x, y)
            segs = 6
            for sgi in range(segs):
                x += math.cos(ang) * ln / segs * 1.0
                y += (math.sin(ang) * ln / segs) * 0.28 + rng.uniform(-6, 6)
                ctx.line_to(x, y)
            ctx.stroke()
    elif k == 'pillar':
        # glowing light pillar (rage burst)
        life = kw.get('life', 1.2)
        if age > life:
            return
        q = age / life
        col = kw.get('color', (1.0, 0.8, 0.2))
        wdt = kw.get('w', 150) * (1 - q) ** 0.6 * min(1, age / 0.12)
        g = cairo.LinearGradient(ev.x - wdt, 0, ev.x + wdt, 0)
        g.add_color_stop_rgba(0, *col, 0.0)
        g.add_color_stop_rgba(0.5, *mixc(col, (1, 1, 1), 0.6), 0.75 * (1 - q))
        g.add_color_stop_rgba(1, *col, 0.0)
        ctx.set_source(g)
        ctx.rectangle(ev.x - wdt, -400, wdt * 2, 1400)
        ctx.fill()


def draw_speed_lines(ctx, sl, t, W_, H_):
    """screen-space horizontal streaks.  sl=(t0,t1,strength,dir)"""
    t0, t1, s, d = sl
    if not (t0 <= t <= t1):
        return
    fade = min(1.0, (t - t0) / 0.1, (t1 - t) / 0.2)
    rng = random.Random(int(t * 60))
    for i in range(int(26 * s)):
        y = rng.uniform(0, H_)
        x = rng.uniform(-200, W_)
        ln = rng.uniform(260, 900) * K
        ctx.set_source_rgba(0.1, 0.1, 0.12, 0.28 * fade * rng.uniform(0.4, 1.0))
        ctx.set_line_width(rng.uniform(1.5, 4.5) * K)
        ctx.move_to(x, y)
        ctx.line_to(x + d * ln, y)
        ctx.stroke()


# ======================================================================================
# post processing
# ======================================================================================
_vig = None
_grain = None


def _prep():
    global _vig, _grain
    if _vig is None:
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        nx = (xx - W / 2) / (W / 2)
        ny = (yy - H / 2) / (H / 2)
        r2 = nx * nx * 0.55 + ny * ny * 0.85
        _vig = (1.0 - 0.36 * np.clip(r2, 0, 1.6) ** 1.35).astype(np.float32)[..., None]
        rng = np.random.default_rng(5)
        _grain = [rng.normal(0, 1, (H // 2 + 1, W // 2 + 1)).astype(np.float32) for _ in range(4)]


def surface_to_np(surf):
    buf = np.frombuffer(surf.get_data(), dtype=np.uint8).reshape(surf.get_height(), surf.get_stride() // 4, 4)
    return buf[:, :surf.get_width(), :]


def post(main_surf, em_surf, frame_idx, fx):
    """returns uint8 RGB (H,W,3).  fx: dict(flash, invert, fade, chroma, blur_dir, white_fade)"""
    _prep()
    a = surface_to_np(main_surf)
    img = (a[..., [2, 1, 0]].astype(np.float32)) / 255.0

    # --- emissive bloom
    if fx.get('invert'):
        img = 1.0 - img
        img = np.clip((img - 0.5) * 1.6 + 0.5, 0, 1)
        s = int(round(fx.get('chroma', 1.0)))
        if s > 0:
            img[..., 0] = np.roll(img[..., 0], s, axis=1)
            img[..., 2] = np.roll(img[..., 2], -s, axis=1)
        return (np.clip(img, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    e = surface_to_np(em_surf)
    eh, ew = e.shape[0], e.shape[1]
    pil = Image.fromarray(np.ascontiguousarray(e[..., [2, 1, 0, 3]]), 'RGBA')
    big = pil.filter(ImageFilter.GaussianBlur(7 * K)).resize((W, H), Image.BILINEAR)
    big2 = pil.filter(ImageFilter.GaussianBlur(22 * K)).resize((W, H), Image.BILINEAR)
    b1 = np.asarray(big, dtype=np.float32) / 255.0
    b2 = np.asarray(big2, dtype=np.float32) / 255.0
    # premultiplied cairo -> straight: Pillow treats as straight already in 'RGBA' mode (values premult)
    bl_rgb = b1[..., :3] * 1.0 + b2[..., :3] * 0.9
    bl_a = np.clip(b1[..., 3:4] * 1.0 + b2[..., 3:4] * 0.9, 0, 1)
    lum = (img[..., 0:1] * 0.3 + img[..., 1:2] * 0.59 + img[..., 2:3] * 0.11)
    lw = np.clip((lum - 0.35) / 0.5, 0, 1)
    # dark background: additive glow ; bright background: tinted darkening
    col = bl_rgb / np.maximum(bl_a, 1e-3)
    col = np.clip(col, 0, 1)
    add = img + bl_rgb * 1.15
    tint = img * (1 - np.clip(bl_a * 0.85, 0, 1) * (1 - col) * 0.9)
    img = add * (1 - lw) + tint * lw

    # --- directional blur for whips
    bd = fx.get('blur', 0.0)
    if bd > 0.03:
        k = int(4 + bd * 26)
        acc = np.zeros_like(img)
        n = 7
        for i in range(n):
            s = int((i - n // 2) * k / (n // 2))
            acc += np.roll(img, s, axis=1)
        img = acc / n

    # --- chromatic aberration
    ch = fx.get('chroma', 1.0)
    s = int(round(ch))
    if s > 0:
        img[..., 0] = np.roll(img[..., 0], s, axis=1)
        img[..., 2] = np.roll(img[..., 2], -s, axis=1)

    # --- vignette (soft; keeps whites mostly white)
    img = img * (0.88 + 0.12 * _vig) * 1.0
    img = img * _vig * 0.0 + img if False else img
    # --- grain
    g = _grain[frame_idx % 4]
    g = np.repeat(np.repeat(g, 2, axis=0), 2, axis=1)[:H, :W, None]
    img = img + g * 0.009

    # --- flashes
    fl = fx.get('flash', 0.0)
    if fl > 0:
        img = img * (1 - fl) + fl
    wf = fx.get('white', 0.0)
    if wf > 0:
        img = img * (1 - wf) + wf
    bf = fx.get('black', 0.0)
    if bf > 0:
        img = img * (1 - bf)
    img = np.clip(img, 0, 1)
    return (img * 255.0 + 0.5).astype(np.uint8)

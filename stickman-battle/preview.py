"""Dev tool: render a contact sheet of poses to check the rig."""
import sys
import math
import cairo
from rig import *

COLS = 6


def draw_fig(ctx, p, ox, oy, color=(0.1, 0.45, 1.0), face=1.0, scale=1.0):
    p = dict(p)
    p.setdefault('son', 1.0)
    p.setdefault('twohand', 0.0)
    J = skeleton(p, face)
    base = -lowest(J)
    ctx.save()
    ctx.translate(ox, oy)
    ctx.scale(scale, -scale)
    ctx.translate(0, base)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.set_line_width(6)
    ctx.set_source_rgb(*color)

    def seg(a, b):
        ctx.move_to(*J[a]); ctx.line_to(*J[b]); ctx.stroke()

    for a, b in (('P', 'N'), ('S', 're'), ('re', 'rh'), ('S', 'le'), ('le', 'lh'),
                 ('P', 'rk'), ('rk', 'rf'), ('P', 'lk'), ('lk', 'lf')):
        seg(a, b)
    ctx.arc(J['H'][0], J['H'][1], HEAD_R, 0, 2 * math.pi)
    ctx.fill()
    ctx.set_source_rgb(0.15, 0.15, 0.15)
    ctx.set_line_width(5)
    seg('pommel', 'hilt')
    ctx.set_source_rgb(1, 0.2, 0.2)
    ctx.set_line_width(4)
    seg('hilt', 'tip')
    ctx.restore()


def sheet(names, out, extra=None):
    n = len(names)
    rows = (n + COLS - 1) // COLS
    W, H = 330 * COLS, 330 * rows
    s = cairo.ImageSurface(cairo.FORMAT_RGB24, W, H)
    c = cairo.Context(s)
    c.set_source_rgb(1, 1, 1)
    c.paint()
    for i, nm in enumerate(names):
        col, row = i % COLS, i // COLS
        ox, oy = 165 + col * 330, 250 + row * 330
        c.set_source_rgb(0.8, 0.8, 0.8)
        c.move_to(ox - 150, oy); c.line_to(ox + 150, oy); c.set_line_width(1); c.stroke()
        p = POSES[nm] if isinstance(nm, str) else nm[1]
        label = nm if isinstance(nm, str) else nm[0]
        pp = dict(p)
        if label in ('lock', 'lock_low'):
            pp['twohand'] = 1.0
        draw_fig(c, pp, ox, oy, scale=1.2)
        c.set_source_rgb(0, 0, 0)
        c.select_font_face('DejaVu Sans')
        c.set_font_size(18)
        c.move_to(ox - 140, oy + 40)
        c.show_text(label)
    s.write_to_png(out)


if __name__ == '__main__':
    names = sys.argv[2:] or list(POSES.keys())
    sheet(names, sys.argv[1])

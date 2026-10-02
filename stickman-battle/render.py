"""Frame renderer.  usage:  python3 render.py still <script_t> out.png | video out.mp4"""
import sys, math, os, subprocess
import cairo
import numpy as np
from draw import *
import story
from scene import HORIZON

S = story.build()
FPS = story.FPS
BD = Backdrop()


def render_at(out_idx, script_t=None):
    if script_t is None:
        ot = out_idx / FPS
        t = S.warp.to_script(ot)
    else:
        t = script_t
        ot = S.warp.to_out(t)
    cam = S.cam.at(t)
    surf = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H)
    ctx = cairo.Context(surf)
    em_s = cairo.ImageSurface(cairo.FORMAT_ARGB32, W // 4, H // 4)
    em = cairo.Context(em_s)
    em.scale(0.25, 0.25)

    def apply_cam(c):
        c.translate(W / 2 + cam['sx'] * K, H / 2 + cam['sy'] * K)
        c.rotate((cam['rot'] + cam['srot']) * math.pi / 180.0)
        z = cam['zoom'] * K
        c.scale(z, -z)
        c.translate(-cam['cx'], -cam['cy'])

    windx = story.wind(t)
    ctx.save()
    apply_cam(ctx)
    BD.draw(ctx, cam, t, windx)
    for ev in S.events:
        if ev.kind in ('ring', 'crack', 'pillar') and t - ev.t < 3:
            draw_event(ctx, ev, t)
    order = sorted(S.fighters.values(), key=lambda f: S.zorder(f, t))
    for f in order:
        draw_fighter_aura(ctx, f, t)
    for f in order:
        draw_fighter(ctx, f, t, S)
    for ev in S.events:
        if ev.kind not in ('ring', 'crack', 'pillar') and 0 <= t - ev.t < 3:
            draw_event(ctx, ev, t)
    BD.draw_foreground(ctx, cam, t)
    ctx.restore()

    ctx.save()
    BD.draw_flakes(ctx, cam, t, windx, W, H)
    BD.draw_flakes(ctx, cam, t, windx, W, H, fg=True)
    for sl in S.speed_lines:
        draw_speed_lines(ctx, sl, t, W, H)
    ctx.restore()

    # emissive layer
    em.save()
    em.translate((W / 2 + cam['sx'] * K), (H / 2 + cam['sy'] * K))
    em.rotate((cam['rot'] + cam['srot']) * math.pi / 180.0)
    em.scale(cam['zoom'] * K, -cam['zoom'] * K)
    em.translate(-cam['cx'], -cam['cy'])
    for f in S.fighters.values():
        draw_saber_emissive(em, f, t, S)
    for ev in S.events:
        if 0 <= t - ev.t < 3:
            draw_event(em, ev, t, emissive=True)
    em.restore()

    fx = S.fx(ot, t, cam)
    return post(surf, em_s, out_idx, fx)


def write_png(arr, path):
    from PIL import Image
    Image.fromarray(arr).save(path)


def _worker(i):
    return render_at(i).tobytes()


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'still':
        t = float(sys.argv[2])
        write_png(render_at(0, script_t=t), sys.argv[3])
    elif cmd == 'stills':
        out = sys.argv[2]
        os.makedirs(out, exist_ok=True)
        for t in sys.argv[3:]:
            write_png(render_at(0, script_t=float(t)), f'{out}/t{float(t):06.2f}.png')
    elif cmd == 'video':
        import multiprocessing as mp
        out = sys.argv[2]
        a0 = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
        a1 = float(sys.argv[4]) if len(sys.argv) > 4 else S.warp.duration
        i0, i1 = int(a0 * FPS), int(a1 * FPS)
        ff = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
                               '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-', '-c:v', 'libx264', '-preset', 'fast',
                               '-crf', '19', '-pix_fmt', 'yuv420p', out], stdin=subprocess.PIPE)
        with mp.Pool(4) as pool:
            for n, buf in enumerate(pool.imap(_worker, range(i0, i1), chunksize=2)):
                ff.stdin.write(buf)
                if n % 60 == 0:
                    print(f'frame {n}/{i1 - i0}', flush=True)
        ff.stdin.close()
        ff.wait()

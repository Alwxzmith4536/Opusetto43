import os, sys, time
os.environ['QUICK'] = '0.25'
import multiprocessing as mp
import render

def work(i):
    try:
        render.render_at(i)
        return None
    except Exception as e:
        import traceback
        return (i, traceback.format_exc())

if __name__ == '__main__':
    n = int(render.S.warp.duration * render.FPS)
    idx = list(range(0, n, 5))
    t = time.time()
    with mp.Pool(4) as p:
        res = [r for r in p.imap_unordered(work, idx, chunksize=8) if r]
    print('frames', len(idx), 'errors', len(res), 'time', round(time.time() - t, 1))
    for r in res[:3]:
        print(r[0]); print(r[1])

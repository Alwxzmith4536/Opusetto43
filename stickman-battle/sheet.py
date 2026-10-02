"""contact sheet of stills:  QUICK=0.5 python3 sheet.py out.png t1 t2 ..."""
import sys, os
os.environ.setdefault('QUICK', '0.5')
from PIL import Image, ImageDraw
import render
out = sys.argv[1]
ts = [float(x) for x in sys.argv[2:]]
cols = 3 if len(ts) > 4 else 2
rows = (len(ts) + cols - 1) // cols
frames = []
for t in ts:
    a = render.render_at(0, script_t=t)
    im = Image.fromarray(a)
    d = ImageDraw.Draw(im)
    d.text((8, 6), f't={t:.2f}', fill=(255, 0, 0))
    frames.append(im)
w, h = frames[0].size
sh = Image.new('RGB', (w * cols, h * rows), (255, 255, 255))
for i, im in enumerate(frames):
    sh.paste(im, ((i % cols) * w, (i // cols) * h))
sh.save(out)

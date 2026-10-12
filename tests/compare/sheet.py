#!/usr/bin/env python3
"""Contact sheet of a run's frames (exploration helper): sheet.py <run> [cols] [scale]"""
import sys, glob, os
from PIL import Image, ImageDraw
run = sys.argv[1]; cols = int(sys.argv[2]) if len(sys.argv) > 2 else 4; sc = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
here = os.path.dirname(os.path.abspath(__file__))
fs = sorted(glob.glob(os.path.join(here, 'runs', run, 'frames', '*.png')))
ims = [Image.open(f) for f in fs]
w, h = int(ims[0].width * sc), int(ims[0].height * sc)
rows = (len(ims) + cols - 1) // cols
sheet = Image.new('RGB', (w * cols, h * rows))
for i, (f, im) in enumerate(zip(fs, ims)):
    t = im.resize((w, h)); ImageDraw.Draw(t).text((3, 3), os.path.basename(f)[:-4], fill=(255, 255, 0))
    sheet.paste(t, ((i % cols) * w, (i // cols) * h))
out = os.path.join(here, 'runs', run, 'sheet.png'); sheet.save(out); print(out, len(ims))

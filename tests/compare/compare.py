#!/usr/bin/env python3
"""Compares two capture runs frame by frame (see README.md).

Usage: compare.py <runA> <runB> [--out DIR] [--name NAME] [--strict]
  runA, runB   folders under tests/compare/runs/ (or paths) holding frames/*.png
  --strict     exit 1 when any frame pair differs at all (determinism checks)
For every frame present in both: PSNR, maximum absolute channel difference, the share of pixels
with any channel differing by more than 2 and by more than 16, and a clamped mean absolute
difference. Writes, per frame, <out>/<name>/<frame>_heat.png (the difference times 8, so a
difference of 32 levels is full white; pixels differing at all show at least 40) and
<frame>_side.png (A | B | heat), then prints a table and the worst frames.
"""
import argparse, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def load(p):
    return np.asarray(Image.open(p).convert('RGB'), dtype=np.int16)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('a'); ap.add_argument('b')
    ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    ap.add_argument('--name')
    ap.add_argument('--strict', action='store_true')
    ap.add_argument('--no-images', action='store_true')
    a = ap.parse_args()
    ra = a.a if os.path.isdir(a.a) else os.path.join(HERE, 'runs', a.a)
    rb = a.b if os.path.isdir(a.b) else os.path.join(HERE, 'runs', a.b)
    name = a.name or f'{os.path.basename(ra.rstrip("/"))}__{os.path.basename(rb.rstrip("/"))}'
    od = os.path.join(a.out, name); os.makedirs(od, exist_ok=True)
    fa = {f for f in os.listdir(os.path.join(ra, 'frames')) if f.endswith('.png')}
    fb = {f for f in os.listdir(os.path.join(rb, 'frames')) if f.endswith('.png')}
    for f in sorted(fa ^ fb):
        print(f'only in one run: {f}')
    rows = []
    for f in sorted(fa & fb):
        x, y = load(os.path.join(ra, 'frames', f)), load(os.path.join(rb, 'frames', f))
        if x.shape != y.shape:
            print(f'{f}: size {x.shape} vs {y.shape}'); rows.append((f, 0.0, 255, 100.0, 100.0, 255.0)); continue
        d = np.abs(x - y)
        m = d.max(axis=2)
        mse = float((d.astype(np.float64) ** 2).mean())
        psnr = float('inf') if mse == 0 else 10 * np.log10(255 ** 2 / mse)
        rows.append((f, psnr, int(d.max()), 100.0 * (m > 2).mean(), 100.0 * (m > 16).mean(), float(d.mean()), 100.0 * (m > 0).mean()))
        if not a.no_images and d.max() > 0:
            heat = np.clip(m * 8, 0, 255).astype(np.uint8)
            heat = np.where(m > 0, np.maximum(heat, 40), 0).astype(np.uint8)
            h3 = np.stack([heat, np.zeros_like(heat), np.zeros_like(heat)], axis=2)
            # visible heatmap: grey picture of A underneath, difference in red on top
            base = (x.mean(axis=2) * 0.25).astype(np.uint8)
            h3 = np.stack([np.maximum(base, heat), base, base], axis=2)
            stem = f[:-4]
            Image.fromarray(h3).save(os.path.join(od, f'{stem}_heat.png'))
            side = np.concatenate([x.astype(np.uint8), y.astype(np.uint8), h3], axis=1)
            Image.fromarray(side).save(os.path.join(od, f'{stem}_side.png'))
    print(f'A = {ra}\nB = {rb}')
    print(f'{"frame":22} {"PSNR dB":>8} {"maxdiff":>7} {"%>0":>7} {"%>2":>7} {"%>16":>7} {"mean":>6}')
    for r in rows:
        f, psnr, mx, p2, p16, mean = r[:6]; p0 = r[6] if len(r) > 6 else 100.0
        ps = 'inf' if psnr == float('inf') else f'{psnr:.2f}'
        print(f'{f[:-4]:22} {ps:>8} {mx:>7} {p0:>7.3f} {p2:>7.3f} {p16:>7.3f} {mean:>6.3f}')
    worst = sorted(rows, key=lambda r: (r[3], r[2]), reverse=True)[:5]
    if worst and worst[0][2] > 0:
        print('worst frames (by % of pixels differing by more than 2, then max diff):')
        for r in worst:
            print(f'  {r[0][:-4]}: >2 {r[3]:.3f}%, >16 {r[4]:.3f}%, max {r[2]}  -> {od}/{r[0][:-4]}_side.png')
    else:
        print('all frames pixel identical')
    ident = sum(1 for r in rows if r[2] == 0)
    print(f'{ident}/{len(rows)} frames identical')
    sys.exit(1 if (a.strict and ident != len(rows)) else 0)


if __name__ == '__main__':
    main()

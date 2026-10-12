#!/usr/bin/env python3
"""Compares several runs of one build with several runs of another, frame by frame (see README.md).

Usage: compare_runs.py <scenario> [flavorA flavorB] [--out DIR]
Uses runs/<flavorA>_<scenario>_* and runs/<flavorB>_<scenario>_* (as made by run_all.sh); the
flavors are ref, port or astc, default ref and port. "ref/port" below reads "A/B".

A run is not always identical to the next one of the same build (see README, "Determinism"), so a
single ref against port pair can differ because the game itself diverged. For every frame this
prints, over all pairs of runs:
  ref/ref    worst pair of cmp-ref runs, share of pixels differing by more than 2 (0 = all runs agree)
  port/port  the same for cmp-port runs
  ref/port   the BEST pair (smallest share), with its PSNR, max abs channel difference and shares
             above 2 and above 16; this is the shader comparison where the runs agree
and writes heat map and side by side images for the best ref/port pair of each frame that is not
pixel identical (out/<scenario>_best/). A frame is "game diverged" when no ref/port pair is within
the spread the same build shows against itself; otherwise the best pair is what the shaders did.
"""
import argparse, glob, itertools, os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def load(p):
    return np.asarray(Image.open(p).convert('RGB'), dtype=np.int16)


def stats(x, y):
    d = np.abs(x - y); m = d.max(axis=2)
    mse = float((d.astype(np.float64) ** 2).mean())
    psnr = float('inf') if mse == 0 else 10 * np.log10(255 ** 2 / mse)
    return dict(psnr=psnr, mx=int(d.max()), p0=100 * (m > 0).mean(), p2=100 * (m > 2).mean(), p16=100 * (m > 16).mean(), m=m)


def heat(x, y, m):
    h = np.where(m > 0, np.maximum(np.clip(m * 8, 0, 255), 40), 0).astype(np.uint8)
    base = (x.mean(axis=2) * 0.25).astype(np.uint8)
    return np.stack([np.maximum(base, h), base, base], axis=2)


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('scenario'); ap.add_argument('fa', nargs='?', default='ref'); ap.add_argument('fb', nargs='?', default='port'); ap.add_argument('--out', default=os.path.join(HERE, 'out'))
    a = ap.parse_args()
    refs = sorted(glob.glob(os.path.join(HERE, 'runs', f'{a.fa}_{a.scenario}_*')))
    ports = sorted(glob.glob(os.path.join(HERE, 'runs', f'{a.fb}_{a.scenario}_*')))
    if not refs or not ports:
        sys.exit('no runs')
    od = os.path.join(a.out, f'{a.scenario}_{a.fa}_{a.fb}_best'); os.makedirs(od, exist_ok=True)
    frames = sorted(set.intersection(*[{f for f in os.listdir(os.path.join(r, 'frames')) if f.endswith('.png')} for r in refs + ports]))
    print(f'scenario {a.scenario}: {a.fa} runs {[os.path.basename(r) for r in refs]}, {a.fb} runs {[os.path.basename(r) for r in ports]}')
    print(f'{"frame":18} {(a.fa+"/"+a.fa)[:8]:>8} {(a.fb+"/"+a.fb)[:9]:>9} | best A/B pair: {"PSNR":>7} {"max":>4} {"%>0":>7} {"%>2":>7} {"%>16":>7}  verdict')
    worst = []
    for f in frames:
        im = {r: load(os.path.join(r, 'frames', f)) for r in refs + ports}
        rr = max([stats(im[p], im[q])['p2'] for p, q in itertools.combinations(refs, 2)] or [0.0])
        pp = max([stats(im[p], im[q])['p2'] for p, q in itertools.combinations(ports, 2)] or [0.0])
        best = None
        for r, p in itertools.product(refs, ports):
            s = stats(im[r], im[p])
            if best is None or (s['p2'], s['p16'], s['mx']) < (best[0]['p2'], best[0]['p16'], best[0]['mx']):
                best = (s, r, p)
        s, r, p = best
        spread = max(rr, pp)
        if s['mx'] == 0: v = 'identical'
        elif s['p2'] == 0 and s['mx'] <= 2: v = f'rounding only (max {s["mx"]})'
        elif s['p2'] <= spread + 1e-9 and spread > 0: v = 'within the build to build spread (game diverged)'
        else: v = 'DIFFERENT'
        print(f'{f[:-4]:18} {rr:8.3f} {pp:9.3f} | {"inf" if s["psnr"] == float("inf") else f"{s["psnr"]:.2f}":>26} {s["mx"]:>4} {s["p0"]:>7.3f} {s["p2"]:>7.3f} {s["p16"]:>7.3f}  {v}')
        if s['mx'] > 0:
            h = heat(im[r], im[p], s['m']); stem = f[:-4]
            Image.fromarray(h).save(os.path.join(od, f'{stem}_heat.png'))
            Image.fromarray(np.concatenate([im[r].astype(np.uint8), im[p].astype(np.uint8), h], axis=1)).save(os.path.join(od, f'{stem}_side.png'))
        worst.append((s['p2'], s['mx'], f, v))
    bad = [w for w in worst if w[3] == 'DIFFERENT']
    print(f'{sum(1 for w in worst if w[1] == 0)} of {len(worst)} frames identical for the best pair, '
          f'{sum(1 for w in worst if w[3].startswith("rounding"))} differ by rounding only, '
          f'{sum(1 for w in worst if w[3].startswith("within"))} inside the build to build spread, {len(bad)} unexplained')
    for w in sorted(bad, reverse=True)[:5]:
        print(f'  unexplained: {w[2][:-4]} >2 {w[0]:.3f}% max {w[1]}  -> {od}/{w[2][:-4]}_side.png')


if __name__ == '__main__':
    main()

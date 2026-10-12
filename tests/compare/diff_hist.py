#!/usr/bin/env python3
"""Histogram of the per channel differences of two runs' frames, next to the sRGB step sizes (see README.md).

Usage: diff_hist.py <runA> <runB> [frame ...]     (default: every frame both runs have)
Shows how often each difference value occurs (all frames summed). The game renders into an 8 bit
linear buffer and encodes to sRGB on the way out, so when two GPUs round one buffer value apart
(+-1 level) the output differs by the sRGB step at that level: 13 (0 to 1), 9 (1 to 2), 6, 5, 4, 4,
4, 3 ... A histogram with peaks at those values means rounding in the linear buffer, not a
different picture.
"""
import os, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))


def srgb(n):
    c = n / 255.0
    return 255.0 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)


def main():
    ra, rb = [a if os.path.isdir(a) else os.path.join(HERE, 'runs', a) for a in sys.argv[1:3]]
    frames = sys.argv[3:] or sorted(f[:-4] for f in os.listdir(os.path.join(ra, 'frames')) if f.endswith('.png'))
    h = np.zeros(256, dtype=np.int64)
    for f in frames:
        x = np.asarray(Image.open(os.path.join(ra, 'frames', f + '.png')).convert('RGB'), dtype=np.int16)
        y = np.asarray(Image.open(os.path.join(rb, 'frames', f + '.png')).convert('RGB'), dtype=np.int16)
        h += np.bincount(np.abs(x - y).ravel(), minlength=256)
    exact = [srgb(n + 1) - srgb(n) for n in range(12)]
    steps = {int(np.floor(v)) for v in exact[:3]} | {int(np.ceil(v)) for v in exact[:3]}   # the steps that stand out
    print('sRGB steps of linear levels 0->1, 1->2, ...: ' + ' '.join(f'{v:.1f}' for v in exact))
    tot = h[1:].sum()
    print(f'{len(frames)} frames, {h.sum()} channel values, {tot} differ')
    print('diff  count   share of the differing values')
    for d in range(1, 40):
        if h[d]:
            print(f'{d:4} {h[d]:7}   {100.0 * h[d] / tot:6.2f}%' + ('   <- an sRGB step' if d in steps else ''))
    big = h[40:].sum()
    if big:
        print(f' >=40 {big:6}   {100.0 * big / tot:6.2f}%   (largest {int(np.nonzero(h)[0].max())})')


if __name__ == '__main__':
    main()

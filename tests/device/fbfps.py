import time, sys
# Presented frames per second, counted from framebuffer page flips (fb0/pan changes), sampled at ~1 kHz.
dur = float(sys.argv[1]) if len(sys.argv) > 1 else 5
last = None; flips = 0; t0 = time.time()
while time.time() - t0 < dur:
    with open('/sys/class/graphics/fb0/pan') as f: p = f.read()
    if p != last:
        if last is not None: flips += 1
        last = p
    time.sleep(0.001)
print('flips/s %.1f' % (flips / dur))

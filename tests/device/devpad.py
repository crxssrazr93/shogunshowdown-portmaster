#!/usr/bin/env python3
"""Inject button presses into the device's own controller (runs ON the device).
Writing events to the controller's evdev node delivers them to every reader (evdev, joydev, SDL)
as if the buttons were pressed, so games see them on their usual joystick 0.
Usage: devpad.py "wait 2; press A; hold dleft 0.5; press START"
Steps: wait <s> | press <BTN> [secs] | hold <dpad-dir|BTN> <s> | chord <BTN> <BTN> (both held 0.5 s)
Names are the printed button labels of Anbernic H700 devices."""
import sys, time, glob
from evdev import InputDevice, ecodes as e

# Key codes of the Anbernic H700 internal controller as Knulli reports them (es_input.cfg); they are
# not the standard gamepad codes (BTN_SOUTH is the A button here, and Select/Start are BTN_TL2/TR2).
BTN = {'A': 304, 'B': 305, 'Y': 306, 'X': 307, 'L1': 308, 'R1': 309, 'SELECT': 310, 'START': 311,
       'MENU': 312, 'L3': 313, 'L2': 314, 'R2': 315, 'R3': 316}
HAT = {'dup': (e.ABS_HAT0Y, -1), 'ddown': (e.ABS_HAT0Y, 1), 'dleft': (e.ABS_HAT0X, -1), 'dright': (e.ABS_HAT0X, 1)}

dev = next(InputDevice(p) for p in glob.glob('/dev/input/event*') if 'Controller' in InputDevice(p).name)

def put(t, c, v):
    dev.write(t, c, v); dev.write(e.EV_SYN, e.SYN_REPORT, 0)

for step in [s.strip() for s in sys.argv[1].split(';') if s.strip()]:
    cmd, *a = step.split()
    if cmd == 'wait':
        time.sleep(float(a[0]))
    elif cmd == 'press':
        put(e.EV_KEY, BTN[a[0]], 1); time.sleep(float(a[1]) if len(a) > 1 else 0.15)
        put(e.EV_KEY, BTN[a[0]], 0); time.sleep(0.25)
    elif cmd == 'hold':
        if a[0] in HAT:
            code, val = HAT[a[0]]; put(e.EV_ABS, code, val); time.sleep(float(a[1])); put(e.EV_ABS, code, 0)
        else:
            put(e.EV_KEY, BTN[a[0]], 1); time.sleep(float(a[1])); put(e.EV_KEY, BTN[a[0]], 0)
        time.sleep(0.25)
    elif cmd == 'chord':
        for b in a: put(e.EV_KEY, BTN[b], 1); time.sleep(0.05)
        time.sleep(0.5)
        for b in a: put(e.EV_KEY, BTN[b], 0)
        time.sleep(0.25)
    print('done:', step, flush=True)

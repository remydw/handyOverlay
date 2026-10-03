#!/usr/bin/env python3
"""Print the mic RMS level (0..1) about 25 times a second, one number per line."""
import array
import math
import os
import signal
import subprocess
import sys

RATE = 16000
CHUNK = RATE // 25  # samples per report

# arecord writes unbuffered raw PCM to stdout (pw-record/pw-cat buffer it).
cmd = ["arecord", "-q", "-t", "raw", "-f", "S16_LE", "-r", str(RATE), "-c", "1"]
# argv[1]: PipeWire node name of the mic to meter (default: the system default source).
env = dict(os.environ)
if len(sys.argv) > 1 and sys.argv[1]:
    env["PIPEWIRE_NODE"] = sys.argv[1]
proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env)
def stop(*_):
    proc.terminate()
    sys.exit(0)


# DMS stops us with SIGTERM; make sure the arecord child dies with us.
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGHUP, stop)
try:
    while True:
        buf = proc.stdout.read(CHUNK * 2)
        if not buf:
            break
        samples = array.array("h", buf[: len(buf) // 2 * 2])
        if not samples:
            continue
        rms = math.sqrt(sum(s * s for s in samples) / len(samples)) / 32768.0
        print(f"{min(1.0, rms * 6.0):.3f}", flush=True)
finally:
    proc.terminate()

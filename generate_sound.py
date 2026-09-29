#!/usr/bin/env python3
"""Generate six original short PCM sound effects with Python's standard library."""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44_100
OUT = Path(__file__).resolve().parent / "generated-sounds"
OUT.mkdir(exist_ok=True)


def write_sound(name, duration, sample):
    rng = random.Random(name)
    frames = bytearray()
    for index in range(round(duration * RATE)):
        t = index / RATE
        value = max(-1.0, min(1.0, sample(t, rng))) * 0.72
        frames.extend(struct.pack("<h", round(value * 32767)))
    with wave.open(str(OUT / f"{name}.wav"), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        audio.writeframes(frames)
    print(f"Wrote {OUT / f'{name}.wav'}")


def shotgun(t, rng):
    attack = min(1.0, t / 0.002)
    decay = math.exp(-24 * t)
    phase = 2 * math.pi * (135 * t - 193 * t * t)
    thump = math.sin(phase) * math.exp(-19 * t)
    crackle = rng.uniform(-1, 1) * decay
    return attack * (0.65 * crackle + 0.3 * thump)


def boing(t, rng):
    pitch_phase = 2 * math.pi * (700 * t - 540 * t * t)
    wobble = math.sin(2 * math.pi * 20 * t) * 0.18
    return math.sin(pitch_phase + wobble) * math.exp(-7 * t) * min(1, t / 0.005)


def beep(t, rng):
    edge = min(1, t / 0.008, (0.28 - t) / 0.012)
    return math.sin(2 * math.pi * 1040 * t) * max(0, edge) * 0.65


def fart(t, rng):
    flutter = 1 + 0.25 * math.sin(2 * math.pi * 34 * t)
    phase = 2 * math.pi * (95 * t - 30 * t * t)
    noise = rng.uniform(-1, 1) * 0.16
    return (math.sin(phase) * 0.7 + noise) * flutter * math.exp(-5 * t)


def pew(t, rng):
    burst = t if t < 0.16 else t - 0.18
    if burst < 0:
        return 0
    phase = 2 * math.pi * (950 * burst - 1800 * burst * burst)
    return math.sin(phase) * math.exp(-18 * burst) * min(1, burst / 0.003)


def quack(t, rng):
    phase = 2 * math.pi * (290 * t - 115 * t * t)
    nasal = math.sin(phase) + 0.45 * math.sin(2 * phase) + 0.2 * math.sin(3 * phase)
    envelope = (1 if t < 0.11 else 0.7) * math.exp(-6 * t)
    return nasal * envelope * min(1, t / 0.003) * 0.55


for name, duration, generator in [
    ("shotgun", 0.22, shotgun),
    ("boing", 0.42, boing),
    ("beep", 0.28, beep),
    ("fart", 0.46, fart),
    ("pew", 0.43, pew),
    ("quack", 0.30, quack),
]:
    write_sound(name, duration, generator)

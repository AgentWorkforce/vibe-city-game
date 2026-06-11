#!/usr/bin/env python3
"""Procedurally generate placeholder SFX for VIBE CITY.

Pure-stdlib synthesis (no numpy). Output: assets/audio/sfx/*.wav
Run from repo root: python3 tools/gen_audio.py
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")


def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
            for s in samples
        )
        w.writeframes(frames)
    print("wrote", os.path.relpath(path))


def lowpass(samples, alpha):
    out, prev = [], 0.0
    for s in samples:
        prev += alpha * (s - prev)
        out.append(prev)
    return out


def highpass(samples, alpha):
    lp = lowpass(samples, alpha)
    return [s - l for s, l in zip(samples, lp)]


def envelope(n, attack, decay_tau):
    env = []
    for i in range(n):
        t = i / SR
        a = min(1.0, t / attack) if attack > 0 else 1.0
        env.append(a * math.exp(-t / decay_tau))
    return env


def noise(n, rng):
    return [rng.uniform(-1, 1) for _ in range(n)]


def footstep(rng, dur, lp_alpha, hp_alpha, decay):
    n = int(SR * dur)
    s = noise(n, rng)
    s = lowpass(s, lp_alpha)
    s = highpass(s, hp_alpha)
    env = envelope(n, 0.002, decay)
    return [x * e for x, e in zip(s, env)]


def land_thud(rng):
    n = int(SR * 0.25)
    env = envelope(n, 0.001, 0.06)
    body = [math.sin(2 * math.pi * (80 - 35 * i / n) * i / SR) for i in range(n)]
    click = [x * e for x, e in zip(lowpass(noise(n, rng), 0.35), envelope(n, 0.0005, 0.015))]
    return [b * e * 0.9 + c * 0.4 for b, e, c in zip(body, env, click)]


def engine_loop():
    base = 88.0
    cycles = round(base * 1.0)          # whole cycles -> seamless loop
    n = int(SR * cycles / base)
    out = []
    for i in range(n):
        t = i / SR
        v = 0.0
        for mult, amp in ((1, 0.5), (2, 0.3), (3, 0.14), (4.03, 0.06)):
            v += amp * math.sin(2 * math.pi * base * mult * t)
        v += 0.08 * math.sin(2 * math.pi * base * 0.5 * t)  # sub rumble
        out.append(math.tanh(1.6 * v))
    return out


def tire_screech_loop():
    rng = random.Random(7)
    n = int(SR * 0.6)
    s = noise(n, rng)
    # crude resonator near ~1.1 kHz
    out, y1, y2 = [], 0.0, 0.0
    f = 1100.0 / SR
    q = 0.97
    w = 2 * math.pi * f
    a1, a2 = 2 * q * math.cos(w), -q * q
    for x in s:
        y = x * 0.08 + a1 * y1 + a2 * y2
        y2, y1 = y1, y
        out.append(y)
    # crossfade tail into head for seamless loop
    fade = int(SR * 0.05)
    for i in range(fade):
        k = i / fade
        out[i] = out[i] * k + out[n - fade + i] * (1 - k)
    return out[: n - fade]


def impact_crunch(rng):
    n = int(SR * 0.45)
    thump = [math.sin(2 * math.pi * (55 - 20 * i / n) * i / SR) for i in range(n)]
    thump = [t * e for t, e in zip(thump, envelope(n, 0.001, 0.09))]
    crunch = [x * e for x, e in zip(highpass(noise(n, rng), 0.25), envelope(n, 0.001, 0.05))]
    ring = []
    for i in range(n):
        t = i / SR
        ring.append(0.18 * math.sin(2 * math.pi * 820 * t) * math.exp(-t / 0.12)
                    + 0.12 * math.sin(2 * math.pi * 1340 * t) * math.exp(-t / 0.08))
    return [a + 0.5 * b + c for a, b, c in zip(thump, crunch, ring)]


def main():
    rng = random.Random(42)
    for i in range(1, 5):
        write_wav(f"footstep_concrete_{i}.wav",
                  footstep(rng, 0.09, 0.55, 0.12, 0.025))
    for i in range(1, 5):
        write_wav(f"footstep_sand_{i}.wav",
                  footstep(rng, 0.14, 0.18, 0.04, 0.045))
    write_wav("land_thud.wav", land_thud(rng))
    write_wav("engine_loop.wav", engine_loop())
    write_wav("tire_screech_loop.wav", tire_screech_loop())
    write_wav("impact_crunch.wav", impact_crunch(rng))


if __name__ == "__main__":
    main()

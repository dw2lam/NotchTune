#!/usr/bin/env python3
"""Synthesize NotchTune's bundled notification sound pack.

Every sound is generated here from oscillators, modal partials, filters and
envelopes (Python stdlib only), so the pack is original and reproducible:
re-running the script writes byte-identical files.

Each sound is loudness-matched to the macOS system alert sounds (the max
100 ms K-weighted loudness of /System/Library/Sounds sits around
TARGET_LOUDNESS), peaks no higher than PEAK_CEILING_DB, starts and ends on
short fades so nothing clicks, and is written as 16-bit mono 44.1 kHz WAV to
Sources/NotchTuneApp/Resources/Sounds/notchtune-<slug>.wav.

    python3 scripts/generate-notification-sounds.py            # write the pack
    python3 scripts/generate-notification-sounds.py --report   # also print stats
"""

import math
import os
import random
import struct
import sys
import wave

SR = 44100
TARGET_LOUDNESS = -22.0   # dB, max 100 ms K-weighted loudness (system median -22.4)
PEAK_CEILING_DB = -1.0
FADE_IN_S = 0.003
FADE_OUT_S = 0.04

OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..",
    "Sources", "NotchTuneApp", "Resources", "Sounds",
)


# MARK: - Primitives

def silence(seconds):
    return [0.0] * int(round(seconds * SR))


def fade_tail(x, seconds):
    """Cosine fade over the last `seconds` (no-op on silence)."""
    n = min(len(x), int(seconds * SR))
    for i in range(n):
        x[-1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / n)
    return x


def mix_into(buffer, signal, at_seconds=0.0, gain=1.0, release=0.006):
    """Adds `signal` at `at_seconds`. Every note ends on a short release fade,
    so a note cut off mid-ring (a beep's end, a bell's tail) never clicks."""
    signal = fade_tail(list(signal), release)
    start = int(round(at_seconds * SR))
    end = start + len(signal)
    if end > len(buffer):
        buffer.extend([0.0] * (end - len(buffer)))
    for i, value in enumerate(signal):
        buffer[start + i] += value * gain
    return buffer


def note(name):
    """'A4' / 'C#6' → Hz (equal temperament, A4 = 440)."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4,
             "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def envelope(n, attack, decay, hold=0.0):
    """Smooth attack ramp, optional hold, then exponential decay."""
    out = []
    for i in range(n):
        t = i / SR
        if t < attack:
            x = t / attack
            out.append(x * x * (3 - 2 * x))
        elif t < attack + hold:
            out.append(1.0)
        else:
            out.append(math.exp(-(t - attack - hold) / decay))
    return out


def poly_blep(t, dt):
    if t < dt:
        t /= dt
        return t + t - t * t - 1.0
    if t > 1.0 - dt:
        t = (t - 1.0) / dt
        return t * t + t + t + 1.0
    return 0.0


def pulse(freqs, duty=0.5):
    """Band-limited (PolyBLEP) pulse wave following a per-sample frequency list."""
    out, phase = [], 0.0
    for f in freqs:
        dt = f / SR
        value = 1.0 if phase < duty else -1.0
        value += poly_blep(phase, dt)
        value -= poly_blep((phase - duty) % 1.0, dt)
        out.append(value)
        phase = (phase + dt) % 1.0
    return out


def saw(freqs):
    out, phase = [], 0.0
    for f in freqs:
        dt = f / SR
        out.append(2.0 * phase - 1.0 - poly_blep(phase, dt))
        phase = (phase + dt) % 1.0
    return out


def sine(freqs, phase=0.0):
    out = []
    for f in freqs:
        out.append(math.sin(phase))
        phase += 2 * math.pi * f / SR
    return out


def triangle(freqs):
    # Odd harmonics at 1/n², alternating sign; 7 terms is plenty at these pitches.
    out, phase = [], 0.0
    for f in freqs:
        value = 0.0
        for k in range(7):
            n = 2 * k + 1
            if n * f >= SR * 0.45:
                break
            value += (-1) ** k * math.sin(n * phase) / (n * n)
        out.append(value * 8 / math.pi ** 2)
        phase += 2 * math.pi * f / SR
    return out


def constant(f, seconds):
    return [f] * int(round(seconds * SR))


def glide(f0, f1, seconds, curve=1.0):
    """Exponential glide from f0 to f1 (curve > 1 lingers near f0)."""
    n = int(round(seconds * SR))
    return [f0 * (f1 / f0) ** ((i / max(1, n - 1)) ** curve) for i in range(n)]


def modal(freq, seconds, partials, attack=0.002, release=0.04):
    """Struck object: partials of (ratio, amplitude, decay seconds), with a
    `release` fade so the tail never stops abruptly."""
    n = int(round(seconds * SR))
    out = [0.0] * n
    for ratio, amp, decay in partials:
        f = freq * ratio
        if f >= SR * 0.45:
            continue
        w = 2 * math.pi * f / SR
        for i in range(n):
            out[i] += amp * math.sin(w * i) * math.exp(-i / SR / decay)
    ramp = int(attack * SR)
    for i in range(min(ramp, n)):
        x = i / ramp
        out[i] *= x * x * (3 - 2 * x)
    return fade_tail(out, release)


def noise(seconds, rng):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(round(seconds * SR)))]


def one_pole_lowpass(x, cutoff):
    a = math.exp(-2 * math.pi * cutoff / SR)
    y, out = 0.0, []
    for v in x:
        y = (1 - a) * v + a * y
        out.append(y)
    return out


def biquad(x, b0, b1, b2, a0, a1, a2):
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for v in x:
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, y
        out.append(y)
    return out


def bandpass(x, center, q):
    w0 = 2 * math.pi * center / SR
    alpha = math.sin(w0) / (2 * q)
    return biquad(x, alpha, 0.0, -alpha, 1 + alpha, -2 * math.cos(w0), 1 - alpha)


def highpass(x, cutoff, q=0.7071):
    w0 = 2 * math.pi * cutoff / SR
    alpha, c = math.sin(w0) / (2 * q), math.cos(w0)
    return biquad(x, (1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)


def svf_lowpass(x, cutoffs, q=0.9):
    """State-variable low-pass with a per-sample cutoff (for the pluck sweep)."""
    low = band = 0.0
    out = []
    damp = 1.0 / q
    for v, fc in zip(x, cutoffs):
        f = 2 * math.sin(math.pi * min(fc, SR / 6) / SR)
        low += f * band
        high = v - low - damp * band
        band += f * high
        out.append(low)
    return out


def shaped(signal, env):
    return [s * e for s, e in zip(signal, env)]


# MARK: - The pack

def pixel_ping():
    first = shaped(pulse(constant(note("E6"), 0.07), duty=0.25), envelope(int(0.07 * SR), 0.002, 0.06))
    second = shaped(pulse(constant(note("B6"), 0.2), duty=0.25), envelope(int(0.2 * SR), 0.002, 0.055))
    out = silence(0.27)
    mix_into(out, first, 0.0, 0.8)
    mix_into(out, second, 0.07)
    return one_pole_lowpass(out, 7000)


def level_up():
    out = silence(0.52)
    steps = ["C5", "E5", "G5", "C6"]
    for i, name in enumerate(steps):
        last = i == len(steps) - 1
        length = 0.3 if last else 0.065
        env = envelope(int(length * SR), 0.002, 0.11 if last else 0.06)
        mix_into(out, shaped(pulse(constant(note(name), length), duty=0.5), env), i * 0.065, 0.9 if last else 0.75)
    # A quiet octave echo of the top note: the "ding" of the level-up.
    echo = shaped(pulse(constant(note("C7"), 0.16), duty=0.25), envelope(int(0.16 * SR), 0.002, 0.05))
    mix_into(out, echo, 0.27, 0.25)
    return one_pole_lowpass(out, 6500)


def coin():
    out = silence(0.46)
    first = shaped(pulse(constant(note("A5"), 0.06), duty=0.125), envelope(int(0.06 * SR), 0.002, 0.08))
    # The second note bends up into pitch, a little chirp.
    bend = glide(note("E6") * 0.985, note("E6"), 0.03) + constant(note("E6"), 0.35)
    second = shaped(pulse(bend, duty=0.125), envelope(len(bend), 0.002, 0.11))
    mix_into(out, first, 0.0, 0.8)
    mix_into(out, second, 0.06)
    return one_pole_lowpass(out, 6000)


CHIME_PARTIALS = [(1.0, 1.0, 0.36), (2.0, 0.22, 0.22), (3.0, 0.07, 0.14), (4.16, 0.05, 0.09)]


def soft_chime():
    out = silence(1.1)
    mix_into(out, modal(note("G5"), 1.0, CHIME_PARTIALS, attack=0.006), 0.0, 0.85)
    mix_into(out, modal(note("C6"), 0.92, CHIME_PARTIALS, attack=0.006), 0.17)
    return out


def glass_tap():
    rng = random.Random(5)
    body = modal(2200, 0.45, [(1.0, 1.0, 0.22), (2.76, 0.45, 0.11), (5.40, 0.22, 0.05), (8.93, 0.1, 0.025)], attack=0.0008)
    click = shaped(highpass(noise(0.004, rng), 3000), envelope(int(0.004 * SR), 0.0003, 0.0012))
    out = silence(0.45)
    mix_into(out, body)
    mix_into(out, click, 0.0, 0.25)
    return out


MARIMBA_PARTIALS = [(1.0, 1.0, 0.16), (3.93, 0.32, 0.06), (9.2, 0.08, 0.025)]


def marimba():
    rng = random.Random(6)
    out = silence(0.66)
    for at, name, gain in [(0.0, "G5", 0.85), (0.12, "D6", 1.0)]:
        mix_into(out, modal(note(name), 0.54, MARIMBA_PARTIALS, attack=0.0015), at, gain)
        thump = shaped(one_pole_lowpass(noise(0.006, rng), 1200), envelope(int(0.006 * SR), 0.0005, 0.002))
        mix_into(out, thump, at, 0.12)
    return out


KALIMBA_PARTIALS = [(1.0, 1.0, 0.22), (5.4, 0.28, 0.05), (9.6, 0.06, 0.02)]


def kalimba():
    out = silence(0.9)
    for at, name, gain in [(0.0, "A5", 0.9), (0.09, "C#6", 0.8), (0.18, "E6", 1.0)]:
        mix_into(out, modal(note(name), 0.7, KALIMBA_PARTIALS, attack=0.001), at, gain)
    return out


def bubble():
    out = silence(0.24)
    for at, f0, f1, gain in [(0.0, 380, 1300, 1.0), (0.085, 560, 1900, 0.55)]:
        sweep = glide(f0, f1, 0.09, curve=0.6)
        mix_into(out, shaped(sine(sweep), envelope(len(sweep), 0.003, 0.035)), at, gain)
    return out


BELL_PARTIALS = [(0.5, 0.2, 0.45), (1.0, 1.0, 0.38), (1.19, 0.28, 0.28),
                 (1.5, 0.18, 0.24), (2.0, 0.24, 0.2), (2.74, 0.07, 0.12)]


def ding_dong():
    out = silence(1.2)
    mix_into(out, modal(note("E5"), 1.2, BELL_PARTIALS, attack=0.004), 0.0, 0.9)
    mix_into(out, modal(note("C5"), 0.88, BELL_PARTIALS, attack=0.004), 0.32)
    return out


def pluck():
    out = silence(0.62)
    for at, name in [(0.0, "E5"), (0.0, "B5"), (0.08, "E6")]:
        length = 0.54
        raw = saw(constant(note(name), length))
        cutoffs = [600 + 4200 * math.exp(-(i / SR) / 0.06) for i in range(len(raw))]
        tone = svf_lowpass(raw, cutoffs)
        mix_into(out, shaped(tone, envelope(len(tone), 0.002, 0.16)), at, 0.55 if name != "E6" else 0.35)
    return out


def sparkle():
    rng = random.Random(11)
    out = silence(0.62)
    scale = ["C7", "D7", "E7", "G7", "A7", "C8"]
    at = 0.0
    for i in range(7):
        name = scale[min(len(scale) - 1, i * len(scale) // 7 + rng.randint(0, 1))]
        ping = modal(note(name) * rng.uniform(0.997, 1.003), 0.2, [(1.0, 1.0, 0.07), (2.01, 0.15, 0.03)], attack=0.0015)
        mix_into(out, ping, at, 0.55 + 0.45 * (i / 6))
        at += 0.045 + rng.uniform(-0.008, 0.008)
    return out


def knock():
    rng = random.Random(13)
    out = silence(0.36)
    for at, gain in [(0.0, 0.85), (0.13, 1.0)]:
        drop = glide(170, 105, 0.12, curve=0.5)
        body = shaped(sine(drop), envelope(len(drop), 0.0015, 0.045))
        tap = shaped(bandpass(noise(0.03, rng), 900, 1.4), envelope(int(0.03 * SR), 0.0005, 0.008))
        mix_into(out, body, at, gain)
        mix_into(out, tap, at, gain * 0.9)
    return out


def bloop():
    sweep = glide(900, 430, 0.2, curve=0.7)
    tone = [s + 0.18 * h for s, h in zip(sine(sweep), sine([2 * f for f in sweep]))]
    return shaped(tone, envelope(len(tone), 0.005, 0.07))


def arcade_alert():
    out = silence(0.32)
    for i, name in enumerate(["E6", "A6", "E6", "A6"]):
        beep = shaped(pulse(constant(note(name), 0.058), duty=0.5), envelope(int(0.058 * SR), 0.002, 0.045))
        mix_into(out, beep, i * 0.065, 0.8)
    return one_pole_lowpass(out, 6000)


WOOD_PARTIALS = [(1.0, 1.0, 0.05), (2.57, 0.4, 0.024), (4.9, 0.14, 0.012)]


def wood_block():
    rng = random.Random(17)
    out = silence(0.3)
    for at, f in [(0.0, 820), (0.11, 1050)]:
        mix_into(out, modal(f, 0.2, WOOD_PARTIALS, attack=0.0006), at)
        click = shaped(bandpass(noise(0.005, rng), 2200, 2.0), envelope(int(0.005 * SR), 0.0003, 0.0015))
        mix_into(out, click, at, 0.35)
    return out


PAN_PARTIALS = [(1.0, 1.0, 0.2), (1.003, 0.35, 0.2), (2.0, 0.45, 0.14), (3.0, 0.2, 0.09), (4.01, 0.1, 0.06)]


def steel_drum():
    out = silence(0.76)
    mix_into(out, modal(note("A5"), 0.6, PAN_PARTIALS, attack=0.003), 0.0, 0.85)
    mix_into(out, modal(note("E6"), 0.6, PAN_PARTIALS, attack=0.003), 0.14)
    return out



# MARK: - The second set

def fm_piano(freq, seconds, index=2.0, index_decay=0.18, decay=0.4, attack=0.003):
    """A soft electric piano: one sine phase-modulated by itself (ratio 1),
    the brightness falling away faster than the note."""
    n = int(round(seconds * SR))
    w = 2 * math.pi * freq / SR
    out = []
    for i in range(n):
        depth = index * math.exp(-i / SR / index_decay)
        out.append(math.sin(w * i + depth * math.sin(w * i)))
    return shaped(out, envelope(n, attack, decay))


def detuned_saws(freq, seconds, cents=(-7, 0, 7)):
    voices = [saw(constant(freq * 2 ** (c / 1200), seconds)) for c in cents]
    return [sum(v) / len(voices) for v in zip(*voices)]


def swell():
    # A warm Cadd9 pad that blooms in and fades: no strike at all.
    length = 1.15
    out = silence(length)
    for name in ["C4", "G4", "D5", "E5"]:
        mix_into(out, detuned_saws(note(name), length), 0.0, 0.25)
    tone = svf_lowpass(out, [700 + 900 * min(1.0, i / SR / 0.45) for i in range(len(out))], q=0.8)
    env = []
    for i in range(len(tone)):
        t = i / SR
        rise = math.sin(math.pi * 0.5 * min(1.0, t / 0.38)) ** 2
        env.append(rise * (1.0 if t < 0.62 else math.exp(-(t - 0.62) / 0.16)))
    return shaped(tone, env)


HARP_PARTIALS = [(1.0, 1.0, 0.42), (2.0, 0.42, 0.24), (3.0, 0.18, 0.15), (4.0, 0.08, 0.09), (5.0, 0.04, 0.06)]


def harp():
    # A quick pentatonic run up the strings, the top note left ringing.
    out = silence(1.05)
    run = ["D5", "E5", "G5", "A5", "B5", "D6", "E6"]
    for i, name in enumerate(run):
        last = i == len(run) - 1
        mix_into(out, modal(note(name), 0.8 if last else 0.5, HARP_PARTIALS, attack=0.0025), i * 0.045, 1.0 if last else 0.55)
    return one_pole_lowpass(out, 7000)


MUSIC_BOX_PARTIALS = [(1.0, 1.0, 0.5), (1.0016, 0.6, 0.45), (3.01, 0.06, 0.12), (6.4, 0.12, 0.05)]


def music_box():
    # Four tiny comb tines in the top octave; each tine is doubled a hair
    # sharp, which gives the box its shimmer.
    out = silence(1.15)
    for at, name, gain in [(0.0, "E6", 0.8), (0.16, "B6", 0.75), (0.32, "G6", 0.7), (0.48, "D7", 1.0)]:
        mix_into(out, modal(note(name), 0.66, MUSIC_BOX_PARTIALS, attack=0.0012), at, gain)
    return out


VIBES_PARTIALS = [(1.0, 1.0, 0.7), (4.0, 0.2, 0.18), (10.0, 0.04, 0.05)]


def vibraphone():
    # A soft-mallet dyad, then a third bar, under the motor's tremolo.
    out = silence(1.15)
    for at, name, gain in [(0.0, "F5", 0.7), (0.0, "A5", 0.6), (0.14, "C6", 0.8)]:
        mix_into(out, modal(note(name), 1.0, VIBES_PARTIALS, attack=0.004), at, gain)
    return [v * (1 - 0.3 * (0.5 - 0.5 * math.cos(2 * math.pi * 5.6 * i / SR))) for i, v in enumerate(out)]


def flute():
    # Two breathy notes slurred together, the second with a little vibrato.
    rng = random.Random(23)
    first, slide, second = 0.24, 0.035, 0.5
    pitch = (constant(note("E5"), first) + glide(note("E5"), note("B5"), slide)
             + constant(note("B5"), second))
    vibrato_from, release_at = first + 0.12, first + slide + second - 0.22
    pitch = [f * (1 + 0.006 * min(1.0, max(0.0, (i / SR - vibrato_from) / 0.2))
                  * math.sin(2 * math.pi * 5.2 * i / SR))
             for i, f in enumerate(pitch)]
    tone = [a + 0.12 * b for a, b in zip(sine(pitch), sine([2 * f for f in pitch]))]
    breath = one_pole_lowpass(bandpass(noise(len(pitch) / SR, rng), note("B5"), 1.2), 5000)
    env = []
    for i in range(len(tone)):
        t = i / SR
        env.append(min(1.0, t / 0.06) * (1.0 if t < release_at else math.exp(-(t - release_at) / 0.07)))
    return shaped([v + 0.22 * b for v, b in zip(tone, breath)], env)


DESK_BELL_PARTIALS = [(1.0, 1.0, 0.55), (2.32, 0.42, 0.3), (4.25, 0.24, 0.14), (6.63, 0.1, 0.07)]


def desk_bell():
    # A hotel-desk bell, tapped twice: "service, please".
    rng = random.Random(29)
    out = silence(1.15)
    for at, gain in [(0.0, 0.85), (0.17, 1.0)]:
        mix_into(out, modal(1320, 0.95, DESK_BELL_PARTIALS, attack=0.0008), at, gain)
        clack = shaped(bandpass(noise(0.004, rng), 3500, 2.0), envelope(int(0.004 * SR), 0.0003, 0.001))
        mix_into(out, clack, at, gain * 0.2)
    return out


GONG_PARTIALS = [(1.0, 1.0, 0.7), (1.47, 0.55, 0.55), (2.09, 0.5, 0.42), (2.56, 0.32, 0.3), (3.27, 0.25, 0.22), (4.18, 0.14, 0.15)]


def gong():
    # A small gong: the upper partials bloom a beat after the strike while
    # the pitch sags a touch; centred high enough for laptop speakers.
    rng = random.Random(31)
    length = 1.2
    n = int(length * SR)
    base = 233.0
    out = [0.0] * n
    for k, (ratio, amp, decay) in enumerate(GONG_PARTIALS):
        bloom = 0.002 if k == 0 else 0.03 + 0.03 * k
        phase = 0.0
        for i in range(n):
            t = i / SR
            f = base * ratio * (1 - 0.008 * (1 - math.exp(-t / 0.25)))
            phase += 2 * math.pi * f / SR
            out[i] += amp * math.sin(phase) * (1 - math.exp(-t / bloom)) * math.exp(-t / decay)
    mallet = shaped(one_pole_lowpass(noise(0.02, rng), 900), envelope(int(0.02 * SR), 0.001, 0.006))
    mix_into(out, mallet, 0.0, 0.5)
    return fade_tail(out, 0.05)


def question():
    # A rising minor triad on electric piano whose last note lifts up a
    # semitone: an unresolved "hm?".
    out = silence(0.86)
    for at, name in [(0.0, "D5"), (0.11, "F5")]:
        mix_into(out, fm_piano(note(name), 0.4, decay=0.22), at, 0.75)
    lift = constant(note("A5"), 0.08) + glide(note("A5"), note("A#5"), 0.12, curve=0.6) + constant(note("A#5"), 0.4)
    n = len(lift)
    w = [2 * math.pi * f / SR for f in lift]
    phase, tone = 0.0, []
    for i in range(n):
        phase += w[i]
        tone.append(math.sin(phase + 1.6 * math.exp(-i / SR / 0.18) * math.sin(phase)))
    mix_into(out, shaped(tone, envelope(n, 0.003, 0.3)), 0.22)
    return out


def resolve():
    # A dominant chord settling home on electric piano: done, and well.
    out = silence(1.15)
    for name in ["G4", "B4", "D5", "F5"]:
        mix_into(out, fm_piano(note(name), 0.3, index=1.6, decay=0.14), 0.0, 0.32)
    for name in ["C5", "E5", "G5", "C6"]:
        mix_into(out, fm_piano(note(name), 0.95, index=1.8, decay=0.36), 0.2, 0.34)
    return out


def ta_da():
    # Two brassy hits, short then long, the filter opening on each.
    out = silence(1.15)
    for at, chord, length, gain in [(0.0, ["G4", "D5", "G5"], 0.12, 0.6), (0.15, ["C5", "G5", "C6", "E6"], 0.95, 0.5)]:
        hit = silence(length)
        for name in chord:
            mix_into(hit, detuned_saws(note(name), length, cents=(-5, 5)), 0.0, gain)
        cut = [500 + 3800 * (1 - math.exp(-(i / SR) / 0.03)) * math.exp(-(i / SR) / 0.5) for i in range(len(hit))]
        tone = svf_lowpass(hit, cut, q=1.1)
        env = [min(1.0, (i / SR) / 0.012) * math.exp(-(i / SR) / (0.06 if length < 0.2 else 0.32)) for i in range(len(tone))]
        mix_into(out, shaped(tone, env), at)
    return out


def modem():
    # A dial-up-ish handshake: two-tone warble, a sweep, an answering tone,
    # all squeezed through a phone line's band.
    out = silence(0.52)
    warble = [1270 if (i // int(0.012 * SR)) % 2 == 0 else 1070 for i in range(int(0.16 * SR))]
    mix_into(out, shaped(sine(warble), envelope(len(warble), 0.004, 0.5, hold=0.12)), 0.0, 0.6)
    sweep = glide(600, 2400, 0.1, curve=1.0)
    mix_into(out, shaped(triangle(sweep), envelope(len(sweep), 0.004, 0.2, hold=0.06)), 0.17, 0.5)
    answer = constant(2100, 0.17)
    mix_into(out, shaped(sine(answer), envelope(len(answer), 0.004, 0.05, hold=0.08)), 0.3, 0.55)
    return bandpass(out, 1500, 0.55)


def power_on():
    # A pulse wave revving up, landing on a bright open fifth.
    out = silence(0.62)
    rev = glide(180, 1400, 0.12, curve=1.4)
    mix_into(out, shaped(pulse(rev, duty=0.25), envelope(len(rev), 0.002, 0.5, hold=0.09)), 0.0, 0.45)
    for name, gain in [("E6", 0.7), ("B6", 0.5)]:
        tone = triangle(constant(note(name), 0.46))
        mix_into(out, shaped(tone, envelope(len(tone), 0.003, 0.13)), 0.13, gain)
    return one_pole_lowpass(out, 7000)


def water_drop():
    # One drip into still water, echoing off the walls of a cave.
    rng = random.Random(37)
    out = silence(0.62)
    drop = silence(0.07)
    plink = glide(1100, 2600, 0.035, curve=0.5) + constant(2600, 0.02)
    mix_into(drop, shaped(sine(plink), envelope(len(plink), 0.0015, 0.018)), 0.004)
    tap = shaped(highpass(noise(0.002, rng), 4000), envelope(int(0.002 * SR), 0.0002, 0.0006))
    mix_into(drop, tap, 0.0, 0.3)
    for at, gain, cutoff in [(0.0, 1.0, 12000), (0.12, 0.3, 3500), (0.24, 0.14, 2500), (0.36, 0.06, 1800)]:
        mix_into(out, one_pole_lowpass(drop, cutoff), at, gain)
    return out


def chirp():
    # Three little bird calls, quick falling whistles with a flutter; the
    # last one longer.
    out = silence(0.5)
    for at, top, low, length, gain in [(0.0, 4200, 2700, 0.05, 0.75), (0.1, 4400, 2800, 0.05, 0.8), (0.2, 4600, 2600, 0.11, 1.0)]:
        sweep = glide(top, low, length, curve=0.7)
        sweep = [f * (1 + 0.02 * math.sin(2 * math.pi * 55 * i / SR)) for i, f in enumerate(sweep)]
        n = len(sweep)
        env = [math.sin(math.pi * i / n) ** 1.5 for i in range(n)]
        mix_into(out, shaped(sine(sweep), env), at, gain)
    return out


def tick():
    # The quietest cue in the pack: a single small watch-like tick.
    rng = random.Random(41)
    out = silence(0.16)
    click = shaped(bandpass(noise(0.006, rng), 2400, 3.0), envelope(int(0.006 * SR), 0.0004, 0.0018))
    ping = modal(2900, 0.05, [(1.0, 1.0, 0.008), (2.3, 0.3, 0.004)], attack=0.0004, release=0.01)
    mix_into(out, click, 0.004)
    mix_into(out, ping, 0.004, 0.5)
    return out


def pip():
    # A single soft sine pip, for people who want the least sound possible.
    out = silence(0.16)
    tone = [a + 0.15 * b for a, b in zip(sine(constant(note("G6"), 0.09)), sine(constant(2 * note("G6"), 0.09)))]
    mix_into(out, shaped(tone, envelope(len(tone), 0.004, 0.022)), 0.004)
    return out

# slug → (title, synth, character). The app lists them by title.
PACK = [
    ("pixel-ping", "Pixel Ping", pixel_ping, "two-note 8-bit blip"),
    ("level-up", "Level Up", level_up, "rising chiptune arpeggio"),
    ("coin", "Coin", coin, "bright arcade confirm"),
    ("soft-chime", "Soft Chime", soft_chime, "gentle rising two-note chime"),
    ("glass-tap", "Glass Tap", glass_tap, "crisp tap on glass"),
    ("marimba", "Marimba", marimba, "warm two-note mallet"),
    ("kalimba", "Kalimba", kalimba, "plinked thumb-piano triad"),
    ("bubble", "Bubble", bubble, "two bubbly pops"),
    ("ding-dong", "Ding Dong", ding_dong, "soft doorbell"),
    ("pluck", "Pluck", pluck, "filtered synth pluck"),
    ("sparkle", "Sparkle", sparkle, "quick shimmer of high notes"),
    ("knock", "Knock", knock, "low double knock, for needs-you moments"),
    ("bloop", "Bloop", bloop, "soft falling bloop"),
    ("arcade-alert", "Arcade Alert", arcade_alert, "alternating 8-bit alert"),
    ("wood-block", "Wood Block", wood_block, "two woody tonks"),
    ("steel-drum", "Steel Drum", steel_drum, "bright island steel pan"),
    # The second set, appended so the first sixteen keep their dither seeds
    # and stay byte-identical.
    ("swell", "Swell", swell, "warm pad that blooms in and fades"),
    ("harp", "Harp", harp, "quick pentatonic run up the strings"),
    ("music-box", "Music Box", music_box, "four tiny shimmering comb tines"),
    ("vibraphone", "Vibraphone", vibraphone, "soft mallets under a slow tremolo"),
    ("flute", "Flute", flute, "two breathy slurred notes"),
    ("desk-bell", "Desk Bell", desk_bell, "hotel desk bell, tapped twice, for needs-you moments"),
    ("gong", "Gong", gong, "small blooming gong, for needs-you moments"),
    ("question", "Question", question, "rising triad that lifts at the end: hm?"),
    ("resolve", "Resolve", resolve, "electric-piano chord settling home"),
    ("ta-da", "Ta Da", ta_da, "two brassy hits, short then long"),
    ("modem", "Modem", modem, "dial-up handshake in miniature"),
    ("power-on", "Power On", power_on, "pulse rev landing on an open fifth"),
    ("water-drop", "Water Drop", water_drop, "one drip echoing in a cave"),
    ("chirp", "Chirp", chirp, "three little bird calls"),
    ("tick", "Tick", tick, "a single small tick, the quietest cue"),
    ("pip", "Pip", pip, "one soft sine pip"),
]


# MARK: - Mastering

def k_weight(x):
    """ITU-R BS.1770 pre-filter (high shelf + high pass) for loudness."""
    f0, gain_db, q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
    a = 10 ** (gain_db / 40)
    w0 = 2 * math.pi * f0 / SR
    alpha, c, s = math.sin(w0) / (2 * q), math.cos(w0), math.sqrt(a)
    shelf = biquad(
        x,
        a * ((a + 1) + (a - 1) * c + 2 * s * alpha),
        -2 * a * ((a - 1) + (a + 1) * c),
        a * ((a + 1) + (a - 1) * c - 2 * s * alpha),
        (a + 1) - (a - 1) * c + 2 * s * alpha,
        2 * ((a - 1) - (a + 1) * c),
        (a + 1) - (a - 1) * c - 2 * s * alpha,
    )
    return highpass(shelf, 38.13547087602444, 0.5003270373238773)


def max_loudness(x, window=0.1, hop=0.025):
    """Loudest 100 ms of K-weighted signal, in dB (−0.691 offset as in LUFS)."""
    y = k_weight(x)
    w, h = int(window * SR), int(hop * SR)
    best = 1e-12
    for i in range(0, max(1, len(y) - w + 1), h):
        segment = y[i:i + w]
        best = max(best, sum(v * v for v in segment) / len(segment))
    return -0.691 + 10 * math.log10(best)


def master(x):
    """DC-free, faded, loudness-matched, peak-capped."""
    x = highpass(x, 20.0)
    mean = sum(x) / len(x)
    x = [v - mean for v in x]
    fade_in, fade_out = int(FADE_IN_S * SR), int(FADE_OUT_S * SR)
    for i in range(fade_in):
        x[i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade_in)
    for i in range(fade_out):
        x[-1 - i] *= 0.5 - 0.5 * math.cos(math.pi * i / fade_out)
    gain = 10 ** ((TARGET_LOUDNESS - max_loudness(x)) / 20)
    peak = max(abs(v) for v in x) * gain
    ceiling = 10 ** (PEAK_CEILING_DB / 20)
    if peak > ceiling:
        gain *= ceiling / peak
    return [v * gain for v in x]


def write_wav(path, x, seed):
    rng = random.Random(seed)
    frames = bytearray()
    for v in x:
        dither = (rng.random() - rng.random()) / 32768.0   # TPDF, ±1 LSB
        sample = max(-32768, min(32767, int(round((v + dither) * 32767))))
        frames += struct.pack("<h", sample)
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SR)
        out.writeframes(bytes(frames))


def main():
    report = "--report" in sys.argv
    os.makedirs(OUT_DIR, exist_ok=True)
    for index, (slug, title, synth, character) in enumerate(PACK):
        x = master(synth())
        path = os.path.join(OUT_DIR, f"notchtune-{slug}.wav")
        write_wav(path, x, seed=1000 + index)
        if report:
            peak = 20 * math.log10(max(abs(v) for v in x))
            print(f"{title:13s} {len(x) / SR:5.2f}s  peak {peak:6.1f} dBFS  "
                  f"loudness {max_loudness(x):6.1f} dB  {character}")
    print(f"wrote {len(PACK)} sounds to {os.path.normpath(OUT_DIR)}")


if __name__ == "__main__":
    main()

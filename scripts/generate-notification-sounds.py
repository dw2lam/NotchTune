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

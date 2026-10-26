"""Sonidos de la sala del jefe, sintetizados (sin samples: son del proyecto, CC0).

    python3 -I tools/audio/make_boss_sfx.py

Escribe en assets/audio/ui/ (los reproduce SceneRouter.play_ui):
  extra_jefe_reja.wav     "gate"     las rejas que caen y traban
  extra_jefe_brasero.wav  "brazier"  un brasero que se enciende de golpe
  extra_jefe_entrada.wav  "boss"     el golpe grave cuando el jefe se levanta
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "ui"
RNG = np.random.default_rng(7)


def t_axis(sec):
    return np.arange(int(RATE * sec)) / RATE


def lowpass(x, cutoff):
    """Filtro de un polo; cutoff puede ser un arreglo (barrido)."""
    cutoff = np.broadcast_to(np.asarray(cutoff, float), x.shape)
    a = np.exp(-2 * np.pi * cutoff / RATE)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


def place(buf, snd, at):
    i = int(at * RATE)
    n = min(len(snd), len(buf) - i)
    buf[i:i + n] += snd[:n]


def clang(sec, base, decay, amp=1.0):
    """Golpe de hierro: parciales inarmónicos que se apagan a distinto ritmo."""
    t = t_axis(sec)
    out = np.zeros_like(t)
    for ratio, d, a in ((1.0, 1.0, 1.0), (2.71, 1.6, 0.7), (4.19, 2.3, 0.5), (6.4, 3.1, 0.35), (8.45, 4.0, 0.25)):
        out += a * np.sin(2 * np.pi * base * ratio * t + RNG.uniform(0, 6)) * np.exp(-t * decay * d)
    click = RNG.normal(0, 1, len(t)) * np.exp(-t * 90)
    return amp * (out + 0.6 * click)


def gate():
    buf = np.zeros(int(RATE * 1.4))
    t = t_axis(0.5)
    # el golpe contra el piso: grave que cae de tono y un soplo de polvo
    thud = np.sin(2 * np.pi * (70 * t - 40 * t * t)) * np.exp(-t * 9)
    dust = lowpass(RNG.normal(0, 1, len(t)), 500) * np.exp(-t * 12) * 2.5
    place(buf, 1.2 * thud + dust, 0.0)
    place(buf, clang(1.3, 310, 4.5), 0.0)
    # rebotes y traqueteo de los barrotes
    for at, amp, base in ((0.11, 0.45, 290), (0.19, 0.3, 335), (0.24, 0.22, 300), (0.31, 0.12, 320)):
        place(buf, clang(0.8, base, 7, amp), at)
    return buf


def brazier():
    sec = 1.1
    t = t_axis(sec)
    noise = RNG.normal(0, 1, len(t))
    # fwoosh: el filtro se abre rápido y se cierra despacio
    cut = 300 + 3200 * np.clip(t / 0.09, 0, 1) * np.exp(-np.clip(t - 0.09, 0, None) * 3.0)
    env = np.clip(t / 0.05, 0, 1) * np.exp(-np.clip(t - 0.05, 0, None) * 2.6)
    body = lowpass(noise, cut) * env * 3.0
    roar = lowpass(noise, 140) * env * 4.0
    out = body + roar
    # chasquidos de brasas
    for _ in range(14):
        at = RNG.uniform(0.12, sec - 0.05)
        i = int(at * RATE)
        n = int(0.004 * RATE)
        out[i:i + n] += RNG.normal(0, 1, n) * np.exp(-np.arange(n) / (0.0015 * RATE)) * RNG.uniform(0.2, 0.5)
    return out


def boss():
    sec = 3.2
    t = t_axis(sec)
    buf = np.zeros(len(t))
    # golpe grave
    boom = np.sin(2 * np.pi * (52 * t - 9 * t * t)) * np.exp(-t * 2.2)
    boom += lowpass(RNG.normal(0, 1, len(t)), 220) * np.exp(-t * 6) * 3.0
    buf += 1.3 * boom
    # coro disonante que crece y se va (quinta disminuida, voces desafinadas)
    swell = np.clip(t / 0.7, 0, 1) ** 2 * np.exp(-np.clip(t - 0.9, 0, None) * 1.3)
    pad = np.zeros(len(t))
    for f in (110.0, 130.8, 155.6, 220.0):
        for det in (-0.6, 0.0, 0.7):
            vib = 0.004 * np.sin(2 * np.pi * 5.1 * t + f)
            ph = 2 * np.pi * (f + det) * t * (1 + vib)
            pad += np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    buf += lowpass(pad, 900) * swell * 0.11
    # campana
    for ratio, a, d in ((1.0, 1.0, 1.6), (2.76, 0.5, 2.4), (5.4, 0.25, 3.5), (8.93, 0.12, 5.0)):
        buf += 0.35 * a * np.sin(2 * np.pi * 196 * ratio * t) * np.exp(-t * d)
    return buf


def write(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.89
    fade = int(0.02 * RATE)
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"{name}: {len(x) / RATE:.2f} s")


if __name__ == "__main__":
    write("extra_jefe_reja.wav", gate())
    write("extra_jefe_brasero.wav", brazier())
    write("extra_jefe_entrada.wav", boss())

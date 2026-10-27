"""Sonidos del combate, sintetizados (sin samples: son del proyecto, CC0).

    python3 -I tools/audio/make_combat_sfx.py

Escribe en assets/audio/ui/ (los reproduce SceneRouter.play_ui):
  combate_golpe.wav     "hit"    un golpe que entra: golpe sordo y chasquido de hueso
  combate_critico.wav   "crit"   crítico: chasquido seco, hierro que suena y un brillo
  combate_herida.wav    "hurt"   el héroe recibe un golpe: sordo, apagado y grave
  combate_muerte.wav    "kill"   el enemigo cae: huesos que se quiebran y el alma que se va
  combate_sinergia.wav  "proc"   salta una sinergia (afinidad, pacto): campanitas que suben
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "ui"
RNG = np.random.default_rng(11)


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


def bandpass(x, lo, hi):
    return lowpass(x, hi) - lowpass(x, lo)


def place(buf, snd, at):
    i = int(at * RATE)
    n = min(len(snd), len(buf) - i)
    buf[i:i + n] += snd[:n]


def thud(sec, f0, f1, decay):
    """Golpe sordo: un seno que cae de f0 a f1."""
    t = t_axis(sec)
    f = f1 + (f0 - f1) * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * decay)


def crack(sec, lo, hi, decay, amp=1.0):
    t = t_axis(sec)
    return amp * bandpass(RNG.normal(0, 1, len(t)), lo, hi) * np.exp(-t * decay)


def bell(sec, f, decay, amp=1.0):
    t = t_axis(sec)
    out = np.zeros_like(t)
    for ratio, a, d in ((1.0, 1.0, 1.0), (2.0, 0.4, 1.6), (3.01, 0.25, 2.2), (4.2, 0.12, 3.0)):
        out += a * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * decay * d)
    return amp * out * np.clip(t / 0.004, 0, 1)


def hit():
    buf = np.zeros(int(RATE * 0.3))
    place(buf, 1.2 * thud(0.25, 170, 55, 18), 0.0)
    place(buf, crack(0.08, 900, 3800, 60, 2.6), 0.0)
    place(buf, crack(0.04, 2500, 6000, 120, 1.2), 0.012)
    return buf


def crit():
    buf = np.zeros(int(RATE * 0.75))
    place(buf, 1.3 * thud(0.35, 200, 50, 12), 0.0)
    place(buf, crack(0.1, 1500, 7000, 45, 3.2), 0.0)
    # hierro que suena: parciales inarmónicos agudos
    t = t_axis(0.6)
    ring = np.zeros_like(t)
    for ratio, a, d in ((1.0, 1.0, 1.0), (2.71, 0.6, 1.5), (4.19, 0.4, 2.1), (6.4, 0.25, 2.8)):
        ring += a * np.sin(2 * np.pi * 1180 * ratio * t + RNG.uniform(0, 6)) * np.exp(-t * 7 * d)
    place(buf, 0.45 * ring, 0.01)
    # brillo: un chirrido corto que sube
    t = t_axis(0.25)
    chirp = np.sin(2 * np.pi * np.cumsum(2400 + 5200 * t / 0.25) / RATE) * np.exp(-t * 14)
    place(buf, 0.22 * chirp, 0.06)
    return buf


def hurt():
    buf = np.zeros(int(RATE * 0.45))
    place(buf, 1.4 * thud(0.4, 120, 42, 10), 0.0)
    place(buf, lowpass(RNG.normal(0, 1, int(RATE * 0.25)), 600) * np.exp(-t_axis(0.25) * 18) * 3.0, 0.0)
    # quejido: un tono apagado que baja
    t = t_axis(0.3)
    moan = np.sin(2 * np.pi * np.cumsum(260 - 120 * t / 0.3) / RATE) * np.exp(-t * 9)
    place(buf, 0.3 * lowpass(moan, 800), 0.03)
    return buf


def kill():
    buf = np.zeros(int(RATE * 1.1))
    place(buf, 1.4 * thud(0.7, 140, 38, 5), 0.0)
    # huesos que se quiebran: chasquidos de distinto tono en un cuarto de segundo
    for _ in range(11):
        at = RNG.uniform(0.0, 0.28)
        lo = RNG.uniform(700, 2200)
        place(buf, crack(0.05, lo, lo * 2.6, RNG.uniform(70, 140), RNG.uniform(1.2, 2.4)), at)
    # el alma que se va: soplido que se abre y se apaga
    t = t_axis(0.8)
    cut = 400 + 2600 * np.clip(t / 0.35, 0, 1)
    whoosh = lowpass(RNG.normal(0, 1, len(t)), cut) * np.sin(np.pi * np.clip(t / 0.8, 0, 1)) ** 2
    place(buf, 1.1 * whoosh, 0.18)
    return buf


def proc():
    buf = np.zeros(int(RATE * 0.8))
    for i, f in enumerate((1046.5, 1318.5, 1568.0)):
        place(buf, bell(0.6, f, 5.5, 0.6 - i * 0.1), i * 0.055)
    # destello: ruido muy agudo y corto
    place(buf, crack(0.12, 5000, 9000, 30, 0.5), 0.0)
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
    write("combate_golpe.wav", hit())
    write("combate_critico.wav", crit())
    write("combate_herida.wav", hurt())
    write("combate_muerte.wav", kill())
    write("combate_sinergia.wav", proc())

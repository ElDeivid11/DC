"""Sonidos de la tragaperras de los cofres, sintetizados (sin samples: son del
proyecto, CC0).

    python3 -I tools/audio/make_chest_sfx.py

Escribe en assets/audio/ui/ (los reproduce SceneRouter.play_ui):
  cofre_tic.wav      "slot_tick"  un símbolo que pasa por la línea (madera y hierro)
  cofre_rodillo.wav  "slot_stop"  un rodillo que se clava: golpe seco y traba
  cofre_casi.wav     "slot_near"  dos iguales y el tercero no: dos notas que caen
  cofre_premio.wav   "slot_win"   tres iguales: campanas que suben y lluvia de monedas
"""
import wave
from pathlib import Path

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "ui"
RNG = np.random.default_rng(23)


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


def bell(sec, f, decay, amp=1.0):
    t = t_axis(sec)
    out = np.zeros_like(t)
    for ratio, a, d in ((1.0, 1.0, 1.0), (2.0, 0.45, 1.5), (3.01, 0.25, 2.1), (4.2, 0.12, 2.8)):
        out += a * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t * decay * d)
    return amp * out * np.clip(t / 0.003, 0, 1)


def coin(sec=0.25, f=2600.0):
    """Moneda chica: dos parciales metálicos muy cortos."""
    t = t_axis(sec)
    return (np.sin(2 * np.pi * f * t) + 0.6 * np.sin(2 * np.pi * f * 1.48 * t)) * np.exp(-t * 22)


def tick():
    t = t_axis(0.05)
    click = bandpass(RNG.normal(0, 1, len(t)), 1800, 5200) * np.exp(-t * 160)
    knock = np.sin(2 * np.pi * 620 * t) * np.exp(-t * 90)
    return 1.6 * click + 0.7 * knock


def stop():
    buf = np.zeros(int(RATE * 0.35))
    t = t_axis(0.3)
    thud = np.sin(2 * np.pi * np.cumsum(180 - 100 * np.clip(t / 0.08, 0, 1)) / RATE) * np.exp(-t * 20)
    place(buf, 1.3 * thud, 0.0)
    place(buf, 2.2 * bandpass(RNG.normal(0, 1, int(RATE * 0.06)), 900, 3600) * np.exp(-t_axis(0.06) * 70), 0.0)
    # la traba de hierro que cae
    place(buf, 0.5 * bell(0.2, 1350, 18), 0.03)
    return buf


def near():
    buf = np.zeros(int(RATE * 0.7))
    for i, f in enumerate((660.0, 523.3)):
        place(buf, bell(0.45, f, 7, 0.7), i * 0.16)
    return lowpass(buf, 3000)


def win():
    buf = np.zeros(int(RATE * 1.8))
    # arpegio que sube y una campana larga arriba
    notes = (523.3, 659.3, 784.0, 1046.5, 1318.5)
    for i, f in enumerate(notes):
        place(buf, bell(0.7, f, 4.5, 0.55), i * 0.07)
    place(buf, bell(1.4, 1568.0, 2.2, 0.7), len(notes) * 0.07)
    # lluvia de monedas
    for _ in range(26):
        place(buf, 0.18 * coin(0.2, RNG.uniform(2200, 3400)), RNG.uniform(0.2, 1.3))
    return buf


def write(name, x):
    x = x / max(np.abs(x).max(), 1e-6) * 0.89
    fade = int(min(0.02, len(x) / RATE / 4) * RATE)
    x[-fade:] *= np.linspace(1, 0, fade)
    data = (x * 32767).astype("<i2").tobytes()
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"{name}: {len(x) / RATE:.2f} s")


if __name__ == "__main__":
    write("cofre_tic.wav", tick())
    write("cofre_rodillo.wav", stop())
    write("cofre_casi.wav", near())
    write("cofre_premio.wav", win())

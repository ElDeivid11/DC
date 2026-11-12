#!/usr/bin/env python3
"""Genera las texturas de pared / piso / techo de cada tema de piso con
estética PS1 oscura (Lunacid / King's Field) a partir de fotos tileables CC0.

Fuente: WRAD Textures, de wriks (CC0 1.0) — https://github.com/wwwriks/wrad-textures
Solo se usa la carpeta `seamless/` (fotos de 1024 px que repiten sin costura).
Cómo bajar solo los archivos necesarios: ver tools/assets/README.md.

Uso (desde la raíz del proyecto; -I porque las imágenes bajadas son datos no
confiables y así Python no carga módulos del directorio actual):

    python3 -I tools/assets/make_textures.py --src /ruta/a/wrad-textures \
        --out assets/textures [--preview hoja.png] [--temas luna,abismo] [--zoom 2]

Salida, por tema (tabla THEMES):
    assets/textures/<tema>/wall_a.png    pared principal
    assets/textures/<tema>/wall_b.png    pared variante (~15 % de las caras)
    assets/textures/<tema>/floor_a.png   piso principal
    assets/textures/<tema>/floor_b.png   piso variante
    assets/textures/<tema>/ceiling.png   techo
    assets/textures/LICENSE_WRAD.txt     copia de la licencia CC0 de la fuente

Cada textura es un PNG RGB de 8 bits de 128x128 que cubre 4 m x 4 m en el
juego (2x2 celdas) y repite sin costuras en ambos ejes.

Proceso de cada textura (cada filtro usa "wrap", así nada rompe el tileado):

 1. Carga: RGBA → RGB sobre negro. Rotación opcional de 90° (`rot`; rotar un
    cuadrado tileable sigue siendo tileable).
 2. Reducción BOX de la imagen ENTERA a 128 px (o a 128/`repetir` px y luego
    se repite NxN, para achicar la escala del material). Nunca se recorta:
    recortar rompe el tileado.
 3. Gradación: desaturar (`sat` = fracción de saturación que queda), contraste
    alrededor de la media (`contraste`), "aplanar" la iluminación de baja
    frecuencia de la foto (`aplanar`, para que no se note la repetición) y
    realzar el detalle fino (`nitidez`, unsharp mask). Ambos con desenfoque
    gaussiano por FFT, que es periódico por construcción.
 4. Luminancia normalizada por percentiles (2-98 %) y curva gamma. La gamma no
    es fija: se busca por bisección la que deja la luminancia MEDIA del
    resultado (luma Rec.601 sobre sRGB, 0..1) en el objetivo del slot (`lum`):
    paredes y piso ~0.23-0.32 (el Abismo, a propósito, ~0.21), techo
    ~0.11-0.16. Así ninguna textura queda negra (lo que pasaba con los pisos
    del prototipo) ni lavada, y el contraste local se conserva.
 5. Mapa de degradado: la luminancia se pasa por la rampa del tema (5 colores,
    oscuro → claro; `rango` < 1 usa solo la parte oscura, para techos sin
    aplastar el contraste con una gamma enorme). Se mezcla `mezcla` (70-80 %)
    de rampa con el color original de la foto llevado a la MISMA luminancia,
    para que el material conserve algo de identidad sin salirse de la paleta.
 6. Capas opcionales de ruido tileable (ruido blanco filtrado por FFT, por lo
    tanto periódico): musgo (crece en juntas y grietas), hollín, chorretes
    verticales de humedad, grietas (ruido "ridged"), vetas que brillan y
    manchas de color. Las variantes (wall_b / floor_b) usan estas capas para
    parecer el mismo material dañado o sucio.
 7. Cuantización a 16 colores por textura (median cut, como una CLUT de 4 bits
    de PlayStation) con trama ordenada Bayer 4x4 suave (`dither`; el juego
    además aplica un dither de 15 bits en post-proceso). El color de las vetas
    va reservado en la paleta (si no, el median cut se lo come).
 8. PNG RGB de 8 bits. Todo es determinista (semillas fijas, sin azar global).

`--preview` arma una hoja de contacto: cada textura repetida 2x2 (para ver
costuras), con su luminancia media, agrupadas por tema.
"""
import argparse
import os
import shutil
import sys
import unicodedata
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

SIZE = 128
SLOTS = ("wall_a", "wall_b", "floor_a", "floor_b", "ceiling")
LUMA = np.array([0.299, 0.587, 0.114])
# Umbrales Bayer 4x4 centrados en 0 (-0.47..0.47).
BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0 - 0.5

# Valores por defecto de cada slot (se pisan en THEMES).
DEFAULTS = {
    "rot": 0,           # 0 o 90 grados
    "repetir": 1,       # 1 = la foto entera cubre 4 m; 2 = cubre 2 m (se repite 2x2)
    "sat": 0.6,         # saturación que queda tras desaturar
    "contraste": 1.2,
    "aplanar": 0.5,     # 0..1: cuánto de la luz de baja frecuencia se quita
    "radio_aplanar": 16,  # sigma (px) de esa "baja frecuencia"; menor = iguala piezas vecinas
    "nitidez": 0.2,     # fuerza del unsharp mask
    "juntas": 0.0,      # 0..1: oscurece las líneas finas MÁS claras que su entorno (mortero)
    "radio_juntas": 1.5,  # sigma (px) del entorno con el que se comparan las juntas
    "rango": 1.0,       # parte de la rampa que se usa (techo: < 1, se queda en lo oscuro)
    "mezcla": None,     # None = la del tema
    "dither": 0.05,     # amplitud de la trama Bayer (0..1)
    "capas": [],
}

# --- Temas ------------------------------------------------------------------------
# `src` = nombre del archivo en wrad-textures/seamless/ sin ".png".
# `lum` = luminancia media objetivo del resultado.
# Capas: tipo + parámetros (ver aplicar_capa()). Los colores, en hex.
THEMES = {
    "catacumbas": {
        "nombre": "Catacumbas del Pozo",
        "rampa": ["#120e0b", "#3b2f25", "#6b5a45", "#a08a68", "#d9c39a"],
        "mezcla": 0.75,
        "slots": {
            # Sillares de arenisca ocre con algo de mugre.
            "wall_a": {"src": "bricks5", "lum": 0.31, "contraste": 1.0,
                       "capas": [{"tipo": "hollin", "cantidad": 0.3, "escala": 14, "umbral": 0.4, "semilla": 10}]},
            # Los mismos sillares, ahumados por las velas y agrietados.
            "wall_b": {"src": "bricks5", "lum": 0.28, "contraste": 1.0,
                       "capas": [{"tipo": "hollin", "cantidad": 0.6, "escala": 12, "umbral": 0.0, "semilla": 11},
                                 {"tipo": "grietas", "cantidad": 0.8, "escala": 9, "ancho": 0.1, "semilla": 12}]},
            # Losas gastadas (radio_aplanar chico: iguala el brillo de losas vecinas).
            "floor_a": {"src": "bricks4", "lum": 0.27, "contraste": 1.0, "aplanar": 0.8, "radio_aplanar": 6, "juntas": 1.0, "radio_juntas": 3.5},
            "floor_b": {"src": "bricks4", "lum": 0.25, "contraste": 1.0, "aplanar": 0.8, "radio_aplanar": 6, "juntas": 1.0, "radio_juntas": 3.5,
                        "capas": [{"tipo": "manchas", "color": "#5a4630", "cantidad": 0.8, "escala": 10, "umbral": 0.2, "semilla": 13},
                                  {"tipo": "grietas", "cantidad": 0.9, "escala": 8, "ancho": 0.14, "semilla": 14}]},
            "ceiling": {"src": "stone2", "lum": 0.16, "rango": 0.55},
        },
    },
    "cisterna": {
        "nombre": "Cisterna Anegada",
        "rampa": ["#0b1512", "#1f3a33", "#3f6b58", "#7fa37a", "#c9d68f"],
        "mezcla": 0.75,
        "slots": {
            "wall_a": {"src": "bricks3", "lum": 0.29, "juntas": 1.0, "radio_juntas": 3.0},
            # Ladrillo con manchones de musgo (más en las juntas) y chorretes de humedad.
            "wall_b": {"src": "bricks3", "lum": 0.27, "juntas": 1.0, "radio_juntas": 3.0,
                       "capas": [{"tipo": "musgo", "color": "#5a7a2a", "cantidad": 0.75, "escala": 12, "umbral": 0.55, "juntas": 0.3, "semilla": 21},
                                 {"tipo": "chorretes", "cantidad": 0.7, "escala": 1.5, "umbral": 0.8, "largo": 0.7, "semilla": 22}]},
            # Losa húmeda con charcos oscuros.
            "floor_a": {"src": "concrete3", "lum": 0.26, "juntas": 1.0, "radio_juntas": 3.0,
                        "capas": [{"tipo": "hollin", "cantidad": 0.4, "escala": 12, "umbral": 0.3, "semilla": 23}]},
            "floor_b": {"src": "concrete3", "lum": 0.25, "juntas": 1.0, "radio_juntas": 3.0,
                        "capas": [{"tipo": "musgo", "color": "#55722a", "cantidad": 0.75, "escala": 9, "umbral": 0.5, "juntas": 0.6, "semilla": 24},
                                  {"tipo": "grietas", "cantidad": 0.8, "escala": 8, "ancho": 0.12, "semilla": 25}]},
            "ceiling": {"src": "bricks2", "lum": 0.15, "rango": 0.55, "juntas": 1.0, "radio_juntas": 3.0},
        },
    },
    "luna": {
        "nombre": "Salones de la Luna",
        "rampa": ["#070a16", "#1b2440", "#3a4d7a", "#7f95c4", "#d6e0ff"],
        "mezcla": 0.8,
        "slots": {
            # Sillería de caliza gris azulada.
            "wall_a": {"src": "bricks2", "lum": 0.32, "nitidez": 0.0, "contraste": 1.0},
            # La misma, ennegrecida, agrietada y con algo de escarcha plateada.
            "wall_b": {"src": "bricks2", "lum": 0.31, "nitidez": 0.0, "contraste": 1.0,
                       "capas": [{"tipo": "hollin", "cantidad": 0.45, "escala": 10, "umbral": 0.3, "semilla": 29},
                                 {"tipo": "manchas", "color": "#b8c6ee", "cantidad": 0.3, "escala": 12, "umbral": 0.6, "semilla": 30},
                                 {"tipo": "grietas", "cantidad": 1.0, "escala": 8, "ancho": 0.16, "semilla": 31}]},
            # Baldosas ornamentales desaturadas = mármol labrado (una pieza por celda).
            "floor_a": {"src": "tiles1", "lum": 0.29, "sat": 0.2, "contraste": 0.9},
            "floor_b": {"src": "tiles1", "lum": 0.27, "sat": 0.2, "contraste": 0.9,
                        "capas": [{"tipo": "hollin", "cantidad": 0.5, "escala": 12, "umbral": 0.3, "semilla": 33},
                                  {"tipo": "grietas", "cantidad": 1.0, "escala": 7, "ancho": 0.18, "semilla": 32}]},
            "ceiling": {"src": "stone2", "lum": 0.13, "rango": 0.5},
        },
    },
    "castillo": {
        "nombre": "Castillo Carmesí",
        "rampa": ["#120406", "#3a0b10", "#6e1a1f", "#a8433a", "#e0a46a"],
        "mezcla": 0.75,
        "slots": {
            # Ladrillo granate con juntas de oro viejo.
            "wall_a": {"src": "bricks1", "lum": 0.25, "sat": 0.35, "contraste": 1.0, "rango": 0.9, "juntas": 1.0, "radio_juntas": 3.0,
                       "capas": [{"tipo": "hollin", "cantidad": 0.2, "escala": 14, "umbral": 0.5, "semilla": 40}]},
            "wall_b": {"src": "bricks1", "lum": 0.23, "sat": 0.35, "contraste": 1.0, "rango": 0.9, "juntas": 1.0, "radio_juntas": 3.0,
                       "capas": [{"tipo": "hollin", "cantidad": 0.35, "escala": 10, "umbral": 0.5, "semilla": 41},
                                 {"tipo": "grietas", "cantidad": 0.85, "escala": 9, "ancho": 0.12, "semilla": 43},
                                 {"tipo": "chorretes", "color": "#2a0508", "cantidad": 0.75, "escala": 1.2, "umbral": 1.0, "largo": 0.5, "semilla": 42}]},
            # Tablones viejos (rotados: quedan horizontales).
            "floor_a": {"src": "planks4", "lum": 0.24, "rot": 90, "aplanar": 0.8, "radio_aplanar": 4},
            "floor_b": {"src": "planks5", "lum": 0.24, "rot": 90, "aplanar": 0.8, "radio_aplanar": 4},
            # Vigas de madera casi negra.
            "ceiling": {"src": "planks2", "lum": 0.13, "rango": 0.5, "sat": 0.3},
        },
    },
    "abismo": {
        "nombre": "El Abismo",
        "rampa": ["#05030a", "#1a1030", "#3a2560", "#6b4fa0", "#c9b8ff"],
        "mezcla": 0.8,
        "slots": {
            # Roca negra vidriosa: mucho negro y brillos duros (contraste alto).
            "wall_a": {"src": "stone4", "lum": 0.21, "nitidez": 0.0, "contraste": 1.8, "rango": 0.9},
            "wall_b": {"src": "stone4", "lum": 0.21, "nitidez": 0.0, "contraste": 1.8, "rango": 0.9,
                       "capas": [{"tipo": "vetas", "color": "#5fe0e8", "cantidad": 0.9, "escala": 10, "ancho": 0.15, "semilla": 51}]},
            # Ceniza y esquirlas negras.
            "floor_a": {"src": "ash", "lum": 0.21, "nitidez": 0.0, "contraste": 1.3, "rango": 0.9},
            "floor_b": {"src": "ash", "lum": 0.21, "nitidez": 0.0, "contraste": 1.3, "rango": 0.9,
                        "capas": [{"tipo": "vetas", "color": "#5fe0e8", "cantidad": 0.8, "escala": 12, "ancho": 0.12, "semilla": 52}]},
            "ceiling": {"src": "stone2", "lum": 0.11, "rango": 0.45, "nitidez": 0.0},
        },
    },
}


# --- Utilidades -------------------------------------------------------------------

def hex_rgb(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float64) / 255.0


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb @ LUMA


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def desenfocar(a: np.ndarray, sx: float, sy: float | None = None) -> np.ndarray:
    """Desenfoque gaussiano por FFT: periódico, así que respeta el tileado.
    sx / sy = sigma en píxeles (horizontal / vertical)."""
    sy = sx if sy is None else sy
    fy = np.fft.fftfreq(a.shape[0])[:, None]
    fx = np.fft.fftfreq(a.shape[1])[None, :]
    g = np.exp(-2.0 * np.pi ** 2 * ((sx * fx) ** 2 + (sy * fy) ** 2))
    if a.ndim == 3:
        return np.stack([desenfocar(a[..., c], sx, sy) for c in range(a.shape[2])], axis=-1)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


@lru_cache(maxsize=None)
def ruido(semilla: int, escala: float, octavas: int = 3) -> np.ndarray:
    """Ruido fractal tileable (media 0, desvío 1). `escala` = sigma en px de la
    octava más gruesa; cada octava siguiente es la mitad de grande y pesa la mitad."""
    rng = np.random.default_rng(semilla)
    total = np.zeros((SIZE, SIZE))
    amp = 1.0
    for o in range(octavas):
        s = max(escala / (2 ** o), 0.5)
        n = desenfocar(rng.standard_normal((SIZE, SIZE)), s)
        total += amp * n / (n.std() + 1e-9)
        amp *= 0.5
    total = (total - total.mean()) / (total.std() + 1e-9)
    total.flags.writeable = False  # va en caché: que nadie lo modifique
    return total


def ridged(semilla: int, escala: float, ancho: float, octavas: int = 2) -> np.ndarray:
    """Líneas finas: donde el ruido cruza por cero. Con más octavas el trazo es
    más quebrado (grietas); con 2, más suave (vetas). Se cortan con otro ruido
    para que no cubran toda la textura."""
    n = ruido(semilla, escala, octavas)
    linea = 1.0 - smoothstep(0.0, ancho, np.abs(n))
    corte = smoothstep(-0.1, 0.7, ruido(semilla + 1000, escala * 2.0, 2))
    return linea * corte


def ruido_1d(semilla: int, sigma: float) -> np.ndarray:
    """Ruido 1D periódico de largo SIZE (media 0, desvío 1)."""
    rng = np.random.default_rng(semilla)
    f = np.fft.fftfreq(SIZE)
    n = np.real(np.fft.ifft(np.fft.fft(rng.standard_normal(SIZE)) * np.exp(-2.0 * np.pi ** 2 * (sigma * f) ** 2)))
    return (n - n.mean()) / (n.std() + 1e-9)


def chorretes(semilla: int, ancho: float, umbral: float, largo: float) -> np.ndarray:
    """Chorretes de humedad: columnas finas (ruido 1D en x por encima de
    `umbral`) que arrancan a una altura al azar y se desvanecen hacia abajo a lo
    largo de `largo` (fracción de la altura). La altura de arranque es periódica
    (frac), así que también tilea en vertical."""
    col = smoothstep(umbral - 0.25, umbral + 0.25, ruido_1d(semilla, ancho))[None, :]
    fase = (ruido_1d(semilla + 1, 6.0) * 0.5)[None, :]  # arranque suave entre columnas vecinas
    y = (np.arange(SIZE) / SIZE)[:, None]
    dist = np.mod(y - fase, 1.0)  # 0 = arranque, crece hacia abajo
    caida = np.clip(1.0 - dist / largo, 0.0, 1.0) ** 1.5
    return col * caida


# --- Capas --------------------------------------------------------------------------

def aplicar_capa(rgb: np.ndarray, lum_n: np.ndarray, capa: dict, rampa: np.ndarray) -> np.ndarray:
    """rgb: imagen ya mapeada a la rampa. lum_n: luminancia normalizada (0..1),
    útil para que el musgo crezca en las juntas oscuras."""
    tipo = capa["tipo"]
    cant = capa.get("cantidad", 0.5)
    sem = capa.get("semilla", 1)
    esc = capa.get("escala", 8.0)
    umbral = capa.get("umbral", 0.3)
    oscuro = hex_rgb(capa["color"]) if "color" in capa else rampa[0]
    if tipo == "musgo":
        # Más probable en las zonas oscuras (juntas, grietas) que en las caras.
        n = ruido(sem, esc) + capa.get("juntas", 1.0) * (0.5 - lum_n) * 2.0
        m = smoothstep(umbral - 0.35, umbral + 0.35, n)[..., None] * cant
        musgo = hex_rgb(capa["color"]) * (0.45 + 1.1 * lum_n[..., None])
        return rgb * (1 - m) + musgo * m
    if tipo == "hollin":
        m = smoothstep(umbral - 0.6, umbral + 0.6, ruido(sem, esc))[..., None] * cant
        return rgb * (1 - m) + oscuro * m
    if tipo == "chorretes":
        m = chorretes(sem, esc, umbral, capa.get("largo", 0.5))[..., None] * cant
        return rgb * (1 - m) + oscuro * m
    if tipo == "grietas":
        m = ridged(sem, esc, capa.get("ancho", 0.1), 4)
        # Borde de luz de 1 px debajo de la grieta (a mano, estilo PS1).
        luz = np.clip(np.roll(m, 1, axis=0) - m, 0.0, 1.0)[..., None] * cant * 0.35
        m = m[..., None] * cant
        rgb = rgb * (1 - m) + oscuro * m
        return rgb * (1 - luz) + rampa[-2] * luz
    if tipo == "vetas":
        # Línea brillante + halo tenue (desenfoque periódico) alrededor.
        linea = ridged(sem, esc, capa.get("ancho", 0.08))
        halo = np.clip(desenfocar(linea, 1.5) * 1.5, 0.0, 1.0) * 0.45
        m = np.maximum(linea, halo)[..., None] * cant
        return rgb * (1 - m) + hex_rgb(capa["color"]) * m
    if tipo == "manchas":
        m = smoothstep(umbral - 0.3, umbral + 0.3, ruido(sem, esc))[..., None] * cant
        mancha = hex_rgb(capa["color"]) * (0.5 + lum_n[..., None])
        return rgb * (1 - m) + mancha * m
    raise ValueError(f"capa desconocida: {tipo}")


# --- Pipeline -----------------------------------------------------------------------

def cargar(src_dir: str, nombre: str, rot: int, repetir: int) -> np.ndarray:
    ruta = os.path.join(src_dir, "seamless", nombre + ".png")
    im = Image.open(ruta).convert("RGBA")
    fondo = Image.new("RGBA", im.size, (0, 0, 0, 255))
    fondo.alpha_composite(im)
    im = fondo.convert("RGB")
    if rot == 90:
        im = im.transpose(Image.Transpose.ROTATE_90)
    lado = SIZE // repetir
    # BOX promedia la imagen entera: la reducción sigue siendo tileable.
    im = im.resize((lado, lado), Image.Resampling.BOX)
    a = np.asarray(im, dtype=np.float64) / 255.0
    return np.tile(a, (repetir, repetir, 1))


def graduar(rgb: np.ndarray, p: dict) -> np.ndarray:
    y = luma(rgb)[..., None]
    rgb = y + (rgb - y) * p["sat"]
    media = luma(rgb).mean()
    rgb = (rgb - media) * p["contraste"] + media
    # Aplanar: restar parte de la luz de baja frecuencia (manchas grandes de la foto).
    y = luma(rgb)
    baja = desenfocar(y, p["radio_aplanar"])
    rgb = rgb - (p["aplanar"] * (baja - baja.mean()))[..., None]
    # Juntas: en las fotos el mortero es más claro que la piedra y, reducido a
    # 128 px, se ve como una grilla clara. Las líneas finas más claras que su
    # entorno se invierten (quedan más oscuras que la piedra, como una junta
    # en sombra).
    if p["juntas"] > 0:
        y = luma(rgb)
        claro = np.maximum(y - desenfocar(y, p["radio_juntas"]), 0.0)
        rgb = rgb - (p["juntas"] * 2.0 * claro)[..., None]
    # Nitidez: unsharp mask sobre la luminancia.
    y = luma(rgb)
    rgb = rgb + (p["nitidez"] * (y - desenfocar(y, 1.0)))[..., None]
    return rgb


def mapa_rampa(t: np.ndarray, rampa: np.ndarray) -> np.ndarray:
    pos = np.linspace(0.0, 1.0, len(rampa))
    return np.stack([np.interp(t, pos, rampa[:, c]) for c in range(3)], axis=-1)


def render(graded: np.ndarray, lum_n0: np.ndarray, gamma: float, p: dict, rampa: np.ndarray, mezcla: float) -> np.ndarray:
    t = lum_n0 ** gamma
    col = mapa_rampa(t * p["rango"], rampa)
    # Color original llevado a la luminancia de la rampa (conserva tono/saturación).
    y_orig = np.maximum(luma(graded), 1e-3)[..., None]
    orig = np.clip(graded, 1e-3, None) * (luma(col)[..., None] / y_orig)
    rgb = col * mezcla + orig * (1.0 - mezcla)
    for capa in p["capas"]:
        rgb = aplicar_capa(rgb, t, capa, rampa)
    return np.clip(rgb, 0.0, 1.0)


def exponer(graded: np.ndarray, p: dict, rampa: np.ndarray, mezcla: float, objetivo: float) -> tuple[np.ndarray, float]:
    """Bisección sobre log(gamma) hasta que la luminancia media = objetivo."""
    y = luma(graded)
    lo, hi = np.percentile(y, 2), np.percentile(y, 98)
    lum_n0 = np.clip((y - lo) / max(hi - lo, 1e-6), 0.0, 1.0)
    a, b = np.log(0.2), np.log(5.0)
    for _ in range(40):
        g = np.exp((a + b) / 2.0)
        m = luma(render(graded, lum_n0, g, p, rampa, mezcla)).mean()
        if m > objetivo:
            a = np.log(g)
        else:
            b = np.log(g)
    g = float(np.exp((a + b) / 2.0))
    rgb = render(graded, lum_n0, g, p, rampa, mezcla)
    if abs(luma(rgb).mean() - objetivo) > 0.02:
        print(f"  aviso: luminancia {luma(rgb).mean():.3f} lejos del objetivo {objetivo} (gamma {g:.2f})", file=sys.stderr)
    return rgb, g


def cuantizar(rgb: np.ndarray, ncol: int, amplitud: float, reservados: list) -> np.ndarray:
    """Paleta de `ncol` colores (median cut) + trama ordenada Bayer 4x4.
    `reservados`: colores que se agregan a mano a la paleta (le quitan lugar al
    median cut). Sirve para acentos de pocos píxeles, como las vetas, que el
    median cut si no se "come" y los vuelve del color de la rampa."""
    img = Image.fromarray(np.round(rgb * 255.0).astype(np.uint8), "RGB")
    pal_img = img.quantize(colors=ncol - len(reservados), method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    n = int(np.asarray(pal_img).max()) + 1
    pal = np.array(pal_img.getpalette()[: max(n, 1) * 3], dtype=np.float64).reshape(-1, 3) / 255.0
    if reservados:
        pal = np.concatenate([pal, np.array(reservados)], axis=0)
    yy, xx = np.mgrid[0:SIZE, 0:SIZE]
    src = rgb + BAYER4[yy % 4, xx % 4][..., None] * amplitud
    # Distancia ponderada por luma: prioriza acertar el brillo.
    d = (((src[:, :, None, :] - pal[None, None, :, :]) ** 2) * (LUMA * 3.0)).sum(-1)
    return pal[d.argmin(-1)]


def hacer_textura(src_dir: str, tema: dict, slot: dict) -> tuple[np.ndarray, float]:
    p = dict(DEFAULTS)
    p.update(slot)
    rampa = np.array([hex_rgb(c) for c in tema["rampa"]])
    mezcla = p["mezcla"] if p["mezcla"] is not None else tema["mezcla"]
    base = cargar(src_dir, p["src"], p["rot"], p["repetir"])
    graded = graduar(base, p)
    rgb, gamma = exponer(graded, p, rampa, mezcla, p["lum"])
    # Las vetas son pocos píxeles: su color (y el del halo) va reservado en la paleta.
    reservados = []
    for capa in p["capas"]:
        if capa["tipo"] == "vetas":
            c = hex_rgb(capa["color"])
            reservados += [c, c * 0.45 + rampa[1] * 0.55]
    q = cuantizar(rgb, 16, p["dither"], reservados)
    return q, gamma


def guardar(rgb: np.ndarray, ruta: str) -> None:
    Image.fromarray(np.round(rgb * 255.0).astype(np.uint8), "RGB").save(ruta)


# --- Hoja de contacto ----------------------------------------------------------------

def hoja_contacto(resultados: dict, ruta: str, zoom: int) -> None:
    celda = SIZE * 2 * zoom
    margen, cab, pie = 8, 18, 14
    filas = len(resultados)
    ancho = margen + len(SLOTS) * (celda + margen)
    alto = filas * (cab + celda + pie + margen) + margen
    hoja = Image.new("RGB", (ancho, alto), (24, 24, 24))
    d = ImageDraw.Draw(hoja)
    y = margen
    for tema_id, texs in resultados.items():
        # La fuente por defecto de Pillow no trae tildes: se quitan en el rótulo.
        nombre = unicodedata.normalize("NFKD", THEMES[tema_id]["nombre"]).encode("ascii", "ignore").decode()
        d.text((margen, y + 3), f"{tema_id} - {nombre}", fill=(235, 220, 160))
        y += cab
        for i, slot in enumerate(SLOTS):
            rgb = texs[slot]
            tile = np.tile(np.round(rgb * 255.0).astype(np.uint8), (2, 2, 1))
            im = Image.fromarray(tile, "RGB").resize((celda, celda), Image.Resampling.NEAREST)
            x = margen + i * (celda + margen)
            hoja.paste(im, (x, y))
            d.text((x, y + celda + 2), f"{slot}  {THEMES[tema_id]['slots'][slot]['src']}  lum {luma(rgb).mean():.2f}", fill=(200, 200, 200))
        y += celda + pie + margen
    hoja.save(ruta)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--src", required=True, help="raíz de wrad-textures (contiene seamless/)")
    ap.add_argument("--out", default="assets/textures")
    ap.add_argument("--preview", help="PNG de hoja de contacto (opcional)")
    ap.add_argument("--temas", help="lista separada por comas (por defecto, todos)")
    ap.add_argument("--zoom", type=int, default=1, help="aumento de la hoja de contacto")
    args = ap.parse_args()

    temas = args.temas.split(",") if args.temas else list(THEMES)
    resultados: dict = {}
    for tema_id in temas:
        tema = THEMES[tema_id]
        carpeta = os.path.join(args.out, tema_id)
        os.makedirs(carpeta, exist_ok=True)
        resultados[tema_id] = {}
        for slot in SLOTS:
            q, gamma = hacer_textura(args.src, tema, tema["slots"][slot])
            guardar(q, os.path.join(carpeta, slot + ".png"))
            resultados[tema_id][slot] = q
            print(f"{tema_id}/{slot}.png  src={tema['slots'][slot]['src']}  gamma={gamma:.2f}  lum={luma(q).mean():.3f}")
    lic = os.path.join(args.src, "LICENSE")
    if os.path.isfile(lic):
        shutil.copyfile(lic, os.path.join(args.out, "LICENSE_WRAD.txt"))
    else:
        print("aviso: no se encontró LICENSE en --src; no se copió LICENSE_WRAD.txt", file=sys.stderr)
    if args.preview:
        hoja_contacto(resultados, args.preview, args.zoom)
        print("hoja de contacto:", args.preview)


if __name__ == "__main__":
    main()

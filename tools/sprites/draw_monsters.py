"""Sprites de enemigos de prueba en estilo Dragon Quest HD-2D, dibujados por código.

Arma cada monstruo con formas simples (esferas, elipsoides, huesos con punta
redonda y placas planas) sobre un esqueleto articulado en 2,5D, lo posa
cuadro por cuadro y lo pasa a pixel art con paletas hechas a mano:

    python3 -I tools/sprites/draw_monsters.py [--only=esqueleto_picaro] [--preview=/tmp/hoja.png]

Escribe, por especie, en assets/sprites/enemies/: <especie>.png (hoja),
<especie>_glow.png (lo que brilla) y <especie>.json (formato en
tools/sprites/README.md). Determinista y sin dependencias raras (numpy + Pillow).

Estilo (ver la guía en tools/sprites/README.md):
- Diseño caricaturesco a lo Toriyama: calavera grande con cuencas redondas y
  ojos que brillan, huesos gruesos con nudos, manos y pies grandes.
- Sombreado en bandas (cel) con luz de arriba a la izquierda: cada material
  tiene una rampa de 5 tonos (sombra profunda, sombra, base, luz, brillo).
- Contorno exterior de 1 px del color oscuro de cada material (no negro) y
  líneas interiores donde una parte pasa por delante de otra.
- Píxeles limpios: cada píxel final es el tono más frecuente de sus 4x4
  muestras (sin mezclas ni antialias).
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "sprites" / "enemies"
FW, FH = 144, 144
PIVOT = (72, 140)
PPM = 64
SS = 4
COLUMNS = 16
COVERAGE = 0.45
# Luz de arriba a la izquierda y de frente (espacio de la cámara: x derecha,
# y arriba, z hacia la cámara).
LIGHT = np.array([-0.55, 0.62, 0.56]) / np.linalg.norm([-0.55, 0.62, 0.56])
TONE_CUTS = (0.12, 0.38, 0.68, 0.93)
INNER_LINE_DEPTH = 2.5


def hexc(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


# --- Materiales: rampa de 5 tonos + contorno ----------------------------------------
# Paletas a mano, saturadas y limpias (sombras hacia violeta, luces hacia crema).
MATERIALS = {
    "hueso": (["#4b3550", "#8a6f86", "#d6c2a4", "#f2e6c8", "#fffbef"], "#2a1830", True),
    "hueso_viejo": (["#4a3424", "#86683f", "#c8a868", "#eed79c", "#fff4cf"], "#2b1a12", True),
    "cuenca": (["#160c1c", "#1d1026", "#24142e", "#2b1a36", "#33203e"], "#0c0610", False),
    "grieta": (["#3a2840", "#52405a", "#6a5672", "#7c6884", "#8a7692"], "#1e1224", False),
    "ojo": (["#ffffff"] * 5, "#0c0610", False),
    "oxido": (["#381a1c", "#6c3224", "#a95a34", "#da9452", "#ffdca0"], "#200c10", True),
    "acero": (["#22253a", "#4a5170", "#8791b4", "#c8d2ea", "#ffffff"], "#12131f", True),
    "madera": (["#2a170e", "#53321c", "#86552f", "#b6804a", "#d8a670"], "#170c07", False),
    "tela_verde": (["#0f2219", "#1e4531", "#347548", "#5aa85f", "#8fd17a"], "#08130d", False),
    "tela_morada": (["#170a26", "#311754", "#542a86", "#8350bf", "#b588e4"], "#0c0516", False),
    "oro": (["#48290a", "#875210", "#cc8f22", "#f4cc52", "#fff1a6"], "#251404", True),
    "bronce": (["#36210f", "#6b421e", "#a66e38", "#d6a158", "#f9e09e"], "#1c1007", True),
    "cuero": (["#26150c", "#4b2a16", "#764324", "#a26638", "#c58a56"], "#140a05", False),
    "orbe": (["#ffffff"] * 5, "#0c0610", False),
    # Estela del golpe (el «barrido» de los ataques), casi blanca.
    "destello": (["#e9ddff", "#f3ecff", "#fff7de", "#ffffff", "#ffffff"], "#7a5aa8", False),
}
MAT_NAMES = list(MATERIALS)
MAT_ID = {n: i for i, n in enumerate(MAT_NAMES)}
GLOW_MATS = {MAT_ID["ojo"], MAT_ID["orbe"]}
PALETTE = np.array([[hexc(c) for c in MATERIALS[n][0]] for n in MAT_NAMES], dtype=np.uint8)
OUTLINE = np.array([hexc(MATERIALS[n][1]) for n in MAT_NAMES], dtype=np.uint8)
GLOSS = np.array([MATERIALS[n][2] for n in MAT_NAMES])


# --- Álgebra ------------------------------------------------------------------------

def v3(x, y, z):
    return np.array([x, y, z], dtype=np.float64)


def rot_x(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def axis_rot(axis, deg):
    """Rotación de Rodrigues alrededor de un eje."""
    k = axis / (np.linalg.norm(axis) + 1e-9)
    a = math.radians(deg)
    kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + math.sin(a) * kx + (1 - math.cos(a)) * (kx @ kx)


def limb_dir(pitch, roll, side):
    """Dirección de un miembro que cuelga: primero se abre hacia afuera (roll;
    side = +1 izquierda del personaje, -1 derecha) y después se levanta hacia
    adelante (pitch, +z). Así «brazos arriba y abiertos» (pitch 130, roll 60)
    quedan arriba y a los costados, sin cruzarse."""
    p = math.radians(pitch)
    r = math.radians(roll) * side
    x, y = math.sin(r), -math.cos(r)
    return v3(x, y * math.cos(p), -y * math.sin(p))


# --- Primitivas ---------------------------------------------------------------------
# Todas en el espacio del personaje (px, y arriba, z hacia adelante); cada una
# lleva material y grupo (las líneas interiores van entre grupos distintos).

def sphere(c, r, mat, group):
    return {"t": "ell", "c": np.asarray(c, float), "rad": v3(r, r, r), "R": np.eye(3), "m": mat, "g": group}


def ell(c, rad, mat, group, R=None):
    return {"t": "ell", "c": np.asarray(c, float), "rad": np.asarray(rad, float), "R": np.eye(3) if R is None else R, "m": mat, "g": group}


def bone(a, b, ra, rb, mat, group):
    return {"t": "cap", "a": np.asarray(a, float), "b": np.asarray(b, float), "ra": ra, "rb": rb, "m": mat, "g": group}


def slab(o, u, v, pts, mat, group):
    return {"t": "slab", "o": np.asarray(o, float), "u": np.asarray(u, float), "v": np.asarray(v, float), "pts": pts, "m": mat, "g": group}


def transform(prims, M, offset, scale=1.0):
    """Gira (vista) y escala alrededor de los pies: p' = scale * (M p) + offset."""
    out = []
    for p in prims:
        q = dict(p)
        if p["t"] == "ell":
            q["c"] = scale * (M @ p["c"]) + offset
            q["rad"] = p["rad"] * scale
            q["R"] = M @ p["R"]
        elif p["t"] == "cap":
            q["a"] = scale * (M @ p["a"]) + offset
            q["b"] = scale * (M @ p["b"]) + offset
            q["ra"] = p["ra"] * scale
            q["rb"] = p["rb"] * scale
        else:
            q["o"] = scale * (M @ p["o"]) + offset
            q["u"] = M @ p["u"] * scale
            q["v"] = M @ p["v"] * scale
        out.append(q)
    return out


def bottom_of(p):
    if p["t"] == "ell":
        # Extremo inferior aproximado del elipsoide girado.
        ext = np.abs(p["R"]) @ p["rad"]
        return p["c"][1] - ext[1]
    if p["t"] == "cap":
        return min(p["a"][1] - p["ra"], p["b"][1] - p["rb"])
    pts = [p["o"] + p["u"] * a + p["v"] * b for a, b in p["pts"]]
    return min(q[1] for q in pts)


# --- Render -------------------------------------------------------------------------

class Canvas:
    def __init__(self, frame=(FW, FH), pivot=PIVOT):
        self.fw, self.fh = frame
        self.pivot = pivot
        h, w = self.fh * SS, self.fw * SS
        self.z = np.full((h, w), -1e9)
        self.mat = np.full((h, w), -1, dtype=np.int32)
        self.grp = np.full((h, w), -1, dtype=np.int32)
        self.n = np.zeros((h, w, 3))
        # Centro de cada muestra en px del personaje (y arriba).
        self.xs = (np.arange(w) + 0.5) / SS - pivot[0]
        self.ys = pivot[1] - (np.arange(h) + 0.5) / SS

    def _window(self, x0, x1, y0, y1):
        h, w = self.z.shape
        c0 = max(0, int(math.floor((x0 + self.pivot[0]) * SS)))
        c1 = min(w, int(math.ceil((x1 + self.pivot[0]) * SS)) + 1)
        r0 = max(0, int(math.floor((self.pivot[1] - y1) * SS)))
        r1 = min(h, int(math.ceil((self.pivot[1] - y0) * SS)) + 1)
        if c0 >= c1 or r0 >= r1:
            return None
        X, Y = np.meshgrid(self.xs[c0:c1], self.ys[r0:r1])
        return (slice(r0, r1), slice(c0, c1)), X, Y

    def _write(self, sl, inside, z, n, mat, grp):
        upd = inside & (z > self.z[sl])
        self.z[sl][upd] = z[upd]
        self.n[sl][upd] = n[upd]
        self.mat[sl][upd] = mat
        self.grp[sl][upd] = grp

    def draw(self, p, grp_id):
        m = MAT_ID[p["m"]]
        if p["t"] == "ell":
            self._ell(p, m, grp_id)
        elif p["t"] == "cap":
            self._cap(p, m, grp_id)
        else:
            self._slab(p, m, grp_id)

    def _ell(self, p, m, g):
        c, rad, R = p["c"], p["rad"], p["R"]
        ext = np.abs(R) @ rad
        win = self._window(c[0] - ext[0], c[0] + ext[0], c[1] - ext[1], c[1] + ext[1])
        if win is None:
            return
        sl, X, Y = win
        M = np.diag(1.0 / rad) @ R.T
        d = M[:, 2]
        w = M[:, 0][None, None, :] * (X - c[0])[..., None] + M[:, 1][None, None, :] * (Y - c[1])[..., None]
        dd = d @ d
        wd = w @ d
        ww = (w * w).sum(-1)
        disc = wd * wd - dd * (ww - 1.0)
        inside = disc >= 0
        zr = (-wd + np.sqrt(np.maximum(disc, 0))) / dd
        q = w + zr[..., None] * d
        n = q @ M
        n /= np.linalg.norm(n, axis=-1, keepdims=True) + 1e-9
        self._write(sl, inside, zr + c[2], n, m, g)

    def _cap(self, p, m, g, k=28):
        a, b, ra, rb = p["a"], p["b"], p["ra"], p["rb"]
        r = max(ra, rb)
        win = self._window(min(a[0], b[0]) - r, max(a[0], b[0]) + r, min(a[1], b[1]) - r, max(a[1], b[1]) + r)
        if win is None:
            return
        sl, X, Y = win
        best = np.full(X.shape, -1e9)
        nb = np.zeros(X.shape + (3,))
        for s in np.linspace(0, 1, k):
            P = a + (b - a) * s
            rs = ra + (rb - ra) * s
            dx, dy = X - P[0], Y - P[1]
            d2 = dx * dx + dy * dy
            ok = d2 < rs * rs
            zs = np.where(ok, P[2] + np.sqrt(np.maximum(rs * rs - d2, 0)), -1e9)
            better = zs > best
            best = np.where(better, zs, best)
            nb = np.where(better[..., None], np.stack([dx / rs, dy / rs, (zs - P[2]) / rs], -1), nb)
        self._write(sl, best > -1e8, best, nb, m, g)

    def _slab(self, p, m, g):
        o, u, v = p["o"], p["u"], p["v"]
        nrm = np.cross(u, v)
        nrm /= np.linalg.norm(nrm) + 1e-9
        if abs(nrm[2]) < 0.08:
            return
        if nrm[2] < 0:
            nrm = -nrm
        pts = [o + u * pa + v * pb for pa, pb in p["pts"]]
        xs = [q[0] for q in pts]
        ys = [q[1] for q in pts]
        win = self._window(min(xs), max(xs), min(ys), max(ys))
        if win is None:
            return
        sl, X, Y = win
        h, w = X.shape
        img = Image.new("L", (w, h), 0)
        x0 = (sl[1].start + 0.0) / SS - self.pivot[0]
        y0 = self.pivot[1] - sl[0].start / SS
        poly = [((q[0] - x0) * SS, (y0 - q[1]) * SS) for q in pts]
        ImageDraw.Draw(img).polygon(poly, fill=255)
        inside = np.asarray(img) > 0
        z = o[2] - (nrm[0] * (X - o[0]) + nrm[1] * (Y - o[1])) / nrm[2]
        # Para sombrear, la normal se inclina hacia la cámara: una hoja casi de
        # canto no queda negra.
        shade = nrm + v3(0, 0, 0.7)
        shade /= np.linalg.norm(shade)
        n = np.broadcast_to(shade, X.shape + (3,))
        self._write(sl, inside, z, n, m, g)

    def finish(self, eyes_on=True):
        """Muestras -> pixel art final (RGBA) + máscara de brillo."""
        h, w = self.fh, self.fw
        opaque = self.mat >= 0
        lam = np.clip((self.n * LIGHT).sum(-1), 0, 1)
        tone = np.digitize(lam, TONE_CUTS)
        mat = np.where(opaque, self.mat, 0)
        tone = np.where(GLOSS[mat] | (tone < 4), tone, 3)
        key = np.where(opaque, mat * 5 + tone, -1)
        # Moda por bloque de SSxSS (sin mezclar colores).
        blocks = key.reshape(h, SS, w, SS).transpose(0, 2, 1, 3).reshape(h * w, SS * SS)
        nkeys = len(MAT_NAMES) * 5
        valid = blocks >= 0
        cover = valid.mean(1)
        idx = (np.arange(h * w)[:, None] * (nkeys + 1) + np.where(valid, blocks, nkeys)).ravel()
        counts = np.bincount(idx, minlength=h * w * (nkeys + 1)).reshape(h * w, nkeys + 1)[:, :nkeys]
        best = counts.argmax(1)
        solid = (cover >= COVERAGE).reshape(h, w)
        best = best.reshape(h, w)
        fmat, ftone = best // 5, best % 5
        # Profundidad y grupo por píxel: los de la muestra más cercana.
        zb = self.z.reshape(h, SS, w, SS).transpose(0, 2, 1, 3).reshape(h, w, SS * SS)
        gb = self.grp.reshape(h, SS, w, SS).transpose(0, 2, 1, 3).reshape(h, w, SS * SS)
        near = zb.argmax(-1)
        fz = np.take_along_axis(zb, near[..., None], -1)[..., 0]
        fg = np.take_along_axis(gb, near[..., None], -1)[..., 0]
        # Ojos apagados (dormido / muerto): el brillo pasa a cuenca.
        if not eyes_on:
            off = solid & np.isin(fmat, list(GLOW_MATS))
            fmat = np.where(off, MAT_ID["cuenca"], fmat)
        rgb = PALETTE[fmat, ftone]
        out = np.zeros((h, w, 4), dtype=np.uint8)
        out[..., :3] = rgb
        out[..., 3] = np.where(solid, 255, 0)
        glow = solid & np.isin(fmat, list(GLOW_MATS))
        # Líneas interiores: el píxel de atrás, pegado a una parte de otro grupo
        # que está bastante más adelante, toma el contorno de la de adelante.
        pad_z = np.pad(np.where(solid, fz, -1e9), 1, constant_values=-1e9)
        pad_g = np.pad(np.where(solid, fg, -1), 1, constant_values=-1)
        pad_m = np.pad(fmat, 1)
        line = np.zeros((h, w), dtype=bool)
        line_col = np.zeros((h, w, 3), dtype=np.uint8)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nz = pad_z[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            ng = pad_g[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            nm = pad_m[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            take = solid & ~glow & (ng >= 0) & (ng != fg) & (nz - fz > INNER_LINE_DEPTH) & ~line
            line_col[take] = OUTLINE[nm[take]]
            line |= take
        out[line, :3] = line_col[line]
        # Contorno exterior de 1 px del color oscuro del material vecino.
        pad_s = np.pad(solid, 1)
        edge = np.zeros((h, w), dtype=bool)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ns = pad_s[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            nm = pad_m[1 + dy:1 + dy + h, 1 + dx:1 + dx + w]
            take = ~solid & ns & ~edge
            out[take, :3] = OUTLINE[nm[take]]
            out[take, 3] = 255
            edge |= take
        return out, glow


def render(prims, view_deg=0.0, scale=1.0, shift=(0.0, 0.0), lift=0.0, eyes_on=True, frame=(FW, FH), pivot=PIVOT):
    """Gira el personaje (0 = de frente; 180 de espaldas; + mira a la derecha),
    lo apoya en el piso (el punto más bajo en y = 0, más `lift`) y lo dibuja."""
    prims = transform(prims, rot_y(view_deg), v3(0, 0, 0))
    ground = min(bottom_of(p) for p in prims)
    prims = transform(prims, np.eye(3), v3(shift[0], lift + shift[1] - ground, 0))
    if scale != 1.0:
        prims = transform(prims, np.eye(3), v3(0, 0, 0), scale)
    cv = Canvas(frame, pivot)
    groups = {}
    for p in prims:
        g = groups.setdefault(p["g"], len(groups))
        cv.draw(p, g)
    return cv.finish(eyes_on)


# --- Esqueleto articulado (2,5D) ---------------------------------------------------
# Medidas en px (64 px = 1 m) de un esqueleto «chibi»: calavera grande, huesos
# gruesos. look["k"] escala todo (el guardián es más grande).

BASE_POSE = {
    "lean": 9.0, "side": 0.0, "twist": 0.0,
    "head": (6.0, 0.0, 0.0),          # pitch (+ mira abajo), roll, yaw
    "jaw": 0.12,                       # 0 cerrada, 1 abierta
    "arm_r": (14.0, 16.0, 28.0),      # pitch (+ adelante), roll (+ afuera), codo
    "arm_l": (14.0, 16.0, 28.0),
    "leg_r": (10.0, 7.0, 16.0),       # pitch, roll, rodilla
    "leg_l": (10.0, 7.0, 16.0),
    "wpn_r": 0.0, "wpn_l": 0.0,       # giro extra de lo que lleva cada mano
    "scale": 1.0, "lift": 0.0, "shift": (0.0, 0.0),
    "robe_sway": 0.0, "glow": 1.0, "wind": 0.0,
    "eyes": True,
    # Estela del golpe: fuerza (0 = no hay), arco (grados en pantalla, 0 =
    # derecha, 90 = arriba), radio y centro respecto del pecho.
    "smear": 0.0, "smear_arc": (150.0, 250.0), "smear_r": 34.0, "smear_c": (0.0, 0.0),
}


def lerp_pose(a, b, t):
    out = {}
    for k, va in a.items():
        vb = b.get(k, va)
        if isinstance(va, bool):
            out[k] = va if t < 0.5 else vb
        elif isinstance(va, tuple):
            out[k] = tuple(x + (y - x) * t for x, y in zip(va, vb))
        else:
            out[k] = va + (vb - va) * t
    return out


def pose(**kw):
    p = dict(BASE_POSE)
    p.update(kw)
    return p


def ease(t):
    return t * t * (3 - 2 * t)


def keyed(t, keys):
    """keys = [(tiempo 0..1, pose), ...] ordenadas; interpolación suave."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (t0, p0), (t1, p1) in zip(keys, keys[1:]):
        if t <= t1:
            return lerp_pose(p0, p1, ease((t - t0) / max(t1 - t0, 1e-6)))
    return keys[-1][1]


# Calavera grande (como la referencia: ~1/3 del alto) y cuerpo flaco.
SKULL = 17.0
# Las prendas de la cabeza (capucha, casco) se midieron con una calavera de 15.
HS = SKULL / 15.0


def rig(p, k=1.0):
    """Posiciones de las articulaciones (espacio del personaje, sin apoyar)."""
    thigh, shin, spine, sh_w, hip_w = 14 * k, 14 * k, 23 * k, 12.5 * k, 7.0 * k
    upper, fore, neck, skull = 13 * k, 12.5 * k, 4.5 * k, SKULL * k
    Rt = rot_y(p["twist"]) @ rot_z(p["side"]) @ rot_x(p["lean"])
    Rp = rot_y(p["twist"] * 0.3)
    hp, hr, hy = p["head"]
    Rh = Rt @ rot_y(hy) @ rot_z(hr) @ rot_x(hp)
    pelvis = v3(0, thigh + shin + 4 * k, 0)
    top = pelvis + Rt @ v3(0, spine, 0)
    j = {"Rt": Rt, "Rp": Rp, "Rh": Rh, "pelvis": pelvis, "top": top, "k": k}
    j["chest"] = pelvis + Rt @ v3(0, spine * 0.62, 1.0 * k)
    j["neck"] = top + Rt @ v3(0, neck, 0)
    j["head"] = j["neck"] + Rh @ v3(0, skull * 0.78, 1.5 * k)
    for side, s in (("r", -1), ("l", 1)):
        pitch, roll, bend = p["arm_" + side]
        sh = pelvis + Rt @ v3(s * sh_w, spine * 0.9, 0)
        d1 = Rt @ limb_dir(pitch, roll, s)
        el = sh + d1 * upper
        d2 = Rt @ limb_dir(pitch + bend, roll, s)
        j["sh_" + side], j["el_" + side], j["hand_" + side] = sh, el, el + d2 * fore
        j["fore_" + side] = d2
        pitch, roll, bend = p["leg_" + side]
        hip = pelvis + Rp @ v3(s * hip_w, -2 * k, 0)
        d1 = Rp @ limb_dir(pitch, roll, s)
        kn = hip + d1 * thigh
        # La tibia se abre mucho menos que el muslo: rodillas hacia afuera
        # (patas arqueadas, como en la referencia).
        d2 = Rp @ limb_dir(pitch - bend, roll * 0.25, s)
        j["hip_" + side], j["knee_" + side], j["ankle_" + side] = hip, kn, kn + d2 * shin
        j["shin_" + side] = d2
    return j


def _perp(d, R):
    """Un eje perpendicular a d, lo más «hacia los costados» posible (para
    poner dos huesos lado a lado: radio y cúbito, tibia y peroné)."""
    side = np.cross(d, R @ v3(0, 0, 1))
    if np.linalg.norm(side) < 0.2:
        side = np.cross(d, R @ v3(0, 1, 0))
    return side / (np.linalg.norm(side) + 1e-9)


def ribcage_prims(j, B):
    """Caja torácica de costillas sueltas (arcos) sobre un interior oscuro, con
    esternón adelante y columna atrás."""
    k, Rt, c = j["k"], j["Rt"], j["chest"]
    out = []
    ribs = [(7.2, 9.0, 6.6), (2.8, 11.4, 8.0), (-1.6, 11.8, 8.2), (-6.0, 10.4, 7.4)]
    for i, (y, rx, rz) in enumerate(ribs):
        for s in (-1, 1):
            pts = []
            for phi in range(18, 176, 22):
                f = math.radians(phi)
                pts.append(c + Rt @ (v3(s * rx * math.sin(f), y - 2.6 * math.sin(f), rz * math.cos(f)) * k))
            for a_, b_ in zip(pts, pts[1:]):
                out.append(bone(a_, b_, 1.3 * k, 1.2 * k, B, "ribs"))
    out += [
        ell(c + Rt @ v3(0, 0.4 * k, -0.6 * k), v3(9.2, 9.5, 5.6) * k, "cuenca", "ribs", Rt),
        bone(c + Rt @ v3(0, 8.5 * k, 6.2 * k), c + Rt @ v3(0, -3.0 * k, 8.0 * k), 1.9 * k, 1.6 * k, B, "ribs"),
        # Columna por detrás (se ve de espaldas y entre las costillas de costado).
        bone(c + Rt @ v3(0, 10 * k, -6.2 * k), c + Rt @ v3(0, -9 * k, -6.4 * k), 1.8 * k, 1.8 * k, B, "ribs"),
    ]
    for y in (8.0, 3.5, -1.0, -5.5):
        out.append(sphere(c + Rt @ v3(0, y * k, -7.0 * k), 2.0 * k, B, "ribs"))
    # Clavículas.
    for side, s in (("r", -1), ("l", 1)):
        out.append(bone(c + Rt @ v3(s * 1.5 * k, 9.6 * k, 5.6 * k), j["sh_" + side] + Rt @ v3(0, 0.5 * k, 1.0 * k), 1.35 * k, 1.35 * k, B, "ribs"))
    return out


def pelvis_prims(j, B):
    """Pelvis con las dos alas (ilíacos), sacro y los agujeros oscuros."""
    k, Rp, pv = j["k"], j["Rp"], j["pelvis"]
    out = [ell(pv + Rp @ v3(0, 1.0 * k, -2.0 * k), v3(3.4, 4.8, 2.8) * k, B, "pelvis", Rp),
           ell(pv + Rp @ v3(0, 1.6 * k, 0.6 * k), v3(3.0, 3.0, 2.0) * k, "cuenca", "pelvis", Rp),
           bone(pv + Rp @ v3(-4.2 * k, -3.2 * k, 2.6 * k), pv + Rp @ v3(4.2 * k, -3.2 * k, 2.6 * k), 1.6 * k, 1.6 * k, B, "pelvis")]
    for s in (-1, 1):
        out += [ell(pv + Rp @ v3(s * 5.8 * k, 2.0 * k, -0.4 * k), v3(6.4, 5.2, 2.6) * k, B, "pelvis", Rp @ rot_z(s * 32) @ rot_y(-s * 28)),
                ell(pv + Rp @ v3(s * 3.4 * k, -1.0 * k, 3.4 * k), v3(1.7, 2.1, 1.0) * k, "cuenca", "pelvis", Rp)]
    # Lumbares: de la pelvis a las costillas.
    for f in (0.15, 0.32):
        out.append(sphere(pv + (j["chest"] - pv) * f + j["Rt"] @ v3(0, 2.0 * k, -1.0 * k), 2.4 * k, B, "spine"))
    return out


def skeleton_prims(j, p, bone_mat="hueso", skip=()):
    """El cuerpo de hueso: piernas, pelvis, columna, costillas, brazos y calavera."""
    k, Rt, Rp = j["k"], j["Rt"], j["Rp"]
    B = bone_mat
    out = []
    if "legs" not in skip:
        for side in ("r", "l"):
            g = "leg_" + side
            s = -1 if side == "r" else 1
            kn, an, d2 = j["knee_" + side], j["ankle_" + side], j["shin_" + side]
            off = _perp(d2, Rp) * 1.0 * k
            fwd = Rp @ v3(0, 0, 1)
            out += [
                bone(j["hip_" + side], kn, 2.6 * k, 2.1 * k, B, g),
                sphere(kn, 2.8 * k, B, g),
                sphere(kn + fwd * 2.0 * k + v3(0, 0.6 * k, 0), 1.6 * k, B, g),
                bone(kn - off * 0.4, an - off * 0.4, 1.75 * k, 1.5 * k, B, g),
                bone(kn + off * 1.4 + d2 * 2 * k, an + off * 1.4, 1.1 * k, 1.0 * k, B, g),
                sphere(an, 1.9 * k, B, g),
                ell(an + Rp @ v3(s * 0.3 * k, -0.8 * k, 3.0 * k), v3(3.0, 1.7, 4.4) * k, B, g, Rp),
            ]
            for t in (-1.6, 0.0, 1.6):
                out.append(sphere(an + Rp @ v3((t + s * 0.3) * k, -1.3 * k, 7.0 * k), 1.05 * k, B, g))
    out += pelvis_prims(j, B)
    if "ribs" in skip:
        out += [bone(j["pelvis"], j["top"], 2.4 * k, 2.2 * k, B, "spine"),
                ell(j["chest"], v3(11.0, 10.0, 7.5) * k, B, "ribs", Rt)]
    else:
        out += ribcage_prims(j, B)
    for f in (0.0, 0.55):
        out.append(sphere(j["top"] + (j["neck"] - j["top"]) * f, 2.3 * k, B, "spine"))
    if "arms" not in skip:
        for side in ("r", "l"):
            out += arm_prims(j, side, B)
    out += skull_prims(j, p, B)
    return out


def arm_prims(j, side, mat, sleeve=None):
    k, Rt = j["k"], j["Rt"]
    g = "arm_" + side
    d2 = j["fore_" + side]
    hm = "hueso" if mat != "hueso_viejo" else mat
    out = [sphere(j["sh_" + side], 3.0 * k, mat, g)]
    if sleeve:
        out += [bone(j["sh_" + side], j["el_" + side], 5.0 * k, 5.6 * k, sleeve, g),
                bone(j["el_" + side], j["hand_" + side] - d2 * 2.5 * k, 5.6 * k, 7.0 * k, sleeve, g)]
    else:
        off = _perp(d2, Rt) * 0.95 * k
        out += [bone(j["sh_" + side], j["el_" + side], 2.2 * k, 1.9 * k, mat, g),
                sphere(j["el_" + side], 2.4 * k, mat, g),
                bone(j["el_" + side] - off, j["hand_" + side] - off * 0.7, 1.2 * k, 1.05 * k, mat, g),
                bone(j["el_" + side] + off, j["hand_" + side] + off * 0.7, 1.05 * k, 0.95 * k, mat, g),
                sphere(j["hand_" + side], 1.5 * k, hm, g)]
    # Mano de hueso: palma, nudillos y pulgar (cerrada, como agarrando).
    h = j["hand_" + side] + d2 * 2.4 * k
    out += [ell(h, v3(3.0, 3.4, 2.4) * k, hm, g, Rt),
            ell(h + d2 * 2.2 * k + Rt @ v3(0, 0, 1.0 * k), v3(3.2, 1.6, 2.0) * k, hm, g, Rt),
            sphere(h + Rt @ v3((2.4 if side == "l" else -2.4) * k, 1.2 * k, 1.8 * k), 1.2 * k, hm, g)]
    return out


# Grietas de la calavera: polilíneas en direcciones desde el centro.
CRACKS = [
    [(0.30, 0.95, 0.05), (0.42, 0.80, 0.42), (0.28, 0.66, 0.70), (0.40, 0.55, 0.74)],
    [(-0.62, 0.74, 0.25), (-0.80, 0.50, 0.30), (-0.74, 0.40, 0.55)],
    [(0.05, 0.70, -0.71), (0.30, 0.52, -0.80)],
]


def skull_prims(j, p, mat):
    """Calavera de la referencia: cráneo enorme con grietas, cuencas hondas
    con ceño y pupila que brilla, pómulos, nariz de dos agujeros y una sonrisa
    de dientes grandes (arriba y abajo)."""
    k, Rh = j["k"], j["Rh"]
    c = j["head"]
    jaw = p["jaw"]
    eyes = "ojo" if p["eyes"] else "cuenca"
    S = k
    R = v3(17.0, 16.5, 16.0) * S
    at = lambda x, y, z: c + Rh @ (v3(x, y, z) * S)
    out = [
        ell(c, R, mat, "head", Rh),
        ell(at(0, -6.8, 7.6), v3(12.0, 7.4, 9.6) * S, mat, "head", Rh),
        ell(at(0, -12.6 - 3.0 * jaw, 7.0 + jaw), v3(10.4, 4.8, 9.2) * S, mat, "head", Rh),
    ]
    for s in (-1, 1):
        out += [
            ell(at(s * 10.6, -4.6, 11.4), v3(4.0, 3.2, 3.2) * S, mat, "head", Rh),
            ell(at(s * 6.3, 1.6, 14.4), v3(6.0, 5.8, 3.0) * S, "cuenca", "head", Rh @ rot_z(-s * 10)),
            ell(at(s * 5.5, 7.4, 15.0), v3(7.0, 2.4, 2.4) * S, mat, "head", Rh @ rot_z(s * 22)),
            sphere(at(s * 5.9, 1.0, 17.3), 1.9 * S, eyes, "head"),
            ell(at(s * 1.1, -3.6, 17.0), v3(1.3, 2.4, 1.2) * S, "cuenca", "head", Rh @ rot_z(s * 15)),
        ]
    out.append(ell(at(0, -9.6 - 1.2 * jaw, 15.2), v3(9.0, 1.9 + 2.2 * jaw, 1.8) * S, "cuenca", "head", Rh))
    for x in (-6.25, -3.75, -1.25, 1.25, 3.75, 6.25):
        out.append(ell(at(x, -8.9, 16.3 - 0.045 * x * x), v3(1.15, 1.7, 1.0) * S, mat, "head", Rh))
    for x in (-5.0, -2.5, 0.0, 2.5, 5.0):
        out.append(ell(at(x, -11.1 - 2.6 * jaw, 15.5 - 0.045 * x * x), v3(1.1, 1.4, 0.9) * S, mat, "head", Rh))
    for crack in CRACKS:
        pts = []
        for d in crack:
            u = np.array(d) / np.linalg.norm(d)
            q = u / np.sqrt(((u * u) / (R * R)).sum())          # punto en el elipsoide
            pts.append(c + Rh @ (q * 1.01))
        for a_, b_ in zip(pts, pts[1:]):
            out.append(bone(a_, b_, 0.75 * S, 0.6 * S, "grieta", "head"))
    return out


def weapon_axis(j, side, extra):
    """Eje de lo que lleva la mano: perpendicular al antebrazo (hacia adelante
    con el brazo colgando, hacia arriba con el antebrazo adelante) + giro extra."""
    lateral = j["Rt"] @ v3(1, 0, 0)
    w = axis_rot(lateral, -90 - extra) @ j["fore_" + side]
    return w / np.linalg.norm(w), lateral


# --- Armas y ropa -------------------------------------------------------------------

def sword(j, side, extra, mat="acero"):
    """Espada corta: hoja de acero con canal, guarda curva y pomo dorados."""
    k = j["k"]
    w, lat = weapon_axis(j, side, extra)
    h = j["hand_" + side] + j["fore_" + side] * 2.4 * k
    base = h + w * 3.4 * k
    L, W = 24 * k, 3.3 * k
    g = "wpn_" + side
    blade = slab(base + w * 1.2 * k, w, lat, [(0, -W), (L - 6 * k, -W), (L, 0), (L - 6 * k, W), (0, W)], mat, g)
    fuller = slab(base + w * 1.2 * k + np.cross(lat, w) * 0.3 * k, w, lat, [(1.5 * k, -0.7 * k), (L - 8 * k, -0.7 * k), (L - 8 * k, 0.7 * k), (1.5 * k, 0.7 * k)], "grieta", g)
    R = np.column_stack([lat, w, np.cross(lat, w)])
    return [
        bone(h - w * 4.5 * k, base, 1.4 * k, 1.4 * k, "cuero", g),
        sphere(h - w * 5.2 * k, 1.9 * k, "oro", g),
        ell(base, v3(6.2, 1.5, 2.0) * k, "oro", g, R),
        sphere(base + lat * 6.0 * k + w * 1.0 * k, 1.3 * k, "oro", g),
        sphere(base - lat * 6.0 * k + w * 1.0 * k, 1.3 * k, "oro", g),
        blade, fuller,
    ]


def crossbow(j, extra):
    """Ballesta en la mano derecha, apuntando hacia donde apunta el antebrazo."""
    k = j["k"]
    lat = j["Rt"] @ v3(1, 0, 0)
    a = axis_rot(lat, -extra) @ j["fore_r"]
    a /= np.linalg.norm(a)
    up = np.cross(a, lat)
    up /= np.linalg.norm(up) + 1e-9
    h = j["hand_r"] + j["fore_r"] * 2.0 * k
    tip = h + a * 18 * k
    g = "wpn_r"
    out = [bone(h - a * 7 * k, tip, 2.2 * k, 1.8 * k, "madera", g)]
    for s_ in (-1, 1):
        mid = tip + lat * s_ * 8 * k - a * 1.5 * k
        end = tip + lat * s_ * 14 * k - a * 6 * k
        out += [bone(tip, mid, 1.9 * k, 1.6 * k, "madera", g), bone(mid, end, 1.6 * k, 1.2 * k, "madera", g),
                bone(end, h + a * 4 * k, 0.45 * k, 0.45 * k, "cuenca", g)]
    out += [bone(h + a * 2 * k + up * 2.2 * k, tip + a * 5 * k + up * 2.2 * k, 0.9 * k, 0.9 * k, "acero", g),
            ell(tip + a * 5.5 * k + up * 2.2 * k, v3(1.6, 1.6, 2.6) * k, "acero", g, np.column_stack([lat, up, a]))]
    return out


def axe(j, extra):
    k = j["k"]
    w, lat = weapon_axis(j, "r", extra)
    h = j["hand_r"] + j["fore_r"] * 2.0 * k
    top = h + w * 24 * k
    g = "wpn_r"
    head = slab(top - w * 1 * k, w, lat, [(-5 * k, 0), (-6.5 * k, -8 * k), (-1 * k, -11 * k), (5 * k, -10.5 * k), (6.5 * k, -7 * k), (4 * k, 0)], "acero", g)
    return [bone(h - w * 8 * k, top + w * 3 * k, 1.9 * k, 1.7 * k, "madera", g), head,
            sphere(top + w * 3.5 * k, 2.2 * k, "acero", g)]


def shield(j, extra, face="bronce", rim="oro", boss="oro", radius=16.0, studs=True, yaw=0.0):
    """Escudo redondo en el antebrazo izquierdo, mirando al frente: aro, cara,
    umbo (el centro abultado) y tachas o tablas."""
    k = j["k"]
    Rt = j["Rt"]
    c = j["hand_l"] + Rt @ v3(1.5 * k, 2.0 * k, 4.0 * k) + j["fore_l"] * (-3.0 * k)
    R = Rt @ rot_y(-extra * 0.5 + yaw) @ rot_x(-extra * 0.3)
    u, v = R @ v3(1, 0, 0), R @ v3(0, 1, 0)
    r_out, r_in = radius * k, (radius - 2.2) * k
    ring = [(math.cos(t) * r_out, math.sin(t) * r_out) for t in np.linspace(0, 2 * math.pi, 32, endpoint=False)]
    disc = [(math.cos(t) * r_in, math.sin(t) * r_in) for t in np.linspace(0, 2 * math.pi, 32, endpoint=False)]
    n = R @ v3(0, 0, 1)
    g = "shield"
    out = [slab(c - n * 1.1 * k, u, v, disc, face, g), slab(c - n * 0.5 * k, u, v, ring, rim, g), slab(c, u, v, disc, face, g),
           ell(c + n * 1.5 * k, v3(3.6, 3.6, 2.6) * k, boss, g, R)]
    if studs:
        for y in (9.0, -9.0):
            out.append(ell(c + n * 0.6 * k + R @ v3(0, y * k, 0), v3(3.0, 2.0, 1.0) * k, boss, g, R))
    else:
        # Tablas de madera: dos juntas verticales.
        for x in (-4.2, 4.2):
            h = math.sqrt(max(r_in * r_in - (x * k) ** 2, 0)) - 0.6 * k
            out.append(slab(c + n * 0.25 * k, u, v, [(x * k - 0.45 * k, -h), (x * k + 0.45 * k, -h), (x * k + 0.45 * k, h), (x * k - 0.45 * k, h)], "grieta", g))
    return out


def staff(j, extra, glow):
    """Bastón del nigromante con orbe que brilla (color de ojos en el juego)."""
    k = j["k"]
    w, lat = weapon_axis(j, "r", extra)
    h = j["hand_r"] + j["fore_r"] * 2.0 * k
    top = h + w * 30 * k
    g = "wpn_r"
    out = [bone(h - w * 26 * k, top, 1.8 * k, 1.6 * k, "madera", g)]
    for ang in (0, 120, 240):
        d = axis_rot(w, ang) @ lat
        out.append(bone(top, top + w * 6 * k + d * 4.5 * k, 1.3 * k, 0.8 * k, "oro", g))
    out.append(sphere(top + w * 5.5 * k, 4.2 * k * glow, "orbe", g))
    return out


def hand_orb(j, side, size):
    if size <= 0.05:
        return []
    k = j["k"]
    return [sphere(j["hand_" + side] + j["fore_" + side] * 4.5 * k + j["Rt"] @ v3(0, 1.5 * k, 3.0 * k), 3.2 * k * size, "orbe", "magia")]


def smear(j, p):
    """Media luna blanca que sigue al arma en el cuadro del golpe (frente a la
    cámara, delante del cuerpo). Más gruesa cuanto más fuerte."""
    if p["smear"] <= 0.05:
        return []
    k = j["k"]
    a0, a1 = p["smear_arc"]
    r = p["smear_r"] * k
    thick = 9.0 * k * p["smear"]
    c = j["chest"] + v3(p["smear_c"][0] * k, p["smear_c"][1] * k, 16 * k)
    n = 14
    outer = [(math.cos(math.radians(a0 + (a1 - a0) * i / n)) * r, math.sin(math.radians(a0 + (a1 - a0) * i / n)) * r) for i in range(n + 1)]
    inner = []
    for i in range(n, -1, -1):
        f = math.sin(math.pi * i / n)          # más ancha en el medio
        rr = r - thick * f - 0.5
        a = math.radians(a0 + (a1 - a0) * i / n)
        inner.append((math.cos(a) * rr, math.sin(a) * rr))
    return [slab(c, v3(1, 0, 0), v3(0, 1, 0), outer + inner, "destello", "estela")]


# --- Monstruos ----------------------------------------------------------------------
# Cada uno: función pose -> primitivas. «look» guarda el tamaño de cuadro.

def picaro(p):
    """Esqueleto ballestero: capucha y capa verdes, ballesta."""
    j = rig(p, 0.98)
    Rt, Rh, k = j["Rt"], j["Rh"], j["k"]
    out = skeleton_prims(j, p)
    c = j["head"]
    out += [ell(c + Rh @ v3(0, 2.2 * k, -3.6 * k) * HS, v3(17.4, 16.8, 15.8) * k * HS, "tela_verde", "capucha", Rh),
            ell(c + Rh @ v3(0, -1.0 * k, 8.4 * k) * HS, v3(13.4, 13.8, 2.8) * k * HS, "cuenca", "capucha", Rh),
            bone(c + Rh @ v3(0, 11 * k, -11 * k) * HS, c + Rh @ v3(0, 6 * k, -19 * k) * HS, 4.0 * k, 1.2 * k, "tela_verde", "capucha"),
            ell(j["top"] + Rt @ v3(0, 0, 0.5 * k), v3(13.0, 4.6, 10.0) * k, "tela_verde", "capa", Rt),
            bone(j["top"] + Rt @ v3(0, -3 * k, -7 * k), j["pelvis"] + Rt @ v3(0, -4 * k, -10 * k), 8.5 * k, 10 * k, "tela_verde", "capa"),
            bone(j["chest"] + Rt @ v3(-9 * k, 8 * k, 7.5 * k), j["pelvis"] + Rt @ v3(8 * k, 4 * k, 6.5 * k), 1.3 * k, 1.3 * k, "cuero", "correa")]
    out += crossbow(j, p["wpn_r"])
    out += smear(j, p)
    return out


def guardian(p):
    """Esqueleto guardián (élite): huesos viejos, casco con cuernos, hombreras,
    escudo redondo y hacha."""
    j = rig(p, 1.1)
    Rt, Rh, k = j["Rt"], j["Rh"], j["k"]
    out = skeleton_prims(j, p, bone_mat="hueso_viejo")
    c = j["head"]
    out += [ell(c + Rh @ v3(0, 5.8 * k, -0.6 * k) * HS, v3(16.2, 10.8, 15.0) * k * HS, "acero", "casco", Rh),
            ell(c + Rh @ v3(0, 1.0 * k, 0) * HS, v3(16.6, 1.6, 15.4) * k * HS, "oro", "casco", Rh),
            bone(c + Rh @ v3(0, 6 * k, 14.4 * k) * HS, c + Rh @ v3(0, -2.0 * k, 14.8 * k) * HS, 1.7 * k, 1.4 * k, "acero", "casco")]
    for s_ in (-1, 1):
        base = c + Rh @ v3(s_ * 14 * k, 7 * k, 0) * HS
        mid = base + Rh @ v3(s_ * 8 * k, 4 * k, 1 * k)
        tip = mid + Rh @ v3(s_ * 3 * k, 9 * k, 0)
        out += [bone(base, mid, 3.4 * k, 2.4 * k, "hueso", "cuerno"), bone(mid, tip, 2.4 * k, 0.8 * k, "hueso", "cuerno")]
        out.append(ell(j["sh_" + ("r" if s_ < 0 else "l")] + Rt @ v3(s_ * 1.5 * k, 2.0 * k, 0), v3(7.0, 5.0, 7.0) * k, "acero", "hombrera_" + str(s_), Rt))
    out += axe(j, p["wpn_r"])
    out += shield(j, p["wpn_l"])
    out += smear(j, p)
    return out


def nigromante(p):
    """Nigromante (jefe): túnica y capucha moradas con ribete dorado, manos de
    hueso, bastón con orbe; flota apenas sobre el piso."""
    j = rig(p, 1.05)
    Rt, Rh, k = j["Rt"], j["Rh"], j["k"]
    out = skeleton_prims(j, p, skip=("legs", "arms", "ribs"))
    sway = p["robe_sway"]
    hem = v3(sway * 4 * k, 0, sway * 1.5 * k)
    floor = j["pelvis"] * v3(1, 0, 1) + hem
    # Túnica: campana del pecho al piso, falda ancha y ribete dorado abajo.
    out += [bone(j["chest"] + Rt @ v3(0, 3 * k, -1 * k), floor + v3(0, 16 * k, 0), 12.5 * k, 17 * k, "tela_morada", "tunica"),
            ell(floor + v3(0, 9 * k, 0), v3(21.5, 9.0, 14.5) * k, "tela_morada", "tunica"),
            ell(floor + v3(0, 2.5 * k, 0), v3(22.0, 2.8, 15.0) * k, "oro", "tunica"),
            ell(j["pelvis"] + Rt @ v3(0, 4 * k, 0), v3(12.5, 2.4, 10.0) * k, "oro", "tunica", Rt),
            ell(j["top"] + Rt @ v3(0, 0, 0.5 * k), v3(15.0, 6.5, 11.5) * k, "tela_morada", "tunica", Rt)]
    c = j["head"]
    out += [ell(c + Rh @ v3(0, 2.8 * k, -3.0 * k) * HS, v3(18.2, 17.8, 16.4) * k * HS, "tela_morada", "capucha", Rh),
            ell(c + Rh @ v3(0, -1.0 * k, 9.4 * k) * HS, v3(15.4, 15.6, 3.2) * k * HS, "cuenca", "capucha", Rh)]
    for side in ("r", "l"):
        out += arm_prims(j, side, "hueso", sleeve="tela_morada")
    out += staff(j, p["wpn_r"], p["glow"])
    out += hand_orb(j, "l", p["glow"] - 1.0)
    out += smear(j, p)
    return out


# --- Animaciones --------------------------------------------------------------------
# Cada papel: (cuadros, se repite, duración en s, vistas, función t -> pose).
# t va de 0 a 1 (los que se repiten no repiten el último cuadro). Las vistas
# (hacia dónde mira el monstruo respecto de la cámara): s de frente (0°), se
# tres cuartos a la derecha (45°), e de perfil a la derecha (90°), ne de
# espaldas a la derecha (135°), n de espaldas, y nw, w, sw del otro lado. Solo
# idle y walk van en las ocho: el resto pasa de frente al jugador.

VIEWS = {"s": 0.0, "se": 45.0, "e": 90.0, "ne": 135.0, "n": 180.0, "nw": -135.0, "w": -90.0, "sw": -45.0}
ALL_VIEWS = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]


def wave(t, cycles=1.0, phase=0.0):
    return math.sin(2 * math.pi * (t * cycles) + phase)


def breathe(base, t, amp=1.0):
    """Respiración / balanceo de reposo alrededor de una pose."""
    p = dict(base)
    p["lean"] = base["lean"] + 2.0 * amp * wave(t)
    hp, hr, hy = base["head"]
    p["head"] = (hp + 3.0 * amp * wave(t, 1, 1.0), hr, hy)
    p["jaw"] = base["jaw"] + 0.1 * max(0.0, wave(t, 2))
    for side in ("r", "l"):
        a, r, b = base["arm_" + side]
        p["arm_" + side] = (a, r + 3.0 * amp * wave(t, 1, 0.5), b)
        a, r, b = base["leg_" + side]
        p["leg_" + side] = (a, r, b + 4.0 * amp * (0.5 + 0.5 * wave(t)))
    return p


def walk_cycle(base, t, arm_swing=22.0, robe=False):
    p = dict(base)
    w = wave(t)
    c = math.cos(2 * math.pi * t)
    for side, s in (("r", 1.0), ("l", -1.0)):
        a, r, b = base["leg_" + side]
        p["leg_" + side] = (a + 26 * s * w, r + 4 * s * w, b + 45 * max(0.0, s * c))
        a, r, b = base["arm_" + side]
        p["arm_" + side] = (a - arm_swing * s * w, r, b)
    p["twist"] = base["twist"] + 6 * w
    p["side"] = base["side"] + 5 * w
    hp, hr, hy = base["head"]
    p["head"] = (hp, hr, hy - 4 * w)
    p["jaw"] = base["jaw"] + 0.12 * max(0.0, wave(t, 2))
    if robe:
        p["robe_sway"] = 0.9 * w
        p["lift"] = base["lift"] + 1.5 * (0.5 + 0.5 * wave(t, 2))
    return p


def hit_keys(base, recoil):
    return [(0.0, base), (0.35, recoil), (1.0, base)]


def skeleton_set(STAND, GUARD, attacks, hits):
    DORMANT = pose(lean=30.0, side=10.0, leg_r=(80.0, 18.0, 70.0), leg_l=(80.0, 18.0, 70.0),
                   arm_r=(5.0, 12.0, 5.0), arm_l=(5.0, 12.0, 5.0), head=(45.0, 18.0, 0.0), jaw=0.6,
                   eyes=False, wpn_r=-70.0, wpn_l=GUARD["wpn_l"], glow=1.0)
    BUCKLE = dict(GUARD, leg_r=(40.0, 12.0, 90.0), leg_l=(40.0, 12.0, 90.0), lean=35.0, head=(35.0, 15.0, 0.0),
                  arm_r=(-5.0, 25.0, 10.0), arm_l=(-5.0, 25.0, 10.0), jaw=1.0, wpn_r=-80.0)
    LYING = dict(DORMANT, lean=-80.0, side=0.0, leg_r=(85.0, 20.0, 0.0), leg_l=(85.0, 20.0, 0.0),
                 arm_r=(0.0, 70.0, 0.0), arm_l=(0.0, 70.0, 0.0), head=(-20.0, 10.0, 0.0), jaw=0.5, wpn_r=-80.0)
    RECOIL = dict(GUARD, lean=-18.0, head=(-22.0, 10.0, 0.0), jaw=0.9, arm_r=(-20.0, 45.0, 60.0), arm_l=(-20.0, 45.0, 60.0),
                  leg_r=(0.0, 12.0, 30.0), leg_l=(0.0, 12.0, 30.0), scale=0.97)
    anims = {
        "idle": (6, True, 1.4, ALL_VIEWS, lambda t: breathe(STAND, t)),
        "walk": (8, True, 0.9, ALL_VIEWS, lambda t: walk_cycle(STAND, t)),
        "combat": (6, True, 1.1, ["s"], lambda t: breathe(GUARD, t, 0.8)),
        "death": (10, False, 1.3, ["s"], lambda t: keyed(t, [(0.0, GUARD), (0.2, RECOIL), (0.45, BUCKLE), (0.72, dict(DORMANT, eyes=True)), (0.8, DORMANT), (1.0, LYING)])),
        "spawn": (12, False, 1.5, ["s"], lambda t: keyed(t, [
            (0.0, DORMANT), (0.12, dict(DORMANT, eyes=True, head=(25.0, 5.0, 0.0))),
            (0.3, dict(DORMANT, eyes=True, head=(10.0, 0.0, 0.0), arm_r=(30.0, 30.0, 60.0), arm_l=(30.0, 30.0, 60.0))),
            (0.5, dict(GUARD, leg_r=(55.0, 14.0, 100.0), leg_l=(55.0, 14.0, 100.0), lean=35.0)),
            (0.7, dict(GUARD, leg_r=(25.0, 10.0, 50.0), leg_l=(25.0, 10.0, 50.0), lean=15.0, lift=3.0)),
            (0.85, dict(GUARD, lean=-8.0, arm_r=(-10.0, 40.0, 30.0), arm_l=(-10.0, 40.0, 30.0), jaw=0.9, head=(-15.0, 0.0, 0.0))),
            (1.0, GUARD)])),
        "dormant": (1, True, 1.0, ["s"], lambda t: DORMANT),
    }
    for i, keys in enumerate(attacks):
        anims["attack" if i == 0 else "attack_%d" % (i + 1)] = (8, False, 0.9, ["s"], (lambda ks: lambda t: keyed(t, ks))(keys))
    for i, recoil in enumerate(hits or [RECOIL]):
        recoil = recoil or RECOIL
        anims["hit" if i == 0 else "hit_%d" % (i + 1)] = (4, False, 0.45, ["s"], (lambda ks: lambda t: keyed(t, ks))(hit_keys(GUARD, recoil)))
    return anims


def picaro_anims():
    STAND = pose(arm_r=(25.0, 12.0, 20.0), arm_l=(20.0, 20.0, 20.0))
    # Apunta al jugador con la ballesta un poco inclinada (así se ve la caja y
    # el arco); al disparar, fogonazo en la punta y retroceso.
    GUARD = pose(lean=10.0, head=(8.0, 0.0, 0.0), arm_r=(70.0, -18.0, 20.0), arm_l=(75.0, 18.0, 20.0), wpn_r=-18.0,
                 leg_r=(5.0, 12.0, 18.0), leg_l=(15.0, 12.0, 18.0), jaw=0.15)
    shoot = [(0.0, GUARD),
             (0.25, dict(GUARD, lean=14.0, scale=1.04, head=(12.0, 0.0, 0.0))),
             (0.35, dict(GUARD, lean=-6.0, arm_r=(80.0, -18.0, 10.0), jaw=0.7, head=(-8.0, 0.0, 0.0), scale=1.08,
                         smear=1.0, smear_arc=(0.0, 360.0), smear_r=9.0, smear_c=(-6.0, -6.0))),
             (0.6, dict(GUARD, lean=6.0, arm_l=(20.0, 30.0, 90.0))),
             (1.0, GUARD)]
    side_hit = dict(GUARD, side=-16.0, twist=-20.0, head=(10.0, 20.0, -15.0), arm_l=(-10.0, 60.0, 20.0), jaw=0.7)
    return skeleton_set(STAND, GUARD, [shoot], [None, side_hit])


def guardian_anims():
    STAND = pose(arm_r=(14.0, 16.0, 35.0), wpn_r=-50.0, arm_l=(25.0, 20.0, 60.0))
    GUARD = pose(lean=12.0, head=(10.0, 0.0, 0.0), arm_r=(60.0, 28.0, 70.0), wpn_r=-10.0, arm_l=(40.0, 15.0, 50.0),
                 leg_r=(6.0, 16.0, 26.0), leg_l=(14.0, 16.0, 26.0), jaw=0.2)
    chop = [(0.0, GUARD),
            (0.25, dict(GUARD, lean=-8.0, twist=10.0, arm_r=(165.0, 20.0, 40.0), jaw=0.5, head=(-6.0, 0.0, 0.0))),
            (0.42, dict(GUARD, lean=25.0, arm_r=(50.0, 0.0, 0.0), wpn_r=40.0, scale=1.12, jaw=0.9, head=(16.0, 0.0, 0.0),
                        smear=1.0, smear_arc=(95.0, 235.0), smear_r=38.0, smear_c=(-4.0, 4.0))),
            (0.62, dict(GUARD, lean=20.0, arm_r=(10.0, -10.0, 0.0), wpn_r=60.0, scale=1.06)),
            (1.0, GUARD)]
    bash = [(0.0, GUARD),
            (0.3, dict(GUARD, twist=25.0, lean=0.0, arm_l=(20.0, 30.0, 90.0))),
            (0.45, dict(GUARD, twist=-20.0, lean=22.0, arm_l=(80.0, 0.0, 10.0), scale=1.16, jaw=0.8)),
            (0.65, dict(GUARD, twist=-10.0, lean=16.0, arm_l=(70.0, 5.0, 20.0), scale=1.08)),
            (1.0, GUARD)]
    block = dict(GUARD, lean=-6.0, head=(14.0, 0.0, 0.0), arm_l=(75.0, 4.0, 60.0), scale=0.98, jaw=0.4)
    return skeleton_set(STAND, GUARD, [chop, bash], [block, None])


def nigromante_anims():
    STAND = pose(lean=4.0, head=(8.0, 0.0, 0.0), arm_r=(25.0, 18.0, 60.0), arm_l=(20.0, 25.0, 50.0),
                 leg_r=(0.0, 5.0, 4.0), leg_l=(0.0, 5.0, 4.0), lift=3.0, wpn_r=0.0, jaw=0.1)
    GUARD = dict(STAND, lean=8.0, arm_l=(55.0, 35.0, 45.0), glow=1.3, head=(10.0, 0.0, 0.0))

    def float_(base, t):
        p = breathe(base, t, 0.7)
        p["lift"] = base["lift"] + 2.0 * (0.5 + 0.5 * wave(t))
        p["robe_sway"] = 0.6 * wave(t)
        p["glow"] = base["glow"] + 0.12 * wave(t, 2)
        return p

    HEAP = dict(STAND, lean=70.0, lift=0.0, head=(60.0, 20.0, 0.0), arm_r=(-5.0, 15.0, 10.0), arm_l=(-5.0, 15.0, 10.0),
                jaw=0.6, eyes=False, glow=0.6, wpn_r=-70.0, robe_sway=0.0)
    RECOIL = dict(GUARD, lean=-14.0, head=(-18.0, 8.0, 0.0), arm_l=(-10.0, 45.0, 40.0), arm_r=(10.0, 30.0, 50.0), jaw=0.8, glow=0.9)
    side_hit = dict(GUARD, side=14.0, twist=18.0, head=(8.0, -18.0, 12.0), arm_l=(-5.0, 55.0, 20.0), jaw=0.7)
    ks = lambda keys: (lambda t: keyed(t, keys))
    return {
        "idle": (6, True, 1.6, ALL_VIEWS, lambda t: float_(STAND, t)),
        "walk": (8, True, 1.0, ALL_VIEWS, lambda t: walk_cycle(dict(STAND, lean=8.0), t, 10.0, robe=True)),
        "combat": (6, True, 1.2, ["s"], lambda t: float_(GUARD, t)),
        "attack": (8, False, 0.9, ["s"], ks([(0.0, GUARD), (0.25, dict(GUARD, arm_l=(110.0, 55.0, 70.0), glow=1.6)),
                                               (0.42, dict(GUARD, arm_l=(85.0, 5.0, 0.0), glow=2.0, scale=1.12, jaw=0.8, lean=14.0)),
                                               (0.65, dict(GUARD, arm_l=(70.0, 10.0, 10.0), glow=1.5, scale=1.05)), (1.0, GUARD)])),
        "attack_2": (8, False, 1.0, ["s"], ks([(0.0, GUARD),
                                                 (0.3, dict(GUARD, arm_l=(150.0, 40.0, 20.0), arm_r=(130.0, 10.0, 10.0), glow=1.9, head=(-15.0, 0.0, 0.0), jaw=0.9)),
                                                 (0.45, dict(GUARD, arm_l=(85.0, 10.0, 5.0), arm_r=(85.0, 10.0, 5.0), glow=2.2, scale=1.14, lean=16.0)),
                                                 (0.7, dict(GUARD, glow=1.5, scale=1.05)), (1.0, GUARD)])),
        "ability": (8, False, 1.1, ["s"], ks([(0.0, GUARD), (0.3, dict(GUARD, arm_r=(170.0, 15.0, 40.0), wpn_r=20.0, glow=1.8, lean=-6.0)),
                                                (0.48, dict(GUARD, arm_r=(70.0, 0.0, 0.0), wpn_r=80.0, glow=2.2, scale=1.12, lean=18.0, jaw=0.9)),
                                                (0.7, dict(GUARD, arm_r=(50.0, 5.0, 20.0), wpn_r=40.0, glow=1.5, scale=1.05)), (1.0, GUARD)])),
        # Se ríe con los brazos en alto: el bastón queda vertical (si no, se sale del cuadro).
        "taunt": (10, False, 1.6, ["s"], lambda t: dict(keyed(t, [(0.0, GUARD), (0.25, dict(GUARD, arm_l=(130.0, 60.0, 30.0), arm_r=(120.0, 35.0, 20.0), wpn_r=-70.0, head=(-25.0, 0.0, 0.0), glow=1.6)),
                                                                   (0.8, dict(GUARD, arm_l=(130.0, 60.0, 30.0), arm_r=(120.0, 35.0, 20.0), wpn_r=-70.0, head=(-25.0, 0.0, 0.0), glow=1.6)), (1.0, GUARD)]),
                                                          jaw=0.4 + 0.5 * abs(math.sin(4 * math.pi * t)), side=4.0 * math.sin(6 * math.pi * t))),
        "hit": (4, False, 0.45, ["s"], ks(hit_keys(GUARD, RECOIL))),
        "hit_2": (4, False, 0.45, ["s"], ks(hit_keys(GUARD, side_hit))),
        "death": (10, False, 1.4, ["s"], ks([(0.0, GUARD), (0.2, RECOIL), (0.55, dict(HEAP, lean=40.0, eyes=True, glow=0.9)), (0.8, HEAP), (1.0, dict(HEAP, scale=0.95))])),
        "spawn": (12, False, 1.5, ["s"], ks([(0.0, HEAP), (0.15, dict(HEAP, eyes=True, glow=1.0)), (0.5, dict(STAND, lean=30.0, lift=0.0, glow=1.3)),
                                              (0.8, dict(GUARD, lean=-10.0, arm_l=(120.0, 50.0, 30.0), arm_r=(110.0, 30.0, 30.0), jaw=0.9, lift=5.0)), (1.0, GUARD)])),
        "dormant": (1, True, 1.0, ["s"], lambda t: HEAP),
    }


FRAME = (160, 160)
FRAME_PIVOT = (80, 156)
# especie -> (función de primitivas, animaciones)
MONSTERS = {
    "esqueleto_picaro": (picaro, picaro_anims),
    "esqueleto_guardian": (guardian, guardian_anims),
    "nigromante": (nigromante, nigromante_anims),
}
ROLE_ORDER = ["idle", "walk", "combat", "attack", "attack_2", "hit", "hit_2", "death", "spawn", "dormant", "taunt", "ability"]


def build_species(species, preview_rows):
    build, anim_fn = MONSTERS[species]
    anims = anim_fn()
    frames = []      # (rgba, glow)
    meta_anims = {}
    for name in [n for n in ROLE_ORDER if n in anims]:
        count, loop, length, views, fn = anims[name]
        entry = {"loop": loop, "fps": round(count / length, 2), "dirs": {}}
        for d in views:
            for i in range(count):
                t = i / count if loop else (i / (count - 1) if count > 1 else 0.0)
                p = dict(fn(t))
                p["wind"] = t
                rgba, glow = render(build(p), VIEWS[d], p["scale"], p["shift"], p["lift"], p["eyes"], FRAME, FRAME_PIVOT)
                if rgba[0, :, 3].any() or rgba[:, 0, 3].any() or rgba[:, -1, 3].any():
                    print(f"  aviso: {species}/{name}/{d}/{i} toca el borde del cuadro")
                entry["dirs"].setdefault(d, []).append(len(frames))
                frames.append((rgba, glow))
        meta_anims[name] = entry
    # Recorte: todos los cuadros al rectángulo que usa la animación más ancha
    # (+1 px), así la hoja no guarda aire. El pivote se corre igual.
    alpha = np.zeros((FRAME[1], FRAME[0]), dtype=bool)
    for rgba, _ in frames:
        alpha |= rgba[..., 3] > 0
    ys, xs = np.nonzero(alpha)
    x0, x1 = max(0, xs.min() - 1), min(FRAME[0], xs.max() + 2)
    y0, y1 = max(0, ys.min() - 1), min(FRAME[1], ys.max() + 2)
    frames = [(rgba[y0:y1, x0:x1], glow[y0:y1, x0:x1]) for rgba, glow in frames]
    fw, fh = x1 - x0, y1 - y0
    pivot = [FRAME_PIVOT[0] - x0, FRAME_PIVOT[1] - y0]
    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    sheet = Image.new("RGBA", (COLUMNS * fw, rows * fh), (0, 0, 0, 0))
    glow_sheet = Image.new("L", (COLUMNS * fw, rows * fh), 0)
    for n, (rgba, glow) in enumerate(frames):
        x, y = (n % COLUMNS) * fw, (n // COLUMNS) * fh
        sheet.paste(Image.fromarray(rgba, "RGBA"), (x, y))
        glow_sheet.paste(Image.fromarray(np.where(glow, 255, 0).astype(np.uint8), "L"), (x, y))
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT_DIR / f"{species}.png", optimize=True)
    glow_sheet.save(OUT_DIR / f"{species}_glow.png", optimize=True)
    meta = {"version": 1, "sheet": f"{species}.png", "glow": f"{species}_glow.png", "frame": [int(fw), int(fh)],
            "columns": COLUMNS, "pivot": [int(pivot[0]), int(pivot[1])], "pixels_per_meter": PPM, "anims": meta_anims}
    (OUT_DIR / f"{species}.json").write_text(json.dumps(meta, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{species}: {len(frames)} cuadros de {fw}x{fh}, {len(meta_anims)} animaciones")
    if preview_rows is not None:
        for name, entry in meta_anims.items():
            cells = [Image.fromarray(frames[k][0], "RGBA") for k in entry["dirs"]["s"]]
            preview_rows.append(cells)
        idle = meta_anims["idle"]["dirs"]
        preview_rows.append([Image.fromarray(frames[idle[d][0]][0], "RGBA") for d in ALL_VIEWS if d in idle])


def save_preview(rows, path, zoom=2):
    fw = max(c.width for r in rows for c in r)
    fh = max(c.height for r in rows for c in r)
    width = max(len(r) for r in rows) * fw * zoom
    out = Image.new("RGBA", (width, len(rows) * fh * zoom), (92, 76, 64, 255))
    for r, cells in enumerate(rows):
        for c, cell in enumerate(cells):
            out.alpha_composite(cell.resize((fw * zoom, fh * zoom), Image.NEAREST), (c * fw * zoom, r * fh * zoom))
    out.save(path)
    print(f"vista previa: {path}")


def main(argv):
    only, preview = [], None
    for a in argv:
        if a.startswith("--only="):
            only = a.split("=", 1)[1].split(",")
        elif a.startswith("--preview="):
            preview = a.split("=", 1)[1]
    rows = [] if preview else None
    for species in MONSTERS:
        if only and species not in only:
            continue
        build_species(species, rows)
    if preview:
        save_preview(rows, preview)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

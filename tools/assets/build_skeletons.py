#!/usr/bin/env python3
"""Arma los cuerpos de los esqueletos enemigos con Blender como módulo de
Python (bpy). Es el paso 1 del pipeline; el paso 2 es process_enemies.mjs.

    <venv>/bin/python -I tools/assets/build_skeletons.py \
        --skeleton skeleton-realistic.blend --ual2 UAL2_Standard.glb \
        --ual1 UAL1_Standard.fbx --outfits ".../glTF (Godot-Unreal)/Outfits" \
        --out tools/assets/.work

Fuentes (todas CC0; de dónde bajarlas: tools/assets/README.md):
  --skeleton  .blend con la colección "Skeleton - Realistic" (Paul Kotelevets,
              Blender Human Base Meshes v1.4.1). 135 piezas, 66k triángulos,
              sin rig. Se exige que los metadatos del asset digan CC0.
  --ual2      Quaternius, Universal Animation Library 2 (rig de 65 huesos
              estilo Unreal: root, pelvis, spine_01..., Head, hand_r...).
  --ual1      Quaternius, Universal Animation Library 1, versión FBX con el
              MISMO rig. Se pasa a glTF tal cual (las rotaciones locales de
              los huesos coinciden con UAL2; solo el nodo "Armature" queda
              girado 180°, y process_enemies.mjs no copia sus canales).
  --outfits   carpeta con Male_Ranger.gltf (Quaternius, Modular Character
              Outfits - Fantasy): capucha, chaqueta y mangas del nigromante.

Qué hace, por variante (esqueleto común y nigromante):
  1. Quita la subdivisión y DECIMA las 135 piezas hasta ~--tris triángulos.
  2. Escala el esqueleto al alto del maniquí de UAL2 y encaja brazos y
     piernas en las articulaciones del rig (de pose A a pose T; húmero/fémur,
     antebrazo/pierna y mano/pie por tramos, estirando un poco cada hueso
     largo para que codo, rodilla, muñeca y tobillo caigan en los pivotes).
  3. Skinning RÍGIDO estilo PS1: cada pieza entera (peso 1) a un hueso de
     UAL2: por nombre (PIECE_BONES: cráneo -> Head, falanges -> dedos...) o,
     las vértebras, al segmento de hueso más cercano. Sin pesos mezclados:
     las piezas se mueven sueltas, como en un modelo de PS1.
  4. UV nuevas (smart project: las de origen se pisan entre piezas) y horneado
     con Cycles de oclusión ambiental y altura (los usa skeleton_textures.py
     para oscurecer uniones y ensuciar las piernas).
  5. Ojos: dos esferitas en el centro de las órbitas (objeto "Skeleton_Eyes";
     EnemyVisual les pone el material que brilla sin niebla).
  6. Nigromante: capucha + chaqueta + mangas del Ranger (ajustadas al reposo
     de UAL2, decimadas, con su skinning original) y una falda cónica
     generada hasta los tobillos. Se borran las piezas que tapa la ropa.
  7. Exporta <variante>_base.glb con TODAS las animaciones de UAL2 (el paso 2
     elige cuáles quedan) y ual1_anims.glb con las de UAL1.

Salidas en --out: ual1_anims.glb, esqueleto_base.glb, nigromante_base.glb,
esqueleto_ao.png, esqueleto_height.png, nigromante_ao.png,
nigromante_height.png, report.json (triángulos, alto, asignación de piezas).
"""
import argparse
import json
import math
import os
import sys
from collections import Counter

import bpy  # primero: con bpy como módulo, bmesh y mathutils vienen con él
import bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

PREFIX = "GEO-skeletion."
# Pieza (sin prefijo ni lado) -> hueso de UAL2 (sin lado). Las piezas de los
# costados (.L/.R) llevan _l/_r. Las que no están (vértebras) van al hueso
# cuyo segmento queda más cerca de su centroide.
PIECE_BONES = {
    "skull": "Head", "ripcage": "spine_03", "hip": "pelvis", "sacral": "pelvis", "coccygeal": "pelvis",
    "clavicle": "clavicle", "shoulder_scapula": "clavicle",
    "arm_humerus": "upperarm", "arm_radius": "lowerarm", "arm_ulna": "lowerarm", "hand_center": "hand",
    "metacarpal.index": "hand", "metacarpal.middle": "hand", "metacarpal.ring": "hand",
    "metacarpal.little": "hand", "metacarpal.thumb": "thumb_01",
    "proximal.thumb": "thumb_02", "distal.thumb": "thumb_03",
    "leg_femur": "thigh", "leg_patella": "thigh", "leg_tibula": "calf", "leg_fibula": "calf",
    "foot_talus": "foot", "foot_calcaneus": "foot", "foot_center": "foot",
}
FINGERS = {"index": "index", "middle": "middle", "ring": "ring", "little": "pinky"}
for _f, _b in FINGERS.items():
    PIECE_BONES[f"proximal.{_f}"] = f"{_b}_01"
    PIECE_BONES[f"middle.{_f}"] = f"{_b}_02"
    PIECE_BONES[f"distal.{_f}"] = f"{_b}_03"
for _n in range(1, 6):
    PIECE_BONES[f"metatarsal.{_n}"] = "foot"
    for _p in ("proximal", "middle", "distal"):
        PIECE_BONES[f"{_p}.{_n}"] = "ball"
# Cuadros por segundo de las claves de UAL1_Standard.fbx.
UAL1_FPS = 30
# Huesos del rig que no reciben piezas (control, IK, puntas).
SKIP_BONE_KEYS = ("root", "ik_", "twist", "_end", "leaf")

VARIANTS = {
    # Esqueleto común: las cuatro especies menos el jefe comparten el cuerpo
    # (cambian textura, ojos, armas y animaciones).
    "esqueleto": {"robe": False, "drop_bones": []},
    # Nigromante: túnica con capucha. Lo que tapa la ropa no se dibuja.
    "nigromante": {
        "robe": True,
        "drop_bones": ["pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r",
                       "upperarm_l", "upperarm_r", "thigh_l", "thigh_r"],
    },
}

# Piezas del traje Male_Ranger que se usan (el resto: piernas, botas,
# hombrera, brazaletes, cinturones, se descarta).
ROBE_PARTS = ["Male_Ranger_Head_Hood", "Male_Ranger_Body", "Male_Ranger_Arms"]
# En Male_Ranger_Arms la superficie 1 es la piel del maniquí (manos): fuera.
ROBE_DROP_MATERIAL = {"Male_Ranger_Arms": 1}
# Rectángulo del atlas del Ranger (UV de Blender, origen abajo a la izquierda)
# que cubre la falda: un paño grande de tela lisa.
SKIRT_UV_RECT = (0.03, 0.06, 0.22, 0.30)


def log(*a: object) -> None:
    print("[build_skeletons]", *a, flush=True)


def parse_args() -> argparse.Namespace:
    argv = sys.argv[1:]
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--skeleton", required=True, help=".blend con la colección del esqueleto")
    ap.add_argument("--collection", default="Skeleton - Realistic")
    ap.add_argument("--ual2", required=True, help="UAL2_Standard.glb")
    ap.add_argument("--ual1", required=True, help="UAL1_Standard.fbx (rig estilo Unreal)")
    ap.add_argument("--outfits", required=True, help="carpeta con Male_Ranger.gltf")
    ap.add_argument("--out", required=True, help="carpeta de trabajo")
    ap.add_argument("--tris", type=int, default=3300, help="triángulos objetivo del esqueleto entero")
    ap.add_argument("--robe-ratio", type=float, default=0.2, help="fracción de triángulos que conserva la ropa")
    ap.add_argument("--height", type=float, default=0.97, help="alto del esqueleto / alto del maniquí")
    ap.add_argument("--bake-size", type=int, default=256, help="lado de los mapas horneados (px)")
    ap.add_argument("--uv-angle", type=float, default=66.0,
                    help="ángulo límite del smart project (más alto = menos islas y menos vértices duplicados)")
    ap.add_argument("--variants", default=",".join(VARIANTS), help="variantes a armar (coma)")
    return ap.parse_args(argv)


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def scene() -> bpy.types.Scene:
    return bpy.context.scene


# --- UAL1: FBX -> glTF ----------------------------------------------------------------

def convert_ual1(fbx: str, out: str) -> None:
    reset()
    bpy.ops.import_scene.fbx(filepath=fbx)
    for a in bpy.data.actions:
        a.name = a.name.split("|")[-1]
    names = sorted(a.name for a in bpy.data.actions)
    # Las claves del FBX quedan en cuadros de 30 fps (Idle_Loop: 75 cuadros =
    # 2,5 s, como en la versión glTF del pack); con los 24 fps de la escena
    # vacía el exportador las estiraría un 25%.
    scene().render.fps = UAL1_FPS
    scene().render.fps_base = 1.0
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True, export_yup=True)
    log("UAL1 ->", out, len(names), "animaciones")


# --- Esqueleto --------------------------------------------------------------------------

def load_skeleton(path: str, coll_name: str) -> tuple[list[bpy.types.Object], dict]:
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        if coll_name not in src.collections:
            raise SystemExit(f"{path}: no tiene la colección '{coll_name}' (hay: {list(src.collections)[:20]})")
        dst.collections = [coll_name]
    coll = dst.collections[0]
    scene().collection.children.link(coll)
    ad = coll.asset_data
    meta = {
        "author": ad.author if ad else "",
        "license": ad.license if ad else "",
        "description": ad.description if ad else "",
    }
    log("asset:", meta)
    if "CC0" not in meta["license"].upper():
        raise SystemExit(f"la colección '{coll_name}' no declara licencia CC0: {meta}")
    parts = [o for o in coll.all_objects if o.type == "MESH"]
    for o in parts:
        if o.data.users > 1:
            o.data = o.data.copy()
        for m in list(o.modifiers):
            if m.type == "SUBSURF":
                o.modifiers.remove(m)
    return parts, meta


def eval_tris(objs: list[bpy.types.Object]) -> int:
    dg = bpy.context.evaluated_depsgraph_get()
    n = 0
    for o in objs:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        me.calc_loop_triangles()
        n += len(me.loop_triangles)
        ev.to_mesh_clear()
    return n


def bbox_world(objs: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            p = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def mesh_centroid(o: bpy.types.Object) -> Vector:
    vs = o.data.vertices
    if not vs:
        return o.matrix_world.translation.copy()
    return o.matrix_world @ (sum((v.co for v in vs), Vector()) / len(vs))


def import_ual2(path: str) -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    arm.data.pose_position = "REST"
    others = [o for o in new if o is not arm]
    return arm, others


class Rig:
    def __init__(self, arm: bpy.types.Object) -> None:
        self.arm = arm
        self.bones = {b.name: b for b in arm.data.bones}

    def head(self, name: str) -> Vector:
        return self.arm.matrix_world @ self.bones[name].head_local

    def tail(self, name: str) -> Vector:
        return self.arm.matrix_world @ self.bones[name].tail_local

    def candidates(self) -> list[str]:
        return [n for n in self.bones if not any(k in n for k in SKIP_BONE_KEYS)]


def fit_skeleton(parts: list[bpy.types.Object], rig: Rig, mannequin: list[bpy.types.Object], height_ratio: float) -> float:
    """Escala y ubica el esqueleto dentro del maniquí; brazos de pose A a T."""
    mlo, mhi = bbox_world(mannequin)
    slo, shi = bbox_world(parts)
    s = (mhi.z - mlo.z) / (shi.z - slo.z) * height_ratio
    cen = Vector(((slo.x + shi.x) / 2, (slo.y + shi.y) / 2, slo.z))
    to_rig = Matrix.Translation(Vector((0, 0, mlo.z))) @ Matrix.Scale(s, 4) @ Matrix.Translation(-cen)
    for o in parts:
        if o.parent is None:
            o.matrix_world = to_rig @ o.matrix_world
    bpy.context.view_layer.update()
    # Profundidad: la pelvis del esqueleto sobre el hueso pelvis del rig.
    hip = bpy.data.objects.get(PREFIX + "hip")
    if hip is not None:
        dy = rig.head("pelvis").y - mesh_centroid(hip).y
        for o in parts:
            if o.parent is None:
                o.matrix_world = Matrix.Translation(Vector((0, dy, 0))) @ o.matrix_world
        bpy.context.view_layer.update()
    for side in ("L", "R"):
        align_arm(side, rig)
        align_leg(side, rig)
    return s


def piece(name: str) -> bpy.types.Object:
    return bpy.data.objects[PREFIX + name]


def long_axis(o: bpy.types.Object, near: Vector) -> tuple[Vector, Vector]:
    """Extremos de una pieza larga (húmero, radio...) a lo largo de su eje
    principal: primero el más cercano a `near` (el proximal), después el otro."""
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    c = sum(vs, Vector()) / len(vs)
    cov = Matrix(((0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))
    for v in vs:
        d = v - c
        cov += Matrix(((d.x * d.x, d.x * d.y, d.x * d.z), (d.y * d.x, d.y * d.y, d.y * d.z), (d.z * d.x, d.z * d.y, d.z * d.z)))
    axis = Vector((0.3, 0.5, 0.8))
    for _ in range(40):
        axis = (cov @ axis).normalized()
    ts = [(v - c).dot(axis) for v in vs]
    a, b = c + axis * min(ts), c + axis * max(ts)
    return (a, b) if (a - near).length < (b - near).length else (b, a)


def rotate_about(objs: list[bpy.types.Object], pivot: Vector, rot: Matrix) -> None:
    m = Matrix.Translation(pivot) @ rot.to_4x4() @ Matrix.Translation(-pivot)
    for o in objs:
        o.matrix_world = m @ o.matrix_world
    bpy.context.view_layer.update()


def frame(along: Vector, across: Vector) -> Matrix:
    y = along.normalized()
    x = (across - y * across.dot(y)).normalized()
    return Matrix((x, y, x.cross(y))).transposed()


def stretch_mesh(o: bpy.types.Object, origin: Vector, axis: Vector, k: float) -> None:
    """Estira la MALLA (no el objeto: los hijos no se enteran) a lo largo de `axis`."""
    mw = o.matrix_world
    inv = mw.inverted()
    for v in o.data.vertices:
        w = mw @ v.co
        v.co = inv @ (w + axis * ((w - origin).dot(axis) * (k - 1.0)))
    o.data.update()


def translate(objs: list[bpy.types.Object], d: Vector) -> None:
    for o in objs:
        o.matrix_world = Matrix.Translation(d) @ o.matrix_world
    bpy.context.view_layer.update()


def fit_limb(upper: bpy.types.Object, lower: list[bpy.types.Object], end: bpy.types.Object,
             j0: Vector, j1: Vector, j2: Vector) -> tuple[Vector, Vector, Vector]:
    """Encaja un miembro en tres articulaciones del rig (j0 hombro/cadera, j1
    codo/rodilla, j2 muñeca/tobillo). `upper` (húmero/fémur) gira sobre su
    extremo proximal (queda pegado al tronco) y se estira hasta j1; `lower`
    (radio+cúbito / tibia+peroné, el primero manda) se lleva a j1, se orienta
    hacia j2 y se estira hasta j2; `end` (mano/pie) se lleva a j2. Así los
    pivotes del rig caen en las articulaciones de la malla (sin eso, al
    doblar el codo el antebrazo gira 5-7 cm corrido). Devuelve los extremos
    de la malla antes del ajuste, para el registro."""
    a0, a1 = long_axis(upper, j0)
    rotate_about([upper], a0, (a1 - a0).rotation_difference(j1 - a0).to_matrix())
    a0, a1 = long_axis(upper, a0)
    axis = (a1 - a0).normalized()
    stretch_mesh(upper, a0, axis, (j1 - a0).length / max((a1 - a0).length, 1e-6))
    main = lower[0]
    b0, b1 = long_axis(main, a1)
    roots = [o for o in lower if o.parent not in lower]
    translate(roots, j1 - b0)
    b0, b1 = long_axis(main, j1)
    rotate_about(roots, j1, (b1 - b0).rotation_difference(j2 - j1).to_matrix())
    b0, b1 = long_axis(main, j1)
    old_end = b1.copy()
    axis = (b1 - b0).normalized()
    k = (j2 - b0).length / max((b1 - b0).length, 1e-6)
    for o in lower:
        stretch_mesh(o, b0, axis, k)
    translate([end], j2 - old_end)
    return a0, a1, old_end


def align_arm(side: str, rig: Rig) -> None:
    """De pose A a la pose T del rig: húmero, radio+cúbito y mano encajados en
    las articulaciones del rig; después la mano (palma y dedos) se gira sobre
    el marco de hand (importa para que el arma quede en el puño)."""
    sl = side.lower()
    hand = piece(f"hand_center.{side}")
    j0, j1, j2 = rig.head(f"upperarm_{sl}"), rig.head(f"lowerarm_{sl}"), rig.head(f"hand_{sl}")
    a0, a1, w = fit_limb(piece(f"arm_humerus.{side}"), [piece(f"arm_radius.{side}"), piece(f"arm_ulna.{side}")], hand, j0, j1, j2)
    along_s = mesh_centroid(piece(f"proximal.middle.{side}")) - mesh_centroid(hand)
    across_s = mesh_centroid(piece(f"metacarpal.index.{side}")) - mesh_centroid(piece(f"metacarpal.little.{side}"))
    along_r = rig.head(f"middle_01_{sl}") - j2
    across_r = rig.head(f"index_01_{sl}") - rig.head(f"pinky_01_{sl}")
    rotate_about([hand], j2, frame(along_r, across_r) @ frame(along_s, across_s).transposed())
    log(f"brazo {side}: hombro a {round((a0 - j0).length, 3)} m del rig; antes del ajuste, codo a",
        f"{round((a1 - j1).length, 3)} m y muñeca a {round((w - j2).length, 3)} m")


def align_leg(side: str, rig: Rig) -> None:
    sl = side.lower()
    foot = piece(f"foot_talus.{side}")
    j0, j1, j2 = rig.head(f"thigh_{sl}"), rig.head(f"calf_{sl}"), rig.head(f"foot_{sl}")
    lower = [piece(f"leg_tibula.{side}"), piece(f"leg_fibula.{side}")]
    a0, a1, w = fit_limb(piece(f"leg_femur.{side}"), lower, foot, j0, j1, j2)
    # El pie apunta del tobillo a la base de los dedos, como el hueso foot.
    along_s = mesh_centroid(piece(f"proximal.3.{side}")) - j2
    along_s.z = 0.0
    along_r = rig.head(f"ball_{sl}") - j2
    along_r.z = 0.0
    rotate_about([foot], j2, along_s.rotation_difference(along_r).to_matrix())
    log(f"pierna {side}: cadera a {round((a0 - j0).length, 3)} m del rig; antes del ajuste, rodilla a",
        f"{round((a1 - j1).length, 3)} m y tobillo a {round((w - j2).length, 3)} m")


def seg_dist(p: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (a + ab * t - p).length


def assign_bones(parts: list[bpy.types.Object], rig: Rig) -> dict[str, str]:
    cands = rig.candidates()
    assign: dict[str, str] = {}
    for o in parts:
        short = o.name[len(PREFIX):] if o.name.startswith(PREFIX) else o.name
        side = None
        if short.endswith((".L", ".R")):
            side = short[-1].lower()
            short = short[:-2]
        bone = PIECE_BONES.get(short)
        if bone is not None:
            bone = f"{bone}_{side}" if side else bone
            if bone in rig.bones:
                assign[o.name] = bone
                continue
        c = mesh_centroid(o)
        side = "l" if o.name.endswith(".L") else "r" if o.name.endswith(".R") else None
        pool = [n for n in cands if side is None or not n.endswith(("_l", "_r")) or n.endswith("_" + side)]
        assign[o.name] = min(pool, key=lambda n: seg_dist(c, rig.head(n), rig.tail(n)))
    return assign


def find_eyes(skull: bpy.types.Object) -> tuple[Vector, Vector, float]:
    """Centro de cada órbita, con rayos desde el frente (-Y) sobre la cara: un
    mapa de profundidad donde las órbitas son los huecos (más hondos que el
    borde: frente, pómulos) a cada lado de la nariz. El ojo va al centroide de
    cada hueco, poco detrás del borde, para que se vea de frente y de tres
    cuartos (y no quede dentro del cráneo, donde pasan rayos por las fisuras)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = skull.evaluated_get(dg)
    me = ev.to_mesh()
    verts = [skull.matrix_world @ v.co for v in me.vertices]
    me.calc_loop_triangles()
    tris = [tuple(t.vertices) for t in me.loop_triangles]
    ev.to_mesh_clear()
    bvh = BVHTree.FromPolygons(verts, tris)
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    w, d, h = hi.x - lo.x, hi.y - lo.y, hi.z - lo.z
    cx = (lo.x + hi.x) / 2
    steps = 48
    xs = [cx - w * 0.42 + w * 0.84 * i / steps for i in range(steps + 1)]
    zs = [lo.z + h * (0.3 + 0.6 * j / steps) for j in range(steps + 1)]
    depth: list[list[float | None]] = []
    for x in xs:
        col: list[float | None] = []
        for z in zs:
            hit = bvh.ray_cast(Vector((x, lo.y - 0.1, z)), Vector((0, 1, 0)))
            col.append(None if hit[0] is None else hit[0].y - lo.y)
        depth.append(col)
    # Hueco = más hondo que lo más saliente de arriba (la ceja) Y de abajo (el
    # pómulo) en la misma columna. Las sienes son hondas de arriba abajo: no.
    eyes = []
    for side in (0, 1):
        best: list[tuple[float, float, float, float]] = []
        for i, x in enumerate(xs):
            if abs(x - cx) < w * 0.08 or (x < cx) != (side == 0):
                continue
            col = depth[i]
            for j, dd in enumerate(col):
                if dd is None:
                    continue
                above = [v for v in col[j + 1:] if v is not None]
                below = [v for v in col[:j] if v is not None]
                if not above or not below:
                    continue
                score = dd - max(min(above), min(below))
                best.append((score, x, zs[j], max(min(above), min(below))))
        best.sort(reverse=True)
        top = [b for b in best if b[0] > best[0][0] * 0.6][:40]
        if not top or best[0][0] < d * 0.05:
            raise SystemExit("no encontré las órbitas del cráneo")
        ex = sum(b[1] for b in top) / len(top)
        ez = sum(b[2] for b in top) / len(top)
        rim = sum(b[3] for b in top) / len(top)
        eyes.append(Vector((ex, lo.y + rim + d * 0.06, ez)))
    log("órbitas:", [tuple(round(v, 3) for v in e) for e in eyes], "cráneo", round(w, 3), round(d, 3), round(h, 3))
    # Simétricos.
    dx = (abs(eyes[0].x - cx) + abs(eyes[1].x - cx)) / 2
    ey = (eyes[0].y + eyes[1].y) / 2
    ez = (eyes[0].z + eyes[1].z) / 2
    # Llenan casi toda la órbita: a 240 líneas, dos puntos chicos se pierden.
    r = w * 0.095
    return Vector((cx - dx, ey, ez)), Vector((cx + dx, ey, ez)), r


def build_rigid_mesh(parts: list[bpy.types.Object], assign: dict[str, str], name: str) -> bpy.types.Object:
    dg = bpy.context.evaluated_depsgraph_get()
    bm_all = bmesh.new()
    groups = []
    for o in parts:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        me.transform(o.matrix_world)
        if o.matrix_world.determinant() < 0:
            # Las piezas espejadas (escala negativa) quedan del revés al
            # hornear la matriz: se dan vuelta las caras.
            me.flip_normals()
        n0 = len(bm_all.verts)
        bm_all.from_mesh(me)
        ev.to_mesh_clear()
        groups.append((assign[o.name], n0, len(bm_all.verts)))
    mesh = bpy.data.meshes.new(name)
    bm_all.to_mesh(mesh)
    bm_all.free()
    for uv in list(mesh.uv_layers):
        mesh.uv_layers.remove(uv)
    mesh.uv_layers.new(name="UVMap")
    ob = bpy.data.objects.new(name, mesh)
    scene().collection.objects.link(ob)
    for gname, a, b in groups:
        vg = ob.vertex_groups.get(gname) or ob.vertex_groups.new(name=gname)
        vg.add(list(range(a, b)), 1.0, "REPLACE")
    # Sombreado suave (Gouraud, como la PS1): además no duplica vértices por
    # cara. Fuera aristas "sharp" y normales propias del original.
    smooth_all(mesh)
    return ob


def smooth_all(mesh: bpy.types.Mesh) -> None:
    for name in ("sharp_edge", "sharp_face"):
        if name in mesh.attributes:
            mesh.attributes.remove(mesh.attributes[name])
    for p in mesh.polygons:
        p.use_smooth = True


def make_eyes(left: Vector, right: Vector, r: float) -> bpy.types.Object:
    bm = bmesh.new()
    for c in (left, right):
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r, matrix=Matrix.Translation(c))
    mesh = bpy.data.meshes.new("Skeleton_Eyes")
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new("Skeleton_Eyes", mesh)
    scene().collection.objects.link(ob)
    vg = ob.vertex_groups.new(name="Head")
    vg.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    mat = bpy.data.materials.new("Ojos")
    mat.diffuse_color = (1, 1, 1, 1)
    mesh.materials.append(mat)
    return ob


def bind(ob: bpy.types.Object, arm: bpy.types.Object) -> None:
    mw = ob.matrix_world.copy()
    ob.parent = arm
    ob.matrix_world = mw
    for m in list(ob.modifiers):
        if m.type == "ARMATURE":
            ob.modifiers.remove(m)
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def ensure_nodes(mat: bpy.types.Material) -> None:
    # Blender 5 crea los materiales con nodos; use_nodes queda para versiones viejas.
    if mat.node_tree is None:
        mat.use_nodes = True


def apply_modifier(ob: bpy.types.Object, mod_name: str) -> None:
    with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob]):
        bpy.ops.object.modifier_apply(modifier=mod_name)


def smart_uv(ob: bpy.types.Object, angle: float, margin: float = 0.01) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    ob.select_set(False)


# --- Túnica (nigromante) -----------------------------------------------------------------

def import_robe(outfits: str, rig: Rig, ratio: float) -> tuple[list[bpy.types.Object], bpy.types.Image]:
    path = os.path.join(outfits, "Male_Ranger.gltf")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    arm_o = next(o for o in new if o.type == "ARMATURE")
    # El traje trae su propia copia del rig (mismos 65 huesos, mismo "roll"),
    # pero con las proporciones del cuerpo base de Quaternius: brazos ~7 cm
    # más cortos, la columna algo más inclinada. Para pasarle el skinning tal
    # cual al rig de UAL2, primero se lo deforma a ESE reposo: cada hueso del
    # traje se posa sobre el marco de reposo del mismo hueso de UAL2 y se
    # aplica la deformación a la malla.
    dev = 0.0
    for b in arm_o.data.bones:
        if b.name in rig.bones:
            dev = max(dev, ((arm_o.matrix_world @ b.head_local) - rig.head(b.name)).length)
    log("traje: desvío máximo del rig", round(dev, 4), "m (se ajusta)")
    if arm_o.animation_data:
        arm_o.animation_data.action = None
    arm_o.data.pose_position = "POSE"

    def depth(b: bpy.types.Bone) -> int:
        d = 0
        while b.parent:
            b = b.parent
            d += 1
        return d

    to_local = arm_o.matrix_world.inverted() @ rig.arm.matrix_world
    for pb in arm_o.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    for pb in sorted(arm_o.pose.bones, key=lambda p: depth(p.bone)):
        if pb.name in rig.bones:
            pb.matrix = to_local @ rig.bones[pb.name].matrix_local
            bpy.context.view_layer.update()
    keep = []
    for o in new:
        if o.type != "MESH":
            continue
        if o.name not in ROBE_PARTS:
            continue
        keep.append(o)
    for o in new:
        if o not in keep and o is not arm_o:
            bpy.data.objects.remove(o)
    # El atlas de color (no el normal map, que el pack Standard no trae).
    robe_path = os.path.join(outfits, "T_Ranger_BaseColor.png")
    robe_img = bpy.data.images.load(robe_path, check_existing=True) if os.path.exists(robe_path) else None
    if robe_img is None or robe_img.size[0] == 0:
        raise SystemExit("no encontré la textura del Ranger (T_Ranger_BaseColor.png)")
    for o in keep:
        drop = ROBE_DROP_MATERIAL.get(o.name)
        if drop is not None:
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index == drop], context="FACES")
            bm.to_mesh(o.data)
            bm.free()
        # Hornear el ajuste de proporciones (la pose de arriba) en la malla.
        for m in list(o.modifiers):
            if m.type == "ARMATURE" and m.object == arm_o:
                apply_modifier(o, m.name)
        # Decimar con el skinning original (los pesos se interpolan) y atar al rig de UAL2.
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        d = o.modifiers.new("dec", "DECIMATE")
        d.ratio = ratio
        apply_modifier(o, "dec")
        bind(o, rig.arm)
    bpy.data.objects.remove(arm_o)
    return keep, robe_img


def make_skirt(rig: Rig, body: bpy.types.Object) -> bpy.types.Object:
    """Falda cónica de la cintura a los tobillos (la chaqueta del Ranger llega
    a la cadera). Pesos: arriba la pelvis; abajo cada lado sigue a su pierna."""
    vs = [body.matrix_world @ v.co for v in body.data.vertices]
    z_hip = rig.head("pelvis").z
    band = [v for v in vs if abs(v.z - (z_hip + 0.03)) < 0.06] or vs
    x0 = min(v.x for v in band)
    x1 = max(v.x for v in band)
    y0 = min(v.y for v in band)
    y1 = max(v.y for v in band)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    rx, ry = (x1 - x0) / 2 * 0.92, (y1 - y0) / 2 * 0.92
    z_top = z_hip + 0.06
    z_bot = (rig.head("foot_l").z + rig.head("ball_l").z) / 2 + 0.02
    z_knee = rig.head("calf_l").z
    segs, rings = 14, 5
    bm = bmesh.new()
    uv_l = bm.loops.layers.uv.new("UVMap")
    names = ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r"]
    weights: list[dict[str, float]] = []
    u0, v0, u1, v1 = SKIRT_UV_RECT
    # Dos cáscaras (afuera y adentro, con sus propios vértices): el material
    # PSX descarta las caras traseras y desde abajo se vería hueca.
    for shell in range(2):
        grid = []
        for k in range(rings):
            t = k / (rings - 1)
            z = z_top + (z_bot - z_top) * t
            flare = 1.0 + 0.6 * t ** 1.3
            row = []
            for i in range(segs):
                a = 2 * math.pi * i / segs
                row.append(bm.verts.new((cx + math.sin(a) * rx * flare, cy - math.cos(a) * ry * flare, z)))
                side = 0.5 + 0.5 * max(-1.0, min(1.0, math.sin(a) * 1.4))  # 1 = izquierda (x+)
                wp = (1.0 - t) ** 1.6
                legs = 1.0 - wp
                upper = 1.0 if z > z_knee else max(0.0, 1.0 - (z_knee - z) / 0.2)
                weights.append({
                    "pelvis": wp,
                    "thigh_l": legs * side * upper, "thigh_r": legs * (1 - side) * upper,
                    "calf_l": legs * side * (1 - upper), "calf_r": legs * (1 - side) * (1 - upper),
                })
            grid.append(row)
        for k in range(rings - 1):
            for i in range(segs):
                quad = [(grid[k][i], i, k), (grid[k + 1][i], i, k + 1),
                        (grid[k + 1][(i + 1) % segs], i + 1, k + 1), (grid[k][(i + 1) % segs], i + 1, k)]
                if shell == 1:
                    quad.reverse()
                f = bm.faces.new([q[0] for q in quad])
                for loop, (_v, ui, vk) in zip(f.loops, quad):
                    loop[uv_l].uv = (u0 + (u1 - u0) * ui / segs, v1 - (v1 - v0) * vk / (rings - 1))
    mesh = bpy.data.meshes.new("Robe_Skirt")
    bm.to_mesh(mesh)
    bm.free()
    ob = bpy.data.objects.new("Robe_Skirt", mesh)
    scene().collection.objects.link(ob)
    groups = {n: ob.vertex_groups.new(name=n) for n in names}
    for idx, w in enumerate(weights):
        tot = sum(w.values())
        for n, val in w.items():
            if val > 1e-4:
                groups[n].add([idx], val / tot, "REPLACE")
    return ob


# --- Horneado (Cycles) -------------------------------------------------------------------

def bake_maps(ob: bpy.types.Object, ao_path: str, height_path: str, size: int, height: float) -> bpy.types.Image:
    sc = scene()
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    if sc.world is None:
        sc.world = bpy.data.worlds.new("Mundo")
    sc.world.light_settings.distance = 0.06
    img_ao = bpy.data.images.new("skeleton_texture", size, size, alpha=False)
    img_ao.colorspace_settings.name = "Non-Color"
    img_h = bpy.data.images.new("height_bake", size, size, alpha=False)
    img_h.colorspace_settings.name = "Non-Color"
    mat = bpy.data.materials.new("Hueso")
    ensure_nodes(mat)
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img_ao
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    nt.nodes.active = tex
    bpy.ops.object.bake(type="AO", margin=max(2, size // 64), use_clear=True)
    img_ao.filepath_raw = ao_path
    img_ao.file_format = "PNG"
    img_ao.save()
    # Altura (0 = pies, 1 = cabeza) como emisión: ensuciar de abajo hacia arriba.
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.0
    mr.inputs["From Max"].default_value = height
    emit = nt.nodes.new("ShaderNodeEmission")
    out = nt.nodes.get("Material Output")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
    nt.links.new(mr.outputs["Result"], emit.inputs["Color"])
    nt.links.new(emit.outputs[0], out.inputs["Surface"])
    tex.image = img_h
    nt.nodes.active = tex
    bpy.ops.object.bake(type="EMIT", margin=max(2, size // 64), use_clear=True)
    img_h.filepath_raw = height_path
    img_h.file_format = "PNG"
    img_h.save()
    # Material final: textura (la reemplaza process_enemies.mjs) sobre el color base.
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    tex.image = img_ao
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    ob.select_set(False)
    return img_ao


# --- Variante completa ---------------------------------------------------------------------

def build_variant(name: str, cfg: dict, args: argparse.Namespace) -> dict:
    reset()
    parts, meta = load_skeleton(args.skeleton, args.collection)
    arm, ual_meshes = import_ual2(args.ual2)
    rig = Rig(arm)
    mannequin = [o for o in ual_meshes if o.type == "MESH" and o.find_armature() == arm] or [o for o in ual_meshes if o.type == "MESH"]
    full_tris = eval_tris(parts)
    ratio = min(1.0, args.tris / max(full_tris, 1))
    for o in parts:
        d = o.modifiers.new("dec", "DECIMATE")
        d.ratio = ratio
    scale = fit_skeleton(parts, rig, mannequin, args.height)
    assign = assign_bones(parts, rig)
    skull = bpy.data.objects[PREFIX + "skull"]
    eye_l, eye_r, eye_r_size = find_eyes(skull)
    drop = set(cfg["drop_bones"])
    kept = [o for o in parts if assign[o.name] not in drop]
    bones_used = dict(Counter(assign[o.name] for o in kept))
    n_parts, n_kept = len(parts), len(kept)
    body = build_rigid_mesh(kept, assign, "Skeleton_Body")
    eyes = make_eyes(eye_l, eye_r, eye_r_size)
    mlo, mhi = bbox_world(mannequin)
    for o in parts + ual_meshes:
        if o.name in bpy.data.objects:
            bpy.data.objects.remove(o)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    smart_uv(body, args.uv_angle)
    bind(body, arm)
    bind(eyes, arm)
    robe_tris = 0
    if cfg["robe"]:
        robe, robe_img = import_robe(args.outfits, rig, args.robe_ratio)
        torso = next(o for o in robe if o.name == "Male_Ranger_Body")
        skirt = make_skirt(rig, torso)
        bind(skirt, arm)
        robe.append(skirt)
        mat = bpy.data.materials.new("Tunica")
        ensure_nodes(mat)
        nt = mat.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        robe_img.name = "robe_texture"
        tex.image = robe_img
        nt.links.new(tex.outputs["Color"], nt.nodes.get("Principled BSDF").inputs["Base Color"])
        for o in robe:
            o.data.materials.clear()
            o.data.materials.append(mat)
            for p in o.data.polygons:
                p.use_smooth = True
            o.data.calc_loop_triangles()
            robe_tris += len(o.data.loop_triangles)
    height = mhi.z - mlo.z
    bake_maps(body, os.path.join(args.out, f"{name}_ao.png"), os.path.join(args.out, f"{name}_height.png"), args.bake_size, height)
    arm.data.pose_position = "POSE"
    if arm.animation_data:
        arm.animation_data.action = None
    body.data.calc_loop_triangles()
    eyes.data.calc_loop_triangles()
    out = os.path.join(args.out, f"{name}_base.glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_skins=True, export_yup=True,
                              export_apply=False)
    info = {
        "source_tris_no_subsurf": full_tris,
        "decimate_ratio": round(ratio, 4),
        "body_tris": len(body.data.loop_triangles),
        "eye_tris": len(eyes.data.loop_triangles),
        "robe_tris": robe_tris,
        "pieces": n_kept,
        "pieces_dropped": n_parts - n_kept,
        "skeleton_scale": round(scale, 5),
        "rig_height_m": round(height, 4),
        "bones_used": bones_used,
        "asset": meta,
    }
    log(name, "->", out, json.dumps({k: v for k, v in info.items() if k != "bones_used"}))
    return info


def main() -> None:
    args = parse_args()
    os.makedirs(args.out, exist_ok=True)
    report = {}
    convert_ual1(args.ual1, os.path.join(args.out, "ual1_anims.glb"))
    for name in [v for v in args.variants.split(",") if v]:
        report[name] = build_variant(name, VARIANTS[name], args)
    with open(os.path.join(args.out, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    log("listo:", args.out)


if __name__ == "__main__":
    main()

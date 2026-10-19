// Adapta los esqueletos CC0 de KayKit al estilo PSX/Lunacid del juego.
//
//   cd tools/assets && npm install && node process_enemies.mjs [ruta_al_pack]
//
// Por cada enemigo: conserva SOLO las animaciones que usa el juego (de 95),
// reemplaza la textura por una versión de 64 px recoloreada (recolor_texture.py),
// simplifica la malla (polígonos "antiguos", siluetas más toscas) y escribe un
// .glb chico en assets/enemies/. Las armas se procesan igual.
//
// Fuente: KayKit Character Pack: Skeletons 1.0 (Kay Lousberg, CC0)
// https://github.com/KayKit-Game-Assets/kaykit-character-pack-skeletons-1.0

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO } from '@gltf-transform/core';
import { dedup, prune, resample, simplify, weld } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = path.resolve(HERE, '..', '..');
const PACK = process.argv[2] ?? '/home/user/kaykit-game-assets/kaykit-character-pack-skeletons-1.0/addons/kaykit_character_pack_skeletons';
const OUT = path.join(PROJECT, 'assets', 'enemies');
const TMP = path.join(HERE, '.tmp');

// Animaciones comunes a todos (estados del juego) + las de ataque de cada uno.
const COMMON = [
  'Idle', 'Idle_Combat', 'Walking_D_Skeletons', 'Hit_A', 'Hit_B',
  'Death_C_Skeletons', 'Spawn_Ground_Skeletons', 'Skeletons_Inactive_Floor_Pose',
];

const ENEMIES = [
  { id: 'esqueleto_esbirro', src: 'Skeleton_Minion', hue: 95, accentSat: 0.4,
    anims: ['1H_Melee_Attack_Chop', '1H_Melee_Attack_Slice_Diagonal'] },
  { id: 'esqueleto_picaro', src: 'Skeleton_Rogue', hue: 205, accentSat: 0.4,
    anims: ['1H_Ranged_Shoot', '1H_Ranged_Aiming', 'Dodge_Backward'] },
  { id: 'esqueleto_guardian', src: 'Skeleton_Warrior', hue: 18, accentSat: 0.5,
    anims: ['1H_Melee_Attack_Slice_Horizontal', 'Block', 'Block_Hit', 'Block_Attack'] },
  { id: 'nigromante', src: 'Skeleton_Mage', hue: 280, accentSat: 0.55,
    anims: ['Spellcast_Shoot', 'Spellcast_Summon', 'Spellcasting', 'Taunt'] },
];

const WEAPONS = [
  { id: 'hoja', src: 'Skeleton_Blade', hue: 95 },
  { id: 'ballesta', src: 'Skeleton_Crossbow', hue: 205 },
  { id: 'hacha', src: 'Skeleton_Axe', hue: 18 },
  { id: 'escudo', src: 'Skeleton_Shield_Large_A', hue: 18 },
  { id: 'baculo', src: 'Skeleton_Staff', hue: 280 },
];

// Fracción de índices que se conserva al simplificar (polígonos "antiguos").
// El error alto deja que el simplificador cruce costuras de UV: siluetas
// más toscas, como un modelo de PS1.
const SIMPLIFY_RATIO = 0.4;
const SIMPLIFY_ERROR = 0.02;
// Las animaciones se re-muestrean a 12 fps (movimiento entrecortado de PS1,
// y archivos mucho más chicos). El juego además las reproduce a pasos.
const ANIM_FPS = 12;

/** Deja solo una clave cada 1/ANIM_FPS s (más la última) en cada canal. */
function decimateKeys(doc) {
  const step = 1 / ANIM_FPS;
  for (const anim of doc.getRoot().listAnimations()) {
    for (const sampler of anim.listSamplers()) {
      const input = sampler.getInput();
      const output = sampler.getOutput();
      if (!input || !output || sampler.getInterpolation() === 'CUBICSPLINE') continue;
      const times = input.getArray();
      const comps = output.getElementSize();
      const vals = output.getArray();
      const keepT = [];
      const keepV = [];
      let next = -Infinity;
      for (let i = 0; i < times.length; i++) {
        const last = i === times.length - 1;
        if (times[i] + 1e-6 >= next || last) {
          keepT.push(times[i]);
          for (let c = 0; c < comps; c++) keepV.push(vals[i * comps + c]);
          next = times[i] + step;
        }
      }
      input.setArray(new Float32Array(keepT));
      output.setArray(new Float32Array(keepV));
    }
  }
}

const io = new NodeIO();

function recolor(id, hue, accentSat, seed) {
  const out = path.join(TMP, `${id}.png`);
  execFileSync('python3', [
    path.join(HERE, 'recolor_texture.py'), path.join(PACK, 'Textures', 'skeleton_texture.png'), out,
    '--hue', String(hue), '--accent-sat', String(accentSat ?? 0.45), '--seed', String(seed), '--size', '64',
  ]);
  return fs.readFileSync(out);
}

async function adapt(src, dst, { keepAnims = null, texture, simplifyMesh = true }) {
  const doc = await io.read(src);
  const root = doc.getRoot();
  if (keepAnims) {
    for (const anim of root.listAnimations()) {
      if (keepAnims.includes(anim.getName())) continue;
      // dispose() de la animación no suelta sus samplers/canales: sin esto
      // prune() no puede borrar los accessors de las 85 animaciones descartadas.
      for (const c of anim.listChannels()) c.dispose();
      for (const smp of anim.listSamplers()) smp.dispose();
      anim.dispose();
    }
    const missing = keepAnims.filter((n) => !root.listAnimations().some((a) => a.getName() === n));
    if (missing.length) throw new Error(`${path.basename(src)}: faltan animaciones ${missing.join(', ')}`);
  }
  if (keepAnims) decimateKeys(doc);
  for (const tex of root.listTextures()) {
    tex.setImage(texture).setMimeType('image/png').setURI('');
  }
  const steps = [resample(), weld()];
  if (simplifyMesh) {
    await MeshoptSimplifier.ready;
    steps.push(simplify({ simplifier: MeshoptSimplifier, ratio: SIMPLIFY_RATIO, error: SIMPLIFY_ERROR }));
  }
  steps.push(prune(), dedup());
  await doc.transform(...steps);
  await io.write(dst, doc);
  const tris = root.listMeshes().reduce((n, m) => n + m.listPrimitives().reduce((k, p) => k + (p.getIndices()?.getCount() ?? 0) / 3, 0), 0);
  console.log(`${path.basename(dst)}: ${root.listAnimations().length} anims, ${Math.round(tris)} tris, ${(fs.statSync(dst).size / 1024).toFixed(0)} KB`);
}

fs.mkdirSync(path.join(OUT, 'weapons'), { recursive: true });
fs.mkdirSync(TMP, { recursive: true });

let seed = 1;
for (const e of ENEMIES) {
  await adapt(path.join(PACK, 'Characters', 'gltf', `${e.src}.glb`), path.join(OUT, `${e.id}.glb`), {
    keepAnims: [...COMMON, ...e.anims],
    texture: recolor(e.id, e.hue, e.accentSat, seed++),
  });
}
for (const w of WEAPONS) {
  await adapt(path.join(PACK, 'Assets', 'gltf', `${w.src}.gltf`), path.join(OUT, 'weapons', `${w.id}.glb`), {
    texture: recolor(`arma_${w.id}`, w.hue, 0.45, seed++),
    simplifyMesh: false,
  });
}
fs.rmSync(TMP, { recursive: true, force: true });

// Paso 2 del pipeline de enemigos: arma assets/enemies/<id>.glb a partir de los
// intermedios de build_skeletons.py (paso 1, Blender). Ver tools/assets/README.md.
//
//   cd tools/assets && npm ci && node process_enemies.mjs [--work .work] [--kaykit <pack>]
//
// Por enemigo:
//   - Cuerpo: <base>_base.glb (esqueleto realista con skinning rígido al rig de
//     UAL2; el nigromante con su túnica). Se le sacan los atributos que no usa
//     el juego (colores de vértice del traje, segundo juego de UV).
//   - Animaciones: SOLO las que nombra data/species.json (visual.anims de esa
//     especie), armadas según la tabla CLIPS: de UAL2 (vienen en el
//     cuerpo) o de UAL1 (ual1_anims.glb, mismo rig: se copian los canales por
//     nombre de hueso; los del nodo "Armature" no, porque el FBX de UAL1 lo
//     trae girado 180°). Se pueden encadenar clips (golpe + recuperación) y
//     sacar una pose quieta (el primer cuadro de LayToIdle = tirado en el piso).
//     Todo se remuestrea a 12 fps exactos (cuadros en k/12 s): el juego las
//     reproduce a pasos de 1/12 s, así que cada paso cae en una clave.
//   - Texturas: hueso de 128 px (skeleton_textures.py bone, con la oclusión y
//     la altura horneadas en el paso 1 y la paleta de la especie) y, si tiene,
//     la túnica (skeleton_textures.py cloth sobre el atlas del Ranger).
//
// Armas (opcional, --kaykit <ruta a addons/kaykit_character_pack_skeletons>):
// se rehacen desde el pack de KayKit con recolor_texture.py, como antes. Sin
// --kaykit se dejan las que ya están en assets/enemies/weapons/.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { NodeIO } from '@gltf-transform/core';
import { dedup, prune, resample, weld } from '@gltf-transform/functions';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = path.resolve(HERE, '..', '..');
const OUT = path.join(PROJECT, 'assets', 'enemies');
const TMP = path.join(HERE, '.tmp');

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : def;
}
const WORK = path.resolve(arg('--work', path.join(HERE, '.work')));
const KAYKIT = arg('--kaykit', null);
const PYTHON = arg('--python', 'python3');

// Cuadros por segundo de las animaciones finales (movimiento entrecortado de PS1).
const ANIM_FPS = 12;

// Clips finales. src: de dónde sale (ual2 = el cuerpo, ual1 = ual1_anims.glb);
// chain: clips de origen que se encadenan (por defecto, el mismo nombre);
// pose: solo ese instante, como pose quieta de 1 s.
const CLIPS = {
  // UAL2 (vienen en el cuerpo). Los nombres finales no terminan en "_Loop":
  // el importador de Godot les saca ese sufijo (y el juego decide qué papel
  // se repite, ver EnemyVisual.LOOPING).
  Zombie_Idle: { src: 'ual2', chain: ['Zombie_Idle_Loop'] },
  Zombie_Walk: { src: 'ual2', chain: ['Zombie_Walk_Fwd_Loop'] },
  Zombie_Scratch: { src: 'ual2' },
  Shield_Idle: { src: 'ual2', chain: ['Idle_Shield_Loop'] },
  Shield_OneShot: { src: 'ual2' },
  Sword_Block: { src: 'ual2' },
  OverhandThrow: { src: 'ual2' },
  Idle_Rail_Call: { src: 'ual2' },
  LayToIdle: { src: 'ual2' },
  // Gancho con el arma y vuelta a la guardia (los dos clips de UAL2 seguidos).
  Melee_Hook_Full: { src: 'ual2', chain: ['Melee_Hook', 'Melee_Hook_Rec'] },
  // Tirado boca arriba: el primer cuadro de levantarse.
  Floor_Pose: { src: 'ual2', chain: ['LayToIdle'], pose: 0 },
  // UAL1 (ual1_anims.glb).
  Idle: { src: 'ual1', chain: ['Idle_Loop'] },
  Walk: { src: 'ual1', chain: ['Walk_Loop'] },
  Walk_Formal: { src: 'ual1', chain: ['Walk_Formal_Loop'] },
  Sword_Idle: { src: 'ual1' },
  Sword_Attack: { src: 'ual1' },
  Hit_Chest: { src: 'ual1' },
  Hit_Head: { src: 'ual1' },
  Death01: { src: 'ual1' },
  Pistol_Idle: { src: 'ual1', chain: ['Pistol_Idle_Loop'] },
  Pistol_Shoot: { src: 'ual1' },
  Spell_Idle: { src: 'ual1', chain: ['Spell_Simple_Idle_Loop'] },
  // Con el puño a la altura del pecho, como quien sostiene una antorcha: el
  // báculo queda vertical.
  Torch_Idle: { src: 'ual1', chain: ['Idle_Torch_Loop'] },
  Spell_Shoot: { src: 'ual1', chain: ['Spell_Simple_Shoot'] },
  // Conjuro completo: alzar la mano, lanzar y bajarla.
  Spell_Cast_Full: { src: 'ual1', chain: ['Spell_Simple_Enter', 'Spell_Simple_Shoot', 'Spell_Simple_Exit'] },
};

// Qué clips lleva cada enemigo lo dice data/species.json (visual.anims de la
// especie con el mismo id): se arman exactamente esos, ni uno más.
const SPECIES = JSON.parse(fs.readFileSync(path.join(PROJECT, 'data', 'species.json'), 'utf8'));

function speciesAnims(id) {
  const anims = SPECIES[id]?.visual?.anims;
  if (!anims) throw new Error(`data/species.json: ${id} no tiene visual.anims`);
  const names = Object.values(anims).flatMap((v) => (Array.isArray(v) ? v : [v]));
  for (const n of names) {
    if (!CLIPS[n]) throw new Error(`${id}: la animación ${n} de species.json no está en CLIPS`);
  }
  return [...new Set(names)];
}

// bone: colores del hueso (claro, sombra de las uniones, manchas). cloth: túnica.
const ENEMIES = [
  {
    id: 'esqueleto_esbirro', base: 'esqueleto', seed: 1,
    bone: { bone: '#cbbd94', shadow: '#2b2f24', stain: '#5d5a2e' },
  },
  {
    id: 'esqueleto_picaro', base: 'esqueleto', seed: 2,
    bone: { bone: '#bdbbb0', shadow: '#23272e', stain: '#424a55' },
  },
  {
    id: 'esqueleto_guardian', base: 'esqueleto', seed: 3,
    bone: { bone: '#b59d77', shadow: '#2c221d', stain: '#64341f' },
  },
  {
    id: 'nigromante', base: 'nigromante', seed: 4,
    bone: { bone: '#b9b1a6', shadow: '#221b28', stain: '#463650' },
    cloth: { dark: '#0b0810', mid: '#251a2e', light: '#4a3f56', trim: '#4a4030' },
  },
];

const WEAPONS = [
  { id: 'hoja', src: 'Skeleton_Blade', hue: 95 },
  { id: 'ballesta', src: 'Skeleton_Crossbow', hue: 205 },
  { id: 'hacha', src: 'Skeleton_Axe', hue: 18 },
  { id: 'escudo', src: 'Skeleton_Shield_Large_A', hue: 18 },
  { id: 'baculo', src: 'Skeleton_Staff', hue: 280 },
];

const io = new NodeIO();

// --- Animaciones ---------------------------------------------------------------------

/** Canales de un clip: Map "nodo|path" -> {times, values, size}. */
function readClip(doc, name) {
  const anim = doc.getRoot().listAnimations().find((a) => a.getName() === name);
  if (!anim) throw new Error(`falta la animación ${name}`);
  const out = new Map();
  for (const ch of anim.listChannels()) {
    const node = ch.getTargetNode();
    const s = ch.getSampler();
    if (!node || !s || s.getInterpolation() === 'CUBICSPLINE') continue;
    out.set(`${node.getName()}|${ch.getTargetPath()}`, {
      times: Array.from(s.getInput().getArray()),
      values: Array.from(s.getOutput().getArray()),
      size: s.getOutput().getElementSize(),
    });
  }
  return out;
}

function duration(clip) {
  let d = 0;
  for (const c of clip.values()) d = Math.max(d, c.times[c.times.length - 1]);
  return d;
}

/** Valor de un canal en el instante t (lineal; nlerp con signo para cuaterniones). */
function sample(c, t) {
  const { times, values, size } = c;
  if (t <= times[0]) return values.slice(0, size);
  const last = times.length - 1;
  if (t >= times[last]) return values.slice(last * size, last * size + size);
  let i = 0;
  while (times[i + 1] < t) i++;
  const f = (t - times[i]) / Math.max(times[i + 1] - times[i], 1e-9);
  const a = values.slice(i * size, i * size + size);
  const b = values.slice((i + 1) * size, (i + 1) * size + size);
  if (size === 4) {
    const dot = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
    const s = dot < 0 ? -1 : 1;
    const q = a.map((x, k) => x * (1 - f) + b[k] * s * f);
    const len = Math.hypot(...q) || 1;
    return q.map((x) => x / len);
  }
  return a.map((x, k) => x * (1 - f) + b[k] * f);
}

/** Clip final como lista de {key, times, values, size} remuestreada a ANIM_FPS. */
function buildClip(name, docs) {
  const def = CLIPS[name];
  if (/[_-](loop|cycle)$/i.test(name)) throw new Error(`${name}: Godot le saca el sufijo al importar; usar otro nombre`);
  if (!def) throw new Error(`clip ${name} sin definir en CLIPS`);
  const parts = (def.chain ?? [name]).map((n) => readClip(docs[def.src], n));
  const keys = new Set(parts.flatMap((p) => [...p.keys()]));
  const durs = parts.map(duration);
  const total = def.pose !== undefined ? 1.0 : durs.reduce((a, b) => a + b, 0);
  const step = 1 / ANIM_FPS;
  const grid = [];
  for (let k = 0; k * step < total - 1e-4; k++) grid.push(k * step);
  grid.push(total);
  const out = [];
  for (const key of keys) {
    if (key.startsWith('Armature|')) continue;
    const size = parts.find((p) => p.has(key)).get(key).size;
    const values = [];
    for (const t of grid) {
      if (def.pose !== undefined) {
        values.push(...sample(parts[0].get(key) ?? [...parts.find((p) => p.has(key)).values()][0], def.pose));
        continue;
      }
      // Qué clip de la cadena suena en t (el último incluye su final).
      let i = 0;
      let t0 = 0;
      while (i < parts.length - 1 && t > t0 + durs[i] + 1e-6) t0 += durs[i++];
      const c = parts[i].get(key) ?? parts.find((p) => p.has(key)).get(key);
      values.push(...sample(c, t - t0));
    }
    // Canal quieto (escala, la mayoría de las traslaciones): dos claves.
    const still = values.every((v, i) => Math.abs(v - values[i % size]) < 1e-5);
    out.push(still ? { key, times: [0, total], values: [...values.slice(0, size), ...values.slice(0, size)], size }
      : { key, times: grid, values, size });
  }
  return out;
}

function addClip(doc, name, channels) {
  const root = doc.getRoot();
  const buffer = root.listBuffers()[0];
  const nodes = new Map(root.listNodes().map((n) => [n.getName(), n]));
  const anim = doc.createAnimation(name);
  const inputs = new Map(); // los canales con los mismos tiempos comparten accessor
  for (const c of channels) {
    const [nodeName, targetPath] = c.key.split('|');
    const node = nodes.get(nodeName);
    if (!node) continue;
    const tkey = c.times.join(',');
    if (!inputs.has(tkey)) inputs.set(tkey, doc.createAccessor().setType('SCALAR').setArray(new Float32Array(c.times)).setBuffer(buffer));
    const input = inputs.get(tkey);
    const output = doc.createAccessor().setType(c.size === 4 ? 'VEC4' : 'VEC3').setArray(new Float32Array(c.values)).setBuffer(buffer);
    const sampler = doc.createAnimationSampler().setInput(input).setOutput(output).setInterpolation('LINEAR');
    anim.addSampler(sampler);
    anim.addChannel(doc.createAnimationChannel().setTargetNode(node).setTargetPath(targetPath).setSampler(sampler));
  }
}

/** Canales que en TODOS los clips del enemigo se quedan en el valor de reposo
 * del hueso (las escalas, casi todas las traslaciones, las puntas de los
 * dedos): se sacan. Ningún clip los mueve, así que el hueso queda en reposo
 * igual; el .glb pasa de ~1500 accessors a unos cientos. */
function dropRestChannels(doc, clips) {
  const nodes = new Map(doc.getRoot().listNodes().map((n) => [n.getName(), n]));
  const rest = (key) => {
    const [n, p] = key.split('|');
    const node = nodes.get(n);
    if (!node) return null;
    return p === 'rotation' ? node.getRotation() : p === 'translation' ? node.getTranslation() : node.getScale();
  };
  const moving = new Set();
  for (const [, channels] of clips) {
    for (const c of channels) {
      const r = rest(c.key);
      if (!r) continue;
      for (let i = 0; i < c.values.length; i += c.size) {
        let d = 0;
        for (let k = 0; k < c.size; k++) d = Math.max(d, Math.abs(c.values[i + k] - r[k]));
        // q y -q son la misma rotación.
        if (c.size === 4) {
          let d2 = 0;
          for (let k = 0; k < 4; k++) d2 = Math.max(d2, Math.abs(c.values[i + k] + r[k]));
          d = Math.min(d, d2);
        }
        if (d > 1e-4) { moving.add(c.key); break; }
      }
    }
  }
  return clips.map(([n, channels]) => [n, channels.filter((c) => moving.has(c.key))]);
}

function dropAllAnimations(doc) {
  for (const anim of doc.getRoot().listAnimations()) {
    for (const c of anim.listChannels()) c.dispose();
    for (const s of anim.listSamplers()) s.dispose();
    anim.dispose();
  }
}

// --- Texturas ------------------------------------------------------------------------

function py(script, args) {
  execFileSync(PYTHON, ['-I', path.join(HERE, script), ...args], { stdio: ['ignore', 'inherit', 'inherit'] });
}

function boneTexture(e) {
  const out = path.join(TMP, `${e.id}_hueso.png`);
  const b = e.bone;
  py('skeleton_textures.py', ['bone', '--ao', path.join(WORK, `${e.base}_ao.png`), '--height', path.join(WORK, `${e.base}_height.png`),
    '--out', out, '--size', '128', '--seed', String(e.seed), '--bone', b.bone, '--shadow', b.shadow, '--stain', b.stain]);
  return fs.readFileSync(out);
}

function clothTexture(e, srcPng) {
  const src = path.join(TMP, `${e.id}_atlas_src.png`);
  const out = path.join(TMP, `${e.id}_tunica.png`);
  fs.writeFileSync(src, srcPng);
  const c = e.cloth;
  py('skeleton_textures.py', ['cloth', '--src', src, '--out', out, '--size', '128', '--seed', String(e.seed),
    '--dark', c.dark, '--mid', c.mid, '--light', c.light, '--trim', c.trim]);
  return fs.readFileSync(out);
}

function setTexture(doc, material, png, name) {
  let tex = material.getBaseColorTexture();
  if (!tex) throw new Error(`el material ${material.getName()} no tiene textura`);
  tex.setImage(png).setMimeType('image/png').setURI('').setName(name);
}

function countTris(doc) {
  return doc.getRoot().listMeshes().reduce((n, m) => n + m.listPrimitives().reduce((k, p) => k + (p.getIndices()?.getCount() ?? 0) / 3, 0), 0);
}

// --- Enemigos ------------------------------------------------------------------------

async function buildEnemy(e, ual1) {
  const doc = await io.read(path.join(WORK, `${e.base}_base.glb`));
  const docs = { ual2: doc, ual1 };
  const names = speciesAnims(e.id);
  let clips = names.map((n) => [n, buildClip(n, docs)]);
  clips = dropRestChannels(doc, clips);
  dropAllAnimations(doc);
  for (const [n, ch] of clips) addClip(doc, n, ch);
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      for (const sem of prim.listSemantics()) {
        if (sem.startsWith('COLOR_') || sem === 'TEXCOORD_1') prim.setAttribute(sem, null);
      }
    }
  }
  for (const mat of doc.getRoot().listMaterials()) {
    if (mat.getName() === 'Hueso') setTexture(doc, mat, boneTexture(e), 'skeleton_texture');
    if (mat.getName() === 'Tunica') setTexture(doc, mat, clothTexture(e, mat.getBaseColorTexture().getImage()), 'robe_texture');
  }
  await doc.transform(prune(), dedup());
  const dst = path.join(OUT, `${e.id}.glb`);
  await io.write(dst, doc);
  console.log(`${e.id}.glb: ${doc.getRoot().listAnimations().length} anims, ${Math.round(countTris(doc))} tris, ${(fs.statSync(dst).size / 1024).toFixed(0)} KB`);
}

// --- Armas (KayKit, opcional) --------------------------------------------------------

async function buildWeapon(w, seed) {
  const png = path.join(TMP, `arma_${w.id}.png`);
  py('recolor_texture.py', [path.join(KAYKIT, 'Textures', 'skeleton_texture.png'), png, '--hue', String(w.hue), '--accent-sat', '0.45', '--seed', String(seed), '--size', '64']);
  const doc = await io.read(path.join(KAYKIT, 'Assets', 'gltf', `${w.src}.gltf`));
  for (const tex of doc.getRoot().listTextures()) tex.setImage(fs.readFileSync(png)).setMimeType('image/png').setURI('');
  await doc.transform(resample(), weld(), prune(), dedup());
  const dst = path.join(OUT, 'weapons', `${w.id}.glb`);
  await io.write(dst, doc);
  console.log(`weapons/${w.id}.glb: ${Math.round(countTris(doc))} tris`);
}

fs.mkdirSync(TMP, { recursive: true });
const ual1 = await io.read(path.join(WORK, 'ual1_anims.glb'));
for (const e of ENEMIES) await buildEnemy(e, ual1);
if (KAYKIT) {
  let seed = 5; // las mismas semillas que cuando salían junto con los esqueletos de KayKit
  for (const w of WEAPONS) await buildWeapon(w, seed++);
}
fs.rmSync(TMP, { recursive: true, force: true });

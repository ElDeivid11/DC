// Prepara los modelos CC0 que usa tools/portraits/bake_portraits.tscn y los
// deja chicos en tools/portraits/models/ (el juego no los carga: solo la
// herramienta de horneado de retratos).
//
//   node tools/portraits/prepare_models.mjs [--adventures=RUTA] [--halloween=RUTA] [--out=DIR] [--candidatos]
//
// Usa las dependencias de tools/assets (cd tools/assets && npm ci, una vez).
//
// Fuentes (las dos CC0, Kay Lousberg, ver tools/portraits/README.md):
// - KayKit Character Pack: Adventurers 1.0
//   https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0
// - KayKit Halloween Bits 1.0
//   https://github.com/KayKit-Game-Assets/KayKit-Halloween-Bits-1.0
//
// Personajes: se conserva SOLO la animación de la pose del retrato (de 76) y
// se borran las armas y objetos colgados de las manos (hacha, escudo, jarra,
// ballestas, cuchillos...). Así cada .glb pasa de ~3,6 MB a unos cientos de KB.
// Objetos (cráneo y hueso de Halloween Bits): .gltf + .bin + textura externa
// → un .glb autocontenido. Las botellas y la antorcha salen directo de
// addons/kaykit_dungeon_remastered (ya está en el repo).
// --candidatos además exporta los otros personajes del pack (Rogue, Mage,
// Knight) para comparar opciones de retrato.

import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = path.resolve(HERE, '..', '..');
// Las dependencias viven en tools/assets/node_modules (mismo pipeline de assets).
const req = createRequire(path.join(PROJECT, 'tools', 'assets', 'package.json'));
const { NodeIO } = await import(pathToFileURL(req.resolve('@gltf-transform/core')).href);
const { dedup, prune, resample } = await import(pathToFileURL(req.resolve('@gltf-transform/functions')).href);

const args = Object.fromEntries(process.argv.slice(2).map((a) => {
  const [k, ...v] = a.replace(/^--/, '').split('=');
  return [k, v.length ? v.join('=') : true];
}));
// Rutas a los packs bajados (ver tools/portraits/README.md → Regenerar).
if (!args.adventures || !args.halloween) {
  console.error('uso: node tools/portraits/prepare_models.mjs --adventures=<.../kaykit_character_pack_adventures> --halloween=<.../kaykit_halloween_bits> [--out=DIR] [--candidatos]');
  process.exit(1);
}
const ADVENTURES = path.resolve(String(args.adventures));
const HALLOWEEN = path.resolve(String(args.halloween));
const OUT = path.resolve(args.out ?? path.join(HERE, 'models'));

// Nodos que se borran (armas, escudos, jarras: el retrato es de cabeza y hombros).
const PROPS = /^(1H_|2H_|Barbarian_Round_Shield|Mug|Knife|Throwable|Spellbook|Wand|Staff|Badge_Shield|Rectangle_Shield|Round_Shield|Spike_Shield)/;

const CHARACTERS = [
  { id: 'bjorn', src: 'Barbarian', anims: ['Idle'] },
  { id: 'elena', src: 'Rogue_Hooded', anims: ['Idle'] },
];
const CANDIDATES = [
  { id: 'cand_rogue', src: 'Rogue', anims: ['Idle'] },
  { id: 'cand_mage', src: 'Mage', anims: ['Idle'] },
  { id: 'cand_knight', src: 'Knight', anims: ['Idle'] },
];
const PROPS_MODELS = [
  { id: 'skull', src: path.join(HALLOWEEN, 'Assets', 'gltf', 'skull.gltf') },
  { id: 'bone_a', src: path.join(HALLOWEEN, 'Assets', 'gltf', 'bone_A.gltf') },
];

const io = new NodeIO();

function dropAnimation(anim) {
  // dispose() de la animación no suelta sus samplers/canales (igual que en
  // tools/assets/process_enemies.mjs): sin esto prune() no borra sus datos.
  for (const c of anim.listChannels()) c.dispose();
  for (const s of anim.listSamplers()) s.dispose();
  anim.dispose();
}

async function character(c) {
  const src = path.join(ADVENTURES, 'Characters', 'gltf', `${c.src}.glb`);
  const doc = await io.read(src);
  const root = doc.getRoot();
  for (const anim of root.listAnimations()) {
    if (!c.anims.includes(anim.getName())) dropAnimation(anim);
  }
  const missing = c.anims.filter((n) => !root.listAnimations().some((a) => a.getName() === n));
  if (missing.length) throw new Error(`${c.src}: faltan animaciones ${missing.join(', ')}`);
  const removed = [];
  for (const node of root.listNodes()) {
    if (node.getMesh() && PROPS.test(node.getName())) {
      removed.push(node.getName());
      node.dispose();
    }
  }
  await doc.transform(resample(), prune(), dedup());
  const dst = path.join(OUT, `${c.id}.glb`);
  await io.write(dst, doc);
  report(dst, doc, `${c.src}, sin: ${removed.join(', ') || '-'}`);
}

async function prop(p) {
  const doc = await io.read(p.src);
  await doc.transform(prune(), dedup());
  const dst = path.join(OUT, `${p.id}.glb`);
  await io.write(dst, doc);
  report(dst, doc, path.basename(p.src));
}

function report(dst, doc, note) {
  const root = doc.getRoot();
  const tris = root.listMeshes().reduce((n, m) => n + m.listPrimitives().reduce((k, pr) => k + (pr.getIndices()?.getCount() ?? 0) / 3, 0), 0);
  console.log(`${path.basename(dst)}: ${root.listAnimations().length} anims, ${Math.round(tris)} tris, ${(fs.statSync(dst).size / 1024).toFixed(0)} KB (${note})`);
}

fs.mkdirSync(OUT, { recursive: true });
for (const c of CHARACTERS) await character(c);
if (args.candidatos) for (const c of CANDIDATES) await character(c);
for (const p of PROPS_MODELS) await prop(p);

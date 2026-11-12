# tools/art — arte de ambiente con un modelo abierto local

Genera las pinturas de `assets/art/` (fondo del Hub, postales de bioma) con
Stable Diffusion corriendo en la máquina: gratis, sin cuenta y sin subir nada.
En CPU tarda unos 30 s por imagen (4 núcleos).

## Instalar (una vez, en un entorno aparte)

```
python3 -m venv venv_ai
venv_ai/bin/pip install --index-url https://download.pytorch.org/whl/cpu torch
venv_ai/bin/pip install diffusers transformers accelerate safetensors pillow numpy
```

## Usar

```
venv_ai/bin/python tools/art/generate.py                      # todo prompts.json
venv_ai/bin/python tools/art/generate.py --only=bioma_luna    # una sola
venv_ai/bin/python tools/art/generate.py --only=fondo_hub --seed=21 --raw=/tmp/crudas   # otra variante
venv_ai/bin/python tools/art/generate.py --raw=/tmp/crudas --post-only   # solo rehacer el filtro
```

- `prompts.json`: el modelo, el estilo común (se agrega a cada texto) y por
  imagen: `prompt`, `seed`, `size` (lo que pinta el modelo), `pixel` (la
  resolución final del juego), `bits` (color por canal, 5 = PS1) y `colors`
  (opcional: limita la paleta; deja manchas en los degradados).
- El filtro (`retro()`): reduce a `pixel`, sube un poco el contraste, baja
  la saturación y pasa a 15 bits con trama de Bayer 4×4, igual que la vista
  3D (`RetroView`). Las imágenes se muestran a escala entera (×2).
- Para sumar una imagen: una entrada más en `prompts.json`, generarla,
  mirarla y, si sirve, usarla desde el juego. Las que no convencen no se
  commitean.
- Probado y descartado: retratos de objetos (a 64 px salen embarrados y
  distintos entre sí; los de `tools/portraits/` son mejores) y enemigos
  (la animación cuadro a cuadro no queda pareja: siguen dibujados por código).

Licencias y procedencia: `assets/art/README.md`.

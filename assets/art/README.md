# Arte de ambiente (generado)

Pinturas de ambiente del juego: el fondo del Hub y la postal de cada bioma
(se muestra al llegar a un piso). **Son imágenes generadas con un modelo de
IA que corre en la máquina**, sin servicio externo, cuenta ni costo, y
después pasadas al aspecto del juego (resolución de píxel y color de 15 bits
con trama, como la vista 3D).

| Archivo | Uso | Tamaño |
|---|---|---|
| `fondo_hub.png` | Fondo del Hub (`HubScreen`), a ×2 | 640×360 |
| `bioma_catacumbas.png` … `bioma_abismo.png` | Postal al llegar al piso (`UIFloorCard`, `floors.json → themes.<bioma>.postal`), a ×2 | 320×180 |

## Cómo se hicieron

`tools/art/generate.py` con los textos y semillas de `tools/art/prompts.json`
(ver `tools/art/README.md`): mismo texto + misma semilla = misma imagen.

## Modelo y licencias

- Modelo: **LCM Dreamshaper v7** (`SimianLuo/LCM_Dreamshaper_v7`, Hugging
  Face), licencia **MIT** según su ficha. Es una destilación de Dreamshaper 7
  (`Lykon/dreamshaper-7`), un ajuste de Stable Diffusion 1.5, ambos con
  licencia **CreativeML OpenRAIL-M**: permite usar las imágenes generadas,
  también con fines comerciales, no reclama derechos sobre ellas y deja al
  usuario como responsable de lo que genera (con una lista de usos
  prohibidos que acá no aplican).
- Las imágenes **no son CC0 ni CC-BY**: son salida propia del proyecto. La
  regla del repo («solo CC0/CC-BY verificados») es para material de
  terceros; esto no trae material de terceros.
- Ojo: en varios países una imagen hecha solo por IA puede no tener derecho
  de autor (cualquiera podría copiarla). Para el juego no cambia nada, pero
  conviene saberlo si algún día se venden como arte suelto.
- El modelo (≈4 GB) no está en el repo: se baja solo la primera vez.

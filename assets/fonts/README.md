# Fuentes (todas SIL Open Font License 1.1)

| Archivo | Fuente | Uso | Licencia | Notas |
|---|---|---|---|---|
| `PixelifySans-Regular.woff` | Pixelify Sans (subconjunto latino de @fontsource/pixelify-sans 5.3.0) | Cuerpo de texto (20 y 16 px) | `OFL_PixelifySans.txt` | Sin cambios. |
| `Jacquard12-Regular.ttf` | Jacquard 12 (The Soft Type Project Authors) | Minúsculas de los títulos góticos (`UIGothicLabel`, 42 px) | `OFL_Jacquard.txt` | Sin cambios. |
| `Jacquard24-Regular.ttf` | Jacquard 24 | Solo el logo, que `tools/ui/make_ui_kit.py` dibuja en el atlas | `OFL_Jacquard.txt` | Sin cambios. |
| `JacquardaBastarda9-Regular.ttf` | Jacquarda Bastarda 9 | Minúsculas de las citas góticas (lema, epitafios) | `OFL_JacquardaBastarda9.txt` | Sin cambios. |
| `Jersey15-Regular.ttf` | Jersey 15 | Mayúsculas y capitulares de todo texto gótico (las fraktur confunden I/J, A/Il) | `OFL_Jersey15.txt` | Sin cambios. |
| `Micro5-Regular.ttf` | Micro 5 | Cifras: monedas, HP, rangos, conteos (22, 33 y 44 px) | `OFL_Micro5.txt` | Sin cambios. |
| `NotoSansSymbols2-Regular.woff` | Noto Sans Symbols 2 (@fontsource) | Respaldo de símbolos | `OFL_NotoSansSymbols2.txt` | **Modificada**: recortada a flechas, formas geométricas, símbolos y dingbats (U+2190–21FF, 25A0–25FF, 2600–27BF, 2B00–2BFF) y con métricas verticales igualadas a Pixelify Sans (ascent 920 / descent 280), para que el respaldo de símbolos no agrande el interlineado. |
| `NotoSansSymbols-Regular.woff` | Noto Sans Symbols (@fontsource) | Respaldo de flechas ← ↑ → ↓ | `OFL_NotoSansSymbols.txt` | **Modificada** igual que la anterior. |

Las cinco de The Soft Type Project salen del repositorio `google/fonts` (carpeta `ofl/` de cada familia), con su `OFL.txt`.

Los `.import` tienen `antialiasing=0` y `hinting=0`: texto pixelado nítido. Los tamaños son múltiplos de la grilla de cada fuente (ver `UIStyle`); `tests/unit/test_ui_kit.gd` lo revisa.

A 16 px las flechas ↑ ↓ del respaldo se ven como barras: en textos chicos se escribe «Flechas» y en Opciones las teclas van en placas (`UITabs.make_keycap`), con Micro 5.

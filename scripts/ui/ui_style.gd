class_name UIStyle
extends RefCounted
## Design tokens de la UI «Grimorio de la Cripta»: ÚNICO lugar con colores,
## tamaños de fuente y espaciados. El Theme (theme_builder.gd) y los
## componentes salen de acá; ninguna pantalla usa colores sueltos.
##
## La paleta vive también en data/ui_palette.json (la lee el generador del kit,
## tools/ui/make_ui_kit.py); tests/unit/test_ui_kit.gd exige que coincidan.
## Dos temperaturas: fuego (VELA/BRASA) para lo interactivo y lo propio, y el
## azul de ALMA como único color frío. HP siempre SANGRE; EXP/nivel AMATISTA.

# --- Paleta (nombres de data/ui_palette.json) ---------------------------------------
const TINTA := Color("#070505")
const CRIPTA := Color("#0b0908")
const VITELA := Color("#191411")
const VITELA_ALTA := Color("#231c17")
const HIERRO := Color("#4d453d")
const BRONCE := Color("#b88a4a")
const HUESO := Color("#e8dcc0")
const CENIZA := Color("#a89a80")
const CENIZA_OSC := Color("#6e6353")
const VELA := Color("#ffd88a")
const BRASA := Color("#e8892e")
const RUBRICA := Color("#c4483c")
const RUBRICA_CLARA := Color("#de6a5a")
const SANGRE := Color("#a8322a")
const ALMA := Color("#6ab7d9")
const MONEDA := Color("#e8c85a")
const MUSGO := Color("#8fb866")
const AMATISTA := Color("#a98ad8")
const HIERRO_LUZ := Color("#7a7064")
const HIERRO_OSC := Color("#2a2420")
const HIERRO_GRANO := Color("#433c35")
const BRONCE_LUZ := Color("#e0b878")
const BRONCE_OSC := Color("#5e4426")
const BRONCE_FILETE := Color("#6b4e2c")
const PIEDRA := Color("#2b231d")
const PIEDRA_LUZ := Color("#4a3f35")
const PIEDRA_OSC := Color("#17120f")
const NICHO := Color("#15110e")
const HUNDIDO := Color("#0e0b09")
const BORDE_HUNDIDO := Color("#3a3029")
const NOTA := Color("#2a2019")
const SANGRE_LUZ := Color("#e0644e")
const SANGRE_OSC := Color("#5e1714")
const ALMA_LUZ := Color("#c4ecfa")
const ALMA_OSC := Color("#2c5f7a")
const ALMA_FONDO := Color("#121a20")
const MONEDA_LUZ := Color("#fff0a8")
const MONEDA_OSC := Color("#8a6a1e")
const AMATISTA_LUZ := Color("#d6c4f2")
const AMATISTA_OSC := Color("#4e3a72")
const VELA_BLANCA := Color("#fff4d0")
const BRASA_OSC := Color("#a8401e")
const RUBRICA_OSC := Color("#7a2620")
const LACRE_SOMBRA := Color("#3e0e0b")

## Nombre → color, para el test de sincronía con data/ui_palette.json.
const PALETTE := {
	"TINTA": TINTA,
	"CRIPTA": CRIPTA,
	"VITELA": VITELA,
	"VITELA_ALTA": VITELA_ALTA,
	"HIERRO": HIERRO,
	"BRONCE": BRONCE,
	"HUESO": HUESO,
	"CENIZA": CENIZA,
	"CENIZA_OSC": CENIZA_OSC,
	"VELA": VELA,
	"BRASA": BRASA,
	"RUBRICA": RUBRICA,
	"RUBRICA_CLARA": RUBRICA_CLARA,
	"SANGRE": SANGRE,
	"ALMA": ALMA,
	"MONEDA": MONEDA,
	"MUSGO": MUSGO,
	"AMATISTA": AMATISTA,
	"HIERRO_LUZ": HIERRO_LUZ,
	"HIERRO_OSC": HIERRO_OSC,
	"HIERRO_GRANO": HIERRO_GRANO,
	"BRONCE_LUZ": BRONCE_LUZ,
	"BRONCE_OSC": BRONCE_OSC,
	"BRONCE_FILETE": BRONCE_FILETE,
	"PIEDRA": PIEDRA,
	"PIEDRA_LUZ": PIEDRA_LUZ,
	"PIEDRA_OSC": PIEDRA_OSC,
	"NICHO": NICHO,
	"HUNDIDO": HUNDIDO,
	"BORDE_HUNDIDO": BORDE_HUNDIDO,
	"NOTA": NOTA,
	"SANGRE_LUZ": SANGRE_LUZ,
	"SANGRE_OSC": SANGRE_OSC,
	"ALMA_LUZ": ALMA_LUZ,
	"ALMA_OSC": ALMA_OSC,
	"ALMA_FONDO": ALMA_FONDO,
	"MONEDA_LUZ": MONEDA_LUZ,
	"MONEDA_OSC": MONEDA_OSC,
	"AMATISTA_LUZ": AMATISTA_LUZ,
	"AMATISTA_OSC": AMATISTA_OSC,
	"VELA_BLANCA": VELA_BLANCA,
	"BRASA_OSC": BRASA_OSC,
	"RUBRICA_OSC": RUBRICA_OSC,
	"LACRE_SOMBRA": LACRE_SOMBRA,
}

# --- Tokens semánticos (lo que usa el código) -------------------------------------
const BG_DEEP := CRIPTA
const PANEL := VITELA
const PANEL_ALT := VITELA_ALTA
const BORDER := HIERRO
const BORDER_FOCUS := BRASA
const TEXT := HUESO
const TEXT_DIM := CENIZA
const TEXT_OFF := CENIZA_OSC
const ACCENT := VELA
const EMBER := BRASA
const BRONZE := BRONCE
const BRONZE_LIGHT := BRONCE_LUZ
const BRONZE_DARK := BRONCE_OSC
const INK := TINTA
const GOOD := MUSGO
const DANGER := RUBRICA_CLARA
const DANGER_FILL := RUBRICA
const HP := SANGRE
const XP := AMATISTA
const SOUL := ALMA
const SOUL_LIGHT := ALMA_LUZ
const COIN := MONEDA
const FALLEN_TINT := CENIZA_OSC
const MAP_FLOOR := PIEDRA_LUZ
const MAP_WALL := HIERRO
const MAP_BG := HUNDIDO
const MAP_SEEN := PIEDRA
const CAPITAL := RUBRICA_CLARA
## Velo de los modales (sobre el 3D o la pantalla de abajo).
const VEIL := Color(CRIPTA, 0.62)

## Token → nombre de la paleta, para el test de sincronía.
const TOKENS := {
	"BG_DEEP": "CRIPTA",
	"PANEL": "VITELA",
	"PANEL_ALT": "VITELA_ALTA",
	"BORDER": "HIERRO",
	"BORDER_FOCUS": "BRASA",
	"TEXT": "HUESO",
	"TEXT_DIM": "CENIZA",
	"TEXT_OFF": "CENIZA_OSC",
	"ACCENT": "VELA",
	"EMBER": "BRASA",
	"BRONZE": "BRONCE",
	"BRONZE_LIGHT": "BRONCE_LUZ",
	"BRONZE_DARK": "BRONCE_OSC",
	"INK": "TINTA",
	"GOOD": "MUSGO",
	"DANGER": "RUBRICA_CLARA",
	"DANGER_FILL": "RUBRICA",
	"HP": "SANGRE",
	"XP": "AMATISTA",
	"SOUL": "ALMA",
	"SOUL_LIGHT": "ALMA_LUZ",
	"COIN": "MONEDA",
	"FALLEN_TINT": "CENIZA_OSC",
	"MAP_FLOOR": "PIEDRA_LUZ",
	"MAP_WALL": "HIERRO",
	"MAP_BG": "HUNDIDO",
	"MAP_SEEN": "PIEDRA",
	"CAPITAL": "RUBRICA_CLARA",
}

## Color de texto de una rampa de íconos del kit (las afinidades de almas
## dicen su rampa en sinergias.json: el nombre se pinta del mismo color).
static func ramp_color(ramp: String) -> Color:
	match ramp:
		"hueso":
			return HUESO
		"sangre":
			return RUBRICA_CLARA
		"amatista":
			return AMATISTA
		"alma":
			return ALMA
		"acero":
			return CENIZA
		"moneda":
			return MONEDA
		"vela":
			return VELA
		"bronce":
			return BRONCE_LUZ
	return TEXT

# --- Escala del pixel art -----------------------------------------------------------
## 1 píxel de arte del kit = PIXEL_SCALE px de la UI (ventana base 1280×720).
const PIXEL_SCALE := 2

# --- Tipografías (OFL; ver assets/fonts/README.md) ----------------------------------
## Cuerpo y detalle: Pixelify Sans. Góticas: Jacquard 12 (minúsculas) con
## mayúsculas de Jersey 15 (las fraktur se confunden: I/J, A/Il); citas en
## Jacquarda Bastarda 9; cifras en Micro 5; el logo en Jacquard 24 (horneado
## en el kit). Los tamaños son múltiplos de la grilla nativa de cada fuente.
const FONT_PATH := "res://assets/fonts/PixelifySans-Regular.woff"
const FONT_GOTHIC_PATH := "res://assets/fonts/Jacquard12-Regular.ttf"
const FONT_CAP_PATH := "res://assets/fonts/Jersey15-Regular.ttf"
const FONT_QUOTE_PATH := "res://assets/fonts/JacquardaBastarda9-Regular.ttf"
const FONT_NUM_PATH := "res://assets/fonts/Micro5-Regular.ttf"
const FONT_LOGO_PATH := "res://assets/fonts/Jacquard24-Regular.ttf"
const FONT_FALLBACK_PATHS: Array[String] = [
	"res://assets/fonts/NotoSansSymbols2-Regular.woff",
	"res://assets/fonts/NotoSansSymbols-Regular.woff",
]

const FONT_GOTHIC := 42      # Jacquard 12 ×2 (grilla 21)
const FONT_GOTHIC_CAP := 54  # Jersey 15 ×2 (grilla 27)
const FONT_QUOTE := 26       # Jacquarda Bastarda 9 ×2 (grilla 13)
const FONT_QUOTE_CAP := 27   # Jersey 15 ×1
const FONT_HEAD := 27        # Jersey 15 ×1: encabezados, botones, pestañas
const FONT_BODY := 20        # Pixelify Sans
const FONT_DETAIL := 16      # Pixelify Sans
const FONT_NUM_S := 22       # Micro 5 ×2 (grilla 11)
const FONT_NUM := 33         # Micro 5 ×3
const FONT_NUM_L := 44       # Micro 5 ×4

# --- Espaciado ----------------------------------------------------------------------
## Siempre pares (múltiplos de PIXEL_SCALE).
const SPACE := 4
const MARGIN_SCREEN := 24
const BUTTON_MIN_H := 40
const ICON_SIZE := 32

## Duración de transiciones (fundidos, aparición de paneles). El movimiento
## va por pasos, no suave.
const TRANSITION := 0.1

const COIN_SYMBOL := "◈"
const SOUL_SYMBOL := "✦"

## Íconos del kit (game-icons.net, CC BY 3.0): id → rampas horneadas en
## ui/kit/manifest.json. En el Theme: UIIcons/<id>_<rampa>.
const ICON_IDS: Array[String] = [
	"almas", "atacar", "bestiario", "continuar", "desbloqueos", "estadisticas", "estado", "exp",
	"habilidad", "hp", "huir", "iniciar", "inventario", "mapa", "mejoras", "monedas", "muerte",
	"objeto", "opciones", "piso", "retiro", "salir", "stat_agi", "stat_atq", "stat_def", "stat_esp",
	"stat_sue", "stat_vit", "tiempo", "victoria",
	"afin_hueso", "afin_sangre", "afin_sombra", "afin_espiritu", "afin_acero", "afin_fortuna",
	"pacto", "estado_aturdido", "estado_marca", "estado_debil", "escudo",
]

## Color del rango (10 = débil → 1 = fuerte), por cortes dentro de la paleta.
static func rank_color(rank: int) -> Color:
	if rank >= 8:
		return CENIZA
	if rank >= 5:
		return BRONCE_LUZ
	if rank >= 2:
		return VELA
	return RUBRICA_CLARA

## El HP es siempre rojo sangre: el HP bajo se marca con un destello, no con
## otro color.
static func hp_color(_fraction: float) -> Color:
	return HP

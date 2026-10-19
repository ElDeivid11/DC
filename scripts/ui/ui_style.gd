class_name UIStyle
extends RefCounted
## Design tokens de la UI: ÚNICO lugar con colores, tamaños de fuente y
## espaciados. El Theme (theme_builder.gd) y los componentes salen de acá;
## ninguna pantalla usa colores sueltos.
##
## Dirección visual: gótico oscuro + PS1. Fondos casi negros con tinte azul,
## bordes finos de piedra/metal, ámbar para lo interactivo, rojo apagado para
## peligro. Esquinas rectas, sin suavizado.

const BG_DEEP := Color("#0c0d12")
const PANEL := Color("#161821")
const PANEL_ALT := Color("#1d2030")
const BORDER := Color("#3a3f55")
const BORDER_FOCUS := Color("#e0a63a")
const TEXT := Color("#d8d4c8")
const TEXT_DIM := Color("#8a8778")
const ACCENT := Color("#e0a63a")
const GOOD := Color("#6fae5a")
const DANGER := Color("#b04a4a")
const SOUL := Color("#6ab7d9")
const COIN := Color("#e8c85a")

## Fuente pixel (OFL). Si el archivo no existe, el Theme usa la fuente por
## defecto de Godot sin antialiasing.
const FONT_PATH := "res://assets/fonts/PixelifySans-Regular.woff"

const FONT_TITLE := 28
const FONT_SUBTITLE := 20
const FONT_BODY := 16
const FONT_DETAIL := 13

## Espaciado: siempre múltiplos de 4 px.
const SPACE := 4
const MARGIN_SCREEN := 24
const BUTTON_MIN_H := 40
const BORDER_W := 2

## Duración de transiciones (fundidos, aparición de paneles).
const TRANSITION := 0.15

const COIN_SYMBOL := "◈"
const SOUL_SYMBOL := "✦"

## Color de la insignia de rango: rango 10 (débil) apagado → rango 1 (fuerte)
## rojo. El ámbar queda en el medio.
static func rank_color(rank: int) -> Color:
	var t := clampf((10.0 - float(rank)) / 9.0, 0.0, 1.0)
	if t < 0.5:
		return TEXT_DIM.lerp(ACCENT, t * 2.0)
	return ACCENT.lerp(DANGER, (t - 0.5) * 2.0)

## Color para una fracción de HP (barras): verde → ámbar → rojo.
static func hp_color(fraction: float) -> Color:
	if fraction > 0.5:
		return GOOD
	if fraction > 0.25:
		return ACCENT
	return DANGER

extends Node
## Acciones de entrada del juego (teclado + mando). Se registran por código al
## arrancar para tenerlas todas en un solo lugar y poder listarlas en
## Opciones → Controles. Los menús usan las acciones ui_* de Godot (que ya
## incluyen cruceta/stick y A/B del mando); Esc/B = ui_cancel = atrás.

const ACTIONS := {
	"move_forward": {"keys": [KEY_UP, KEY_W], "buttons": [JOY_BUTTON_DPAD_UP], "axis": [JOY_AXIS_LEFT_Y, -1.0]},
	"move_back": {"keys": [KEY_DOWN, KEY_S], "buttons": [JOY_BUTTON_DPAD_DOWN], "axis": [JOY_AXIS_LEFT_Y, 1.0]},
	"turn_left": {"keys": [KEY_LEFT, KEY_A], "buttons": [JOY_BUTTON_DPAD_LEFT], "axis": [JOY_AXIS_LEFT_X, -1.0]},
	"turn_right": {"keys": [KEY_RIGHT, KEY_D], "buttons": [JOY_BUTTON_DPAD_RIGHT], "axis": [JOY_AXIS_LEFT_X, 1.0]},
	"open_status": {"keys": [KEY_TAB], "buttons": [JOY_BUTTON_Y], "axis": []},
	"open_inventory": {"keys": [KEY_I], "buttons": [JOY_BUTTON_X], "axis": []},
	"open_map": {"keys": [KEY_M], "buttons": [JOY_BUTTON_BACK], "axis": []},
	"pause": {"keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START], "axis": []},
	"debug_panel": {"keys": [KEY_F1], "buttons": [], "axis": []},
}

## Orden en que se muestran en Opciones → Controles.
const DISPLAY_ORDER: Array[String] = [
	"move_forward", "move_back", "turn_left", "turn_right",
	"open_status", "open_inventory", "open_map", "pause",
]

## Nombres en pantalla de teclas que Godot devuelve en inglés.
const KEY_NAMES := {
	KEY_UP: "↑",
	KEY_DOWN: "↓",
	KEY_LEFT: "←",
	KEY_RIGHT: "→",
	KEY_ESCAPE: "Esc",
}

const BUTTON_NAMES := {
	JOY_BUTTON_DPAD_UP: "Cruceta ↑",
	JOY_BUTTON_DPAD_DOWN: "Cruceta ↓",
	JOY_BUTTON_DPAD_LEFT: "Cruceta ←",
	JOY_BUTTON_DPAD_RIGHT: "Cruceta →",
	JOY_BUTTON_Y: "Y / △",
	JOY_BUTTON_X: "X / □",
	JOY_BUTTON_BACK: "Select",
	JOY_BUTTON_START: "Start",
}

func _ready() -> void:
	ensure_actions()

func ensure_actions() -> void:
	for action: String in ACTIONS.keys():
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		var def: Dictionary = ACTIONS[action]
		for key: Variant in def.keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(key) as Key
			InputMap.action_add_event(action, ev)
		for b: Variant in def.buttons:
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(b) as JoyButton
			InputMap.action_add_event(action, jb)
		var axis: Array = def.axis
		if axis.size() == 2:
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(axis[0]) as JoyAxis
			jm.axis_value = float(axis[1])
			InputMap.action_add_event(action, jm)

## Nombres en pantalla de las teclas de una acción ("W", "↑").
func key_names(action: String) -> Array[String]:
	var out: Array[String] = []
	if ACTIONS.has(action):
		var def: Dictionary = ACTIONS[action]
		for key: Variant in def.keys:
			out.append(String(KEY_NAMES.get(int(key), OS.get_keycode_string(int(key)))))
	return out

## Nombres en pantalla de los botones de mando de una acción.
func pad_names(action: String) -> Array[String]:
	var out: Array[String] = []
	if ACTIONS.has(action):
		var def: Dictionary = ACTIONS[action]
		for b: Variant in def.buttons:
			out.append(String(BUTTON_NAMES.get(int(b), "Botón %d" % int(b))))
	return out

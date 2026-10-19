extends Node
## Regenera res://ui/theme_main.tres desde scripts/ui/theme_builder.gd:
##   godot --headless --path . res://tools/build_theme.tscn

func _ready() -> void:
	var err := ThemeBuilder.save_theme()
	if err != OK:
		printerr("No se pudo guardar el theme: ", error_string(err))
	else:
		print("Theme guardado en ", ThemeBuilder.THEME_PATH)
	get_tree().quit(0 if err == OK else 1)

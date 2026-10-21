class_name UISoulSlots
extends HBoxContainer
## Espacios de alma de un personaje: llamas azules llenas o apagadas.

func _init(used := 0, capacity := 1) -> void:
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	setup(used, capacity)

func setup(used: int, capacity: int) -> void:
	for c in get_children():
		c.queue_free()
	for i in maxi(capacity, used):
		add_child(UISprite.new("soul_full" if i < used else "soul_empty"))

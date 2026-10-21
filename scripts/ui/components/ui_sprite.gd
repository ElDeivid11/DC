class_name UISprite
extends TextureRect
## Sprite suelto del kit (sello, cimera, pip, llama de alma, marcador del
## mapa, logo) a su tamaño (ya escalado ×2), sin estirar.

func _init(sprite_name := "", scale_factor := 1) -> void:
	texture = UIIcon.kit_texture(sprite_name)
	stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if texture and scale_factor != 1:
		expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stretch_mode = TextureRect.STRETCH_SCALE
		custom_minimum_size = texture.get_size() * scale_factor

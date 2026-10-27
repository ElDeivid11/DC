class_name UIPanel
extends PanelContainer
## Panel con título: [Encabezado] / filete con rombo / cuerpo. El contenido va
## en `body`. Variaciones: "" (tapa de hierro), "PanelAlt" (inserto hundido),
## "HudPanel", "Card", "CardSoul", "CardFocus".

var body: VBoxContainer
var title_label: Label
var divider: UIDivider

func _init(title := "", variation := "", title_variation := "HeadLabel") -> void:
	if variation != "":
		theme_type_variation = variation
	var vbox := VBoxContainer.new()
	add_child(vbox)
	title_label = Label.new()
	title_label.theme_type_variation = title_variation
	title_label.text = title
	title_label.visible = title != ""
	vbox.add_child(title_label)
	divider = UIDivider.new(120)
	divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	divider.visible = title != ""
	vbox.add_child(divider)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

func set_title(t: String) -> void:
	title_label.text = t
	title_label.visible = t != ""
	divider.visible = t != ""

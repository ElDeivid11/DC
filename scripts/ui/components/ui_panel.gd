class_name UIPanel
extends PanelContainer
## Panel con título: [Título] / separador / cuerpo. El contenido va en `body`.
## Variaciones: "" (panel normal), "PanelAlt", "HudPanel", "Card".

var body: VBoxContainer
var title_label: Label

func _init(title := "", variation := "", title_variation := "SubtitleLabel") -> void:
	if variation != "":
		theme_type_variation = variation
	var vbox := VBoxContainer.new()
	add_child(vbox)
	title_label = Label.new()
	title_label.theme_type_variation = title_variation
	title_label.text = title
	title_label.visible = title != ""
	vbox.add_child(title_label)
	var sep := HSeparator.new()
	sep.visible = title != ""
	vbox.add_child(sep)
	body = VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(body)

func set_title(t: String) -> void:
	title_label.text = t
	title_label.visible = t != ""

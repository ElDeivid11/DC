class_name UILabel
extends RefCounted
## Atajo para crear etiquetas con variación del Theme.
##   body.add_child(UILabel.make("Texto", "DimLabel", true))

static func make(text: String, variation := "", wrapped := false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrapped:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
